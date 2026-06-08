# Backend tests (Firebase Emulator Suite)

`backend_emulator_test.dart` runs the **real** `GloveBackend` against local
Firebase emulators — so it exercises Firestore, Auth, **and your security
rules** exactly as production would, with zero cloud cost and no real project.

## Prerequisites

* Firebase CLI: `npm install -g firebase-tools`
* The emulators configured in `firebase.json` (already in this repo).
* A target device for `flutter test` (web/desktop is easiest):
  `flutter config --enable-<platform>-desktop` or just use `-d chrome`.

## Run it (one command — emulators auto start & stop)

```bash
firebase emulators:exec --project=demo-intelliglove \
  "flutter test integration_test/backend_emulator_test.dart -d chrome"
```

* `--project=demo-intelliglove` uses a **demo** project id, so the emulators
  run fully offline (no Firebase project or billing needed).
* `emulators:exec` boots Auth + Firestore (loading `firestore.rules`), runs the
  tests, then shuts the emulators down.

### Or run emulators manually

```bash
# terminal 1
firebase emulators:start --project=demo-intelliglove
# terminal 2
flutter test integration_test/backend_emulator_test.dart -d chrome
```

## What is covered

| Test | Verifies |
|------|----------|
| signup creates profile + unique username | auth + username transaction |
| duplicate username throws | uniqueness guard |
| login refreshes lastLoginAt | login flow |
| add + rename glove + counter | device flow + denormalised count |
| connect writes log + alert | orchestration in `setConnectionStatus` |
| critical battery alert | `reportBattery` threshold logic |
| session aggregates + messages | gesture → session → realtime message chain |
| cross-user device read denied | **Firestore security rules** |

> Each test wipes emulator state first (via the emulator REST API) so they run
> independently and in any order.
