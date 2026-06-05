# Example UI (reference only)

These screens are **not** part of the backend deliverable — they are a small,
runnable demo that shows how to wire each `GloveBackend` flow into Flutter
widgets. They use plain Material 3 + callback navigation (no `go_router`,
theme tokens, or state-management package) so they compile in any project.

| File | Shows |
|------|-------|
| `example_app.dart` | `MaterialApp` + shared `GloveBackend` instance |
| `auth_gate.dart` | redirect on `authStateChanges()` |
| `login_screen.dart` | email + Google sign-in, forgot-password link |
| `signup_screen.dart` | registration with **live username availability** |
| `forgot_password_screen.dart` | password reset email |
| `home_shell.dart` | 3-tab shell + unread-alert **badge** |
| `devices_tab.dart` | add / rename / connect / battery (logs + alerts) |
| `translate_tab.dart` | start → gesture → message → end (the full chain) |
| `alerts_tab.dart` | live alert centre, mark read, swipe to delete |

## Run the demo

1. Complete `docs/SETUP_GUIDE.md` (Firebase project + `flutterfire configure`).
2. Point your `main()` at the demo app:

   ```dart
   import 'package:flutter/material.dart';
   import 'package:firebase_core/firebase_core.dart';
   import 'firebase_options.dart';
   import 'example_ui/example_app.dart';

   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await Firebase.initializeApp(
       options: DefaultFirebaseOptions.currentPlatform,
     );
     runApp(const ExampleApp());
   }
   ```

3. `flutter run`.

## Moving these into the real IntelliGlove app

* Replace `Navigator.push(...)` with `context.push(AppRoutes.signup)` etc.
* Replace `Theme.of(context)` colours with your `ThemeProviderScope` tokens.
* Swap the `AppBar` for your `AppTopBar`, and the `NavigationBar` for your
  existing bottom-nav.
* Host the single `GloveBackend` instance in your DI container instead of the
  top-level `backend` in `example_app.dart`.
