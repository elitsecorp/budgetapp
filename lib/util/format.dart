import 'package:intl/intl.dart';

import '../models/models.dart';

String currencySymbol(String currency) {
  switch (currency.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    default:
      return '';
  }
}

/// Best-effort symbol for a group of transactions (first non-empty wins).
String symbolFor(List<Transaction> tx) {
  for (final t in tx) {
    final s = currencySymbol(t.currency);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// First non-empty currency code in the list (e.g. 'INR'), or ''.
String currencyFor(List<Transaction> tx) {
  for (final t in tx) {
    if (t.currency.isNotEmpty) return t.currency;
  }
  return '';
}

String formatMoney(double v, {String currency = '', bool showSign = false}) {
  final symbol = currencySymbol(currency);
  final n = NumberFormat('#,##0.00').format(v);
  final sign = showSign ? (v >= 0 ? '+' : '-') : '';
  final body = symbol.isEmpty ? n : '$symbol$n';
  return '$sign$body';
}

String formatDay(DateTime d) => DateFormat('d MMM yyyy').format(d);

String formatTime(DateTime d) => DateFormat('HH:mm').format(d);

String formatDayTime(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);
