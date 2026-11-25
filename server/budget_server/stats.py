"""Budget statistics — the server-side counterpart of lib/stats/stats_engine.dart.

Every aggregate takes an optional ``user_id``; ``None`` aggregates across all
users (used by the admin dashboard). Dates are stored as epoch milliseconds,
exactly as the Flutter app writes them, and are bucketed into days/months using
the server's local timezone — run the server in your users' timezone (or set
the ``TZ`` environment variable) so day boundaries line up.
"""
from datetime import datetime, timedelta

from .db import get_db


def tz_offset_ms() -> int:
    """Local UTC offset in milliseconds (epoch ms + offset = local wall clock)."""
    offset = datetime.now().astimezone().utcoffset()
    return int(offset.total_seconds() * 1000)


def month_bounds(now=None):
    """``[start, end)`` epoch-ms bounds of the month containing ``now``."""
    now = now or datetime.now()
    start = datetime(now.year, now.month, 1)
    if now.month == 12:
        end = datetime(now.year + 1, 1, 1)
    else:
        end = datetime(now.year, now.month + 1, 1)
    return int(start.timestamp() * 1000), int(end.timestamp() * 1000)


def month_start_ms(now=None):
    return month_bounds(now)[0]


def _scope(user_id):
    if user_id is None:
        return "", {}
    return "WHERE t.user_id = :uid", {"uid": user_id}


def _where(where, condition):
    """Append ``condition`` (written without a leading AND) to the user scope."""
    return f"{where} AND {condition}" if where else f"WHERE {condition}"


def totals(user_id=None):
    """Spent / received overall and in the current month, plus a transaction count."""
    conn = get_db()
    where, params = _scope(user_id)
    overall = conn.execute(
        f"""
        SELECT COUNT(*) AS tx_count,
               COALESCE(SUM(CASE WHEN t.type = 'debit' THEN t.amount ELSE 0 END), 0) AS spent,
               COALESCE(SUM(CASE WHEN t.type = 'credit' THEN t.amount ELSE 0 END), 0) AS received
        FROM transactions t
        {where}
        """,
        params,
    ).fetchone()
    start, end = month_bounds()
    month = conn.execute(
        f"""
        SELECT COALESCE(SUM(CASE WHEN t.type = 'debit' THEN t.amount ELSE 0 END), 0) AS spent_month,
               COALESCE(SUM(CASE WHEN t.type = 'credit' THEN t.amount ELSE 0 END), 0) AS received_month
        FROM transactions t
        {_where(where, "t.date >= :ms AND t.date < :me")}
        """,
        {**params, "ms": start, "me": end},
    ).fetchone()
    return {**_d(overall), **_d(month)}


def daily_frequency(user_id=None, days=30, tx_type="debit"):
    """Debit count/amount per day for the last ``days`` days, oldest first."""
    conn = get_db()
    where, params = _scope(user_id)
    today = datetime.now().date()
    first = today - timedelta(days=days - 1)
    start_ms = int(datetime(first.year, first.month, first.day).timestamp() * 1000)
    rows = conn.execute(
        f"""
        SELECT strftime('%Y-%m-%d', (t.date + :off) / 1000, 'unixepoch') AS day,
               COUNT(*) AS n,
               COALESCE(SUM(t.amount), 0) AS amount
        FROM transactions t
        {_where(where, "t.type = :tx_type AND t.date >= :start")}
        GROUP BY day
        ORDER BY day
        """,
        {**params, "off": tz_offset_ms(), "tx_type": tx_type, "start": start_ms},
    ).fetchall()
    by_day = {row["day"]: row for row in rows}
    out = []
    for i in range(days):
        day = first + timedelta(days=i)
        row = by_day.get(day.isoformat())
        out.append(
            {
                "day": day.isoformat(),
                "label": day.strftime("%d %b"),
                "short": day.strftime("%d"),
                "count": row["n"] if row else 0,
                "amount": row["amount"] if row else 0.0,
            }
        )
    return out


def monthly_spend(user_id=None, months=12):
    """Spent/received per month for the last ``months`` months, oldest first."""
    conn = get_db()
    where, params = _scope(user_id)
    now = datetime.now()
    year, month = now.year, now.month
    for _ in range(months - 1):
        month -= 1
        if month == 0:
            month, year = 12, year - 1
    first = datetime(year, month, 1)
    start_ms = int(first.timestamp() * 1000)
    rows = conn.execute(
        f"""
        SELECT strftime('%Y-%m', (t.date + :off) / 1000, 'unixepoch') AS ym,
               COUNT(*) AS n,
               COALESCE(SUM(CASE WHEN t.type = 'debit' THEN t.amount ELSE 0 END), 0) AS spent,
               COALESCE(SUM(CASE WHEN t.type = 'credit' THEN t.amount ELSE 0 END), 0) AS received
        FROM transactions t
        {_where(where, "t.date >= :start")}
        GROUP BY ym
        ORDER BY ym
        """,
        {**params, "off": tz_offset_ms(), "start": start_ms},
    ).fetchall()
    by_ym = {row["ym"]: row for row in rows}
    out = []
    cursor = first
    for _ in range(months):
        key = cursor.strftime("%Y-%m")
        row = by_ym.get(key)
        out.append(
            {
                "month": key,
                "label": cursor.strftime("%b %y"),
                "short": cursor.strftime("%b"),
                "count": row["n"] if row else 0,
                "spent": row["spent"] if row else 0.0,
                "received": row["received"] if row else 0.0,
            }
        )
        if cursor.month == 12:
            cursor = datetime(cursor.year + 1, 1, 1)
        else:
            cursor = datetime(cursor.year, cursor.month + 1, 1)
    return out


def by_category(user_id=None, tx_type="debit", days=None, limit=None):
    """Spend grouped by category (largest first); ``Other`` for blanks."""
    conn = get_db()
    where, params = _scope(user_id)
    condition = "t.type = :tx_type"
    if days is not None:
        today = datetime.now().date()
        first = today - timedelta(days=days - 1)
        start_ms = int(datetime(first.year, first.month, first.day).timestamp() * 1000)
        params = {**params, "start": start_ms}
        condition += " AND t.date >= :start"
    rows = conn.execute(
        f"""
        SELECT COALESCE(NULLIF(TRIM(t.category), ''), 'Other') AS category,
               COUNT(*) AS n,
               COALESCE(SUM(t.amount), 0) AS amount
        FROM transactions t
        {_where(where, condition)}
        GROUP BY category
        ORDER BY amount DESC
        """,
        {**params, "tx_type": tx_type},
    ).fetchall()
    out = [{"category": row["category"], "count": row["n"], "amount": row["amount"]} for row in rows]
    return out[:limit] if limit else out


def top_merchants(user_id=None, limit=8, tx_type="debit", days=None):
    """Highest-spending merchants (largest first), falling back to the bank name."""
    conn = get_db()
    where, params = _scope(user_id)
    condition = "t.type = :tx_type"
    if days is not None:
        today = datetime.now().date()
        first = today - timedelta(days=days - 1)
        start_ms = int(datetime(first.year, first.month, first.day).timestamp() * 1000)
        params = {**params, "start": start_ms}
        condition += " AND t.date >= :start"
    rows = conn.execute(
        f"""
        SELECT COALESCE(NULLIF(TRIM(t.merchant), ''), NULLIF(TRIM(t.bank), ''), 'Unknown') AS merchant,
               COUNT(*) AS n,
               COALESCE(SUM(t.amount), 0) AS amount
        FROM transactions t
        {_where(where, condition)}
        GROUP BY merchant
        ORDER BY amount DESC
        LIMIT :lim
        """,
        {**params, "tx_type": tx_type, "lim": limit},
    ).fetchall()
    return [{"merchant": row["merchant"], "count": row["n"], "amount": row["amount"]} for row in rows]


def average_purchase(user_id=None, days=30):
    """Average debit amount over the last ``days`` days."""
    rows = daily_frequency(user_id, days=days, tx_type="debit")
    count = sum(row["count"] for row in rows)
    amount = sum(row["amount"] for row in rows)
    return amount / count if count else 0.0


def latest_balance(user_id):
    """Most recent recorded balance, or ``None``."""
    row = get_db().execute(
        """
        SELECT balance, date FROM transactions
        WHERE user_id = ? AND balance IS NOT NULL
        ORDER BY date DESC LIMIT 1
        """,
        (user_id,),
    ).fetchone()
    return _d(row) if row else None


def top_spenders(limit=10, this_month=True):
    """Users with the highest debit totals, largest first."""
    conn = get_db()
    start = month_start_ms() if this_month else 0
    return conn.execute(
        """
        SELECT u.id, u.name, u.phone,
               COALESCE(SUM(t.amount), 0) AS spent,
               COUNT(t.id) AS n
        FROM users u
        JOIN transactions t ON t.user_id = u.id
        WHERE t.type = 'debit' AND t.date >= :start
        GROUP BY u.id
        ORDER BY spent DESC
        LIMIT :lim
        """,
        {"start": start, "lim": limit},
    ).fetchall()


def bar_chart(items, value_key):
    """Add a ``pct`` (0-100, scaled to the peak) field for CSS bar charts."""
    values = [max(0.0, float(item.get(value_key) or 0)) for item in items]
    peak = max(values, default=0.0) or 1.0
    out = []
    for item, value in zip(items, values):
        entry = dict(item)
        entry["pct"] = 0 if value <= 0 else max(3, round(100 * value / peak))
        out.append(entry)
    return out


def _d(row):
    return {key: row[key] for key in row.keys()}
