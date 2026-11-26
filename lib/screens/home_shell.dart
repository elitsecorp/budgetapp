import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/transaction_providers.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'transactions_screen.dart';

/// Bottom-nav shell. Also owns the live SMS subscription: every incoming
/// message is parsed and stored as soon as it arrives.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  StreamSubscription<SmsMessage>? _subscription;

  static const _screens = <Widget>[
    DashboardScreen(),
    TransactionsScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(smsServiceProvider).incoming.listen((msg) {
      ref.read(transactionsProvider.notifier).ingest(msg);
    });
    // Flush anything queued while the app was closed (e.g. messages that
    // arrived overnight) once we're up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushQueue());
  }

  Future<void> _flushQueue() async {
    final svc = ref.read(smsServiceProvider);
    if (!await svc.hasPermission()) return;
    final pending = await svc.drainPending();
    if (pending.isEmpty) return;
    final notifier = ref.read(transactionsProvider.notifier);
    for (final m in pending) {
      await notifier.ingest(m);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
