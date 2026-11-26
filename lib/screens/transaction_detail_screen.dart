import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../parsers/extractors.dart';
import '../providers/transaction_providers.dart';
import '../services/settings_service.dart';
import '../util/format.dart';
import '../util/reason.dart';

/// Full breakdown of one transaction: parsed fields, the classified reason,
/// and the original raw SMS it was parsed from. The category row opens a
/// picker so the user can correct/assign categories.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  late Transaction _tx;

  @override
  void initState() {
    super.initState();
    _tx = widget.transaction;
  }

  Future<void> _pickCategory() async {
    final settings = ref.read(settingsProvider);
    final options = <String>{
      ...allCategories,
      ...settings.customCategories,
      if (_tx.category != null && _tx.category != 'Other') _tx.category!,
    }.toList()
      ..sort();

    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Choose category',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final c in options)
            ListTile(
              dense: true,
              leading: Icon(iconForCategory(c), size: 20),
              title: Text(c),
              trailing: c == _tx.category
                  ? Icon(Icons.check,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(c),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 20),
            title: const Text('Add custom category…'),
            onTap: () async {
              final controller = TextEditingController();
              final custom = await showDialog<String>(
                context: ctx,
                builder: (dctx) => AlertDialog(
                  title: const Text('New category'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration:
                        const InputDecoration(hintText: 'e.g. Education'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dctx)
                          .pop(controller.text.trim()),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
              if (custom == null || custom.isEmpty) return;
              await ref
                  .read(settingsProvider.notifier)
                  .addCustomCategory(custom);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop(custom);
            },
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;
    await ref
        .read(transactionsProvider.notifier)
        .setCategory(_tx, chosen);
    if (!mounted) return;
    setState(() => _tx = _tx.copyWith(category: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _tx;
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
                  ListTile(
                    dense: true,
                    title: Text('Category',
                        style: theme.textTheme.bodyMedium),
                    subtitle: Text(
                      t.category ?? 'Uncategorized',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: _pickCategory,
                  ),
                  if (t.senderName != null)
                    _field(context, 'Contact', t.senderName!),
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
