import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification_item.dart';

/// Inbox entries written by Cloud Functions. Users can only read their own
/// (enforced by rules); marking read happens through the
/// markNotificationsRead callable so the backend can verify ownership.
class NotificationsRepository {
  NotificationsRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  Stream<List<NotificationItem>> watchInbox({int limit = 50}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(NotificationItem.fromDoc).toList());
  }

  Stream<int> watchUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _functions
        .httpsCallable('markNotificationsRead')
        .call<dynamic>({'ids': ids});
  }
}
