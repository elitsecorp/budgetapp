import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/transaction_providers.dart';
import '../services/settings_service.dart';

/// Requests SMS permission if needed, imports inbox history, shows a
/// snackbar — then **auto-syncs** to the server so targeted advice can be
/// computed as early as possible.
Future<void> runImport(BuildContext context, WidgetRef ref) async {
  final svc = ref.read(smsServiceProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (!await svc.hasPermission()) {
    final status = await svc.requestPermission();
    if (!status.isGranted) {
      messenger.showSnackBar(const SnackBar(
          content: Text('SMS permission is required to read bank messages.')));
      if (status.isPermanentlyDenied && context.mounted) {
        await svc.openSystemSettings();
      }
      return;
    }
  }

  messenger.showSnackBar(
      const SnackBar(content: Text('Importing messages…')));
  final n = await ref.read(transactionsProvider.notifier).importFromDevice();
  if (!context.mounted) return;
  if (n < 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SMS permission is required. Grant it in Settings.')));
    return;
  }

  // Permission just got satisfied (or an import ran) → push everything the
  // server hasn't seen yet.
  final settings = ref.read(settingsProvider);
  var syncNote = '';
  if (settings.ownerPhone.trim().isNotEmpty &&
      settings.serverUrl.trim().isNotEmpty) {
    final syncMsg =
        await ref.read(transactionsProvider.notifier).sendUnsent(
              url: settings.serverUrl,
              apiKey: settings.serverApiKey,
              ownerName: settings.ownerName,
              ownerPhone: settings.ownerPhone,
            );
    if (!context.mounted) return;
    syncNote = ' $syncMsg';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $n new transactions.$syncNote')));
}
