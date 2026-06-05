// alert_service.dart
// Writer + reader for `alerts/{alertId}`, plus a typed helper for every
// alert the app raises. Drives the in-app alert centre and the unread badge;
// a Cloud Function fans each new alert out as an FCM push notification.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/glove_alert.dart';

class AlertService {
  final FirebaseFirestore _db;
  AlertService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Generic create ──────────────────────────────────────────────────────

  /// Creates an alert document and returns its id.
  Future<String> create({
    required String userId,
    required String deviceId,
    required AlertType alertType,
    required String title,
    required String message,
    AlertSeverity severity = AlertSeverity.low,
  }) async {
    final ref = FirebaseRefs.alerts.doc();
    await ref.set({
      'alertId': ref.id,
      'userId': userId,
      'deviceId': deviceId,
      'alertType': alertType.wire,
      'title': title,
      'message': message,
      'severity': severity.wire,
      'isRead': false,
      'createdAt': serverNow,
    });
    return ref.id;
  }

  // ── Typed helpers (one per required alert) ───────────────────────────────

  Future<String> deviceConnected(String uid, String deviceId, String name) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.deviceConnected,
        title: 'Device connected',
        message: '$name is now connected.',
        severity: AlertSeverity.low,
      );

  Future<String> deviceDisconnected(String uid, String deviceId, String name) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.deviceDisconnected,
        title: 'Device disconnected',
        message: '$name has been disconnected.',
        severity: AlertSeverity.medium,
      );

  Future<String> connectionLost(String uid, String deviceId, String name) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.connectionLost,
        title: 'Connection lost',
        message: 'Lost connection to $name.',
        severity: AlertSeverity.high,
      );

  Future<String> connectionRestored(String uid, String deviceId, String name) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.connectionRestored,
        title: 'Connection restored',
        message: '$name is back online.',
        severity: AlertSeverity.low,
      );

  Future<String> batteryLow(String uid, String deviceId, String name, int pct) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.batteryLow,
        title: 'Battery low',
        message: '$name battery is at $pct%. Consider charging it.',
        severity: AlertSeverity.medium,
      );

  Future<String> batteryCritical(
          String uid, String deviceId, String name, int pct) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.batteryCritical,
        title: 'Battery critical',
        message: '$name battery is at $pct%. Charge now to avoid shutdown.',
        severity: AlertSeverity.critical,
      );

  /// Emergency SOS raised from the SOS tab.
  Future<String> emergencySos(String uid, String deviceId, {String? note}) =>
      create(
        userId: uid,
        deviceId: deviceId,
        alertType: AlertType.emergencySos,
        title: 'Emergency SOS',
        message: note?.trim().isNotEmpty == true
            ? note!.trim()
            : 'An emergency SOS was triggered.',
        severity: AlertSeverity.critical,
      );

  // ── Reads ──────────────────────────────────────────────────────────────

  /// All alerts for a user, newest first (the alert centre list).
  Stream<List<GloveAlert>> watchAlerts(String uid, {int limit = 100}) =>
      FirebaseRefs.alerts
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(GloveAlert.fromDoc).toList());

  /// Unread alerts only — feeds the bell-icon badge.
  Stream<List<GloveAlert>> watchUnread(String uid) => FirebaseRefs.alerts
      .where('userId', isEqualTo: uid)
      .where('isRead', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map(GloveAlert.fromDoc).toList());

  /// Live unread count for the badge number.
  Stream<int> watchUnreadCount(String uid) => FirebaseRefs.alerts
      .where('userId', isEqualTo: uid)
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((q) => q.docs.length);

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> markRead(String alertId) =>
      FirebaseRefs.alerts.doc(alertId).update({'isRead': true});

  /// Marks every unread alert for a user as read, in one batch.
  Future<void> markAllRead(String uid) async {
    final unread = await FirebaseRefs.alerts
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> delete(String alertId) =>
      FirebaseRefs.alerts.doc(alertId).delete();
}
