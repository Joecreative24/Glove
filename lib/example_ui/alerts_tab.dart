// alerts_tab.dart
// Live alert centre: streams the user's alerts, lets them mark one (or all)
// read, and swipe to delete. The unread count drives the nav badge.

import 'package:flutter/material.dart';

import '../backend/backend.dart';

class AlertsTab extends StatelessWidget {
  final GloveBackend backend;
  final String uid;
  const AlertsTab({super.key, required this.backend, required this.uid});

  Color _severityColor(AlertSeverity s) => switch (s) {
        AlertSeverity.critical => Colors.red,
        AlertSeverity.high => Colors.deepOrange,
        AlertSeverity.medium => Colors.amber,
        AlertSeverity.low => Colors.blueGrey,
      };

  IconData _icon(AlertType t) => switch (t) {
        AlertType.batteryLow || AlertType.batteryCritical => Icons.battery_alert,
        AlertType.connectionLost => Icons.link_off,
        AlertType.connectionRestored => Icons.link,
        AlertType.deviceConnected => Icons.bluetooth_connected,
        AlertType.deviceDisconnected => Icons.bluetooth_disabled,
        AlertType.emergencySos => Icons.sos,
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GloveAlert>>(
      stream: backend.alerts.watchAlerts(uid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final alerts = snap.data!;
        if (alerts.isEmpty) {
          return const Center(child: Text('No alerts. All good 👍'));
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => backend.alerts.markAllRead(uid),
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all read'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: alerts.length,
                itemBuilder: (context, i) {
                  final a = alerts[i];
                  return Dismissible(
                    key: ValueKey(a.alertId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => backend.alerts.delete(a.alertId),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _severityColor(a.severity),
                        child: Icon(_icon(a.alertType), color: Colors.white, size: 20),
                      ),
                      title: Text(
                        a.title,
                        style: TextStyle(
                          fontWeight: a.isRead ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(a.message),
                      trailing: a.isRead
                          ? null
                          : const Icon(Icons.circle, size: 10, color: Colors.cyan),
                      onTap: () => backend.alerts.markRead(a.alertId),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
