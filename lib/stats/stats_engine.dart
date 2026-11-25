/// Pure aggregation functions over parsed transactions — kept separate from
/// UI so the statistics are easy to unit-test.
library;

import '../models/models.dart';

class DayFrequency {
  final DateTime day;
  final int count;
  final double amount;
  const DayFrequency(this.day, this.count, this.amount);
}

class MerchantStat {
  final String name;
  final int count;
  final double total;
  const MerchantStat(this.name, this.count, this.total);
}

class CategoryStat {
  final String name;
  final int count;
  final double total;
  const CategoryStat(this.name, this.count, this.total);
}

class MonthTotal {
  final DateTime month; // first day of the month
  final int count;
  final double amount;
  const MonthTotal(this.month, this.count, this.amount);
}

class StatsEngine {
  StatsEngine._();

  static bool _inWindow(DateTime d, DateTime? from, DateTime? to) {
    if (from != null && d.isBefore(from)) return false;
    if (to != null && !d.isBefore(to)) return false;
    return true;
  }

  /// Debit count (and spend) per day for the last [days] days, oldest first.
  static List<DayFrequency> purchaseFrequency(
    List<Transaction> tx, {
    int days = 30,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final start =
        DateTime(ref.year, ref.month, ref.day).subtract(Duration(days: days - 1));
    final byDay = <DateTime, DayFrequency>{};
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      byDay[d] = DayFrequency(d, 0, 0);
    }
    for (final t in tx) {
      if (t.type != TxType.debit) continue;
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final cur = byDay[d];
      if (cur != null) {
        byDay[d] = DayFrequency(d, cur.count + 1, cur.amount + t.amount);
      }
    }
    return byDay.values.toList(growable: false);
  }

  static double sum(
    List<Transaction> tx,
    TxType type, {
    DateTime? from,
    DateTime? to,
  }) {
    var total = 0.0;
    for (final t in tx) {
      if (t.type != type) continue;
      if (!_inWindow(t.date, from, to)) continue;
      total += t.amount;
    }
    return total;
  }

  static double monthSpend(List<Transaction> tx, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final start = DateTime(ref.year, ref.month, 1);
    final end = DateTime(ref.year, ref.month + 1, 1);
    return sum(tx, TxType.debit, from: start, to: end);
  }

  static double monthReceived(List<Transaction> tx, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final start = DateTime(ref.year, ref.month, 1);
    final end = DateTime(ref.year, ref.month + 1, 1);
    return sum(tx, TxType.credit, from: start, to: end);
  }

  static double averagePurchase(
    List<Transaction> tx, {
    int days = 30,
    DateTime? now,
  }) {
    final freq = purchaseFrequency(tx, days: days, now: now);
    var count = 0;
    var total = 0.0;
    for (final d in freq) {
      count += d.count;
      total += d.amount;
    }
    return count == 0 ? 0 : total / count;
  }

  /// Debit totals per calendar month, oldest first.
  /// [months] = null → every month present in the data.
  static List<MonthTotal> monthlySpend(
    List<Transaction> tx, {
    int? months,
    TxType type = TxType.debit,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final DateTime startMonth;
    if (months != null) {
      startMonth = DateTime(ref.year, ref.month - (months - 1), 1);
    } else {
      var earliest = ref;
      for (final t in tx) {
        if (t.date.isBefore(earliest)) earliest = t.date;
      }
      startMonth = DateTime(earliest.year, earliest.month, 1);
    }
    final endMonth = DateTime(ref.year, ref.month, 1);

    final buckets = <DateTime, (int, double)>{};
    for (var m = startMonth;
        !m.isAfter(endMonth);
        m = DateTime(m.year, m.month + 1, 1)) {
      buckets[m] = (0, 0.0);
    }
    for (final t in tx) {
      if (t.type != type) continue;
      final m = DateTime(t.date.year, t.date.month, 1);
      final cur = buckets[m];
      if (cur != null) buckets[m] = (cur.$1 + 1, cur.$2 + t.amount);
    }
    return [
      for (final e in buckets.entries)
        MonthTotal(e.key, e.value.$1, e.value.$2),
    ];
  }

  /// Spend grouped by category (largest first).
  static List<CategoryStat> byCategory(
    List<Transaction> tx, {
    TxType type = TxType.debit,
    int? days,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final from = days == null
        ? null
        : DateTime(ref.year, ref.month, ref.day).subtract(Duration(days: days - 1));
    final counts = <String, (int, double)>{};
    for (final t in tx) {
      if (t.type != type) continue;
      if (!_inWindow(t.date, from, null)) continue;
      final key = t.category ?? 'Other';
      final cur = counts[key] ?? (0, 0.0);
      counts[key] = (cur.$1 + 1, cur.$2 + t.amount);
    }
    final out = [
      for (final e in counts.entries) CategoryStat(e.key, e.value.$1, e.value.$2),
    ];
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// Highest-spending merchants (largest first).
  static List<MerchantStat> topMerchants(
    List<Transaction> tx, {
    int limit = 5,
    TxType type = TxType.debit,
    int? days,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final from = days == null
        ? null
        : DateTime(ref.year, ref.month, ref.day).subtract(Duration(days: days - 1));
    final counts = <String, (int, double)>{};
    for (final t in tx) {
      if (t.type != type) continue;
      if (!_inWindow(t.date, from, null)) continue;
      final key = (t.merchant ?? t.bank).trim();
      if (key.isEmpty) continue;
      final cur = counts[key] ?? (0, 0.0);
      counts[key] = (cur.$1 + 1, cur.$2 + t.amount);
    }
    final out = [
      for (final e in counts.entries) MerchantStat(e.key, e.value.$1, e.value.$2),
    ];
    out.sort((a, b) => b.total.compareTo(a.total));
    return out.take(limit).toList();
  }
}
