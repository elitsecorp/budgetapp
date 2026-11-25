import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/transaction_providers.dart';
import '../services/settings_service.dart';
import '../services/upload_service.dart';
import '../util/import_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<bool> _permission;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _apkCtrl;
  late final TextEditingController _serverCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _permission = ref.read(smsServiceProvider).hasPermission();
    final s = ref.read(settingsProvider);
    _nameCtrl = TextEditingController(text: s.ownerName);
    _phoneCtrl = TextEditingController(text: s.ownerPhone);
    _apkCtrl = TextEditingController(text: s.apkUrl);
    _serverCtrl = TextEditingController(text: s.serverUrl);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _apkCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
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

    _snack('Re-scanning messages…');
    final n = await ref.read(transactionsProvider.notifier).reparseAll();
    if (!mounted) return;
    _snack('Rebuilt $n transactions.');
  }

  Future<void> _detectIdentity() async {
    setState(() => _busy = true);
    final msg =
        await ref.read(transactionsProvider.notifier).detectIdentity();
    if (!mounted) return;
    setState(() => _busy = false);
    final s = ref.read(settingsProvider);
    _nameCtrl.text = s.ownerName;
    _phoneCtrl.text = s.ownerPhone;
    _snack(msg);
  }

  Future<void> _toggleContactLookup(bool enabled) async {
    if (enabled) {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        _snack('Contacts permission is required to look up names.');
        return;
      }
      await ref.read(settingsProvider.notifier).setContactLookup(true);
      if (!mounted) return;
      _snack('Looking up contact names…');
      final n =
          await ref.read(transactionsProvider.notifier).resolveContactNames();
      _snack('Resolved $n contact name(s).');
    } else {
      await ref.read(settingsProvider.notifier).setContactLookup(false);
    }
    setState(() {});
  }

  Future<void> _editMaxAmount() async {
    final current = ref.read(settingsProvider).maxAmount;
    final controller = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ignore amounts above'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 50000 (0 = no limit)',
            suffixText: 'per transaction',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(settingsProvider.notifier).setMaxAmount(
            result < 0 ? 0 : result,
          );
      setState(() {});
    }
  }

  Future<void> _updateApk() async {
    final url = _apkCtrl.text.trim();
    if (!url.startsWith('http')) {
      _snack('Paste a direct .apk download link first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download update?'),
        content: Text('The APK will be downloaded from:\n\n$url\n\n'
            'Your browser/installer will ask you to confirm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final status = await ref
          .read(smsServiceProvider)
          .downloadAndInstallApk(url);
      _snack(status);
    } on PlatformException catch (e) {
      _snack('Update failed: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendToServer() async {
    final url = _serverCtrl.text.trim();
    if (url.isEmpty) {
      _snack('Enter your server URL first.');
      return;
    }
    setState(() => _busy = true);
    final tx = await ref.read(transactionsProvider.future);
    final s = ref.read(settingsProvider);
    final result = await sendTransactions(
      url: url,
      transactions: tx,
      ownerName: s.ownerName.isEmpty ? null : s.ownerName,
      ownerPhone: s.ownerPhone.isEmpty ? null : s.ownerPhone,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Settings', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),

          // ── Permissions ──────────────────────────────────────────
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

          // ── Profile (detected from your messages) ────────────────
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
                      Text('Profile', style: theme.textTheme.titleMedium),
                      TextButton.icon(
                        onPressed: _busy ? null : _detectIdentity,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Detect'),
                      ),
                    ],
                  ),
                  Text(
                    'Detected from the greetings and numbers inside your '
                    'own messages.',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setOwnerName(v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Your phone number',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setOwnerPhone(v),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Look up contact names'),
                    subtitle:
                        const Text('Resolve names for numbers in your '
                            'contacts (READ_CONTACTS)'),
                    value: settings.contactLookup,
                    onChanged: _busy ? null : _toggleContactLookup,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Spending filter ──────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Exclude money transfers'),
                  subtitle: const Text(
                      'Don\'t count transfers between your own accounts '
                      'as spending'),
                  value: settings.excludeTransfers,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setExcludeTransfers(v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Ignore amounts above'),
                  subtitle: Text(
                    settings.maxAmount > 0
                        ? 'Transactions over ${settings.maxAmount.toStringAsFixed(0)} '
                              'are left out of spending stats'
                        : 'No limit — big internal moves can skew stats',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _editMaxAmount,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Data ─────────────────────────────────────────────────
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
                  leading:
                      Icon(Icons.refresh, color: theme.colorScheme.primary),
                  title: const Text('Re-scan from scratch'),
                  subtitle: const Text('Clear parsed data and rebuild it'),
                  onTap: _reScan,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── App updates ──────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App updates', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Paste a direct .apk download link — the app downloads '
                    'it and opens the installer.',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apkCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://…/app-release.apk',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.link),
                    ),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setApkUrl(v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _updateApk,
                    icon: const Icon(Icons.system_update),
                    label: const Text('Download & install update'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Server export ────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send to server',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'POSTs your latest transactions as JSON to the URL '
                    'below for external processing. Default works for '
                    'testing — replace it with your own endpoint.',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://your-server.example/api/transactions',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.cloud_upload),
                    ),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setServerUrl(v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sendToServer,
                    icon: const Icon(Icons.send),
                    label: const Text('Send latest transactions'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Privacy ──────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading:
                  Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
              title: const Text('Privacy'),
              subtitle: const Text(
                'Messages are parsed and stored only on this device. '
                'The internet is touched ONLY when you tap "Update" or '
                '"Send to server" — never in the background.',
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            margin: EdgeInsets.zero,
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About'),
              subtitle: Text('Budget App v0.2.0'),
            ),
          ),
        ],
      ),
    );
  }
}
