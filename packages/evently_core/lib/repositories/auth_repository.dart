import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

/// Wraps FirebaseAuth + the users/{uid} profile stream. UI code never touches
/// FirebaseAuth or FirebaseFunctions directly — it talks to repositories.
class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Auth user + Firestore profile combined into one stream.
  Stream<(User?, AppUser?)> get userWithProfile {
    late StreamController<(User?, AppUser?)> controller;
    StreamSubscription<User?>? authSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profileSub;

    User? latestUser;

    void emit(AppUser? profile) {
      if (latestUser != null) {
        controller.add((latestUser, profile));
      }
    }

    controller = StreamController<(User?, AppUser?)>(
      onListen: () {
        authSub = authStateChanges.listen((user) {
          latestUser = user;
          profileSub?.cancel();
          profileSub = null;
          if (user == null) {
            controller.add((null, null));
            return;
          }
          final uid = user.uid;
          profileSub =
              _db.collection('users').doc(uid).snapshots().listen((snap) {
            emit(
                snap.exists ? AppUser.fromDoc(snap) : AppUser.placeholder(uid));
          });
        });
      },
      onCancel: () async {
        await profileSub?.cancel();
        await authSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<UserCredential> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> register(
      String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    await cred.user?.updateDisplayName(displayName);
    return cred;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();

  Future<void> updateProfile({String? displayName, String? photoUrl}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (displayName != null) {
      await user.updateDisplayName(displayName);
      await user.reload();
    }
    await call('updateProfile', {
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
    });
  }

  Future<void> saveFcmToken(String token) =>
      call('saveFcmToken', {'token': token});

  Future<void> setRole(String targetUid, {required bool admin}) => call(
      'setAdminRole',
      {'targetUid': targetUid, 'role': admin ? 'admin' : 'user'});

  /// Generic callable invocation with JSON-friendly payload.
  Future<Map<String, dynamic>> call(
      String function, Map<String, dynamic> data) async {
    final result = await _functions
        .httpsCallable(function,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<dynamic>(data);
    final raw = result.data;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return const <String, dynamic>{};
  }
}
