import 'package:budget_app/models/models.dart';
import 'package:budget_app/stats/stats_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction tx({
  required double amount,
  TxType type = TxType.debit,
  required DateTime date,
  String merchant = 'MERCHANT',
  String? category,
}) =>
    Transaction(
      sender: 'SENDER',
      bank: 'BANK',
      merchant: merchant,
      amount: amount,
      type: type,
      date: date,
      category: category,
      raw: 'raw',
    );

void main() {
  final now = DateTime(2026, 11, 25);
  final list = [
    tx(amount: 100, date: DateTime(2026, 11, 25, 10),
        merchant: 'A', category: 'Food'),
    tx(amount: 200, date: DateTime(2026, 11, 25, 18),
        merchant: 'A', category: 'Food'),
    tx(amount: 50, type: TxType.credit, date: DateTime(2026, 11, 25, 12)),
    tx(amount: 250, date: DateTime(2026, 11, 10),
        merchant: 'B', category: 'Travel'),
    tx(amount: 400, date: DateTime(2026, 10, 30), merchant: 'X'),
  ];

  group('StatsEngine', () {
    test('monthSpend counts only debits of the current month', () {
      expect(StatsEngine.monthSpend(list, now: now), 550);
      expect(StatsEngine.monthReceived(list, now: now), 50);
    });

    test('purchaseFrequency buckets debits per day', () {
      final freq = StatsEngine.purchaseFrequency(list, days: 30, now: now);
      expect(freq.length, 30);

      final nov25 = freq.firstWhere((d) => d.day == DateTime(2026, 11, 25));
      expect(nov25.count, 2);
      expect(nov25.amount, 300);

      final nov10 = freq.firstWhere((d) => d.day == DateTime(2026, 11, 10));
      expect(nov10.count, 1);

      final total = freq.fold<int>(0, (s, d) => s + d.count);
      expect(total, 4); // includes 30 Oct, inside the 30-day window
    });

    test('averagePurchase divides window spend by purchase count', () {
      // (100 + 200 + 250 + 400) / 4
      expect(StatsEngine.averagePurchase(list, now: now), 237.5);
    });

    test('topMerchants sorts by spend', () {
      final top = StatsEngine.topMerchants(list, limit: 5, now: now);
      expect(top.length, 3);
      expect(top.first.name, 'X');
      expect(top.first.total, 400);
      expect(top.first.count, 1);
    });

    test('byCategory groups debits, largest first', () {
      final cats = StatsEngine.byCategory(list, now: now);
      expect(cats.first.name, 'Other'); // 400 with no category
      expect(cats.first.total, 400);

      final food = cats.firstWhere((c) => c.name == 'Food');
      expect(food.total, 300);
      expect(food.count, 2);
    });

    test('monthlySpend buckets debits per calendar month', () {
      final months = StatsEngine.monthlySpend(list, now: now);
      expect(months.length, 2);
      expect(months.first.month, DateTime(2026, 10));
      expect(months.first.amount, 400);
      expect(months.last.month, DateTime(2026, 11));
      expect(months.last.amount, 550);
      expect(months.last.count, 3);

      // Limited window: only the current month.
      final nov = StatsEngine.monthlySpend(list, months: 1, now: now);
      expect(nov.length, 1);
      expect(nov.single.amount, 550);
    });
  });
}
