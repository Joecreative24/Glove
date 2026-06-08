// example_app.dart
// ─────────────────────────────────────────────────────────────────────────────
//  REFERENCE UI — NOT part of the backend deliverable.
//
//  A tiny, dependency-light example app that wires the screens below to
//  `GloveBackend`. It uses plain Material widgets and callback navigation so it
//  compiles anywhere (no go_router / theme tokens / state-mgmt package needed).
//
//  In your real IntelliGlove app you would instead:
//    • drop these flows into your existing go_router routes (AppRoutes.*)
//    • restyle with your ThemeProviderScope tokens + AppTopBar
//    • host a single GloveBackend instance in your DI (get_it / Provider / Riverpod)
//
//  To preview this example standalone, point your main() at ExampleApp:
//
//      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//      runApp(const ExampleApp());
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../backend/backend.dart';
import 'auth_gate.dart';

/// A process-wide backend instance. In production prefer proper DI.
final GloveBackend backend = GloveBackend();

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntelliGlove (Backend Demo)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF22D3EE), // cyan, matches the app accent
        brightness: Brightness.dark,
      ),
      home: AuthGate(backend: backend),
    );
  }
}
