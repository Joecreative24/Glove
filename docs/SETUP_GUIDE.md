# Setup Guide — Intelligent Glove Firebase Backend

This guide walks you through setting the backend up **on your own computer**,
end to end. Follow the steps in order. Commands are written for macOS / Linux;
on Windows use PowerShell (the `firebase` / `flutter` commands are identical).

> **What you are setting up:** Firebase Authentication (email + Google),
> Cloud Firestore (8 collections), Storage (profile photos), optional Cloud
> Functions (push + username), and the Flutter data layer in `lib/backend/`.

---

## 0. Prerequisites (install once)

| Tool | Why | Install |
|------|-----|---------|
| **Flutter SDK** (3.19+) | builds the app | <https://docs.flutter.dev/get-started/install> |
| **Node.js** (18 or 20) | Firebase CLI + Functions | <https://nodejs.org> |
| **Firebase CLI** | deploy rules / functions | `npm install -g firebase-tools` |
| **FlutterFire CLI** | generates `firebase_options.dart` | `dart pub global activate flutterfire_cli` |
| **A Google account** | to create the Firebase project | — |

Verify everything is on your `PATH`:

```bash
flutter --version
node --version
firebase --version
flutterfire --version
```

Log the Firebase CLI into your Google account:

```bash
firebase login
```

---

## 1. Put this backend into your Flutter app

You have two options.

**A) You already have the IntelliGlove Flutter app** (the one with
`app_routes.dart`, the theme, etc.):

1. Copy the `lib/backend/` folder into your app's `lib/`.
2. Copy `firestore.rules`, `storage.rules`, `firestore.indexes.json`,
   `firebase.json`, `.firebaserc`, and the `functions/` folder into the
   **root** of your app.
3. Merge the `dependencies:` block from this repo's `pubspec.yaml` into your
   app's `pubspec.yaml`.

**B) Start from this repo directly** — it is already a valid Flutter package
layout; just add your UI under `lib/`.

Then pull the packages:

```bash
flutter pub get
```

---

## 2. Create the Firebase project

1. Go to <https://console.firebase.google.com> → **Add project**.
2. Name it e.g. `intelliglove` and finish the wizard (Analytics optional).
3. Open the project. You'll connect to it from the CLI in the next step.

---

## 3. Connect the project to the CLI

Edit **`.firebaserc`** and replace the placeholder with your real project id:

```json
{ "projects": { "default": "intelliglove-1a2b3c" } }
```

(Find the id under **Project settings → General → Project ID**.)

---

## 4. Generate `firebase_options.dart`

From the app root, run:

```bash
flutterfire configure
```

* Pick your project.
* Select the platforms you target (Android, iOS, Web…).

This **overwrites** the placeholder `lib/firebase_options.dart` with real keys
and registers an app per platform. It also drops `google-services.json`
(Android) and `GoogleService-Info.plist` (iOS) into place.

> These generated files contain API keys but are **safe to keep out of git**
> (already in `.gitignore`). They are not secrets in the password sense, but
> keeping them untracked avoids confusion across machines.

---

## 5. Enable Authentication providers

Firebase Console → **Build → Authentication → Get started → Sign-in method**:

1. Enable **Email/Password**.
2. Enable **Google** (set the support email).

### Google Sign-In platform wiring

* **Android** — add your debug **SHA-1** (and SHA-256) fingerprint:

  ```bash
  cd android && ./gradlew signingReport
  ```

  Copy the `SHA1` value → Console → **Project settings → Your apps → Android →
  Add fingerprint**. Then re-download `google-services.json` and replace the
  one in `android/app/`.

* **iOS** — open `ios/Runner/Info.plist` and add the reversed client ID
  (found in `GoogleService-Info.plist` as `REVERSED_CLIENT_ID`) as a URL
  scheme. See the [google_sign_in iOS docs](https://pub.dev/packages/google_sign_in#ios-integration).

* **Web** — add the OAuth web client ID to `web/index.html`:

  ```html
  <meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
  ```

---

## 6. Create the Firestore database

Console → **Build → Firestore Database → Create database** →
start in **Production mode** → choose a location (e.g. `eur3` /
`nam5` — pick the one closest to your users; **you cannot change it later**).

---

## 7. Deploy security rules + indexes

From the app root:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

* Rules lock every collection to its owner (see `firestore.rules`).
* Indexes back the analytics / history queries (see `firestore.indexes.json`).

Index builds take a few minutes; watch progress under **Firestore → Indexes**.

---

## 8. Initialise Firebase in your app

In your `main.dart` (or wherever the app boots):

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

Now you can use the backend anywhere:

```dart
import 'package:intelliglove/backend/backend.dart';

final backend = GloveBackend(); // make this a singleton in your DI setup

// Sign up
await backend.registerWithEmail(
  fullName: 'Sara Ali',
  email: 'sara@example.com',
  password: 'strongPass123',
  username: 'sara_ali',
);
```

Run it:

```bash
flutter run
```

---

## 9. (Optional) Cloud Functions — push notifications & secure usernames

Cloud Functions require the **Blaze (pay-as-you-go)** plan. The app works
fully **without** them (the client handles alerts/logs). Deploy them to add:

* **Push notifications** when an alert is created (`sendAlertPush`).
* **Server-validated username reservation** (`reserveUsername`).

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

To enable **Firebase Cloud Messaging**:

1. Console → **Project settings → Cloud Messaging** (no extra setup for the
   default sender on modern SDKs).
2. After login, call once in the app:

   ```dart
   final messaging = MessagingService();
   await messaging.requestPermission();
   await messaging.registerToken(backend.auth.uid!);
   ```

3. For Android push, ensure `android/app/google-services.json` is present
   (step 4) — that's all the v2 Messaging SDK needs.

> ⚠️ If you turn on the **gated** functions (`ENABLE_SERVER_SIDE_ALERTS=true`),
> delete the matching client-side calls in `GloveBackend.setConnectionStatus`
> / `reportBattery` so alerts aren't created twice. See `functions/index.js`.

---

## 10. (Recommended) Test locally with the Emulator Suite

No cloud writes, instant resets — perfect while developing:

```bash
firebase emulators:start
```

Point the app at the emulators (debug builds only) right after
`Firebase.initializeApp`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

if (kDebugMode) {
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

---

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| `PERMISSION_DENIED` on a read/write | The doc's `userId`/`ownerId` must equal the signed-in uid; check you're querying with `where('userId', isEqualTo: uid)`. |
| `FAILED_PRECONDITION: The query requires an index` | Click the link in the error, or run `firebase deploy --only firestore:indexes`. |
| Google sign-in returns null | User cancelled the picker — expected. If it always fails on Android, your SHA-1 isn't registered (step 5). |
| `MissingPluginException` | Stop the app and do a full `flutter clean && flutter pub get && flutter run`. |
| Functions deploy says "Blaze required" | Upgrade the project plan, or skip functions (the app still works). |
