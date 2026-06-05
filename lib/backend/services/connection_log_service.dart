// connection_log_service.dart
// Append-only writer + reader for `connectionLogs/{logId}`.
// Every connect / disconnect / lost / restored event is recorded here so
// the app can show a timeline and analytics can measure reliability.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/connection_log.dart';

class ConnectionLogService {
  final FirebaseFirestore _db;
  ConnectionLogService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Records one connection event. Returns the new log id.
  Future<String> log({
    required String userId,
    required String deviceId,
    required String deviceName,
    required ConnectionEventType eventType,
    int batteryLevel = 0,
    String? sessionId,
  }) async {
    final ref = FirebaseRefs.connectionLogs.doc();
    await ref.set({
      'logId': ref.id,
      'userId': userId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'eventType': eventType.wire,
      'timestamp': serverNow,
      'batteryLevel': batteryLevel,
      'sessionId': sessionId,
    });
    return ref.id;
  }

  /// Full connection history for a user, newest first.
  Stream<List<ConnectionLog>> watchUserHistory(String uid, {int limit = 100}) =>
      FirebaseRefs.connectionLogs
          .where('userId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(ConnectionLog.fromDoc).toList());

  /// History for a single device (Device detail screen).
  Stream<List<ConnectionLog>> watchDeviceHistory(String deviceId,
          {int limit = 100}) =>
      FirebaseRefs.connectionLogs
          .where('deviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(ConnectionLog.fromDoc).toList());
}
