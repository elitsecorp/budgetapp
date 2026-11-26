import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/transaction_providers.dart';
import '../stats/stats_engine.dart';
import '../util/format.dart';

/// Reports tab: money flow (month/year/all-time), monthly spent-vs-received
/// trend, and spending broken down by category over time.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
        child: txAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.only(top: 120),
            children: const [Center(child: CircularProgressIndicator())],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [Text('Could not load data: $e')],
          ),
          data: (tx) => tx.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 60),
                    Text(
                      'No data yet — import your SMS in Settings.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                )
              : _buildBody(context, tx),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Transaction> tx) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currency = currencyFor(tx);

    final monthFrom = DateTime(now.year, now.month, 1);
    final yearFrom = DateTime(now.year, 1, 1);
    final rows = <_FlowRow>[
      _FlowRow(
        'This month',
        StatsEngine.sum(tx, TxType.debit, from: monthFrom),
        StatsEngine.sum(tx, TxType.credit, from: monthFrom),
      ),
      _FlowRow(
        'This year',
        StatsEngine.sum(tx, TxType.debit, from: yearFrom),
        StatsEngine.sum(tx, TxType.credit, from: yearFrom),
      ),
      _FlowRow(
        'All time',
        StatsEngine.sum(tx, TxType.debit),
        StatsEngine.sum(tx, TxType.credit),
      ),
    ];

    final spentMonths =
        StatsEngine.monthlySpend(tx, months: 12, now: now);
    final receivedMonths =
        StatsEngine.monthlySpend(tx, months: 12, type: TxType.credit, now: now);
    final byCategory =
        StatsEngine.byCategory(tx, days: 365, now: now);
    final categoryTotal = byCategory.fold<double>(0, (s, c) => s + c.total);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Statistics', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),

        // ── Money flow: month / year / all-time ────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Money flow', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text('Period',
                            style: theme.textTheme.labelMedium)),
                    Expanded(
                      child: Text('Spent',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.primary)),
                    ),
                    Expanded(
                      child: Text('Received',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: Colors.green)),
                    ),
                  ],
                ),
                const Divider(),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(row.label,
                                style: theme.textTheme.bodyMedium)),
                        Expanded(
                          child: Text(
                            formatMoney(row.spent, currency: currency),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            formatMoney(row.received, currency: currency),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Monthly trend: spent vs received ───────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly trend', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Last 12 months · spent vs received',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _legendDot(theme.colorScheme.primary, 'Spent'),
                    const SizedBox(width: 16),
                    _legendDot(Colors.green, 'Received'),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 190,
                  child: BarChart(
                    BarChartData(
                      maxY: _maxOf(spentMonths, receivedMonths) * 1.15,
                      barTouchData: BarTouchData(enabled: true),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                            color: theme.dividerColor, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) => Text(
                              value >= 1000
                                  ? '${(value / 1000).toStringAsFixed(1)}k'
                                  : value.toInt().toString(),
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= spentMonths.length) {
                                return const SizedBox.shrink();
                              }
                              final m = spentMonths[i].month;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  m.month == 1
                                      ? DateFormat('MMM yy').format(m)
                                      : DateFormat('MMM').format(m),
                                  style: theme.textTheme.labelSmall,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < spentMonths.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: spentMonths[i].amount,
                                width: 7,
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              BarChartRodData(
                                toY: i < receivedMonths.length
                                    ? receivedMonths[i].amount
                                    : 0,
                                width: 7,
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Spending by category (last 12 months) ──────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spending by category',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Last 12 months · tap Transactions to re-categorize',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                if (byCategory.isEmpty)
                  Text('No spending in this period.',
                      style: theme.textTheme.bodyMedium)
                else
                  for (final c in byCategory)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c.name,
                                    style: theme.textTheme.bodyMedium),
                              ),
                              Text(
                                '${c.count}×  '
                                '${formatMoney(c.total, currency: currency)}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                categoryTotal > 0
                                    ? '${(c.total / categoryTotal * 100).toStringAsFixed(0)}%'
                                    : '',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: categoryTotal > 0
                                  ? (c.total / categoryTotal)
                                  : 0,
                              minHeight: 8,
                              backgroundColor: theme
                                  .colorScheme.primary
                                  .withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  double _maxOf(List<MonthTotal> a, List<MonthTotal> b) {
    var m = 0.0;
    for (final x in a) {
      if (x.amount > m) m = x.amount;
    }
    for (final x in b) {
      if (x.amount > m) m = x.amount;
    }
    return m <= 0 ? 1 : m;
  }
}

class _FlowRow {
  final String label;
  final double spent;
  final double received;
  const _FlowRow(this.label, this.spent, this.received);
}
