// firebase_options.dart — runtime Firebase configuration (admin app).
//
// See user_app/lib/firebase_options.dart for the rationale: no real API keys
// are committed; every developer supplies their own project config through
// --dart-define values or regenerates this file with `flutterfire configure`.

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
    iosBundleId: 'com.evently.adminApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: _kApiKey,
    appId: _kAppId,
    messagingSenderId: _kSenderId,
    projectId: _kProjectId,
    storageBucket: _kStorageBucket,
    iosBundleId: 'com.evently.adminApp',
  );
}
