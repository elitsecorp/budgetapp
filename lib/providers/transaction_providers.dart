import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../parsers/sms_parser.dart';
import '../services/settings_service.dart';
import '../services/sms_service.dart';
import '../services/upload_service.dart';
import '../util/identity.dart';

final smsServiceProvider = Provider<SmsService>((ref) => SmsService());

/// All parsed transactions, newest first.
final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
        TransactionsNotifier.new);

/// How many transactions are still waiting to be pushed to the server.
final unsentCountProvider = FutureProvider<int>(
    (ref) => BudgetDatabase.instance.unsentCount());

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  @override
  Future<List<Transaction>> build() => BudgetDatabase.instance.all();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => BudgetDatabase.instance.all());
    ref.invalidate(unsentCountProvider);
  }

  /// Pushes every transaction that has never been confirmed by the server.
  /// Successful chunks are flagged `sent` so they are never re-sent.
  Future<String> sendUnsent({
    required String url,
    required String apiKey,
    String? ownerName,
    String? ownerPhone,
  }) async {
    if (ownerPhone == null || ownerPhone.trim().isEmpty) {
      return 'Set your phone number in Profile first — the server requires it '
          'to identify you.';
    }
    final db = BudgetDatabase.instance;
    final pending = await db.unsent();
    if (pending.isEmpty) {
      return 'Nothing to send — every transaction is already synced.';
    }

    final outcome = await sendTransactions(
      url: url,
      transactions: pending,
      ownerName: (ownerName ?? '').isEmpty ? null : ownerName,
      ownerPhone: ownerPhone,
      apiKey: apiKey,
    );
    if (outcome.sentIds.isNotEmpty) {
      await db.markSent(outcome.sentIds);
      await refresh();
    }
    return outcome.message;
  }

  /// Ingests one live SMS. Returns true when it produced a new transaction.
  Future<bool> ingest(SmsMessage msg) async {
    final t = ParserRegistry.parse(msg);
    if (t == null) return false;
    final isNew = await BudgetDatabase.instance.insertIfNew(t);
    if (isNew) await refresh();
    return isNew;
  }

  /// Imports device SMS history + queued messages.
  /// Returns the number of new transactions, or -1 when SMS permission is
  /// missing.
  Future<int> importFromDevice({int limit = 2000}) async {
    final svc = ref.read(smsServiceProvider);
    if (!await svc.hasPermission()) return -1;

    final pending = await svc.drainPending();
    final inbox = await svc.fetchInbox(limit: limit);

    var inserted = 0;
    final bodies = <String>[];
    for (final m in [...pending, ...inbox]) {
      bodies.add(m.body);
      final t = ParserRegistry.parse(m);
      if (t == null) continue;
      if (await BudgetDatabase.instance.insertIfNew(t)) inserted++;
    }

    // The corpus greets you by name and quotes your own number — harvest
    // the profile if the user hasn't filled it in.
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (settings.ownerName.isEmpty) {
      final name = detectOwnerName(bodies);
      if (name != null) await settingsNotifier.setOwnerName(name);
    }
    if (settings.ownerPhone.isEmpty) {
      final phone = detectOwnerPhone(bodies);
      if (phone != null) await settingsNotifier.setOwnerPhone(phone);
    }

    if (ref.read(settingsProvider).contactLookup) {
      await resolveContactNames();
    }

    await refresh();
    return inserted;
  }

  /// Re-detects owner name/phone from the inbox (Settings → Detect).
  Future<String> detectIdentity() async {
    final svc = ref.read(smsServiceProvider);
    if (!await svc.hasPermission()) return 'SMS permission required';
    final inbox = await svc.fetchInbox(limit: 3000);
    final bodies = inbox.map((m) => m.body).toList();

    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final name = settings.ownerName.isEmpty ? detectOwnerName(bodies) : null;
    final phone = settings.ownerPhone.isEmpty ? detectOwnerPhone(bodies) : null;
    if (name != null) await notifier.setOwnerName(name);
    if (phone != null) await notifier.setOwnerPhone(phone);

    if (name == null && phone == null) {
      return 'Could not detect a name or number in your messages';
    }
    final parts = <String>[
      if (name != null) 'name: $name',
      if (phone != null) 'phone: $phone',
    ];
    return 'Detected ${parts.join(' • ')}';
  }

  /// Resolves contact display names for numeric senders (READ_CONTACTS).
  Future<int> resolveContactNames() async {
    final svc = ref.read(smsServiceProvider);
    final senders = await BudgetDatabase.instance.sendersNeedingContact();
    var resolved = 0;
    for (final s in senders) {
      final name = await svc.lookupContact(s);
      if (name != null && name.isNotEmpty) {
        await BudgetDatabase.instance.setSenderName(s, name);
        resolved++;
      }
    }
    if (resolved > 0) await refresh();
    return resolved;
  }

  /// Wipes stored transactions and re-imports + re-parses from the inbox.
  Future<int> reparseAll() async {
    await BudgetDatabase.instance.clear();
    return importFromDevice();
  }
}
