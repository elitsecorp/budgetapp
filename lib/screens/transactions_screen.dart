import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/transaction_providers.dart';
import '../util/format.dart';
import '../util/reason.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _query = '';
  TxType? _filter;

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search merchant, bank, category…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _filterChip(null, 'All'),
                    const SizedBox(width: 8),
                    _filterChip(TxType.debit, 'Spent'),
                    const SizedBox(width: 8),
                    _filterChip(TxType.credit, 'Received'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: txAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load data: $e')),
              data: (tx) {
                final filtered = tx.where((t) {
                  if (_filter != null && t.type != _filter) return false;
                  final q = _query.trim().toLowerCase();
                  if (q.isEmpty) return true;
                  return (t.merchant ?? '').toLowerCase().contains(q) ||
                      t.bank.toLowerCase().contains(q) ||
                      (t.category ?? '').toLowerCase().contains(q) ||
                      t.raw.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      tx.isEmpty
                          ? 'No transactions yet — import your SMS in Settings.'
                          : 'Nothing matches your filter.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                // Interleave day headers with the transaction tiles.
                final rows = <Object>[];
                String? lastDay;
                for (final t in filtered) {
                  final day = formatDay(t.date);
                  if (day != lastDay) {
                    rows.add(day);
                    lastDay = day;
                  }
                  rows.add(t);
                }

                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          row,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      );
                    }
                    return _tile(context, row as Transaction);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(TxType? type, String label) {
    final selected = _filter == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = type),
    );
  }

  Widget _tile(BuildContext context, Transaction t) {
    final theme = Theme.of(context);
    final isDebit = t.type == TxType.debit;
    final sign = isDebit ? '-' : '+';
    final color = isDebit ? theme.colorScheme.primary : Colors.green;

    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: t),
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(iconForCategory(t.category), size: 20, color: color),
      ),
      title: Text(
        t.merchant ?? t.bank,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${t.category ?? 'Uncategorized'} • ${formatDayTime(t.date)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign${formatMoney(t.amount, currency: t.currency)}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            isDebit ? 'spent' : 'received',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
