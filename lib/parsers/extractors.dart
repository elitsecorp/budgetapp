/// Regex-based extraction of structured fields from raw bank SMS text.
///
/// These are pure functions so they can be unit-tested against real
/// (anonymized) SMS samples — see test/extractors_test.dart.
library;

import '../models/models.dart';

class AmountResult {
  final double value;
  final bool negative;
  final String currency;
  const AmountResult(this.value, this.negative, this.currency);
}

// Note: word-boundaries around currency codes are intentionally loose so
// formats like "INR1234" and "Rs.1,234.56" both work. This can rarely match
// a substring like "orders 500"; bank-specific parsers can tighten this later.
final _currencyAmountRe = RegExp(
  r'(?:rs\.?|inr|usd|eur|gbp|aud|cad|sgd|aed|etb(?=[\s\d])|birr(?=[\s\d])|ksh(?=[\s\d])|[₹$€£])\s*(-?[\d,]+(?:\.\d{1,2})?)',
  caseSensitive: false,
);

final _negCurrencyRe = RegExp(
  r'-\s*(?:rs\.?|inr|usd|eur|gbp|[₹$€£])',
  caseSensitive: false,
);

final _bareAmountRe =
    RegExp(r'\b(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+\.\d{1,2})\b');

const _maxReasonableAmount = 100000000.0;

AmountResult? extractAmount(String body) {
  final m = _currencyAmountRe.firstMatch(body);
  if (m != null) {
    final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (value != null && value > 0 && value < _maxReasonableAmount) {
      final negative = m.group(1)!.startsWith('-') || _negCurrencyRe.hasMatch(body);
      return AmountResult(value, negative, _currencyOf(m.group(0)!));
    }
  }

  final b = _bareAmountRe.firstMatch(body);
  if (b != null) {
    final value = double.tryParse(b.group(1)!.replaceAll(',', ''));
    if (value != null && value > 0 && value < _maxReasonableAmount) {
      final before =
          b.start > 0 ? body[b.start - 1] : '';
      return AmountResult(value, before == '-', '');
    }
  }
  return null;
}

String _currencyOf(String matched) {
  final s = matched.toLowerCase();
  if (s.contains('etb') || s.contains('birr')) return 'ETB';
  if (s.contains('ksh')) return 'KES';
  if (s.contains('rs') || s.contains('inr') || s.contains('₹')) return 'INR';
  if (s.contains(r'$') || s.contains('usd')) return 'USD';
  if (s.contains('€') || s.contains('eur')) return 'EUR';
  if (s.contains('£') || s.contains('gbp')) return 'GBP';
  return '';
}

final _debitRe = RegExp(
  r'\b(debited|debit|deducted|withdrawn|withdrawal|spent|purchase|paid|payment|charged|booked|used\s+at|sent|transferred|deb)\b',
  caseSensitive: false,
);
final _creditRe = RegExp(
  r'\b(credited|credit|deposited|deposit|received|refund|refunded|added|repayment|cr)\b',
  caseSensitive: false,
);

/// Returns null when the SMS does not clearly indicate direction.
TxType? extractType(String body) {
  final d = _debitRe.firstMatch(body);
  final c = _creditRe.firstMatch(body);
  if (d == null && c == null) return null;
  if (d == null) return TxType.credit;
  if (c == null) return TxType.debit;
  // The keyword appearing first in the sentence usually governs the meaning.
  return d.start <= c.start ? TxType.debit : TxType.credit;
}

final _isoDateRe = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _dmyDateRe = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
final _textDateRe = RegExp(
  r'\b(\d{1,2})[\s-](Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s-](\d{2,4})\b',
  caseSensitive: false,
);
final _timeRe = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?');

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Extracts the transaction date from the body, falling back to the SMS
/// timestamp when the message carries none.
DateTime extractDate(String body, DateTime fallback) {
  DateTime? date;

  final iso = _isoDateRe.firstMatch(body);
  if (iso != null) {
    date = _validDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
    if (date != null) date = _withTime(body, iso, date);
  }

  if (date == null) {
    final m = _dmyDateRe.firstMatch(body);
    if (m != null) {
      final g1 = int.parse(m.group(1)!);
      final g2 = int.parse(m.group(2)!);
      if (!(g1 > 12 && g2 > 12)) {
        // Day-first by default; month-first only when field 2 > 12.
        final monthFirst = g2 > 12;
        final day = monthFirst ? g2 : g1;
        final month = monthFirst ? g1 : g2;
        final yearRaw = m.group(3)!;
        final year =
            yearRaw.length == 2 ? 2000 + int.parse(yearRaw) : int.parse(yearRaw);
        final d = _validDate(year, month, day);
        if (d != null) date = _withTime(body, m, d);
      }
    }
  }

  if (date == null) {
    final m = _textDateRe.firstMatch(body);
    if (m != null) {
      final month = _months[m.group(2)!.toLowerCase()]!;
      final yearRaw = m.group(3)!;
      final year =
          yearRaw.length == 2 ? 2000 + int.parse(yearRaw) : int.parse(yearRaw);
      final d = _validDate(year, month, int.parse(m.group(1)!));
      if (d != null) date = _withTime(body, m, d);
    }
  }

  return date ?? fallback;
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  // Rejects impossible dates like 31 Feb.
  if (d.month != month || d.day != day) return null;
  return d;
}

DateTime? _withTime(String body, Match dateMatch, DateTime date) {
  final tail = body.substring(dateMatch.end);
  final t = _timeRe.firstMatch(tail.length > 16 ? tail.substring(0, 16) : tail);
  if (t == null) return date;
  final hour = int.parse(t.group(1)!);
  final minute = int.parse(t.group(2)!);
  final second = t.group(3) == null ? 0 : int.parse(t.group(3)!);
  if (hour > 23 || minute > 59) return date;
  return DateTime(date.year, date.month, date.day, hour, minute, second);
}

// Merchant patterns: UPI/VPA handles first ("to SWIGGY@ybl"), then
// possessive payees ("to Hana Chala Ibsa's account"), then "to X",
// ALL-CAPS company after "for", then "at/by X", "from X", and finally a
// parenthesized payee ("(Mussie Tsegaye Girmay)" — CBE style).
final _vpaRe = RegExp(
  r'\b(?:to|vpa|paid\s+to)\s*\(?\s*([A-Za-z0-9][A-Za-z0-9._\- ]{1,30}?)\s*@',
  caseSensitive: false,
);
final _toPossessiveRe = RegExp(
  r"\bto\s+([A-Za-z][A-Za-z0-9 .'/_-]{2,40}?)\s*'s\b",
  caseSensitive: false,
);
final _forCompanyRe = RegExp(
  r"\bfor\s+([A-Z][A-Z0-9 &.'/_-]{2,40}?)(?=[,]|\s+on\b|\s+at\b)",
);
final _parenPayeeRe = RegExp(r"\(([A-Za-z][A-Za-z0-9 .'/_-]{2,40})\)");
final _toMerchantRe = RegExp(
  r"\bto\s+([A-Za-z0-9&.'\-_ /]{2,40}?)(?=\s+via\b|\s+upi\b|\s+on\b|\s+for\b|[,.;:\n]|\s*$)",
  caseSensitive: false,
);
final _atMerchantRe = RegExp(
  r"\b(?:at|by)\s+([A-Za-z0-9&.'\-_ /]{2,40}?)(?=\s+on\b|\s+via\b|[,.;:\n]|\s*$)",
  caseSensitive: false,
);
final _fromMerchantRe = RegExp(
  r"\bfrom\s+([A-Za-z0-9&.'\-_ /]{2,40}?)(?=\s+on\b|[,.;:\n]|\s*$)",
  caseSensitive: false,
);

const _junkMerchants = {
  'a/c', 'acct', 'account', 'via', 'upi', 'no', 'ref', 'xx', 'your', 'the',
  'to', 'at', 'from', 'on', 'for', 'inr', 'rs', 'usd', 'card', 'acc',
};

// Verbs that start instruction phrases ("to download your receipt").
const _junkVerbs = {
  'download', 'view', 'click', 'check', 'see', 'call', 'visit', 'apply',
  'download your', 'view your', 'check your', 'read',
};

String? extractMerchant(String body) {
  for (final re in [
    _vpaRe,
    _toPossessiveRe,
    _toMerchantRe,
    _forCompanyRe,
    _atMerchantRe,
    _fromMerchantRe,
    _parenPayeeRe,
  ]) {
    for (final m in re.allMatches(body)) {
      final cleaned = _cleanMerchant(m.group(1)!);
      if (cleaned != null) return cleaned;
    }
  }
  return null;
}

String? _cleanMerchant(String raw) {
  var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r"[.,;:]+$"), '');
  s = s.split(RegExp(r'\s+via\s+', caseSensitive: false)).first.trim();
  if (s.length < 2) return null;
  final low = s.toLowerCase();
  if (_junkMerchants.contains(low)) return null;
  if (_junkVerbs.contains(low) ||
      _junkVerbs.contains(low.split(' ').first)) {
    return null;
  }
  if (low.startsWith('your') ||
      low.startsWith('account') ||
      low.startsWith('acct') ||
      low.startsWith('a/c')) {
    return null;
  }
  if (RegExp(r'^[x\d\s]+$').hasMatch(s)) return null; // XX1234 / 123456
  return s;
}

final _balanceRe = RegExp(
  r'(?:(?:avl|avbl)(?:\.?\s*bal(?:ance)?|\s*lmt|\s*limit)?|a/c\s*bal|avail(?:able)?(?:\s*bal(?:ance)?|\s*limit|\s*credit\s*limit)|total\s*bal(?:ance)?|new\s*bal(?:ance)?|updated\s*bal(?:ance)?|current\s+bal(?:ance)?|outstanding\s*(?:limit|amount)?|balance)\s*(?:is|of|:)?\s*(?:rs\.?|inr|₹|usd|\$|etb(?=[\s\d])|birr(?=[\s\d])|ksh(?=[\s\d]))?\s*([\d,]+(?:\.\d{1,2})?)',
  caseSensitive: false,
);

double? extractBalance(String body) {
  final m = _balanceRe.firstMatch(body);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

final _otpRe = RegExp(
  r'\b(otp|one[\s-]?time[\s-]?password|verification code|auth(?:entication)? code)\b',
  caseSensitive: false,
);

// The word "OTP" alone isn't enough — payment confirmations say things
// like "paid … by telebirr SMS OTP". Only reject when an actual code is
// being delivered (digit next to "is"/":" or a sharing/expiry warning).
final _otpCodeRe = RegExp(
  r"(?:is|:)\s*\d{4,8}\b|\b\d{4,8}\s+is\b|do\s+n[o']?t\s+share|"
  r'never\s+share|expires?\s+in|valid\s+for\s+\d',
  caseSensitive: false,
);

bool looksLikeOtp(String body) =>
    _otpRe.hasMatch(body) && _otpCodeRe.hasMatch(body);

// Lender reminders ("kindly repay Rs.4,735 due on 30-11") were the single
// biggest source of false transactions in open-source parsers (see
// abdus.net's Spends writeup) — money is NOT moving in these.
final _reminderRe = RegExp(
  r'\b(kindly\s+repay|repayment\s+due|payment\s+due|due\s+on|due\s+date|last\s+date\s+to|overdue|please\s+pay|minimum\s+due|outstanding\s+due|pay\s+by\s+the|remind(?:er)?)\b',
  caseSensitive: false,
);

bool looksLikeReminder(String body) => _reminderRe.hasMatch(body);

/// Keyword → category rules, most specific first.
const categoryRules = <String, List<String>>{
  'Food & Dining': [
    'swiggy', 'zomato', 'restaurant', 'cafe', 'coffee', 'mcdonald', 'kfc',
    'dominos', 'pizza', 'burger', 'food', 'eatery', 'biryani', 'dhaba',
  ],
  'Groceries': [
    'bigbasket', 'blinkit', 'grofers', 'grocery', 'dmart', 'supermarket',
    'kirana', 'vegetables', 'mart',
  ],
  'Shopping': [
    'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'shopping', 'mall',
    'store', 'shop', 'nike', 'zara', 'ikea',
  ],
  'Transport': [
    'uber', 'ola', 'rapido', 'petrol', 'fuel', 'metro', 'fastag', 'irctc',
    'taxi', 'cab', 'parking', 'toll',
  ],
  'Entertainment': [
    'netflix', 'spotify', 'hotstar', 'prime video', 'movie', 'bookmyshow',
    'cinema', 'game', 'youtube premium',
  ],
  'Health': [
    'pharmacy', 'hospital', 'medical', 'apollo', 'clinic', 'doctor',
    'medicine', '1mg', 'pharmeasy',
  ],
  'Internet & Phone': [
    'internet', 'wifi', 'broadband', 'fiber', 'fibre', 'airtel', 'jio',
    'vodafone', 'bsnl', 'recharge', 'postpaid', 'prepaid', 'mobile',
    'hathway', 'act fibernet', 'data pack',
  ],
  'Bills & Utilities': [
    'electricity', 'water bill', 'gas bill', 'lpg', 'bill payment',
    'utility', 'sewerage', 'maintenance',
  ],
  'Travel': [
    'airline', 'indigo', 'makemytrip', 'goibibo', 'booking.com', 'oyo',
    'hotel', 'flight', 'irctc',
  ],
  'Salary & Income': ['salary', 'payroll', 'interest', 'cashback', 'refund'],
  'Family Support': [
    'family', 'mom', 'dad', 'mother', 'father', 'parents', 'brother',
    'sister',
  ],
  'Loan': ['loan', 'emi', 'installment', 'principal', 'lender'],
  // Keep last: almost every SMS mentions UPI/transfer.
  'Money Transfer': [
    'upi', 'imps', 'neft', 'rtgs', 'transfer', 'transferred', 'sent to',
  ],
};

/// Every category the app knows (built-in detection order) plus "Other".
final allCategories = <String>[...categoryRules.keys, 'Other'];

// Compiled once: keyword → word-boundary pattern. Word boundaries stop
// "mom" from matching inside "moment" and "emi" inside "premium".
final _categoryPatterns = {
  for (final entry in categoryRules.entries)
    entry.key: [
      for (final kw in entry.value)
        RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false),
    ],
};

String inferCategory(String? merchant, String body) {
  final hay = '${merchant ?? ''} $body'.toLowerCase();
  for (final entry in _categoryPatterns.entries) {
    for (final pattern in entry.value) {
      if (pattern.hasMatch(hay)) return entry.key;
    }
  }
  return 'Other';
}

/// Bank identification from the sender ID (alphanumeric senders like
/// "HDFCBK", "SBIPPG", or a phone number we can't identify).
const bankMarkers = <(List<String>, String)>[
  // Ethiopia
  (['CBE'], 'Commercial Bank of Ethiopia'),
  (['BOA', 'ABYSSINIA'], 'Bank of Abyssinia'),
  (['AWACH'], 'Awash SACCO'),
  (['AWASH'], 'Awash Bank'),
  (['DASHEN', 'DB SUPERAPP'], 'Dashen Bank'),
  (['NIB'], 'NIB Bank'),
  (['GADAA'], 'Gadaa Bank'),
  (['LION'], 'Lion Bank'),
  (['ZEMEN'], 'Zemen Bank'),
  (['ABAY'], 'Abay Bank'),
  (['OROMIA'], 'Oromia Bank'),
  (['AMHARA'], 'Amhara Bank'),
  (['CNETPAY'], 'CNETPay'),
  (['EEU'], 'Ethio Electric Utility'),
  (['USP'], 'USP Parking'),
  (['TELEBIRR'], 'telebirr'),
  (['MPESA'], 'M-PESA'),
  (['SAFARICOM'], 'Safaricom'),
  // India
  (['HDFC'], 'HDFC Bank'),
  (['ICICI', 'ICIC'], 'ICICI Bank'),
  (['SBIN', 'SBIIN', 'SBIP', 'SBI'], 'State Bank of India'),
  (['KKBK', 'KOTAK'], 'Kotak Mahindra Bank'),
  (['AXBK', 'AXIS'], 'Axis Bank'),
  (['PNBS', 'PUNB'], 'Punjab National Bank'),
  (['CNRB'], 'Canara Bank'),
  (['BARB'], 'Bank of Baroda'),
  (['YESB'], 'Yes Bank'),
  (['IDFB', 'IDFC'], 'IDFC First Bank'),
  (['INDUS', 'INDB'], 'IndusInd Bank'),
  (['AUBK'], 'AU Small Finance Bank'),
  (['FDRL'], 'Federal Bank'),
];

/// User-assigned labels for senders (lowercased sender → display name),
/// loaded from Settings at startup — lets the user rename any number to
/// its bank/institution ("251994" → "Ethio Telecom").
final Map<String, String> senderLabels = {};

String detectBank(String sender) {
  final custom = senderLabels[sender.toLowerCase()];
  if (custom != null && custom.isNotEmpty) return custom;
  final s = sender.toUpperCase();
  for (final (markers, name) in bankMarkers) {
    if (markers.any(s.contains)) return name;
  }
  return sender;
}
