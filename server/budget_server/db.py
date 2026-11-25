"""SQLite storage: per-request connections and schema bootstrap."""
import os
import sqlite3

from flask import current_app, g

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL DEFAULT '',
    phone         TEXT NOT NULL UNIQUE,
    email         TEXT NOT NULL DEFAULT '',
    notes         TEXT NOT NULL DEFAULT '',
    device_id     TEXT,
    created_at    INTEGER NOT NULL,
    last_sync_at  INTEGER
);

CREATE TABLE IF NOT EXISTS transactions (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender       TEXT NOT NULL DEFAULT '',
    bank         TEXT NOT NULL DEFAULT '',
    merchant     TEXT,
    amount       REAL NOT NULL,
    type         TEXT NOT NULL CHECK (type IN ('debit', 'credit')),
    currency     TEXT NOT NULL DEFAULT '',
    date         INTEGER NOT NULL,          -- epoch milliseconds, as written by the app
    balance      REAL,
    category     TEXT,
    raw          TEXT NOT NULL DEFAULT '',
    dedupe       TEXT NOT NULL,
    received_at  INTEGER NOT NULL,
    UNIQUE (user_id, dedupe)
);

CREATE INDEX IF NOT EXISTS idx_tx_user_date ON transactions(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date DESC);
"""


def get_db() -> sqlite3.Connection:
    """Connection for the current request, created on first use."""
    if "db" not in g:
        conn = sqlite3.connect(current_app.config["DATABASE"])
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        g.db = conn
    return g.db


def close_db(_exc=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def init_app(app):
    """Create the schema once at startup."""
    app.teardown_appcontext(close_db)
    directory = os.path.dirname(app.config["DATABASE"])
    if directory:
        os.makedirs(directory, exist_ok=True)
    conn = sqlite3.connect(app.config["DATABASE"])
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        conn.close()
