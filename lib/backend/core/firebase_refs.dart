// firebase_refs.dart
// One central place that names every Firestore collection and exposes a
// typed reference to it. Import this instead of hard-coding collection
// strings — that way a rename is a one-line change.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical collection names. Keep these in sync with `firestore.rules`.
class Collections {
  Collections._();

  static const users = 'users';
  static const usernames = 'usernames';
  static const devices = 'devices';
  static const connectionLogs = 'connectionLogs';
  static const gestureReadings = 'gestureReadings';
  static const translationSessions = 'translationSessions';
  static const realtimeMessages = 'realtimeMessages';
  static const alerts = 'alerts';
}

/// Typed, ready-to-use collection references.
class FirebaseRefs {
  FirebaseRefs._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get users =>
      db.collection(Collections.users);

  static CollectionReference<Map<String, dynamic>> get usernames =>
      db.collection(Collections.usernames);

  static CollectionReference<Map<String, dynamic>> get devices =>
      db.collection(Collections.devices);

  static CollectionReference<Map<String, dynamic>> get connectionLogs =>
      db.collection(Collections.connectionLogs);

  static CollectionReference<Map<String, dynamic>> get gestureReadings =>
      db.collection(Collections.gestureReadings);

  static CollectionReference<Map<String, dynamic>> get translationSessions =>
      db.collection(Collections.translationSessions);

  static CollectionReference<Map<String, dynamic>> get realtimeMessages =>
      db.collection(Collections.realtimeMessages);

  static CollectionReference<Map<String, dynamic>> get alerts =>
      db.collection(Collections.alerts);

  // Document helpers ─────────────────────────────────────────────────────
  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      users.doc(uid);

  /// Usernames are stored lower-cased so checks are case-insensitive.
  static DocumentReference<Map<String, dynamic>> username(String name) =>
      usernames.doc(name.trim().toLowerCase());

  static DocumentReference<Map<String, dynamic>> device(String id) =>
      devices.doc(id);

  static DocumentReference<Map<String, dynamic>> session(String id) =>
      translationSessions.doc(id);
}
