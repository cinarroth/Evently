/// Lifecycle status of an event. Mirrors the TypeScript `EventStatus` union in
/// functions/src/events.ts — keep both in sync.
enum EventStatus {
  upcoming('UPCOMING'),
  ongoing('ONGOING'),
  completed('COMPLETED'),
  canceled('CANCELED');

  const EventStatus(this.wire);

  /// Value stored in Firestore.
  final String wire;

  static EventStatus fromWire(String? value) {
    for (final s in EventStatus.values) {
      if (s.wire == value) return s;
    }
    return EventStatus.upcoming;
  }

  bool get isPast =>
      this == EventStatus.completed || this == EventStatus.canceled;
}

/// Categories used by the filter chips in both apps. `general` is the
/// fallback when an event has no explicit category.
const eventCategories = <String>[
  'general',
  'academic',
  'sports',
  'culture',
  'music',
  'technology',
  'community',
];
