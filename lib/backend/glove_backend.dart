// glove_backend.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The single entry point the UI talks to.
//
//  It wires the focused services together into the real-world FLOWS the app
//  needs — signing up (auth + username + profile, atomically), connecting a
//  glove (device update + connection log + alert + last-device, in one call),
//  running a translation session, and so on.
//
//  Usage (e.g. behind a Provider / Riverpod / get_it singleton):
//
//      final backend = GloveBackend();
//      await backend.registerWithEmail(
//        fullName: 'Sara Ali', email: 'sara@x.com',
//        password: 'secret123', username: 'sara_ali',
//      );
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'core/enums.dart';
import 'core/firebase_refs.dart';
import 'models/app_user.dart';
import 'models/glove_device.dart';
import 'models/translation_session.dart';
import 'services/alert_service.dart';
import 'services/auth_service.dart';
import 'services/connection_log_service.dart';
import 'services/device_service.dart';
import 'services/gesture_service.dart';
import 'services/message_service.dart';
import 'services/session_service.dart';
import 'services/user_service.dart';
import 'services/username_service.dart';

class GloveBackend {
  GloveBackend({
    FirebaseFirestore? db,
    AuthService? auth,
    UserService? users,
    UsernameService? usernames,
    DeviceService? devices,
    ConnectionLogService? connectionLogs,
    GestureService? gestures,
    SessionService? sessions,
    MessageService? messages,
    AlertService? alerts,
  })  : _db = db ?? FirebaseFirestore.instance,
        auth = auth ?? AuthService(),
        users = users ?? UserService(),
        usernames = usernames ?? UsernameService(),
        devices = devices ?? DeviceService(),
        connectionLogs = connectionLogs ?? ConnectionLogService(),
        gestures = gestures ?? GestureService(),
        sessions = sessions ?? SessionService(),
        messages = messages ?? MessageService(),
        alerts = alerts ?? AlertService();

  final FirebaseFirestore _db;

  // Sub-services are public so screens can also call them directly.
  final AuthService auth;
  final UserService users;
  final UsernameService usernames;
  final DeviceService devices;
  final ConnectionLogService connectionLogs;
  final GestureService gestures;
  final SessionService sessions;
  final MessageService messages;
  final AlertService alerts;

  String get _uid {
    final id = auth.uid;
    if (id == null) {
      throw StateError('No signed-in user. Call a sign-in method first.');
    }
    return id;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  AUTHENTICATION FLOWS
  // ═══════════════════════════════════════════════════════════════════════

  /// SIGN-UP FLOW (email/password).
  ///   1. validate username format + availability
  ///   2. create the FirebaseAuth credential
  ///   3. set the display name
  ///   4. atomically reserve the username AND create the profile (transaction)
  ///   5. roll back the auth user if the transaction loses a race
  Future<AppUser> registerWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String username,
  }) async {
    final formatError = UsernameService.validateFormat(username);
    if (formatError != null) throw ArgumentError(formatError);

    if (!await usernames.isAvailable(username)) {
      throw UsernameTakenException(username);
    }

    final cred = await auth.createWithEmail(email: email, password: password);
    final user = cred.user!;
    await auth.updateDisplayName(fullName);

    try {
      await _db.runTransaction((txn) async {
        await usernames.reserveInTransaction(txn, username, user.uid);
        txn.set(
          FirebaseRefs.user(user.uid),
          UserService.newProfileData(
            uid: user.uid,
            fullName: fullName,
            email: email,
            uniqueUsername: username,
            authProvider: AuthProviderType.emailPassword,
            photoUrl: user.photoURL,
          ),
        );
      });
    } catch (e) {
      // Username got taken between the pre-check and the transaction:
      // remove the orphaned auth account so the user can retry cleanly.
      await user.delete().catchError((_) {});
      rethrow;
    }

    return (await users.getUser(user.uid))!;
  }

  /// LOGIN FLOW (email/password). Stamps lastLoginAt and returns the profile.
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await auth.signInWithEmail(email: email, password: password);
    final uid = cred.user!.uid;
    await users.touchLastLogin(uid);
    return (await users.getUser(uid)) ??
        // Defensive: profile missing (e.g. created out-of-band) → build one.
        await _ensureProfile(cred.user!, AuthProviderType.emailPassword);
  }

  /// GOOGLE LOGIN FLOW.
  ///   • Returns null if the user cancels the Google picker.
  ///   • First-time Google users get a profile + auto-generated unique
  ///     username; returning users just have lastLoginAt refreshed.
  Future<AppUser?> signInWithGoogle() async {
    final cred = await auth.signInWithGoogle();
    if (cred == null) return null; // cancelled

    final user = cred.user!;
    final existing = await users.getUser(user.uid);
    if (existing != null) {
      await users.touchLastLogin(user.uid);
      return existing;
    }
    return _ensureProfile(user, AuthProviderType.google);
  }

  /// FORGOT-PASSWORD FLOW. Sends the reset email.
  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email);

  Future<void> signOut() => auth.signOut();

  /// USERNAME AVAILABILITY CHECK (for live sign-up validation).
  Future<bool> isUsernameAvailable(String username) =>
      usernames.isAvailable(username);

  /// Creates a profile for an auth user that doesn't have one yet (Google
  /// first sign-in, or recovery). Generates a unique username from the email.
  Future<AppUser> _ensureProfile(User user, AuthProviderType provider) async {
    final seed = (user.email ?? 'user').split('@').first;
    final username = await _uniqueUsernameFrom(seed);

    await _db.runTransaction((txn) async {
      await usernames.reserveInTransaction(txn, username, user.uid);
      txn.set(
        FirebaseRefs.user(user.uid),
        UserService.newProfileData(
          uid: user.uid,
          fullName: user.displayName ?? seed,
          email: user.email ?? '',
          uniqueUsername: username,
          authProvider: provider,
          photoUrl: user.photoURL,
        ),
      );
    });
    return (await users.getUser(user.uid))!;
  }

  /// Turns a seed into a valid, free username (sanitise → pad → de-collide).
  Future<String> _uniqueUsernameFrom(String seed) async {
    var base = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (base.length < 3) base = 'user_$base';
    base = base.substring(0, base.length > 16 ? 16 : base.length);

    var candidate = base;
    final rnd = Random();
    for (var attempt = 0; attempt < 10; attempt++) {
      if (await usernames.isAvailable(candidate)) return candidate;
      candidate = '${base}_${rnd.nextInt(9999)}';
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  DEVICE FLOWS
  // ═══════════════════════════════════════════════════════════════════════

  /// ADD-DEVICE FLOW. Pairs a new glove, bumps the user's device counter,
  /// and raises a "device connected" alert if it pairs in a connected state.
  Future<GloveDevice> addGlove({
    required String deviceName,
    String? deviceId,
    String gloveModel = '',
    String firmwareVersion = '',
  }) async {
    final device = await devices.addDevice(
      ownerId: _uid,
      deviceName: deviceName,
      deviceId: deviceId,
      gloveModel: gloveModel,
      firmwareVersion: firmwareVersion,
    );
    await users.bumpDeviceCount(_uid, 1);
    return device;
  }

  /// DEVICE-RENAME FLOW.
  Future<void> renameGlove(String deviceId, String newName) =>
      devices.renameDevice(deviceId, newName);

  Future<void> removeGlove(String deviceId) async {
    await devices.deleteDevice(deviceId);
    await users.bumpDeviceCount(_uid, -1);
  }

  /// UPDATE-CONNECTION-STATUS FLOW — the orchestrated version.
  /// Updates the device, appends a connection log, raises the right alert,
  /// and (when connecting) records it as the user's last-connected device.
  Future<void> setConnectionStatus(
    String deviceId,
    ConnectionStatus status,
  ) async {
    final device = await devices.getDevice(deviceId);
    if (device == null) throw StateError('Unknown device $deviceId');

    final prev = device.connectionStatus;
    await devices.updateConnectionStatus(deviceId, status);

    // Decide which event/alert this transition represents.
    late final ConnectionEventType event;
    Future<void> raiseAlert;

    switch (status) {
      case ConnectionStatus.connected:
        if (prev == ConnectionStatus.lost) {
          event = ConnectionEventType.connectionRestored;
          raiseAlert =
              alerts.connectionRestored(_uid, deviceId, device.deviceName);
        } else {
          event = ConnectionEventType.connected;
          raiseAlert =
              alerts.deviceConnected(_uid, deviceId, device.deviceName);
        }
        await users.setLastConnectedDevice(_uid, deviceId);
        break;
      case ConnectionStatus.disconnected:
        event = ConnectionEventType.disconnected;
        raiseAlert =
            alerts.deviceDisconnected(_uid, deviceId, device.deviceName);
        break;
      case ConnectionStatus.lost:
        event = ConnectionEventType.connectionLost;
        raiseAlert = alerts.connectionLost(_uid, deviceId, device.deviceName);
        break;
    }

    await Future.wait([
      connectionLogs.log(
        userId: _uid,
        deviceId: deviceId,
        deviceName: device.deviceName,
        eventType: event,
        batteryLevel: device.batteryLevel,
      ),
      raiseAlert,
    ]);
  }

  /// REPORT-BATTERY FLOW. Stores the level and raises a low/critical alert
  /// only when the battery status BUCKET changes (prevents alert spam).
  Future<void> reportBattery(String deviceId, int level) async {
    final device = await devices.getDevice(deviceId);
    if (device == null) throw StateError('Unknown device $deviceId');

    final prev = device.batteryStatus;
    final next = await devices.updateBattery(deviceId, level);
    if (next == prev) return;

    if (next == BatteryStatus.critical) {
      await alerts.batteryCritical(_uid, deviceId, device.deviceName, level);
    } else if (next == BatteryStatus.low) {
      await alerts.batteryLow(_uid, deviceId, device.deviceName, level);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TRANSLATION FLOWS
  // ═══════════════════════════════════════════════════════════════════════

  /// START-SESSION FLOW.
  Future<TranslationSession> startTranslation({
    required String deviceId,
    required String deviceName,
  }) =>
      sessions.startSession(
        userId: _uid,
        deviceId: deviceId,
        deviceName: deviceName,
      );

  /// RECORD-GESTURE FLOW — stores the reading AND emits a realtime message so
  /// the live transcript updates immediately. (GestureReading → Translation
  /// Session → RealtimeMessage, end to end.)
  Future<void> recordGesture({
    required String sessionId,
    required String deviceId,
    required Map<String, dynamic> rawSensorData,
    required String detectedGesture,
    required double confidenceScore,
    bool emitMessage = true,
  }) async {
    await gestures.addReading(
      userId: _uid,
      deviceId: deviceId,
      sessionId: sessionId,
      rawSensorData: rawSensorData,
      detectedGesture: detectedGesture,
      confidenceScore: confidenceScore,
    );

    if (emitMessage && detectedGesture.isNotEmpty) {
      await messages.createMessage(
        userId: _uid,
        deviceId: deviceId,
        sessionId: sessionId,
        translatedText: detectedGesture,
        messageType: MessageType.translation,
      );
    }
  }

  /// END-SESSION FLOW. Aggregates the session and returns the finalised model.
  Future<TranslationSession> endTranslation(String sessionId) =>
      sessions.endSession(sessionId);

  /// Marks a session interrupted (e.g. the glove dropped mid-session).
  Future<TranslationSession> interruptTranslation(String sessionId) =>
      sessions.interruptSession(sessionId);

  // ═══════════════════════════════════════════════════════════════════════
  //  SOS
  // ═══════════════════════════════════════════════════════════════════════

  /// EMERGENCY-SOS FLOW (SOS tab). Raises a critical alert + a system message.
  Future<void> triggerSos({required String deviceId, String? note}) async {
    await alerts.emergencySos(_uid, deviceId, note: note);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HISTORY (read helpers used by Profile / History / Analytics tabs)
  // ═══════════════════════════════════════════════════════════════════════

  Stream<List<TranslationSession>> sessionHistory({int limit = 50}) =>
      sessions.watchHistory(_uid, limit: limit);

  Stream<AppUser?> currentUserProfile() => users.watchUser(_uid);
}
