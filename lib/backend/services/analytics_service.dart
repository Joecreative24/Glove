// analytics_service.dart
// Read-only aggregations that power the Analytics tab. Every metric the
// brief asks for has a method here. Simple counts use Firestore's server-side
// `.count()` aggregation; averages / groupings fetch the documents and reduce
// them in Dart (fine for per-user volumes in a student project).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/glove_alert.dart';
import '../models/translation_session.dart';

/// A one-call snapshot of a user's headline numbers for the dashboard cards.
class UserAnalytics {
  final int totalSessions;
  final int totalGestures;
  final Duration averageSessionDuration;
  final double averageConfidence; // 0–1
  final String? mostUsedDeviceId;
  final int connectionLossCount;

  const UserAnalytics({
    required this.totalSessions,
    required this.totalGestures,
    required this.averageSessionDuration,
    required this.averageConfidence,
    required this.mostUsedDeviceId,
    required this.connectionLossCount,
  });
}

class AnalyticsService {
  final FirebaseFirestore _db;
  AnalyticsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Counts ─────────────────────────────────────────────────────────────

  /// Number of sessions per user (server-side aggregate count).
  Future<int> sessionCount(String uid) async {
    final agg = await FirebaseRefs.translationSessions
        .where('userId', isEqualTo: uid)
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Connection-loss frequency (count of 'connection_lost' events).
  Future<int> connectionLossCount(String uid) async {
    final agg = await FirebaseRefs.connectionLogs
        .where('userId', isEqualTo: uid)
        .where('eventType', isEqualTo: ConnectionEventType.connectionLost.wire)
        .count()
        .get();
    return agg.count ?? 0;
  }

  // ── Session-derived metrics ──────────────────────────────────────────────

  Future<List<TranslationSession>> _completedSessions(String uid) async {
    final q = await FirebaseRefs.translationSessions
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: SessionStatus.completed.wire)
        .get();
    return q.docs.map(TranslationSession.fromDoc).toList();
  }

  /// Average session duration across completed sessions.
  Future<Duration> averageSessionDuration(String uid) async {
    final sessions = await _completedSessions(uid);
    if (sessions.isEmpty) return Duration.zero;
    final totalSecs =
        sessions.fold<int>(0, (a, s) => a + s.sessionDuration);
    return Duration(seconds: (totalSecs / sessions.length).round());
  }

  /// Total gestures detected (sum of each session's totalGestures).
  Future<int> totalGesturesDetected(String uid) async {
    final sessions = await _completedSessions(uid);
    return sessions.fold<int>(0, (a, s) => a + s.totalGestures);
  }

  /// Gesture accuracy: weighted average confidence over all gestures.
  Future<double> averageConfidence(String uid) async {
    final sessions = await _completedSessions(uid);
    var gestures = 0;
    var weighted = 0.0;
    for (final s in sessions) {
      gestures += s.totalGestures;
      weighted += s.averageConfidence * s.totalGestures;
    }
    return gestures == 0 ? 0 : weighted / gestures;
  }

  /// Sessions grouped by device → { deviceId: count }.
  Future<Map<String, int>> sessionsPerDevice(String uid) async {
    final q = await FirebaseRefs.translationSessions
        .where('userId', isEqualTo: uid)
        .get();
    final counts = <String, int>{};
    for (final d in q.docs) {
      final id = readString(d.data()['deviceId']);
      if (id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// The most-used glove (device id with the most sessions), or null.
  Future<String?> mostUsedDeviceId(String uid) async {
    final counts = await sessionsPerDevice(uid);
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── Battery / reliability per device ─────────────────────────────────────

  /// Battery problems per device → { deviceId: count of low+critical alerts }.
  Future<Map<String, int>> batteryProblemsPerDevice(String uid) async {
    final q = await FirebaseRefs.alerts
        .where('userId', isEqualTo: uid)
        .where('alertType', whereIn: [
      AlertType.batteryLow.wire,
      AlertType.batteryCritical.wire,
    ]).get();

    final counts = <String, int>{};
    for (final d in q.docs) {
      final a = GloveAlert.fromDoc(d);
      counts[a.deviceId] = (counts[a.deviceId] ?? 0) + 1;
    }
    return counts;
  }

  // ── Time-bucketed usage ──────────────────────────────────────────────────

  /// Sessions per calendar day for the last [days] days → { date: count }.
  /// Use for the daily/weekly/monthly usage charts (sum buckets as needed).
  Future<Map<DateTime, int>> sessionsPerDay(String uid, {int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final q = await FirebaseRefs.translationSessions
        .where('userId', isEqualTo: uid)
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('startedAt')
        .get();

    final buckets = <DateTime, int>{};
    for (final d in q.docs) {
      final started = readDate(d.data()['startedAt']);
      if (started == null) continue;
      final day = DateTime(started.year, started.month, started.day);
      buckets[day] = (buckets[day] ?? 0) + 1;
    }
    return buckets;
  }

  // ── One-shot dashboard overview ──────────────────────────────────────────

  /// Computes the headline metrics in parallel for the dashboard cards.
  Future<UserAnalytics> overview(String uid) async {
    final results = await Future.wait([
      sessionCount(uid), // 0
      totalGesturesDetected(uid), // 1
      averageSessionDuration(uid), // 2
      averageConfidence(uid), // 3
      mostUsedDeviceId(uid), // 4
      connectionLossCount(uid), // 5
    ]);

    return UserAnalytics(
      totalSessions: results[0] as int,
      totalGestures: results[1] as int,
      averageSessionDuration: results[2] as Duration,
      averageConfidence: results[3] as double,
      mostUsedDeviceId: results[4] as String?,
      connectionLossCount: results[5] as int,
    );
  }
}
