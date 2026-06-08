// translation_session.dart
// Maps to a document in  translationSessions/{sessionId}.
//
// A continuous translation run: the user starts signing, gestures stream in,
// and the session accumulates them into `translatedText`. Closing the
// session stamps `endedAt` + `sessionDuration` and computes aggregates used
// throughout the Analytics tab.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class TranslationSession {
  final String sessionId;
  final String userId;
  final String deviceId;
  final String deviceName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int sessionDuration; // seconds
  final SessionStatus status;
  final String translatedText;
  final int totalGestures;
  final double averageConfidence; // 0.0 – 1.0
  final DateTime? createdAt;

  const TranslationSession({
    required this.sessionId,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    this.startedAt,
    this.endedAt,
    this.sessionDuration = 0,
    this.status = SessionStatus.active,
    this.translatedText = '',
    this.totalGestures = 0,
    this.averageConfidence = 0,
    this.createdAt,
  });

  factory TranslationSession.fromMap(String id, Map<String, dynamic> m) =>
      TranslationSession(
        sessionId: readString(m['sessionId'], id),
        userId: readString(m['userId']),
        deviceId: readString(m['deviceId']),
        deviceName: readString(m['deviceName']),
        startedAt: readDate(m['startedAt']),
        endedAt: readDate(m['endedAt']),
        sessionDuration: readInt(m['sessionDuration']),
        status: SessionStatus.fromWire(m['status'] as String?),
        translatedText: readString(m['translatedText']),
        totalGestures: readInt(m['totalGestures']),
        averageConfidence: readDouble(m['averageConfidence']),
        createdAt: readDate(m['createdAt']),
      );

  factory TranslationSession.fromDoc(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      TranslationSession.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'userId': userId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'startedAt': toTs(startedAt),
        'endedAt': toTs(endedAt),
        'sessionDuration': sessionDuration,
        'status': status.wire,
        'translatedText': translatedText,
        'totalGestures': totalGestures,
        'averageConfidence': averageConfidence,
        'createdAt': toTs(createdAt),
      };

  bool get isActive => status == SessionStatus.active;

  /// Convenience for the history list ("3m 24s").
  String get durationLabel {
    final d = Duration(seconds: sessionDuration);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}
