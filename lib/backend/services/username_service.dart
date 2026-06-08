// username_service.dart
// Owns the `usernames/{username}` reservation index that guarantees every
// uniqueUsername is globally unique and lets the sign-up screen check
// availability in a single fast document read.
//
// Document shape:  usernames/{lowercased_username} → { uid, createdAt }

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';

/// Thrown when a requested username is already claimed.
class UsernameTakenException implements Exception {
  final String username;
  UsernameTakenException(this.username);
  @override
  String toString() => 'Username "@$username" is already taken.';
}

class UsernameService {
  final FirebaseFirestore _db;
  UsernameService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Allowed: 3–20 chars, lower-case letters, digits, underscore.
  static final RegExp _pattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Returns null if [raw] is a valid format, or a human message if not.
  static String? validateFormat(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return 'Please choose a username.';
    if (name.length < 3) return 'Username must be at least 3 characters.';
    if (name.length > 20) return 'Username must be 20 characters or fewer.';
    if (!_pattern.hasMatch(name)) {
      return 'Use only lower-case letters, numbers and underscores.';
    }
    return null;
  }

  /// Fast existence check used by the sign-up form (single doc read).
  /// Returns true when the username is free to claim.
  Future<bool> isAvailable(String username) async {
    final doc = await FirebaseRefs.username(username).get();
    return !doc.exists;
  }

  /// Claims [username] for [uid] **inside an existing transaction**.
  /// Re-reads the doc to guarantee atomicity against a racing sign-up.
  /// Throws [UsernameTakenException] if it was taken in the meantime.
  Future<void> reserveInTransaction(
    Transaction txn,
    String username,
    String uid,
  ) async {
    final ref = FirebaseRefs.username(username);
    final snap = await txn.get(ref);
    if (snap.exists) throw UsernameTakenException(username);
    txn.set(ref, {'uid': uid, 'createdAt': serverNow});
  }

  /// Releases a username (e.g. when changing it or deleting an account).
  Future<void> release(String username) =>
      FirebaseRefs.username(username).delete();

  /// Changes a user's username atomically: claim the new one, free the old.
  Future<void> changeUsername({
    required String uid,
    required String oldUsername,
    required String newUsername,
  }) async {
    await _db.runTransaction((txn) async {
      await reserveInTransaction(txn, newUsername, uid);
      txn.delete(FirebaseRefs.username(oldUsername));
      txn.update(FirebaseRefs.user(uid), {
        'uniqueUsername': newUsername.trim().toLowerCase(),
      });
    });
  }
}
