import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/event.dart';
import '../models/registration.dart';
import '../models/ticket.dart';

/// Registration data access. Every mutation goes through a callable so the
/// backend can enforce capacity, duplicates and time windows transactionally.
class RegistrationRepository {
  RegistrationRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  String? get currentUserId => _auth.currentUser?.uid;

  /// User operations.

  Future<void> register(String eventId) =>
      _call('registerForEvent', {'eventId': eventId});

  Future<void> cancel(String eventId) =>
      _call('cancelRegistration', {'eventId': eventId});

  Future<Ticket> getTicket(String eventId) async {
    final res = await _call('getMyTicket', {'eventId': eventId});
    return Ticket.fromMap(res);
  }

  /// Streams.

  /// Whether the current user is registered for [eventId] (drives the details
  /// screen CTA).
  Stream<bool> watchIsRegistered(String eventId) {
    final uid = currentUserId;
    if (uid == null) return Stream.value(false);
    return _db
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .doc(uid)
        .snapshots()
        .map(
            (s) => s.exists && ((s.data()?['status'] ?? 'ACTIVE') == 'ACTIVE'));
  }

  /// The caller's registrations joined with their events — the "My events"
  /// screen. Uses a collectionGroup query over all registrations subcollections
  /// plus per-event doc streams.
  Stream<List<RegistrationWithEvent>> watchMyRegistrations(
      {bool past = false}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const <RegistrationWithEvent>[]);

    final regsStream = _db
        .collectionGroup('registrations')
        .where('userId', isEqualTo: uid)
        .snapshots();

    late StreamController<List<RegistrationWithEvent>> controller;
    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub;
    final latestEvents = <String, Event>{};

    controller = StreamController<List<RegistrationWithEvent>>(
      onListen: () {
        sub = regsStream.listen((regsSnap) {
          final regs = regsSnap.docs.map(Registration.fromDoc).toList();

          // Subscribe to each referenced event; re-emit when any changes.
          final eventIds = regs.map((r) => r.eventId).toSet();
          latestEvents.removeWhere((id, _) => !eventIds.contains(id));

          if (regs.isEmpty) {
            controller.add(const <RegistrationWithEvent>[]);
            return;
          }

          var pending =
              eventIds.where((id) => !latestEvents.containsKey(id)).length;
          if (pending == 0) {
            controller.add(_combine(regs, latestEvents, past));
          }
          for (final id in eventIds) {
            if (latestEvents.containsKey(id)) continue;
            _db.collection('events').doc(id).snapshots().listen((snap) {
              if (snap.exists) {
                latestEvents[id] = Event.fromDoc(snap);
              }
              pending--;
              if (pending <= 0) {
                controller.add(_combine(regs, latestEvents, past));
              }
            });
          }
        });
      },
      onPause: () => sub.pause(),
      onResume: () => sub.resume(),
      onCancel: () => sub.cancel(),
    );

    return controller.stream;
  }

  List<RegistrationWithEvent> _combine(
    List<Registration> regs,
    Map<String, Event> events,
    bool past,
  ) {
    final pairs = <RegistrationWithEvent>[];
    for (final reg in regs) {
      final event = events[reg.eventId];
      if (event == null) continue;
      final eventIsPast = event.isPast;
      if (past != eventIsPast) continue;
      pairs.add(RegistrationWithEvent(event: event, registration: reg));
    }
    pairs.sort((a, b) => past
        ? b.event.startAt.compareTo(a.event.startAt)
        : a.event.startAt.compareTo(b.event.startAt));
    return pairs;
  }

  /// Participant list for the admin app.
  Stream<List<Registration>> watchParticipants(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .snapshots()
        .map(
          (s) =>
              s.docs.map(Registration.fromDoc).toList()..sort(_byRegisteredAt),
        );
  }

  /// Check-in map for the admin participant list (uid -> checkedInAt).
  Stream<Map<String, DateTime?>> watchCheckins(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .collection('checkins')
        .snapshots()
        .map((s) {
      final map = <String, DateTime?>{};
      for (final doc in s.docs) {
        final ts = doc.data()['checkedInAt'];
        map[doc.id] = ts is Timestamp ? ts.toDate() : null;
      }
      return map;
    });
  }

  /// Admin operations.

  Future<void> removeParticipant(String eventId, String userId) =>
      _call('adminRemoveParticipant', {'eventId': eventId, 'userId': userId});

  Future<Map<String, dynamic>> checkIn(String eventId, String qrPayload) =>
      _call('checkInParticipant', {'eventId': eventId, 'qrPayload': qrPayload});

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    final res = await _functions
        .httpsCallable(name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<dynamic>(data);
    final raw = res.data;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return const <String, dynamic>{};
  }
}

/// Registration joined with its event for the "My events" list.
class RegistrationWithEvent {
  const RegistrationWithEvent(
      {required this.event, required this.registration});

  final Event event;
  final Registration registration;
}

int _byRegisteredAt(Registration a, Registration b) =>
    (b.registeredAt ?? DateTime(1970))
        .compareTo(a.registeredAt ?? DateTime(1970));
