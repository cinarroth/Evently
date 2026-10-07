import 'package:cloud_firestore/cloud_firestore.dart';

import 'event_status.dart';

/// Firestore document shape for `events/{eventId}`. Server-owned fields
/// (participantsCount, checkedInCount, status, qrToken) are read-only from the
/// client; only `adminCreateEvent`/`adminUpdateEvent` change them.
class Event {
  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.coverImageUrl,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.participantsCount,
    required this.checkedInCount,
    required this.status,
    required this.category,
    required this.organizerId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final String? coverImageUrl;
  final String location;
  final DateTime startAt;
  final DateTime? endAt;
  final int capacity;
  final int participantsCount;
  final int checkedInCount;
  final EventStatus status;
  final String category;
  final String organizerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get spotsAvailable => capacity - participantsCount;
  bool get isFull => spotsAvailable <= 0;
  bool get isUpcoming =>
      status == EventStatus.upcoming && startAt.isAfter(DateTime.now());
  bool get isPast =>
      status.isPast || (endAt != null && endAt!.isBefore(DateTime.now()));

  /// Immutable field-level copy used by the admin editor.
  Event copyWith({
    String? id,
    String? title,
    String? description,
    String? coverImageUrl,
    bool clearCover = false,
    String? location,
    DateTime? startAt,
    DateTime? endAt,
    bool clearEnd = false,
    int? capacity,
    int? participantsCount,
    int? checkedInCount,
    EventStatus? status,
    String? category,
    String? organizerId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverImageUrl: clearCover ? null : (coverImageUrl ?? this.coverImageUrl),
      location: location ?? this.location,
      startAt: startAt ?? this.startAt,
      endAt: clearEnd ? null : (endAt ?? this.endAt),
      capacity: capacity ?? this.capacity,
      participantsCount: participantsCount ?? this.participantsCount,
      checkedInCount: checkedInCount ?? this.checkedInCount,
      status: status ?? this.status,
      category: category ?? this.category,
      organizerId: organizerId ?? this.organizerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Event.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Event(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      coverImageUrl: data['coverImageUrl'] as String?,
      location: (data['location'] as String?) ?? '',
      startAt: _dateOf(data['startAt']) ?? DateTime.now(),
      endAt: _dateOf(data['endAt']),
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      participantsCount: (data['participantsCount'] as num?)?.toInt() ?? 0,
      checkedInCount: (data['checkedInCount'] as num?)?.toInt() ?? 0,
      status: EventStatus.fromWire(data['status'] as String?),
      category: (data['category'] as String?) ?? 'general',
      organizerId: (data['organizerId'] as String?) ?? '',
      createdAt: _dateOf(data['createdAt']),
      updatedAt: _dateOf(data['updatedAt']),
    );
  }

  static DateTime? _dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Client-side editable fields — must match the rules + callable whitelist.
  Map<String, dynamic> editableMap() => {
        'title': title,
        'description': description,
        'coverImageUrl': coverImageUrl,
        'location': location,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'capacity': capacity,
        'category': category,
      };
}
