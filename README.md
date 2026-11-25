# Budget App

A personal budgeting app for Android that reads your bank's SMS alerts,
parses them into transactions, and shows purchase frequency and spending
statistics — **100% on-device, no internet required**.

## Features

- **Transaction details** — tap any transaction for the full breakdown:
  amount, merchant, category, bank, balance-after, contact name, the
  classified *"likely reason"* (e.g. `Food order or dining out`), and the
  **original raw SMS** it was parsed from (selectable + copyable).
- **Classification** — automatic categories: Food & Dining, Groceries,
  Internet & Phone, Bills & Utilities, Transport, Shopping, Entertainment,
  Health, Travel, Salary & Income, Money Transfer.
- **Charts** — switch the dashboard between **Week / Month / Year / All**;
  daily purchase-frequency bars for week & month, monthly spending bars
  for year & all-time, category donut, top merchants.
- **Capture** — live SMS listener + inbox backfill, dedup, works with the
  app closed.
- **Profile detection** — owner name & phone number are mined from the
  messages themselves ("Dear Elias Tsegaye Girmaye …", your number quoted
  repeatedly in telecom SMS), shown and editable in Settings.
- **Contact names** — optional lookup of contact display names for
  numeric senders (READ_CONTACTS).
- **Spending filter** — optionally exclude money transfers and/or
  ignore transactions above an amount, so big internal moves don't skew
  spending stats.
- **App updates** — paste a direct `.apk` link in Settings → the app
  downloads it and opens the system installer.
- **Server export** — Settings has a (modifiable) endpoint URL and a
  **Send** button that POSTs your latest transactions as JSON.

### Supported message formats

Tested against a real 8,644-message corpus: Indian formats (Rs./INR) and
Ethiopian formats (**ETB/Birr**, `dd/mm/yyyy`, CBE/BOA/Dashen/NIB/Gadaa
senders, telebirr, CNETPay POS, EEU utility bills). Guards: OTP rejection,
lender repayment/due-date reminder rejection, UPI/VPA-handle merchants,
parenthesized payees `(Name)`, possessive payees (`to Hana Chala Ibsa's
account`), and expanded balance phrasings (`available limit`,
`current balance`, `outstanding`…).

## How it works

```
SMS arrives on phone
   │
   ▼
SmsReceiver (Kotlin, manifest-declared)         android/app/src/main/kotlin/...
   │  queues to SharedPreferences (survives app being closed)
   │  forwards live over EventChannel
   ▼
Dart ingestion (home_shell.dart) ──► ParserRegistry ──► SQLite ──► StatsEngine ──► UI
                                       (regex per bank)   (sqflite)  (pure Dart)   (fl_chart)
```

- **Ingestion** — `SmsReceiver.kt` captures `SMS_RECEIVED` broadcasts even
  when the app is closed; `MainActivity.kt` exposes them to Dart via an
  `EventChannel`, plus a `MethodChannel` to backfill the existing inbox.
- **Parsing** — `lib/parsers/` extracts amount, direction (debit/credit),
  date, merchant, balance and category. Bank-specific parsers are tried
  first, with a generic fallback. Guards: OTP rejection, lender
  repayment/due-date reminder rejection (the #1 false-positive source in
  open-source parsers), UPI/VPA handle merchants (`to NAME@ybl`),
  expanded balance phrasings (`available limit`, `avbl bal`, `outstanding`…).
- **Storage** — `lib/data/database.dart` (SQLite) with a uniqueness key so
  replayed/duplicate SMS are stored once.
- **Statistics** — `lib/stats/stats_engine.dart`: purchases per day,
  spend per month, monthly totals, averages, top merchants, categories.
- **UI** — Material 3 dashboard, searchable transaction list, detail
  screen, settings.

### Parsing references (open source research)

Patterns and edge cases were adapted from:

- [abdus.net — Parsing Bank SMS with Regex, Classic ML and a Fine-Tuned
  0.5B Model](https://abdus.net/posts/from-regex-to-a-small-language-model)
  — repayment reminders as the biggest false-positive cluster; OTP /
  wallet-top-up rejections; amount-must-appear-in-SMS validation
  (regex captures are inherently literal)
- [saurabhgupta050890/transaction-sms-parser](https://github.com/saurabhgupta050890/transaction-sms-parser)
  — balance keyword list, UPI-handle merchant extraction, debit/credit
  keyword tiers
- [KapilYadav-dev/SmsParser](https://github.com/KapilYadav-dev/SmsParser)
  — 75 KB of bank-by-bank Kotlin regexes (template for adding banks)

## Building

Requires Flutter (tested with 3.50.1) + Android SDK + JDK 17.

```powershell
flutter pub get
flutter test          # parser + stats unit tests
flutter build apk --release
# APK: build\app\outputs\flutter-apk\app-release.apk
```

Install on a phone (USB debugging on):

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

> **Note:** Google Play Protect may warn about sideloaded apps that read
> SMS (it is aggressive about this in India). The APK installs fine from
> file managers after allowing unknown sources; USB install always works.

## First run on a device

1. Open **Settings → Grant SMS access** (Android will ask to allow SMS).
2. Tap **Import SMS history** to parse your existing inbox.
3. New bank alerts are captured automatically from then on.

> **Why sideload?** Google Play does not allow non-default-SMS-handler
> apps to request `READ_SMS`/`RECEIVE_SMS`. This app is distributed as a
> direct APK (e.g. via Telegram), so users just grant the permission when
> asked. All parsing happens locally; no message ever leaves the device.

Some OEMs (Xiaomi, Huawei, Samsung…) kill background processes aggressively.
If messages are only captured while the app is open, whitelist Budget App
in the phone's battery-optimization settings.

## Adding your bank

1. Look at raw messages: temporarily log them, or read
   `SmsReceiver`'s queue — the generic parser already handles most formats:
   `Rs.499.00 debited from a/c XX1234 on 25-11-2026 to MERCHANT via UPI. Avl Bal: Rs.12,345.67`
2. If your bank's wording differs, add a parser in
   `lib/parsers/sms_parser.dart` (see `BankParser`) and register it in
   `ParserRegistry`.
3. Add a sample SMS to `test/sms_parser_test.dart` and run `flutter test`.

## Project layout

```
lib/
├── main.dart                    # App entry, theme
├── models/models.dart           # SmsMessage, Transaction
├── parsers/                     # SMS → Transaction (extractors + registry)
├── data/database.dart           # SQLite storage
├── services/sms_service.dart    # Platform channels + permissions
├── providers/                   # Riverpod state
├── stats/stats_engine.dart      # Aggregations (unit-tested)
├── screens/                     # Dashboard, transactions, settings
└── util/                        # Formatting, import helper
android/app/src/main/kotlin/com/budgetapp/budget_app/
├── MainActivity.kt              # EventChannel + MethodChannel
└── SmsReceiver.kt               # SMS broadcast capture + queue
```
