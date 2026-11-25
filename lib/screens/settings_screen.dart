import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/transaction_providers.dart';
import '../util/import_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<bool> _permission;

  @override
  void initState() {
    super.initState();
    _permission = ref.read(smsServiceProvider).hasPermission();
  }

  Future<void> _requestPermission() async {
    final svc = ref.read(smsServiceProvider);
    var granted = await svc.hasPermission();
    if (!granted) {
      final status = await svc.requestPermission();
      granted = status.isGranted;
      if (!granted && status.isPermanentlyDenied) {
        await svc.openSystemSettings();
      }
    }
    if (mounted) {
      setState(() => _permission = Future.value(granted));
    }
    if (granted && mounted) {
      await runImport(context, ref);
    }
  }

  Future<void> _reScan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-scan all messages?'),
        content: const Text(
          'Stored transactions will be deleted and rebuilt from your '
          'SMS inbox. Nothing else on your phone is touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Re-scan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Re-scanning messages…')));
    final n = await ref.read(transactionsProvider.notifier).reparseAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rebuilt $n transactions.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Settings', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),

          // ── Permissions ──────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: FutureBuilder<bool>(
              future: _permission,
              builder: (context, snap) {
                final granted = snap.data ?? false;
                return ListTile(
                  leading: Icon(
                    granted ? Icons.sms : Icons.sms_failed_outlined,
                    color: granted ? Colors.green : theme.colorScheme.error,
                  ),
                  title: const Text('SMS access'),
                  subtitle: Text(
                    granted
                        ? 'Granted — bank alerts are captured automatically'
                        : 'Not granted — needed to read bank messages',
                  ),
                  trailing: granted
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Text('Grant'),
                  onTap: granted ? null : _requestPermission,
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Data ─────────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Import SMS history'),
                  subtitle:
                      const Text('Parse existing messages from your inbox'),
                  onTap: () => runImport(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.refresh,
                      color: theme.colorScheme.primary),
                  title: const Text('Re-scan from scratch'),
                  subtitle:
                      const Text('Clear parsed data and rebuild it'),
                  onTap: _reScan,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Privacy ──────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.shield_outlined,
                  color: theme.colorScheme.primary),
              title: const Text('Privacy'),
              subtitle: const Text(
                'All messages are parsed and stored only on this device. '
                'The app has no server, sends nothing anywhere, and works '
                'fully offline.',
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('Budget App v0.1.0'),
            ),
          ),
        ],
      ),
    );
  }
}
