import 'package:cloud_firestore/cloud_firestore.dart';

/// `events/{eventId}/registrations/{userId}` document. Written exclusively by
/// the registerForEvent / cancelRegistration / adminRemoveParticipant
/// callables — the security rules deny all direct client writes.
class Registration {
  const Registration({
    required this.userId,
    required this.eventId,
    required this.registeredAt,
    required this.status,
    required this.checkedIn,
    this.reminderSent = false,
  });

  final String userId;
  final String eventId;
  final DateTime? registeredAt;
  final String status; // ACTIVE | REMOVED
  final bool checkedIn;
  final bool reminderSent;

  bool get isActive => status == 'ACTIVE';

  factory Registration.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Registration(
      userId: (data['userId'] as String?) ?? doc.id,
      eventId: (data['eventId'] as String?) ?? '',
      registeredAt: _dateOf(data['registeredAt']),
      status: (data['status'] as String?) ?? 'ACTIVE',
      checkedIn: data['checkedIn'] == true,
      reminderSent: data['reminderSent'] == true,
    );
  }

  static DateTime? _dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
