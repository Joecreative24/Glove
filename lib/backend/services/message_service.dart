// message_service.dart
// Writer + live reader for `realtimeMessages/{messageId}`.
//
// This is the stream the Translate tab renders as chat bubbles. A
// TranslationSession outputs its recognised text here (messageType
// 'translation'); alerts/system notices can share the same feed.

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/realtime_message.dart';

class MessageService {
  /// Pushes one translated message into the live feed. Returns its id.
  Future<String> createMessage({
    required String userId,
    required String deviceId,
    required String sessionId,
    required String translatedText,
    String language = AppLanguage.arabic,
    MessageType messageType = MessageType.translation,
  }) async {
    final ref = FirebaseRefs.realtimeMessages.doc();
    await ref.set({
      'messageId': ref.id,
      'userId': userId,
      'deviceId': deviceId,
      'sessionId': sessionId,
      'translatedText': translatedText,
      'language': language,
      'createdAt': serverNow,
      'messageType': messageType.wire,
    });
    return ref.id;
  }

  /// Live messages for one session, oldest → newest (chat order).
  Stream<List<RealtimeMessage>> watchSessionMessages(String sessionId) =>
      FirebaseRefs.realtimeMessages
          .where('sessionId', isEqualTo: sessionId)
          .orderBy('createdAt')
          .snapshots()
          .map((q) => q.docs.map(RealtimeMessage.fromDoc).toList());

  /// Recent messages across all of a user's sessions.
  Stream<List<RealtimeMessage>> watchRecentForUser(String uid,
          {int limit = 50}) =>
      FirebaseRefs.realtimeMessages
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(RealtimeMessage.fromDoc).toList());
}
