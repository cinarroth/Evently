/// Response of the `getMyTicket` callable: everything the user-app ticket
/// screen needs to render the QR code.
class Ticket {
  const Ticket({
    required this.eventId,
    required this.userId,
    required this.qrPayload,
    required this.status,
    required this.checkedIn,
  });

  final String eventId;
  final String userId;

  /// Signed payload `EV1.<eventId>.<userId>.<sig>` rendered as a QR image.
  final String qrPayload;
  final String status;
  final bool checkedIn;

  factory Ticket.fromMap(Map<String, dynamic> map) => Ticket(
        eventId: (map['eventId'] as String?) ?? '',
        userId: (map['userId'] as String?) ?? '',
        qrPayload: (map['qrPayload'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'ACTIVE',
        checkedIn: map['checkedIn'] == true,
      );
}
