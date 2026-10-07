import 'package:cloud_firestore/cloud_firestore.dart';

/// `notifications/{id}` inbox copy written by the notifyUser helper in
/// Cloud Functions. The user app renders these in the notification screen.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final Map<String, String> data;
  final bool read;
  final DateTime? createdAt;

  factory NotificationItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawData = data['data'];
    return NotificationItem(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'generic',
      data: rawData is Map<String, dynamic>
          ? rawData.map((k, v) => MapEntry(k, v.toString()))
          : const <String, String>{},
      read: data['read'] == true,
      createdAt: _dateOf(data['createdAt']),
    );
  }

  static DateTime? _dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
