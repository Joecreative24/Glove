// gesture_service.dart
// Writer + reader for `gestureReadings/{readingId}`.
//
// Each recognised gesture is appended here and tagged with the `sessionId`
// of the TranslationSession it belongs to. SessionService reads them back to
// compute totals when a session ends. (GestureReading feeds TranslationSession.)

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/gesture_reading.dart';

/// Lightweight roll-up of every reading in a session.
class GestureStats {
  final int total;
  final double averageConfidence; // 0–1
  final String concatenatedText; // gestures joined into a sentence

  const GestureStats({
    required this.total,
    required this.averageConfidence,
    required this.concatenatedText,
  });

  static const empty =
      GestureStats(total: 0, averageConfidence: 0, concatenatedText: '');
}

class GestureService {
  /// Stores one recognised gesture. Returns the new reading id.
  Future<String> addReading({
    required String userId,
    required String deviceId,
    required String sessionId,
    required Map<String, dynamic> rawSensorData,
    required String detectedGesture,
    required double confidenceScore,
    String language = AppLanguage.arabicSignLanguage,
  }) async {
    final ref = FirebaseRefs.gestureReadings.doc();
    await ref.set({
      'readingId': ref.id,
      'userId': userId,
      'deviceId': deviceId,
      'sessionId': sessionId,
      'rawSensorData': rawSensorData,
      'detectedGesture': detectedGesture,
      'confidenceScore': confidenceScore,
      'language': language,
      'timestamp': serverNow,
    });
    return ref.id;
  }

  /// Live readings for a session, in order — drives the Translate ticker.
  Stream<List<GestureReading>> watchSessionReadings(String sessionId) =>
      FirebaseRefs.gestureReadings
          .where('sessionId', isEqualTo: sessionId)
          .orderBy('timestamp')
          .snapshots()
          .map((q) => q.docs.map(GestureReading.fromDoc).toList());

  /// One-shot fetch of all readings in a session (used to aggregate on end).
  Future<List<GestureReading>> getSessionReadings(String sessionId) async {
    final q = await FirebaseRefs.gestureReadings
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('timestamp')
        .get();
    return q.docs.map(GestureReading.fromDoc).toList();
  }

  /// Computes totals for a session from its readings.
  Future<GestureStats> statsForSession(String sessionId) async {
    final readings = await getSessionReadings(sessionId);
    if (readings.isEmpty) return GestureStats.empty;

    final sum = readings.fold<double>(0, (a, r) => a + r.confidenceScore);
    final text = readings
        .map((r) => r.detectedGesture)
        .where((g) => g.isNotEmpty)
        .join(' ');

    return GestureStats(
      total: readings.length,
      averageConfidence: sum / readings.length,
      concatenatedText: text,
    );
  }
}
