import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../parsers/sms_parser.dart';
import '../services/sms_service.dart';

final smsServiceProvider = Provider<SmsService>((ref) => SmsService());

/// All parsed transactions, newest first.
final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
        TransactionsNotifier.new);

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  @override
  Future<List<Transaction>> build() => BudgetDatabase.instance.all();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => BudgetDatabase.instance.all());
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
    for (final m in [...pending, ...inbox]) {
      final t = ParserRegistry.parse(m);
      if (t == null) continue;
      if (await BudgetDatabase.instance.insertIfNew(t)) inserted++;
    }
    await refresh();
    return inserted;
  }

  /// Wipes stored transactions and re-imports + re-parses from the inbox.
  Future<int> reparseAll() async {
    await BudgetDatabase.instance.clear();
    return importFromDevice();
  }
}
