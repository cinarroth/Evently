# Evently — Developer Guide

Prerequisites:

- Flutter SDK 3.24+ (Dart 3.5+)
- Node.js 20/22 + npm
- Java 17+ (Android builds / Firebase emulator)
- Firebase CLI: `npm install -g firebase-tools`

## One-time setup

```bash
# 1. Install Dart/Node dependencies
cd packages/evently_core && flutter pub get && cd ../..
cd user_app && flutter pub get && cd ..
cd admin_app && flutter pub get && cd ..
cd functions && npm install && cd ..

# 2. Point the apps at your own Firebase project
#    Either regenerate firebase_options.dart:
flutterfire configure --project=<your-project-id>   # run inside each app folder
#    …or pass --dart-define values (see lib/firebase_options.dart in each app).

# 3. Log in for deploys (not needed for emulators)
firebase login
```

## Running locally with the emulator suite

```bash
# Terminal 1 — start emulators (auth, firestore, functions, storage, UI)
firebase emulators:start

# Terminal 2 — user app against the emulators
cd user_app && flutter run --dart-define=EMULATOR=true

# Terminal 3 — admin app against the emulators
cd admin_app && flutter run --dart-define=EMULATOR=true
```

On an Android emulator the default host `10.0.2.2` is used automatically; on
desktop/web pass `--dart-define=EMULATOR_HOST=localhost`.

Emulator UI: <http://localhost:4000>

### Creating the first admin

With the emulators running:

```bash
# Grab an ID token from the app (or emulator UI) then from another terminal:
curl -s -X POST "http://localhost:5001/evently-demo/us-central1/setAdminRole" \
  -H "Content-Type: application/json" \
  -d '{"data":{"targetUid":"<UID>","role":"admin"}}'
```

In production, use the admin app once bootstrapped, or the Firebase Console
(Authentication → user → Custom claims: `{"admin": true}`) plus a `role:
"admin"` field on `users/{uid}`.

## Seeding demo data

```bash
cd functions && npm run seed
```

Creates a demo admin + users and a handful of events for manual testing.

## Running tests

```bash
# Dart unit tests
cd packages/evently_core && flutter test

# Cloud Functions tests (auto-starts emulators)
cd functions && npm test

# Firestore rules tests (auto-starts emulators)
cd tests/rules && npm install && npm test
```

## Lint / format gates (same as CI)

```bash
cd packages/evently_core && flutter analyze && dart format --set-exit-if-changed --output=none lib test
cd user_app         && flutter analyze && dart format --set-exit-if-changed --output=none lib test
cd admin_app        && flutter analyze && dart format --set-exit-if-changed --output=none lib test
cd functions        && npm run build
```

## Deploying

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
```

Deploy the Flutter apps to App Stores / Play Console with your normal
release pipeline (`flutter build appbundle`, `flutter build ipa`).
