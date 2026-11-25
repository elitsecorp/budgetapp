import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/transaction_providers.dart';

/// Requests SMS permission if needed, imports inbox history, and reports the
/// result with a snackbar. Shared by the dashboard empty state and Settings.
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
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $n new transactions.')));
  }
}
