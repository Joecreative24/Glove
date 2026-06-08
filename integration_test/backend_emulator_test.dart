// backend_emulator_test.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Integration tests that run the REAL backend against the Firebase Emulator
//  Suite (Auth + Firestore). They verify the flows AND the security rules.
//
//  ▶ How to run (emulators auto start/stop, no real Firebase project needed):
//
//      firebase emulators:exec --project=demo-intelliglove \
//        "flutter test integration_test/backend_emulator_test.dart -d <device>"
//
//    where <device> is e.g. `chrome`, `macos`, `linux`, or an Android emulator.
//
//  Or start emulators yourself (`firebase emulators:start`) in one terminal and
//  run the `flutter test ...` line in another.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intelliglove/backend/backend.dart';

const String projectId = 'demo-intelliglove';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late GloveBackend backend;

  setUpAll(() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:123456789:android:demo',
        messagingSenderId: '123456789',
        projectId: projectId,
      ),
    );
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    backend = GloveBackend();
  });

  // Wipe emulator state before each test for isolation.
  setUp(() async {
    await _clearEmulators();
    await FirebaseAuth.instance.signOut();
  });

  Future<AppUser> register(String user) => backend.registerWithEmail(
        fullName: user.toUpperCase(),
        email: '$user@example.com',
        password: 'secret123',
        username: user,
      );

  // ── Auth + usernames ────────────────────────────────────────────────────
  testWidgets('signup creates profile and reserves a unique username',
      (_) async {
    final u = await register('sara_ali');
    expect(u.uniqueUsername, 'sara_ali');
    expect(u.fullName, 'SARA_ALI');
    expect(u.authProvider, AuthProviderType.emailPassword);
    expect(await backend.isUsernameAvailable('sara_ali'), isFalse);

    // A different account cannot claim the same username.
    await backend.signOut();
    await expectLater(
      backend.registerWithEmail(
        fullName: 'Other',
        email: 'other@example.com',
        password: 'secret123',
        username: 'sara_ali',
      ),
      throwsA(isA<UsernameTakenException>()),
    );
  });

  testWidgets('login refreshes lastLoginAt', (_) async {
    await register('login_user');
    await backend.signOut();
    final u = await backend.signInWithEmail(
      email: 'login_user@example.com',
      password: 'secret123',
    );
    expect(u.lastLoginAt, isNotNull);
  });

  // ── Devices ───────────────────────────────────────────────────────────────
  testWidgets('add + rename glove updates the device counter', (_) async {
    await register('dev_user');
    final d = await backend.addGlove(deviceName: 'Glove 1');
    expect(d.deviceName, 'Glove 1');

    final profile = await backend.users.getUser(backend.auth.uid!);
    expect(profile!.totalDevices, 1);

    await backend.renameGlove(d.deviceId, 'Lab Glove');
    final updated = await backend.devices.getDevice(d.deviceId);
    expect(updated!.deviceName, 'Lab Glove');
  });

  testWidgets('connecting a glove writes a log AND a device_connected alert',
      (_) async {
    await register('conn_user');
    final uid = backend.auth.uid!;
    final d = await backend.addGlove(deviceName: 'G');

    await backend.setConnectionStatus(d.deviceId, ConnectionStatus.connected);

    final dev = await backend.devices.getDevice(d.deviceId);
    expect(dev!.isConnected, isTrue);
    expect(dev.connectionStatus, ConnectionStatus.connected);

    final logs =
        await backend.connectionLogs.watchDeviceHistory(d.deviceId).first;
    expect(logs.any((l) => l.eventType == ConnectionEventType.connected), isTrue);

    final alerts = await backend.alerts.watchAlerts(uid).first;
    expect(alerts.any((a) => a.alertType == AlertType.deviceConnected), isTrue);
  });

  testWidgets('critical battery raises a critical alert', (_) async {
    await register('batt_user');
    final uid = backend.auth.uid!;
    final d = await backend.addGlove(deviceName: 'G');

    await backend.reportBattery(d.deviceId, 4);

    final dev = await backend.devices.getDevice(d.deviceId);
    expect(dev!.batteryStatus, BatteryStatus.critical);

    final alerts = await backend.alerts.watchAlerts(uid).first;
    expect(
      alerts.any((a) =>
          a.alertType == AlertType.batteryCritical &&
          a.severity == AlertSeverity.critical),
      isTrue,
    );
  });

  // ── Translation pipeline ────────────────────────────────────────────────
  testWidgets('session aggregates gestures and emits realtime messages',
      (_) async {
    await register('sess_user');
    final d = await backend.addGlove(deviceName: 'G');
    final s = await backend.startTranslation(
        deviceId: d.deviceId, deviceName: d.deviceName);

    await backend.recordGesture(
      sessionId: s.sessionId,
      deviceId: d.deviceId,
      rawSensorData: const {'flex': [1, 2, 3]},
      detectedGesture: 'سلام',
      confidenceScore: 0.9,
    );
    await backend.recordGesture(
      sessionId: s.sessionId,
      deviceId: d.deviceId,
      rawSensorData: const {'flex': [4, 5, 6]},
      detectedGesture: 'شكراً',
      confidenceScore: 0.8,
    );

    final done = await backend.endTranslation(s.sessionId);
    expect(done.status, SessionStatus.completed);
    expect(done.totalGestures, 2);
    expect(done.averageConfidence, closeTo(0.85, 1e-6));
    expect(done.translatedText, contains('سلام'));

    final msgs =
        await backend.messages.watchSessionMessages(s.sessionId).first;
    expect(msgs.length, 2);
  });

  // ── Security rules ──────────────────────────────────────────────────────
  testWidgets('a user CANNOT read another user\'s device', (_) async {
    await register('owner_a');
    final d = await backend.addGlove(deviceName: 'A Glove');
    await backend.signOut();

    await register('intruder_b');
    await expectLater(
      FirebaseRefs.device(d.deviceId).get(),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'permission-denied')),
    );
  });
}

// ── Emulator helpers ──────────────────────────────────────────────────────────

/// Clears all Firestore documents and Auth accounts via the emulator REST API.
Future<void> _clearEmulators() async {
  final client = HttpClient();
  try {
    await _delete(client,
        'http://localhost:8080/emulator/v1/projects/$projectId/databases/(default)/documents');
    await _delete(
        client, 'http://localhost:9099/emulator/v1/projects/$projectId/accounts');
  } finally {
    client.close(force: true);
  }
}

Future<void> _delete(HttpClient client, String url) async {
  final req = await client.deleteUrl(Uri.parse(url));
  req.headers.set('Authorization', 'Bearer owner'); // required by Auth emulator
  final resp = await req.close();
  await resp.drain<void>();
}
