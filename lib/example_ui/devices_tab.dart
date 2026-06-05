// devices_tab.dart
// Lists the user's gloves and exercises the device flows: add, rename,
// connection-status changes (which also write a log + alert), and battery
// reports (which raise low/critical alerts).

import 'package:flutter/material.dart';

import '../backend/backend.dart';

class DevicesTab extends StatelessWidget {
  final GloveBackend backend;
  final String uid;
  const DevicesTab({super.key, required this.backend, required this.uid});

  Future<void> _addDevice(BuildContext context) async {
    final name = await _promptText(context, 'Add glove', 'Glove name');
    if (name == null || name.isEmpty) return;
    await backend.addGlove(deviceName: name, gloveModel: 'IG-Pro-v2');
  }

  Future<void> _rename(BuildContext context, GloveDevice d) async {
    final name = await _promptText(context, 'Rename glove', 'New name', d.deviceName);
    if (name == null || name.isEmpty) return;
    await backend.renameGlove(d.deviceId, name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<GloveDevice>>(
        stream: backend.devices.watchUserDevices(uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final devices = snap.data!;
          if (devices.isEmpty) {
            return const Center(
              child: Text('No gloves yet.\nTap + to pair one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _DeviceCard(
              device: devices[i],
              backend: backend,
              onRename: () => _rename(context, devices[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDevice(context),
        icon: const Icon(Icons.add),
        label: const Text('Add glove'),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final GloveDevice device;
  final GloveBackend backend;
  final VoidCallback onRename;
  const _DeviceCard(
      {required this.device, required this.backend, required this.onRename});

  Color _statusColor(BuildContext c) => switch (device.connectionStatus) {
        ConnectionStatus.connected => Colors.green,
        ConnectionStatus.lost => Colors.orangeAccent,
        ConnectionStatus.disconnected => Theme.of(c).disabledColor,
      };

  IconData get _batteryIcon => switch (device.batteryStatus) {
        BatteryStatus.critical => Icons.battery_alert,
        BatteryStatus.low => Icons.battery_2_bar,
        BatteryStatus.normal => Icons.battery_full,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.back_hand, color: _statusColor(context)),
        title: Text(device.deviceName),
        subtitle: Text(
          '${device.gloveModel} · ${device.connectionStatus.wire} · '
          '${device.batteryLevel}%',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_batteryIcon, size: 20),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'rename':
                    onRename();
                  case 'connect':
                    await backend.setConnectionStatus(
                        device.deviceId, ConnectionStatus.connected);
                  case 'disconnect':
                    await backend.setConnectionStatus(
                        device.deviceId, ConnectionStatus.disconnected);
                  case 'lost':
                    await backend.setConnectionStatus(
                        device.deviceId, ConnectionStatus.lost);
                  case 'batt_low':
                    await backend.reportBattery(device.deviceId, 18);
                  case 'batt_critical':
                    await backend.reportBattery(device.deviceId, 4);
                  case 'batt_full':
                    await backend.reportBattery(device.deviceId, 95);
                  case 'delete':
                    await backend.removeGlove(device.deviceId);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'connect', child: Text('Connect')),
                PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
                PopupMenuItem(value: 'lost', child: Text('Simulate lost')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'batt_low', child: Text('Battery → 18% (low)')),
                PopupMenuItem(
                    value: 'batt_critical', child: Text('Battery → 4% (critical)')),
                PopupMenuItem(value: 'batt_full', child: Text('Battery → 95%')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small reusable text-input dialog.
Future<String?> _promptText(
  BuildContext context,
  String title,
  String label, [
  String initial = '',
]) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}
