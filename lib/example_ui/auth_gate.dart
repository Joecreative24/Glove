// auth_gate.dart
// Listens to the auth state and shows either the sign-in flow or the main
// shell. This is the pattern your router's `redirect` would use instead.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import 'home_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  final GloveBackend backend;
  const AuthGate({super.key, required this.backend});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: backend.auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final signedIn = snap.data != null;
        return signedIn
            ? HomeShell(backend: backend)
            : LoginScreen(backend: backend);
      },
    );
  }
}
