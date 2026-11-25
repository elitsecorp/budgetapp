"""Tests for the device sync API: auth, validation and deduplication."""
from conftest import sync


def test_health_needs_no_key(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_sync_requires_api_key(client, sample_tx):
    resp = client.post("/api/sync", json={"phone": "+10000000000", "transactions": [sample_tx()]})
    assert resp.status_code == 401
    resp = sync(client, {"phone": "+10000000000", "transactions": [sample_tx()]}, key="wrong")
    assert resp.status_code == 401


def test_sync_requires_phone(client, sample_tx):
    resp = sync(client, {"transactions": [sample_tx()]})
    assert resp.status_code == 400
    assert "phone" in resp.get_json()["error"]


def test_sync_creates_user_and_stores(client, sample_tx):
    resp = sync(
        client,
        {
            "phone": "+15551234567",
            "profile": {"name": "Jane Doe", "email": "jane@example.com"},
            "transactions": [sample_tx()],
        },
    )
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["created"] is True
    assert body["accepted"] == 1
    assert body["duplicates"] == 0

    with client.application.app_context():
        from budget_server.db import get_db

        user = get_db().execute("SELECT * FROM users").fetchone()
        assert user["name"] == "Jane Doe"
        assert user["phone"] == "+15551234567"
        tx = get_db().execute("SELECT * FROM transactions").fetchone()
        assert tx["amount"] == 499.0
        assert tx["type"] == "debit"
        assert tx["date"] == 1764000000000


def test_sync_deduplicates_replays(client, sample_tx):
    payload = {"phone": "+15551234567", "transactions": [sample_tx(), sample_tx(amount=120.0)]}
    first = sync(client, payload).get_json()
    assert (first["accepted"], first["duplicates"]) == (2, 0)

    # The app re-sends the same batch after opening again.
    second = sync(client, payload).get_json()
    assert (second["accepted"], second["duplicates"]) == (0, 2)
    assert second["user_id"] == first["user_id"]


def test_sync_updates_profile_on_existing_user(client, sample_tx):
    sync(client, {"phone": "+15551234567", "profile": {"name": "Old Name"}})
    resp = sync(client, {"phone": "+15551234567", "profile": {"name": "New Name"}})
    assert resp.get_json()["created"] is False
    with client.application.app_context():
        from budget_server.db import get_db

        user = get_db().execute("SELECT name FROM users").fetchone()
        assert user["name"] == "New Name"


def test_sync_rejects_invalid_transactions_atomically(client, sample_tx):
    bad = [sample_tx(), sample_tx(type="refund"), sample_tx(amount=-5)]
    resp = sync(client, {"phone": "+15551234567", "transactions": bad})
    assert resp.status_code == 400
    details = resp.get_json()["details"]
    assert len(details) == 2
    # Nothing stored when any row is invalid.
    with client.application.app_context():
        from budget_server.db import get_db

        count = get_db().execute("SELECT COUNT(*) AS n FROM transactions").fetchone()["n"]
        assert count == 0


def test_sync_accepts_android_app_payload(client, sample_tx):
    """The APK sends `owner: {name, phone}` rather than top-level phone/profile."""
    resp = sync(
        client,
        {
            "owner": {"name": "Elias Tsegaye", "phone": "+251911223344"},
            "sentAt": "2026-11-26T01:20:00.000",
            "count": 1,
            "transactions": [sample_tx()],
        },
    )
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["created"] is True
    assert body["accepted"] == 1
    with client.application.app_context():
        from budget_server.db import get_db

        user = get_db().execute("SELECT * FROM users").fetchone()
        assert user["phone"] == "+251911223344"
        assert user["name"] == "Elias Tsegaye"


def test_sync_accepts_iso_date_and_computes_dedupe(client, sample_tx):
    tx = sample_tx(date_ms=None, date="2026-01-15T10:30:00")
    tx.pop("date_ms")
    resp = sync(client, {"phone": "+15551234567", "transactions": [tx]})
    assert resp.status_code == 200
    with client.application.app_context():
        from budget_server.db import get_db

        row = get_db().execute("SELECT date, dedupe FROM transactions").fetchone()
        assert row["date"] > 0
        assert row["dedupe"].startswith("HDFCBK|")


def test_sync_accepts_epoch_seconds(client, sample_tx):
    tx = sample_tx(date_ms=None, date=1764000000)  # seconds, not ms
    tx.pop("date_ms")
    resp = sync(client, {"phone": "+15551234567", "transactions": [tx]})
    assert resp.status_code == 200
    with client.application.app_context():
        from budget_server.db import get_db

        row = get_db().execute("SELECT date FROM transactions").fetchone()
        assert row["date"] == 1764000000000
