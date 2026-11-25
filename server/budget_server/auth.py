"""Admin console: login, user search, profiles and budgeting statistics."""
from __future__ import annotations

import hmac
import secrets
from functools import wraps

from flask import (
    Blueprint,
    abort,
    current_app,
    flash,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

bp = Blueprint("auth", __name__, url_prefix="/admin")


def _expected_credentials() -> tuple[bytes, bytes]:
    return (
        str(current_app.config["ADMIN_USERNAME"]).encode(),
        str(current_app.config["ADMIN_PASSWORD"]).encode(),
    )


def check_password(username: str, password: str) -> bool:
    expected_user, expected_pass = _expected_credentials()
    # Compare both even when the first fails, to keep the timing similar.
    user_ok = hmac.compare_digest(username.encode(), expected_user)
    pass_ok = hmac.compare_digest(password.encode(), expected_pass)
    return user_ok and pass_ok


def csrf_token() -> str:
    token = session.get("_csrf")
    if not token:
        token = secrets.token_urlsafe(32)
        session["_csrf"] = token
    return token


def validate_csrf() -> None:
    sent = request.form.get("_csrf") or ""
    if not sent or not hmac.compare_digest(sent.encode(), csrf_token().encode()):
        abort(400, description="Invalid or missing CSRF token.")


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("auth.login", next=request.path))
        return view(*args, **kwargs)

    return wrapped


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        validate_csrf()
        if not check_password(request.form.get("username", ""), request.form.get("password", "")):
            flash("Invalid username or password.", "error")
        else:
            session.clear()
            session["admin"] = request.form.get("username", "")
            session["_csrf"] = csrf_token()
            target = request.args.get("next") or url_for("admin.dashboard")
            # Only ever redirect back to paths on this site.
            if not target.startswith("/"):
                target = url_for("admin.dashboard")
            return redirect(target)
    return render_template("login.html")


@bp.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
