import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../util/format.dart';
import '../util/reason.dart';

/// Full breakdown of one transaction: parsed fields, the classified reason,
/// and the original raw SMS it was parsed from.
class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = transaction;
    final isDebit = t.type == TxType.debit;
    final color = isDebit ? theme.colorScheme.primary : Colors.green;

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Amount ────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isDebit ? 'SPENT' : 'RECEIVED',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${isDebit ? '-' : '+'}${formatMoney(t.amount, currency: t.currency)}',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 6),
                  Text(formatDayTime(t.date), style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Classified reason ─────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.lightbulb_outline, color: color),
              title: const Text('Likely reason'),
              subtitle: Text(spendReason(t)),
            ),
          ),
          const SizedBox(height: 12),

          // ── Parsed fields ─────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _field(context, 'Merchant', t.merchant ?? 'Not detected'),
                  _field(context, 'Category', t.category ?? 'Uncategorized'),
                  _field(context, 'Bank', t.bank),
                  _field(context, 'Balance after',
                      t.balance == null
                          ? 'Not in message'
                          : formatMoney(t.balance!, currency: t.currency)),
                  _field(context, 'Type', isDebit ? 'Debit' : 'Credit'),
                  _field(context, 'Sender', t.sender),
                  _field(context, 'Received by app', formatDayTime(t.date)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Raw SMS ───────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Original SMS',
                          style: theme.textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: t.raw));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      t.raw,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace', height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is exactly how the app parsed it — no data left '
                    'your device.',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
