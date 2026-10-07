import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, user }

/// `users/{userId}` profile document. Created by the onUserCreated trigger;
/// clients may only update displayName / photoUrl on their own profile.
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    this.hasFcmToken = false,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final bool hasFcmToken;

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final role =
        (data['role'] as String?) == 'admin' ? UserRole.admin : UserRole.user;
    return AppUser(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? 'Anonymous',
      photoUrl: data['photoUrl'] as String?,
      role: role,
      hasFcmToken: (data['fcmToken'] as String?)?.isNotEmpty == true,
    );
  }

  /// Anonymous placeholder while the profile document is still bootstrapping.
  factory AppUser.placeholder(String uid) => AppUser(
      uid: uid, displayName: 'Loading…', photoUrl: null, role: UserRole.user);
}
