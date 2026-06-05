// session_service.dart
// Lifecycle + history for `translationSessions/{sessionId}`.
//
//   start  → status 'active', startedAt stamped
//   end    → status 'completed', endedAt + duration + aggregates computed
//   abort  → status 'interrupted' (e.g. glove connection lost mid-session)
//
// Aggregates (totalGestures, averageConfidence, translatedText) are pulled
// from GestureService so the History and Analytics tabs need no recompute.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/translation_session.dart';
import 'gesture_service.dart';

class SessionService {
  final FirebaseFirestore _db;
  final GestureService _gestures;

  SessionService({FirebaseFirestore? db, GestureService? gestures})
      : _db = db ?? FirebaseFirestore.instance,
        _gestures = gestures ?? GestureService();

  // ── Start ──────────────────────────────────────────────────────────────

  /// Opens a new active session and returns its model.
  Future<TranslationSession> startSession({
    required String userId,
    required String deviceId,
    required String deviceName,
  }) async {
    final ref = FirebaseRefs.translationSessions.doc();
    final data = {
      'sessionId': ref.id,
      'userId': userId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'startedAt': serverNow,
      'endedAt': null,
      'sessionDuration': 0,
      'status': SessionStatus.active.wire,
      'translatedText': '',
      'totalGestures': 0,
      'averageConfidence': 0.0,
      'createdAt': serverNow,
    };
    await ref.set(data);

    // Keep the user's cached session counter in step (Functions also do this).
    await FirebaseRefs.user(userId)
        .update({'totalSessions': FieldValue.increment(1)});

    return TranslationSession.fromMap(ref.id, data);
  }

  // ── Live updates while active ──────────────────────────────────────────

  /// Appends recognised text to the running transcript. `translatedText` is a
  /// single growing string, so we read-modify-write inside a transaction to
  /// stay correct under concurrent gesture writes. (Optional — you can also
  /// rebuild the transcript from gestures when the session ends.)
  Future<void> appendTranslatedText(String sessionId, String text) {
    final ref = FirebaseRefs.session(sessionId);
    return _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final current = readString(snap.data()?['translatedText']);
      final next = current.isEmpty ? text : '$current $text';
      txn.update(ref, {'translatedText': next});
    });
  }

  // ── End / interrupt ─────────────────────────────────────────────────────

  /// Closes a session: computes duration + gesture aggregates and marks it
  /// completed (or interrupted). Returns the finalised model.
  Future<TranslationSession> endSession(
    String sessionId, {
    bool interrupted = false,
  }) async {
    final stats = await _gestures.statsForSession(sessionId);
    final ref = FirebaseRefs.session(sessionId);

    // Read startedAt so we can compute an accurate duration.
    final snap = await ref.get();
    final startedAt = readDate(snap.data()?['startedAt']) ?? DateTime.now();
    final duration = DateTime.now().difference(startedAt).inSeconds;

    final update = {
      'endedAt': serverNow,
      'sessionDuration': duration < 0 ? 0 : duration,
      'status': (interrupted ? SessionStatus.interrupted : SessionStatus.completed)
          .wire,
      'totalGestures': stats.total,
      'averageConfidence': stats.averageConfidence,
      if (stats.concatenatedText.isNotEmpty)
        'translatedText': stats.concatenatedText,
    };
    await ref.update(update);

    final finalSnap = await ref.get();
    return TranslationSession.fromDoc(finalSnap);
  }

  /// Convenience used when the glove drops mid-session.
  Future<TranslationSession> interruptSession(String sessionId) =>
      endSession(sessionId, interrupted: true);

  // ── Reads / history ──────────────────────────────────────────────────────

  Stream<TranslationSession?> watchSession(String sessionId) =>
      FirebaseRefs.session(sessionId)
          .snapshots()
          .map((d) => d.exists ? TranslationSession.fromDoc(d) : null);

  /// The currently-active session for a user (if any) — Translate tab resume.
  Stream<TranslationSession?> watchActiveSession(String uid) =>
      FirebaseRefs.translationSessions
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: SessionStatus.active.wire)
          .orderBy('startedAt', descending: true)
          .limit(1)
          .snapshots()
          .map((q) =>
              q.docs.isEmpty ? null : TranslationSession.fromDoc(q.docs.first));

  /// Session history, newest first — the Translate › History screen.
  Stream<List<TranslationSession>> watchHistory(String uid, {int limit = 50}) =>
      FirebaseRefs.translationSessions
          .where('userId', isEqualTo: uid)
          .orderBy('startedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(TranslationSession.fromDoc).toList());

  Future<void> deleteSession(String sessionId) =>
      FirebaseRefs.session(sessionId).delete();
}
