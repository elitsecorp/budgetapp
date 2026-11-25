"""Data access for users and transactions (plain SQL over sqlite3)."""
from __future__ import annotations

import time

from .db import get_db

PROFILE_FIELDS = ("name", "email", "notes", "device_id")


def now_ms() -> int:
    return int(time.time() * 1000)


def get_user(user_id: int):
    return get_db().execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def find_user_by_phone(phone: str):
    return get_db().execute("SELECT * FROM users WHERE phone = ?", (phone,)).fetchone()


def create_user(phone: str, name: str = "", email: str = "", notes: str = "", device_id: str | None = None) -> int:
    cur = get_db().execute(
        """INSERT INTO users (name, phone, email, notes, device_id, created_at, last_sync_at)
           VALUES (?, ?, ?, ?, ?, ?, NULL)""",
        (name, phone, email, notes, device_id, now_ms()),
    )
    return cur.lastrowid


def update_profile(user_id: int, fields: dict) -> None:
    """Update only the provided, non-empty profile fields (None/blank = leave as is)."""
    sets, args = [], []
    for key in PROFILE_FIELDS:
        value = fields.get(key)
        if value is not None and str(value).strip():
            sets.append(f"{key} = ?")
            args.append(str(value).strip())
    if not sets:
        return
    args.append(user_id)
    get_db().execute(f"UPDATE users SET {', '.join(sets)} WHERE id = ?", args)


def list_users(search: str = ""):
    """All users with per-user totals, filtered by name/phone/email, biggest monthly spend first."""
    from .stats import month_start_ms

    q = search.strip()
    like = f"%{q}%"
    return get_db().execute(
        """
        SELECT u.*,
               COUNT(t.id) AS tx_count,
               COALESCE(SUM(CASE WHEN t.type = 'debit' THEN t.amount ELSE 0 END), 0) AS total_spent,
               COALESCE(SUM(CASE WHEN t.type = 'debit' AND t.date >= :month_start
                                 THEN t.amount ELSE 0 END), 0) AS spent_month,
               MAX(t.date) AS last_tx_date
        FROM users u
        LEFT JOIN transactions t ON t.user_id = u.id
        WHERE (:q = '' OR u.name LIKE :like OR u.phone LIKE :like OR u.email LIKE :like)
        GROUP BY u.id
        ORDER BY spent_month DESC, total_spent DESC, u.name COLLATE NOCASE
        """,
        {"q": q, "like": like, "month_start": month_start_ms()},
    ).fetchall()


def insert_transactions(user_id: int, items: list[dict]) -> tuple[int, int]:
    """Insert parsed transactions, skipping duplicates.

    Returns ``(accepted, duplicates)``. Each item needs ``sender, amount, type,
    date_ms, raw, dedupe``; the rest are optional.
    """
    conn = get_db()
    accepted = duplicates = 0
    for item in items:
        cur = conn.execute(
            """INSERT OR IGNORE INTO transactions
               (user_id, sender, bank, merchant, amount, type, currency, date,
                balance, category, raw, dedupe, received_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                user_id,
                item.get("sender") or "",
                item.get("bank") or "",
                item.get("merchant"),
                float(item["amount"]),
                item["type"],
                item.get("currency") or "",
                int(item["date_ms"]),
                item.get("balance"),
                item.get("category"),
                item.get("raw") or "",
                item["dedupe"],
                now_ms(),
            ),
        )
        if cur.rowcount:
            accepted += 1
        else:
            duplicates += 1
    return accepted, duplicates


def list_transactions(user_id: int, limit: int | None = None):
    sql = "SELECT * FROM transactions WHERE user_id = ? ORDER BY date DESC"
    args: list = [user_id]
    if limit is not None:
        sql += " LIMIT ?"
        args.append(limit)
    return get_db().execute(sql, args).fetchall()


def touch_sync(user_id: int) -> None:
    get_db().execute("UPDATE users SET last_sync_at = ? WHERE id = ?", (now_ms(), user_id))
