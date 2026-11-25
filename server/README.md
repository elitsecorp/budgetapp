# Budget Server

Flask backend for the Budget App: the Android APK uploads parsed transactions,
each user gets a profile, and an admin console shows search + budgeting
statistics.

```
Android app (parses SMS) ──POST /api/sync──► Flask ──SQLite──► Admin console
                                             (dedupes)          /admin (login)
```

## Quick start

```powershell
cd server
pip install -r requirements.txt
$env:ADMIN_PASSWORD = "change-me"     # admin console password (default: admin)
$env:API_KEY = "some-long-random-key" # shared secret the APK must send
python run.py                         # http://127.0.0.1:5000
```

Open http://127.0.0.1:5000 — it redirects to the admin login.
Username defaults to `admin` (`ADMIN_USERNAME` to change).

> Both default credentials are logged as warnings on startup. **Set them before
> hosting this anywhere public.**

## Configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `ADMIN_USERNAME` | `admin` | Admin console username |
| `ADMIN_PASSWORD` | `admin` | Admin console password — change this |
| `API_KEY` | *(empty)* | `X-API-Key` the APK must send; empty = no auth (dev only) |
| `SECRET_KEY` | random per start | Session signing; set for stable logins across restarts |
| `BUDGET_DB` | `instance/budget.db` | SQLite database path |
| `HOST` / `PORT` | `127.0.0.1` / `5000` | Bind address |
| `FLASK_DEBUG` | off | `1` enables the debug reloader |

## API (called by the Android app)

### `POST /api/sync`

Headers: `X-API-Key: <API_KEY>`, `Content-Type: application/json`

```json
{
  "phone": "+15551234567",
  "device_id": "sdk_gphone64",
  "profile": { "name": "Jane Doe", "email": "jane@example.com" },
  "transactions": [
    {
      "sender": "HDFCBK",
      "bank": "HDFC",
      "merchant": "SWIGGY",
      "amount": 499.0,
      "type": "debit",
      "currency": "INR",
      "date_ms": 1764000000000,
      "balance": 12345.67,
      "category": "Food",
      "raw": "Rs.499.00 debited from a/c XX1234 to SWIGGY",
      "dedupe": "HDFCBK|1764000000000|499.0|Rs.499.00 debited..."
    }
  ]
}
```

- **Identity is the phone number.** The user is found or created by `phone`;
  `profile` fields update the profile on every sync (blank = leave unchanged).
- **Dedup:** send the same `dedupe` key the app already computes
  (`sender|date_ms|amount|raw` — see `lib/models/models.dart`). Replays are
  counted, not stored, so "wait a few seconds then send everything" is safe.
  If `dedupe` is omitted, the server computes the same key.
- `date_ms` is epoch **milliseconds** (what Dart's `millisecondsSinceEpoch`
  produces). Epoch seconds and ISO-8601 strings in `date` are also accepted.
- Amounts must be positive; `type` is `debit` or `credit`.
- If **any** transaction is invalid the whole batch is rejected with
  `400 {"error": "invalid transactions", "details": [{"index": …, "error": …}]}` —
  fix and resend; nothing is half-stored.

Response `200`:

```json
{ "user_id": 3, "created": false, "accepted": 12, "duplicates": 3, "total": 15 }
```

### `GET /api/health`

No auth. Returns `{"status": "ok"}` — use it for uptime checks.

## Admin console (`/admin`)

- **Dashboard** — user/transaction counts, spend this month, 30-day and
  12-month spend charts, top spenders, newest users.
- **Users** — search by name, phone or email; per-user monthly/all-time spend;
  create profiles manually.
- **User page** — profile editing, spend/received/avg-purchase/balance cards,
  daily + monthly charts, category breakdown, top merchants, latest 100
  transactions, manual entry, CSV export.

All state-changing forms carry a per-session CSRF token.

## Running tests

```powershell
python -m pytest tests -q
```

## Production notes

- Behind a reverse proxy (nginx/Caddy), terminate TLS there and set
  `SECRET_KEY` so admin sessions survive restarts.
- The database is plain SQLite with WAL enabled — fine for a personal-scale
  deployment; back up `instance/budget.db`.
- Day/month buckets use the **server's local timezone**; run it in your users'
  timezone (or set `TZ`) so daily stats line up with what people expect.

## Layout

```
server/
├── run.py                    # dev entry point
├── requirements.txt
├── budget_server/
│   ├── __init__.py           # app factory + config
│   ├── db.py                 # SQLite schema/connections
│   ├── models.py             # users & transactions queries
│   ├── stats.py              # aggregations (mirrors lib/stats/stats_engine.dart)
│   ├── auth.py               # admin login, CSRF
│   ├── api.py                # /api/sync for the APK
│   ├── admin.py              # console routes
│   ├── templates/            # Jinja pages
│   └── static/style.css
└── tests/                    # pytest suite (19 tests)
```
