import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evently_core/models/event.dart';
import 'package:evently_core/models/event_status.dart';
import 'package:evently_core/models/registration.dart';
import 'package:evently_core/models/ticket.dart';
import 'package:evently_core/services/error_translator.dart';

void main() {
  group('EventStatus', () {
    test('round-trips through wire format', () {
      for (final s in EventStatus.values) {
        expect(EventStatus.fromWire(s.wire), s);
      }
    });

    test('falls back to upcoming for unknown values', () {
      expect(EventStatus.fromWire('UNKNOWN'), EventStatus.upcoming);
      expect(EventStatus.fromWire(null), EventStatus.upcoming);
    });

    test('past detection', () {
      expect(EventStatus.completed.isPast, isTrue);
      expect(EventStatus.canceled.isPast, isTrue);
      expect(EventStatus.upcoming.isPast, isFalse);
    });
  });

  group('Event', () {
    final now = DateTime.now();
    Event makeEvent({
      int capacity = 10,
      int participants = 4,
      EventStatus status = EventStatus.upcoming,
      DateTime? start,
      DateTime? end,
    }) {
      return Event(
        id: 'e1',
        title: 'T',
        description: 'D',
        coverImageUrl: null,
        location: 'L',
        startAt: start ?? now.add(const Duration(days: 2)),
        endAt: end,
        capacity: capacity,
        participantsCount: participants,
        checkedInCount: 0,
        status: status,
        category: 'general',
        organizerId: 'o',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('spots available math', () {
      final e = makeEvent(capacity: 10, participants: 4);
      expect(e.spotsAvailable, 6);
      expect(e.isFull, isFalse);
    });

    test('full detection', () {
      final e = makeEvent(capacity: 2, participants: 2);
      expect(e.isFull, isTrue);
      expect(e.spotsAvailable, 0);
    });

    test('overbooked still counts as full', () {
      final e = makeEvent(capacity: 2, participants: 3);
      expect(e.isFull, isTrue);
    });

    test('past event by status', () {
      expect(makeEvent(status: EventStatus.completed).isPast, isTrue);
      expect(makeEvent(status: EventStatus.upcoming).isPast, isFalse);
    });

    test('past event by end time', () {
      expect(makeEvent(end: now.subtract(const Duration(hours: 1))).isPast,
          isTrue);
    });

    test('editableMap exposes only client-editable fields', () {
      final map = makeEvent().editableMap();
      expect(map.keys, containsAll(['title', 'description', 'capacity']));
      expect(map.keys, isNot(contains('participantsCount')));
      expect(map.keys, isNot(contains('status')));
      expect(map.keys, isNot(contains('qrToken')));
    });

    test('copyWith preserves untouched fields', () {
      final e = makeEvent(capacity: 50);
      final copy = e.copyWith(title: 'New', capacity: 100);
      expect(copy.title, 'New');
      expect(copy.capacity, 100);
      expect(copy.description, 'D');
      expect(copy.participantsCount, 4);
    });
  });

  group('Registration', () {
    test('active detection', () {
      const reg = Registration(
        userId: 'u1',
        eventId: 'e1',
        registeredAt: null,
        status: 'ACTIVE',
        checkedIn: false,
      );
      expect(reg.isActive, isTrue);
    });
  });

  group('Ticket', () {
    test('parses callable payload', () {
      final t = Ticket.fromMap({
        'eventId': 'e1',
        'userId': 'u1',
        'qrPayload': 'EV1.e1.u1.sig',
        'status': 'ACTIVE',
        'checkedIn': false,
      });
      expect(t.qrPayload, 'EV1.e1.u1.sig');
      expect(t.checkedIn, isFalse);
    });
  });

  group('friendlyError', () {
    FirebaseFunctionsException ffe(String code, String message) {
      return FirebaseFunctionsException(
        code: code,
        message: message,
        details: null,
      );
    }

    test('maps business tokens to friendly copy', () {
      expect(
        friendlyError(ffe(
            'resource-exhausted', 'EVENT_FULL The event is at full capacity.')),
        contains('full'),
      );
      expect(
        friendlyError(ffe('already-exists',
            'ALREADY_REGISTERED You are already registered.')),
        contains('already registered'),
      );
      expect(
        friendlyError(
            ffe('failed-precondition', 'INVALID_QR The QR code is not valid.')),
        contains('not valid'),
      );
      expect(
        friendlyError(ffe('already-exists', 'ALREADY_CHECKED_IN already in.')),
        contains('already checked in'),
      );
    });

    test('maps auth errors', () {
      expect(
        friendlyError(FirebaseAuthException(code: 'wrong-password')),
        contains('Incorrect'),
      );
      expect(
        friendlyError(FirebaseAuthException(code: 'email-already-in-use')),
        contains('already exists'),
      );
      expect(
        friendlyError(FirebaseAuthException(code: 'weak-password')),
        contains('stronger password'),
      );
    });

    test('falls back for unknown errors', () {
      expect(friendlyError(StateError('boom')), contains('went wrong'));
    });
  });
}
