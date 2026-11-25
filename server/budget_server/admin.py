"""Admin console: dashboard, user search, profile editing, manual entries."""
from __future__ import annotations

import io
from datetime import datetime

from flask import (
    Blueprint,
    Response,
    abort,
    flash,
    redirect,
    render_template,
    request,
    url_for,
)

from . import models, stats
from .auth import login_required, validate_csrf
from .db import get_db

bp = Blueprint("admin", __name__, url_prefix="/admin")


@bp.app_template_filter("dt")
def dt_filter(value, fmt="%Y-%m-%d %H:%M"):
    if not value:
        return "—"
    try:
        return datetime.fromtimestamp(value / 1000).strftime(fmt)
    except (OSError, OverflowError, ValueError):
        return "—"


@bp.app_template_filter("money")
def money_filter(value):
    try:
        return f"{float(value):,.2f}"
    except (TypeError, ValueError):
        return "0.00"


@bp.route("/")
@login_required
def dashboard():
    user_count = get_db().execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
    totals = stats.totals()
    daily = stats.bar_chart(stats.daily_frequency(None, 30), "amount")
    monthly = stats.bar_chart(stats.monthly_spend(None, 12), "spent")
    top = stats.top_spenders(limit=10)
    recent = get_db().execute(
        """SELECT u.*, COUNT(t.id) AS tx_count
           FROM users u LEFT JOIN transactions t ON t.user_id = u.id
           GROUP BY u.id ORDER BY u.created_at DESC LIMIT 8"""
    ).fetchall()
    return render_template(
        "dashboard.html",
        user_count=user_count,
        totals=totals,
        daily=daily,
        monthly=monthly,
        top=top,
        recent=recent,
    )


@bp.route("/users")
@login_required
def users():
    query = request.args.get("q", "").strip()
    rows = models.list_users(query)
    return render_template("users.html", users=rows, query=query)


@bp.route("/users", methods=["POST"])
@login_required
def user_create():
    validate_csrf()
    phone = request.form.get("phone", "").strip()
    name = request.form.get("name", "").strip()
    if not phone:
        flash("Phone number is required.", "error")
    elif models.find_user_by_phone(phone):
        flash("A user with that phone number already exists.", "error")
    else:
        user_id = models.create_user(
            phone=phone,
            name=name,
            email=request.form.get("email", "").strip(),
            notes=request.form.get("notes", "").strip(),
        )
        get_db().commit()
        flash(f"Created profile for {name or phone}.", "ok")
        return redirect(url_for("admin.user_detail", user_id=user_id))
    return redirect(url_for("admin.users", q=phone))


@bp.route("/users/<int:user_id>")
@login_required
def user_detail(user_id):
    user = models.get_user(user_id)
    if user is None:
        abort(404)
    totals = stats.totals(user_id)
    daily = stats.bar_chart(stats.daily_frequency(user_id, 30), "amount")
    monthly = stats.bar_chart(stats.monthly_spend(user_id, 12), "spent")
    categories = stats.by_category(user_id, limit=8)
    category_total = sum(c["amount"] for c in categories) or 1.0
    for category in categories:
        category["pct"] = round(100 * category["amount"] / category_total)
    merchants = stats.top_merchants(user_id, limit=8)
    balance = stats.latest_balance(user_id)
    transactions = models.list_transactions(user_id, limit=100)
    tx_total = get_db().execute(
        "SELECT COUNT(*) AS n FROM transactions WHERE user_id = ?", (user_id,)
    ).fetchone()["n"]
    return render_template(
        "user_detail.html",
        user=user,
        totals=totals,
        daily=daily,
        monthly=monthly,
        categories=categories,
        merchants=merchants,
        balance=balance,
        transactions=transactions,
        tx_total=tx_total,
        avg_purchase=stats.average_purchase(user_id, 30),
    )


@bp.route("/users/<int:user_id>/profile", methods=["POST"])
@login_required
def user_save_profile(user_id):
    validate_csrf()
    user = models.get_user(user_id)
    if user is None:
        abort(404)
    phone = request.form.get("phone", "").strip()
    if not phone:
        flash("Phone number is required.", "error")
    elif (other := models.find_user_by_phone(phone)) and other["id"] != user_id:
        flash("Another user already has that phone number.", "error")
    else:
        get_db().execute(
            "UPDATE users SET name = ?, phone = ?, email = ?, notes = ? WHERE id = ?",
            (
                request.form.get("name", "").strip(),
                phone,
                request.form.get("email", "").strip(),
                request.form.get("notes", "").strip(),
                user_id,
            ),
        )
        get_db().commit()
        flash("Profile saved.", "ok")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@bp.route("/users/<int:user_id>/transactions", methods=["POST"])
@login_required
def user_add_transaction(user_id):
    validate_csrf()
    if models.get_user(user_id) is None:
        abort(404)
    date_text = request.form.get("date", "").strip()
    try:
        date_ms = int(datetime.strptime(date_text, "%Y-%m-%d").timestamp() * 1000)
        amount = float(request.form.get("amount", ""))
    except (ValueError, TypeError):
        flash("Enter a valid date (YYYY-MM-DD) and positive amount.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))
    if amount <= 0:
        flash("Amount must be positive.", "error")
        return redirect(url_for("admin.user_detail", user_id=user_id))
    tx_type = request.form.get("type", "debit")
    if tx_type not in ("debit", "credit"):
        tx_type = "debit"
    merchant = request.form.get("merchant", "").strip() or None
    category = request.form.get("category", "").strip() or None
    note = request.form.get("note", "").strip()
    models.insert_transactions(
        user_id,
        [
            {
                "sender": "manual",
                "bank": "manual",
                "merchant": merchant,
                "amount": amount,
                "type": tx_type,
                "currency": "",
                "date_ms": date_ms,
                "balance": None,
                "category": category,
                "raw": note or "Entered manually in admin console",
                "dedupe": f"manual|{user_id}|{date_ms}|{amount}|{merchant or ''}|{note}",
            }
        ],
    )
    get_db().commit()
    flash("Transaction added.", "ok")
    return redirect(url_for("admin.user_detail", user_id=user_id))


@bp.route("/users/<int:user_id>/export")
@login_required
def user_export(user_id):
    user = models.get_user(user_id)
    if user is None:
        abort(404)
    rows = models.list_transactions(user_id)
    buf = io.StringIO()
    buf.write("date,type,amount,currency,merchant,category,bank,sender,balance,raw\n")
    for row in rows:
        when = datetime.fromtimestamp(row["date"] / 1000).strftime("%Y-%m-%d %H:%M")
        fields = [
            when,
            row["type"],
            f'{row["amount"]:.2f}',
            row["currency"] or "",
            row["merchant"] or "",
            row["category"] or "",
            row["bank"] or "",
            row["sender"] or "",
            "" if row["balance"] is None else f'{row["balance"]:.2f}',
            (row["raw"] or "").replace('"', "'"),
        ]
        buf.write(",".join(f'"{f}"' for f in fields) + "\n")
    filename = f'transactions-{user["phone"]}.csv'.replace("+", "")
    return Response(
        buf.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
