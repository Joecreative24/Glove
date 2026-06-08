// glove_device.dart
// Maps to a document in  devices/{deviceId}.
//
// Represents one physical smart glove paired to a user. A user can own
// many devices (User 1-to-many Device). Devices are the source of every
// GestureReading and the subject of ConnectionLogs and Alerts.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class GloveDevice {
  final String deviceId;
  final String ownerId;
  final String deviceName;
  final String deviceType; // always 'smart_glove'
  final String gloveModel;
  final String firmwareVersion;
  final bool isConnected;
  final ConnectionStatus connectionStatus;
  final int batteryLevel; // 0–100
  final BatteryStatus batteryStatus;
  final DateTime? lastConnectedAt;
  final DateTime? lastDisconnectedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GloveDevice({
    required this.deviceId,
    required this.ownerId,
    required this.deviceName,
    this.deviceType = kDeviceTypeSmartGlove,
    this.gloveModel = '',
    this.firmwareVersion = '',
    this.isConnected = false,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.batteryLevel = 0,
    this.batteryStatus = BatteryStatus.normal,
    this.lastConnectedAt,
    this.lastDisconnectedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory GloveDevice.fromMap(String id, Map<String, dynamic> m) => GloveDevice(
        deviceId: readString(m['deviceId'], id),
        ownerId: readString(m['ownerId']),
        deviceName: readString(m['deviceName'], 'Smart Glove'),
        deviceType: readString(m['deviceType'], kDeviceTypeSmartGlove),
        gloveModel: readString(m['gloveModel']),
        firmwareVersion: readString(m['firmwareVersion']),
        isConnected: readBool(m['isConnected']),
        connectionStatus:
            ConnectionStatus.fromWire(m['connectionStatus'] as String?),
        batteryLevel: readInt(m['batteryLevel']),
        batteryStatus: BatteryStatus.fromWire(m['batteryStatus'] as String?),
        lastConnectedAt: readDate(m['lastConnectedAt']),
        lastDisconnectedAt: readDate(m['lastDisconnectedAt']),
        createdAt: readDate(m['createdAt']),
        updatedAt: readDate(m['updatedAt']),
      );

  factory GloveDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      GloveDevice.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'ownerId': ownerId,
        'deviceName': deviceName,
        'deviceType': deviceType,
        'gloveModel': gloveModel,
        'firmwareVersion': firmwareVersion,
        'isConnected': isConnected,
        'connectionStatus': connectionStatus.wire,
        'batteryLevel': batteryLevel,
        'batteryStatus': batteryStatus.wire,
        'lastConnectedAt': toTs(lastConnectedAt),
        'lastDisconnectedAt': toTs(lastDisconnectedAt),
        'createdAt': toTs(createdAt),
        'updatedAt': toTs(updatedAt),
      };

  GloveDevice copyWith({
    String? deviceName,
    String? gloveModel,
    String? firmwareVersion,
    bool? isConnected,
    ConnectionStatus? connectionStatus,
    int? batteryLevel,
    BatteryStatus? batteryStatus,
    DateTime? lastConnectedAt,
    DateTime? lastDisconnectedAt,
    DateTime? updatedAt,
  }) =>
      GloveDevice(
        deviceId: deviceId,
        ownerId: ownerId,
        deviceName: deviceName ?? this.deviceName,
        deviceType: deviceType,
        gloveModel: gloveModel ?? this.gloveModel,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        isConnected: isConnected ?? this.isConnected,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        batteryStatus: batteryStatus ?? this.batteryStatus,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        lastDisconnectedAt: lastDisconnectedAt ?? this.lastDisconnectedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
