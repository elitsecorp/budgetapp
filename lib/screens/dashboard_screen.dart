import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../providers/transaction_providers.dart';
import '../services/settings_service.dart';
import '../stats/stats_engine.dart';
import '../util/format.dart';
import '../util/import_actions.dart';

enum _Range { week, month, year, all }

extension on _Range {
  String get label => switch (this) {
        _Range.week => 'This week',
        _Range.month => 'Last 30 days',
        _Range.year => 'Last 12 months',
        _Range.all => 'All time',
      };
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  _Range _range = _Range.month;

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Number of days in the range (null = everything).
  int? get _days => switch (_range) {
        _Range.week => 7,
        _Range.month => 30,
        _Range.year => 365,
        _Range.all => null,
      };

  DateTime? get _from {
    final now = DateTime.now();
    final days = _days;
    if (days == null) return null;
    return _startOfDay(now).subtract(Duration(days: days - 1));
  }

  @override
  Widget build(BuildContext context) {
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
              ? const _EmptyState()
              : _buildBody(context, tx),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Transaction> tx) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final from = _from;
    final settings = ref.watch(settingsProvider);

    // Spending filter from Settings: optionally drop money-transfers and
    // very large amounts so one big internal move doesn't skew the stats.
    bool include(Transaction t) {
      if (settings.excludeTransfers && t.category == 'Money Transfer') {
        return false;
      }
      if (settings.maxAmount > 0 && t.amount > settings.maxAmount) {
        return false;
      }
      return true;
    }

    final rangeTx =
        from == null ? tx : tx.where((t) => !t.date.isBefore(from)).toList();
    final spendTx = rangeTx
        .where((t) => t.type == TxType.debit && include(t))
        .toList();
    final statTx = rangeTx.where(include).toList();

    final spent = spendTx.fold<double>(0, (s, t) => s + t.amount);
    final received = StatsEngine.sum(rangeTx, TxType.credit, from: from);
    final purchaseCount = spendTx.length;
    final avg = purchaseCount == 0 ? 0.0 : spent / purchaseCount;
    final categories =
        StatsEngine.byCategory(statTx, days: _days, now: now);
    final topMerchants =
        StatsEngine.topMerchants(statTx, limit: 5, days: _days, now: now);
    final currency = currencyFor(tx);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header + range selector ────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Overview', style: theme.textTheme.headlineSmall),
            Text(_range.label, style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final r in _Range.values)
              ChoiceChip(
                label: Text(switch (r) {
                  _Range.week => 'Week',
                  _Range.month => 'Month',
                  _Range.year => 'Year',
                  _Range.all => 'All',
                }),
                selected: _range == r,
                onSelected: (_) => setState(() => _range = r),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Summary ────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.shopping_cart_checkout,
                label: 'Spent',
                value: formatMoney(spent, currency: currency),
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.shopping_bag_outlined,
                label: 'Purchases',
                value: '$purchaseCount',
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                icon: Icons.attach_money,
                label: 'Avg purchase',
                value: formatMoney(avg, currency: currency),
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Trend (daily for week/month, monthly for year/all) ─────
        if (_range == _Range.week || _range == _Range.month)
          _FrequencyCard(
            frequencies:
                StatsEngine.purchaseFrequency(statTx, days: _days!, now: now),
          )
        else
          _MonthlyCard(
            months: StatsEngine.monthlySpend(
              statTx,
              months: _range == _Range.year ? 12 : null,
              now: now,
            ),
            currency: currency,
          ),
        const SizedBox(height: 16),

        _CategoryCard(
          categories: categories,
          total: categories.fold<double>(0, (s, c) => s + c.total),
          currency: currency,
        ),
        const SizedBox(height: 16),
        _TopMerchantsCard(merchants: topMerchants, currency: currency),
        if (received > 0) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Received: ${formatMoney(received, currency: currency)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.savings_outlined,
            size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'No transactions yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Grant SMS access so Budget App can read your bank alerts, '
          'then import your message history to start seeing stats.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => runImport(context, ref),
          icon: const Icon(Icons.download),
          label: const Text('Grant access & import'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FrequencyCard extends StatelessWidget {
  final List<DayFrequency> frequencies;
  const _FrequencyCard({required this.frequencies});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount =
        frequencies.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final totalPurchases = frequencies.fold<int>(0, (s, d) => s + d.count);
    // Label every 5th day for month view, every day for week view.
    final labelEvery = frequencies.length > 10 ? 5 : 1;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Purchase frequency', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$totalPurchases purchases • per day',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: (maxCount + 1).toDouble(),
                  barTouchData: BarTouchData(enabled: true),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        FlLine(color: theme.dividerColor, strokeWidth: 1),
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
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: labelEvery.toDouble(),
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= frequencies.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('d')
                                  .format(frequencies[i].day),
                              style: theme.textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < frequencies.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: frequencies[i].count.toDouble(),
                            width: frequencies.length > 10 ? 7 : 22,
                            color: frequencies[i].count == 0
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.25)
                                : theme.colorScheme.primary,
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
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  final List<MonthTotal> months;
  final String currency;
  const _MonthlyCard({required this.months, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxSpend =
        months.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final totalPurchases = months.fold<int>(0, (s, d) => s + d.count);
    final labelEvery = months.length > 12 ? 2 : 1;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly spending', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$totalPurchases purchases • per month',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxSpend <= 0 ? 1 : maxSpend * 1.15,
                  barTouchData: BarTouchData(enabled: true),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        FlLine(color: theme.dividerColor, strokeWidth: 1),
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
                        interval: labelEvery.toDouble(),
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox.shrink();
                          }
                          final m = months[i].month;
                          final isYearStart = m.month == 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              isYearStart
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
                    for (var i = 0; i < months.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: months[i].amount,
                            width: months.length > 12 ? 14 : 22,
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(3),
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
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final List<CategoryStat> categories;
  final double total;
  final String currency;

  const _CategoryCard({
    required this.categories,
    required this.total,
    required this.currency,
  });

  static const _palette = <Color>[
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFFF4511E),
    Color(0xFFFDD835),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFEC407A),
    Color(0xFF6D4C41),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (categories.isEmpty || total <= 0) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No spending recorded in this period.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final shown = categories.take(5).toList();
    final rest = categories.skip(5).fold<double>(0, (s, c) => s + c.total);
    if (rest > 0) {
      shown.add(CategoryStat('Others', 0, rest));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by category', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Center(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      for (var i = 0; i < shown.length; i++)
                        PieChartSectionData(
                          value: shown[i].total,
                          color: _palette[i % _palette.length],
                          radius: 52,
                          title: '',
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${shown[i].name}  '
                        '${formatMoney(shown[i].total, currency: currency)} '
                        '(${(shown[i].total / total * 100).toStringAsFixed(0)}%)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopMerchantsCard extends StatelessWidget {
  final List<MerchantStat> merchants;
  final String currency;
  const _TopMerchantsCard({required this.merchants, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top merchants', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('By spend in this period', style: theme.textTheme.bodySmall),
            if (merchants.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child:
                    Text('No purchases yet.', style: theme.textTheme.bodyMedium),
              )
            else
              for (final entry in merchants.asMap().entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      '${entry.key + 1}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  title: Text(
                    entry.value.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${entry.value.count} '
                    'purchase${entry.value.count == 1 ? '' : 's'}',
                  ),
                  trailing: Text(
                    formatMoney(entry.value.total, currency: currency),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
