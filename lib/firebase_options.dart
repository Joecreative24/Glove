// firebase_options.dart
//
// ⚠️  TEMPLATE / PLACEHOLDER FILE ⚠️
//
// This file is normally GENERATED for you. Do NOT type values by hand.
// Instead run:
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure
//
// …which connects to your Firebase project and OVERWRITES this file with
// the real keys for every platform (Android, iOS, Web, …).
//
// It is committed here only so the project compiles before you run the CLI.
// See docs/SETUP_GUIDE.md, Step 4.

import 'package:firebase_core/firebase_core.dart'
    show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_ME_WEB_API_KEY',
    appId: 'REPLACE_ME_WEB_APP_ID',
    messagingSenderId: 'REPLACE_ME_SENDER_ID',
    projectId: 'intelliglove-REPLACE-ME',
    authDomain: 'intelliglove-REPLACE-ME.firebaseapp.com',
    storageBucket: 'intelliglove-REPLACE-ME.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME_ANDROID_API_KEY',
    appId: 'REPLACE_ME_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_ME_SENDER_ID',
    projectId: 'intelliglove-REPLACE-ME',
    storageBucket: 'intelliglove-REPLACE-ME.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME_IOS_API_KEY',
    appId: 'REPLACE_ME_IOS_APP_ID',
    messagingSenderId: 'REPLACE_ME_SENDER_ID',
    projectId: 'intelliglove-REPLACE-ME',
    storageBucket: 'intelliglove-REPLACE-ME.appspot.com',
    iosBundleId: 'com.example.intelliglove',
  );
}
