// gesture_reading.dart
// Maps to a document in  gestureReadings/{readingId}.
//
// One recognised hand gesture. The glove streams raw sensor data; the model
// (on-device or server) classifies it into a gesture + confidence. Readings
// are grouped by `sessionId` and feed the TranslationSession that owns them.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class GestureReading {
  final String readingId;
  final String userId;
  final String deviceId;
  final String sessionId;

  /// Raw flex / IMU values straight from the glove, e.g.
  /// { "flex": [820, 410, 230, 190, 600], "accel": {...}, "gyro": {...} }.
  final Map<String, dynamic> rawSensorData;

  final String detectedGesture; // e.g. the Arabic letter / word recognised
  final double confidenceScore; // 0.0 – 1.0
  final String language;
  final DateTime? timestamp;

  const GestureReading({
    required this.readingId,
    required this.userId,
    required this.deviceId,
    required this.sessionId,
    this.rawSensorData = const {},
    this.detectedGesture = '',
    this.confidenceScore = 0,
    this.language = AppLanguage.arabicSignLanguage,
    this.timestamp,
  });

  factory GestureReading.fromMap(String id, Map<String, dynamic> m) =>
      GestureReading(
        readingId: readString(m['readingId'], id),
        userId: readString(m['userId']),
        deviceId: readString(m['deviceId']),
        sessionId: readString(m['sessionId']),
        rawSensorData:
            (m['rawSensorData'] as Map?)?.cast<String, dynamic>() ?? const {},
        detectedGesture: readString(m['detectedGesture']),
        confidenceScore: readDouble(m['confidenceScore']),
        language: readString(m['language'], AppLanguage.arabicSignLanguage),
        timestamp: readDate(m['timestamp']),
      );

  factory GestureReading.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      GestureReading.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'readingId': readingId,
        'userId': userId,
        'deviceId': deviceId,
        'sessionId': sessionId,
        'rawSensorData': rawSensorData,
        'detectedGesture': detectedGesture,
        'confidenceScore': confidenceScore,
        'language': language,
        'timestamp': toTs(timestamp),
      };
}
