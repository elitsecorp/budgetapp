import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from budget_server import create_app  # noqa: E402


@pytest.fixture()
def app(tmp_path):
    return create_app(
        {
            "TESTING": True,
            "DATABASE": str(tmp_path / "test.db"),
            "SECRET_KEY": "test-secret",
            "ADMIN_USERNAME": "admin",
            "ADMIN_PASSWORD": "hunter2",
            "API_KEY": "test-key",
        }
    )


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def admin_client(app):
    """A client already logged into the admin console."""
    client = app.test_client()
    with client.session_transaction() as sess:
        sess["admin"] = "admin"
        sess["_csrf"] = "test-csrf"
    return client


@pytest.fixture()
def sample_tx():
    def make(**overrides):
        tx = {
            "sender": "HDFCBK",
            "bank": "HDFC",
            "merchant": "SWIGGY",
            "amount": 499.0,
            "type": "debit",
            "currency": "INR",
            "date_ms": 1764000000000,  # 2025-11-24
            "balance": 12345.67,
            "category": "Food",
            "raw": "Rs.499.00 debited from a/c XX1234 to SWIGGY",
        }
        tx.update(overrides)
        return tx

    return make


def sync(client, payload, key="test-key"):
    return client.post("/api/sync", json=payload, headers={"X-API-Key": key})
