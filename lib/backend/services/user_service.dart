// user_service.dart
// CRUD + streams for the `users/{uid}` profile document.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';
import '../models/app_user.dart';

class UserService {
  final FirebaseFirestore _db;
  UserService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Reads ──────────────────────────────────────────────────────────────

  Future<AppUser?> getUser(String uid) async {
    final doc = await FirebaseRefs.user(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  /// Live profile — drives the Profile tab header and avatar.
  Stream<AppUser?> watchUser(String uid) => FirebaseRefs.user(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  Future<bool> profileExists(String uid) async =>
      (await FirebaseRefs.user(uid).get()).exists;

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Builds the canonical "new profile" map. Server stamps the timestamps.
  /// Used by the sign-up transaction in `GloveBackend`.
  static Map<String, dynamic> newProfileData({
    required String uid,
    required String fullName,
    required String email,
    required String uniqueUsername,
    required AuthProvider authProvider,
    String? photoUrl,
    String? phoneNumber,
  }) =>
      {
        'uid': uid,
        'fullName': fullName.trim(),
        'email': email.trim(),
        'uniqueUsername': uniqueUsername.trim().toLowerCase(),
        'phoneNumber': phoneNumber,
        'photoUrl': photoUrl,
        'createdAt': serverNow,
        'lastLoginAt': serverNow,
        'authProvider': authProvider.wire,
        'role': UserRole.user.wire,
        'totalDevices': 0,
        'totalSessions': 0,
        'lastConnectedDevice': null,
        'accountStatus': AccountStatus.active.wire,
      };

  /// Creates the profile document (non-transactional convenience).
  Future<void> createProfile(Map<String, dynamic> data) =>
      FirebaseRefs.user(readString(data['uid'])).set(data);

  /// Patches editable profile fields. Identity fields are ignored / blocked
  /// by the security rules even if passed.
  Future<void> updateProfile(
    String uid, {
    String? fullName,
    String? phoneNumber,
    String? photoUrl,
  }) {
    return FirebaseRefs.user(uid).update(withoutNulls({
      'fullName': fullName?.trim(),
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
    }));
  }

  /// Stamps `lastLoginAt` on every successful login.
  Future<void> touchLastLogin(String uid) =>
      FirebaseRefs.user(uid).update({'lastLoginAt': serverNow});

  /// Remembers which glove the user most recently connected (Home header).
  Future<void> setLastConnectedDevice(String uid, String deviceId) =>
      FirebaseRefs.user(uid).update({'lastConnectedDevice': deviceId});

  /// Adjusts the cached device counter. (Cloud Functions keep this exact;
  /// the client increment is a best-effort fallback.)
  Future<void> bumpDeviceCount(String uid, int delta) =>
      FirebaseRefs.user(uid).update({'totalDevices': FieldValue.increment(delta)});

  /// Adjusts the cached session counter.
  Future<void> bumpSessionCount(String uid, int delta) =>
      FirebaseRefs.user(uid).update({'totalSessions': FieldValue.increment(delta)});
}
