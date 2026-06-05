// realtime_message.dart
// Maps to a document in  realtimeMessages/{messageId}.
//
// The live "chat bubble" stream that the Translate tab listens to. A
// TranslationSession outputs its recognised text here as translation
// messages; alerts and system notices can also surface in the same feed.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_utils.dart';

class RealtimeMessage {
  final String messageId;
  final String userId;
  final String deviceId;
  final String sessionId;
  final String translatedText;
  final String language;
  final DateTime? createdAt;
  final MessageType messageType;

  const RealtimeMessage({
    required this.messageId,
    required this.userId,
    required this.deviceId,
    required this.sessionId,
    required this.translatedText,
    this.language = AppLanguage.arabic,
    this.createdAt,
    this.messageType = MessageType.translation,
  });

  factory RealtimeMessage.fromMap(String id, Map<String, dynamic> m) =>
      RealtimeMessage(
        messageId: readString(m['messageId'], id),
        userId: readString(m['userId']),
        deviceId: readString(m['deviceId']),
        sessionId: readString(m['sessionId']),
        translatedText: readString(m['translatedText']),
        language: readString(m['language'], AppLanguage.arabic),
        createdAt: readDate(m['createdAt']),
        messageType: MessageType.fromWire(m['messageType'] as String?),
      );

  factory RealtimeMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      RealtimeMessage.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'userId': userId,
        'deviceId': deviceId,
        'sessionId': sessionId,
        'translatedText': translatedText,
        'language': language,
        'createdAt': toTs(createdAt),
        'messageType': messageType.wire,
      };
}
