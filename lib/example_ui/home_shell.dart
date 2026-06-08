// home_shell.dart
// Signed-in shell with a 3-tab bottom nav (Devices / Translate / Alerts).
// In your real app these map under the Services tab + AppRoutes; here they
// demonstrate every backend flow end to end.

import 'package:flutter/material.dart';

import '../backend/backend.dart';
import 'alerts_tab.dart';
import 'devices_tab.dart';
import 'translate_tab.dart';

class HomeShell extends StatefulWidget {
  final GloveBackend backend;
  const HomeShell({super.key, required this.backend});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final uid = widget.backend.auth.uid!;
    final tabs = [
      DevicesTab(backend: widget.backend, uid: uid),
      TranslateTab(backend: widget.backend, uid: uid),
      AlertsTab(backend: widget.backend, uid: uid),
    ];
    const titles = ['My Gloves', 'Translate', 'Alerts'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          StreamBuilder<AppUser?>(
            stream: widget.backend.currentUserProfile(),
            builder: (context, snap) {
              final name = snap.data?.fullName ?? '';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(name, style: Theme.of(context).textTheme.labelLarge),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => widget.backend.signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.back_hand_outlined), label: 'Gloves'),
          const NavigationDestination(
              icon: Icon(Icons.translate), label: 'Translate'),
          NavigationDestination(
            icon: StreamBuilder<int>(
              stream: widget.backend.alerts.watchUnreadCount(uid),
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.notifications_outlined),
                );
              },
            ),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}
