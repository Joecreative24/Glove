// device_service.dart
// CRUD + streams for `devices/{deviceId}` and the connection/battery
// state machine. The Devices tab and the Home "current glove" card read
// from here.

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/glove_device.dart';

class DeviceService {
  // ── Reads ──────────────────────────────────────────────────────────────

  /// All gloves owned by [uid], newest first. Powers the Devices list.
  Stream<List<GloveDevice>> watchUserDevices(String uid) => FirebaseRefs.devices
      .where('ownerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map(GloveDevice.fromDoc).toList());

  Stream<GloveDevice?> watchDevice(String deviceId) => FirebaseRefs.device(deviceId)
      .snapshots()
      .map((d) => d.exists ? GloveDevice.fromDoc(d) : null);

  Future<GloveDevice?> getDevice(String deviceId) async {
    final doc = await FirebaseRefs.device(deviceId).get();
    return doc.exists ? GloveDevice.fromDoc(doc) : null;
  }

  // ── Add / rename / delete ──────────────────────────────────────────────

  /// Pairs a new glove to [ownerId] and returns the created model.
  /// `deviceId` is the glove's hardware/BLE id; pass one if you have it,
  /// otherwise an auto-id is generated.
  Future<GloveDevice> addDevice({
    required String ownerId,
    required String deviceName,
    String? deviceId,
    String gloveModel = '',
    String firmwareVersion = '',
  }) async {
    final ref = deviceId == null
        ? FirebaseRefs.devices.doc()
        : FirebaseRefs.device(deviceId);

    final data = {
      'deviceId': ref.id,
      'ownerId': ownerId,
      'deviceName': deviceName.trim(),
      'deviceType': kDeviceTypeSmartGlove,
      'gloveModel': gloveModel,
      'firmwareVersion': firmwareVersion,
      'isConnected': false,
      'connectionStatus': ConnectionStatus.disconnected.wire,
      'batteryLevel': 0,
      'batteryStatus': BatteryStatus.normal.wire,
      'lastConnectedAt': null,
      'lastDisconnectedAt': null,
      'createdAt': serverNow,
      'updatedAt': serverNow,
    };

    await ref.set(data);
    return GloveDevice.fromMap(ref.id, data);
  }

  /// Renames a glove ("My Right Glove" → "Lab Glove #3").
  Future<void> renameDevice(String deviceId, String newName) =>
      FirebaseRefs.device(deviceId).update({
        'deviceName': newName.trim(),
        'updatedAt': serverNow,
      });

  Future<void> updateFirmware(String deviceId, String firmwareVersion) =>
      FirebaseRefs.device(deviceId).update({
        'firmwareVersion': firmwareVersion,
        'updatedAt': serverNow,
      });

  Future<void> deleteDevice(String deviceId) =>
      FirebaseRefs.device(deviceId).delete();

  // ── Live state: connection ─────────────────────────────────────────────

  /// Updates the link state. Connecting stamps `lastConnectedAt`;
  /// disconnecting / losing stamps `lastDisconnectedAt`.
  ///
  /// NOTE: prefer `GloveBackend.setConnectionStatus(...)` which ALSO writes a
  /// connection log + alert. Use this method when you only need the device
  /// document touched.
  Future<void> updateConnectionStatus(
    String deviceId,
    ConnectionStatus status,
  ) {
    final connected = status == ConnectionStatus.connected;
    return FirebaseRefs.device(deviceId).update(withoutNulls({
      'connectionStatus': status.wire,
      'isConnected': connected,
      'updatedAt': serverNow,
      if (connected) 'lastConnectedAt': serverNow,
      if (!connected) 'lastDisconnectedAt': serverNow,
    }));
  }

  // ── Live state: battery ────────────────────────────────────────────────

  /// Stores a new battery percentage and derives the status bucket.
  Future<BatteryStatus> updateBattery(String deviceId, int level) async {
    final clamped = level.clamp(0, 100).toInt();
    final status = BatteryStatus.fromLevel(clamped);
    await FirebaseRefs.device(deviceId).update({
      'batteryLevel': clamped,
      'batteryStatus': status.wire,
      'updatedAt': serverNow,
    });
    return status;
  }
}
