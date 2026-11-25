"""Tests for the admin console: auth, search and statistics."""
from conftest import sync


def test_dashboard_requires_login(client):
    resp = client.get("/admin/")
    assert resp.status_code == 302
    assert "/admin/login" in resp.headers["Location"]


def test_login_and_logout(app):
    client = app.test_client()
    # Wrong password is rejected.
    resp = client.post(
        "/admin/login",
        data={"username": "admin", "password": "nope", "_csrf": _csrf(client)},
    )
    assert resp.status_code == 200
    assert b"Invalid username or password" in resp.data

    # Right password lands on the dashboard.
    resp = client.post(
        "/admin/login",
        data={"username": "admin", "password": "hunter2", "_csrf": _csrf(client)},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Dashboard" in resp.data

    resp = client.post("/admin/logout", follow_redirects=True)
    assert b"Sign in" in resp.data
    assert client.get("/admin/").status_code == 302


def test_login_requires_csrf(client):
    resp = client.post("/admin/login", data={"username": "admin", "password": "hunter2"})
    assert resp.status_code == 400


def test_dashboard_shows_statistics(admin_client, client, sample_tx):
    sync(client, {"phone": "+15551110001", "profile": {"name": "Alice"},
                  "transactions": [sample_tx(), sample_tx(amount=250.0)]})
    resp = admin_client.get("/admin/")
    assert resp.status_code == 200
    assert b"Alice" in resp.data
    assert b"749.00" in resp.data  # 499 + 250 spent


def test_user_search(admin_client, client, sample_tx):
    sync(client, {"phone": "+15551110001", "profile": {"name": "Alice Smith"},
                  "transactions": [sample_tx()]})
    sync(client, {"phone": "+15552220002", "profile": {"name": "Bob Jones"}})

    resp = admin_client.get("/admin/users?q=alice")
    assert b"Alice Smith" in resp.data
    assert b"Bob Jones" not in resp.data

    # Phone search too.
    resp = admin_client.get("/admin/users?q=5552220")
    assert b"Bob Jones" in resp.data
    assert b"Alice Smith" not in resp.data

    resp = admin_client.get("/admin/users?q=zzzz")
    assert b"No users match" in resp.data


def test_user_detail_shows_budget_stats(admin_client, client, sample_tx):
    sync(
        client,
        {
            "phone": "+15551110001",
            "profile": {"name": "Alice"},
            "transactions": [
                sample_tx(),
                sample_tx(amount=100.0, category="Transport", merchant="UBER"),
            ],
        },
    )
    with client.application.app_context():
        from budget_server.db import get_db

        user_id = get_db().execute("SELECT id FROM users").fetchone()["id"]

    resp = admin_client.get(f"/admin/users/{user_id}")
    assert resp.status_code == 200
    assert b"Spent all time" in resp.data
    assert b"Food" in resp.data          # category breakdown
    assert b"Transport" in resp.data
    assert b"SWIGGY" in resp.data        # top merchants
    assert b"badge-debit" in resp.data   # transaction list


def test_unknown_user_is_404(admin_client):
    assert admin_client.get("/admin/users/999").status_code == 404


def test_manual_profile_edit(admin_client, client, sample_tx):
    sync(client, {"phone": "+15551110001", "profile": {"name": "Alice"}})
    with client.application.app_context():
        from budget_server.db import get_db

        user_id = get_db().execute("SELECT id FROM users").fetchone()["id"]

    resp = admin_client.post(
        f"/admin/users/{user_id}/profile",
        data={"_csrf": "test-csrf", "name": "Alice B", "phone": "+15551110001",
              "email": "alice@example.com", "notes": "vip"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Profile saved" in resp.data
    with client.application.app_context():
        from budget_server.db import get_db

        user = get_db().execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        assert user["name"] == "Alice B"
        assert user["notes"] == "vip"


def test_manual_transaction_add(admin_client, client, sample_tx):
    sync(client, {"phone": "+15551110001", "profile": {"name": "Alice"}})
    with client.application.app_context():
        from budget_server.db import get_db

        user_id = get_db().execute("SELECT id FROM users").fetchone()["id"]

    resp = admin_client.post(
        f"/admin/users/{user_id}/transactions",
        data={"_csrf": "test-csrf", "date": "2026-11-20", "amount": "75.50",
              "type": "debit", "merchant": "Cafe", "category": "Food"},
        follow_redirects=True,
    )
    assert b"Transaction added" in resp.data
    with client.application.app_context():
        from budget_server.db import get_db

        row = get_db().execute(
            "SELECT * FROM transactions WHERE merchant = 'Cafe'"
        ).fetchone()
        assert row["amount"] == 75.5


def test_csv_export(admin_client, client, sample_tx):
    sync(client, {"phone": "+15551110001", "transactions": [sample_tx()]})
    with client.application.app_context():
        from budget_server.db import get_db

        user_id = get_db().execute("SELECT id FROM users").fetchone()["id"]

    resp = admin_client.get(f"/admin/users/{user_id}/export")
    assert resp.status_code == 200
    assert resp.mimetype == "text/csv"
    assert b"date,type,amount" in resp.data
    assert b"SWIGGY" in resp.data


def _csrf(client):
    with client.session_transaction() as sess:
        token = sess.get("_csrf")
    if not token:
        client.get("/admin/login")
        with client.session_transaction() as sess:
            token = sess["_csrf"]
    return token
