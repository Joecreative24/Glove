// connection_log.dart
// Maps to a document in  connectionLogs/{logId}.
//
// An append-only audit trail of every connect / disconnect / lost / restored
// event for a device. Powers the "connection history" view and the
// "connection loss frequency" analytic.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class ConnectionLog {
  final String logId;
  final String userId;
  final String deviceId;
  final String deviceName;
  final ConnectionEventType eventType;
  final DateTime? timestamp;
  final int batteryLevel;
  final String? sessionId;

  const ConnectionLog({
    required this.logId,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.eventType,
    this.timestamp,
    this.batteryLevel = 0,
    this.sessionId,
  });

  factory ConnectionLog.fromMap(String id, Map<String, dynamic> m) =>
      ConnectionLog(
        logId: readString(m['logId'], id),
        userId: readString(m['userId']),
        deviceId: readString(m['deviceId']),
        deviceName: readString(m['deviceName']),
        eventType: ConnectionEventType.fromWire(m['eventType'] as String?),
        timestamp: readDate(m['timestamp']),
        batteryLevel: readInt(m['batteryLevel']),
        sessionId: m['sessionId'] as String?,
      );

  factory ConnectionLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      ConnectionLog.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'logId': logId,
        'userId': userId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'eventType': eventType.wire,
        'timestamp': toTs(timestamp),
        'batteryLevel': batteryLevel,
        'sessionId': sessionId,
      };
}
