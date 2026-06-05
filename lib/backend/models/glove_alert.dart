// glove_alert.dart
// Maps to a document in  alerts/{alertId}.
//
// A user-facing notification: battery low/critical, connection lost/restored,
// device connected/disconnected, or an emergency SOS. Drives the in-app
// alert centre and (via Cloud Functions + FCM) push notifications.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class GloveAlert {
  final String alertId;
  final String userId;
  final String deviceId;
  final AlertType alertType;
  final String title;
  final String message;
  final AlertSeverity severity;
  final bool isRead;
  final DateTime? createdAt;

  const GloveAlert({
    required this.alertId,
    required this.userId,
    required this.deviceId,
    required this.alertType,
    required this.title,
    required this.message,
    this.severity = AlertSeverity.low,
    this.isRead = false,
    this.createdAt,
  });

  factory GloveAlert.fromMap(String id, Map<String, dynamic> m) => GloveAlert(
        alertId: readString(m['alertId'], id),
        userId: readString(m['userId']),
        deviceId: readString(m['deviceId']),
        alertType: AlertType.fromWire(m['alertType'] as String?),
        title: readString(m['title']),
        message: readString(m['message']),
        severity: AlertSeverity.fromWire(m['severity'] as String?),
        isRead: readBool(m['isRead']),
        createdAt: readDate(m['createdAt']),
      );

  factory GloveAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      GloveAlert.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'alertId': alertId,
        'userId': userId,
        'deviceId': deviceId,
        'alertType': alertType.wire,
        'title': title,
        'message': message,
        'severity': severity.wire,
        'isRead': isRead,
        'createdAt': toTs(createdAt),
      };
}
