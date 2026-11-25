"""Device sync API — the Android app POSTs parsed transactions here.

Auth: ``X-API-Key`` header matching the server's ``API_KEY``.
Dedup: transactions carry a natural-key ``dedupe`` string; replays are ignored.
"""
from __future__ import annotations

import hmac

from flask import Blueprint, current_app, jsonify, request

from . import models
from .db import get_db

bp = Blueprint("api", __name__, url_prefix="/api")


def _api_key_ok() -> bool:
    expected = str(current_app.config.get("API_KEY") or "")
    if not expected:
        return True  # dev mode: no key configured
    given = request.headers.get("X-API-Key", "")
    return hmac.compare_digest(given.encode(), expected.encode())


def _require_key():
    if not _api_key_ok():
        return jsonify({"error": "missing or invalid API key"}), 401
    return None


def _parse_date_ms(raw: dict) -> int:
    """Accept ``date_ms`` (epoch ms), or ``date`` as ISO string / epoch seconds/ms."""
    if raw.get("date_ms") is not None:
        return int(raw["date_ms"])
    value = raw.get("date")
    if value is None:
        raise ValueError("missing date")
    if isinstance(value, (int, float)):
        value = float(value)
        # Heuristic: values below ~1973-03 in ms are really epoch seconds.
        return int(value * 1000 if value < 1e11 else value)
    from datetime import datetime

    text = str(value).strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        raise ValueError(f"unparseable date: {value!r}") from None
    return int(parsed.timestamp() * 1000)


def _parse_transaction(raw: object) -> dict:
    if not isinstance(raw, dict):
        raise ValueError("transaction must be an object")
    try:
        amount = float(raw.get("amount"))
    except (TypeError, ValueError):
        raise ValueError("amount must be a number") from None
    if amount <= 0:
        raise ValueError("amount must be positive")
    tx_type = str(raw.get("type") or "").strip().lower()
    if tx_type not in ("debit", "credit"):
        raise ValueError("type must be 'debit' or 'credit'")
    date_ms = _parse_date_ms(raw)
    sender = str(raw.get("sender") or "").strip()
    raw_text = str(raw.get("raw") or "").strip()
    balance = raw.get("balance")
    try:
        balance = float(balance) if balance is not None else None
    except (TypeError, ValueError):
        raise ValueError("balance must be a number") from None
    dedupe = str(raw.get("dedupe") or "").strip() or f"{sender}|{date_ms}|{amount}|{raw_text}"
    return {
        "sender": sender,
        "bank": str(raw.get("bank") or "").strip(),
        "merchant": str(raw.get("merchant") or "").strip() or None,
        "amount": amount,
        "type": tx_type,
        "currency": str(raw.get("currency") or "").strip(),
        "date_ms": date_ms,
        "balance": balance,
        "category": str(raw.get("category") or "").strip() or None,
        "raw": raw_text,
        "dedupe": dedupe,
    }


def _identify(payload: dict) -> tuple[str, str, str, str, str | None]:
    """Read identity from either payload shape.

    The Android app sends ``{"owner": {"name", "phone"}, ...}``; a hand-rolled
    client may send top-level ``phone``/``profile``. Accept both.
    """
    owner = payload.get("owner") if isinstance(payload.get("owner"), dict) else {}
    profile = payload.get("profile") if isinstance(payload.get("profile"), dict) else {}
    phone = str(payload.get("phone") or owner.get("phone") or "").strip()
    name = str(profile.get("name") or owner.get("name") or payload.get("name") or "").strip()
    email = str(profile.get("email") or owner.get("email") or payload.get("email") or "").strip()
    notes = str(profile.get("notes") or payload.get("notes") or "").strip()
    device_id = str(payload.get("device_id") or "").strip() or None
    return phone, name, email, notes, device_id


def _upsert_user(payload: dict, phone: str) -> tuple[int, bool]:
    _, name, email, notes, device_id = _identify(payload)

    user = models.find_user_by_phone(phone)
    if user is None:
        user_id = models.create_user(phone=phone, name=name, email=email, notes=notes, device_id=device_id)
        return user_id, True
    models.update_profile(user["id"], {"name": name, "email": email, "notes": notes, "device_id": device_id})
    return user["id"], False


@bp.post("/sync")
def sync():
    denied = _require_key()
    if denied:
        return denied
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "JSON body required"}), 400

    phone, _, _, _, _ = _identify(payload)
    if not phone:
        return jsonify({"error": "phone is required"}), 400

    raw_txs = payload.get("transactions")
    if raw_txs is None:
        raw_txs = []
    if not isinstance(raw_txs, list):
        return jsonify({"error": "transactions must be a list"}), 400

    parsed, errors = [], []
    for index, raw in enumerate(raw_txs):
        try:
            parsed.append(_parse_transaction(raw))
        except ValueError as exc:
            errors.append({"index": index, "error": str(exc)})
    if errors:
        return jsonify({"error": "invalid transactions", "details": errors}), 400

    user_id, created = _upsert_user(payload, phone)
    accepted, duplicates = models.insert_transactions(user_id, parsed)
    models.touch_sync(user_id)
    get_db().commit()
    return jsonify(
        {
            "user_id": user_id,
            "created": created,
            "accepted": accepted,
            "duplicates": duplicates,
            "total": len(parsed),
        }
    )


@bp.get("/health")
def health():
    return jsonify({"status": "ok"})
