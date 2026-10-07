// firebase_options.dart — runtime Firebase configuration.
//
// Evently intentionally does NOT commit a real project's API keys. The apps
// read their Firebase configuration from --dart-define values so every
// developer points the apps at their own Firebase project:
//
// flutter run \
//   --dart-define=FIREBASE_API_KEY=AIza... \
//   --dart-define=FIREBASE_PROJECT_ID=my-evently \
//   --dart-define=FIREBASE_APP_ID=1:1234567890:android:abcdef \
//   --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
//   --dart-define=FIREBASE_STORAGE_BUCKET=my-evently.appspot.com
//
// Alternatively run `flutterfire configure` to generate a project-specific
// copy of this file (then keep it out of version control).
//
// Missing values fall back to placeholder strings so `flutter analyze` and
// the emulator suite still work; Firebase.initializeApp only succeeds once
// real values (or the emulators) are provided.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

const String _kApiKey =
    String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'demo-api-key');
const String _kProjectId =
    String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'evently-demo');
const String _kAppId =
    String.fromEnvironment('FIREBASE_APP_ID', defaultValue: 'demo-app-id');
const String _kSenderId =
    String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '0');
const String _kStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET',
    defaultValue: 'evently-demo.appspot.com');

/// Default [FirebaseOptions] for the current platform, sourced from
/// --dart-define values (see file header).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    messagingSenderId: _kSenderId,
    projectId: _kProjectId,
    authDomain: '$_kProjectId.firebaseapp.com',
    storageBucket: _kStorageBucket,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    messagingSenderId: _kSenderId,
    projectId: _kProjectId,
    storageBucket: _kStorageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    messagingSenderId: _kSenderId,
    projectId: _kProjectId,
    storageBucket: _kStorageBucket,
    iosBundleId: 'com.evently.userApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    messagingSenderId: _kSenderId,
    projectId: _kProjectId,
    storageBucket: _kStorageBucket,
    iosBundleId: 'com.evently.userApp',
  );
}
