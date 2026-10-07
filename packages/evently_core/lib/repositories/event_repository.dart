import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/event.dart';
import '../models/event_status.dart';

/// All event-related data access. The UI layer depends on this interface, not
/// on Firestore directly.
class EventRepository {
  EventRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _events =>
      _db.collection('events');

  /// Upcoming events for the catalog, soonest start first.
  Stream<List<Event>> watchUpcoming({String? category}) {
    Query<Map<String, dynamic>> q =
        _events.where('status', isEqualTo: EventStatus.upcoming.wire);
    if (category != null && category.isNotEmpty && category != 'all') {
      q = q.where('category', isEqualTo: category);
    }
    return q.orderBy('startAt').limit(100).snapshots().map(
          (s) => s.docs.map(Event.fromDoc).toList(),
        );
  }

  /// Past events (completed or canceled), most recent first.
  Stream<List<Event>> watchPast({String? category}) {
    Query<Map<String, dynamic>> q = _events.where(
      'status',
      whereIn: [EventStatus.completed.wire, EventStatus.canceled.wire],
    );
    if (category != null && category.isNotEmpty && category != 'all') {
      q = q.where('category', isEqualTo: category);
    }
    return q.orderBy('startAt', descending: true).limit(100).snapshots().map(
          (s) => s.docs.map(Event.fromDoc).toList(),
        );
  }

  /// All events for the admin dashboard, grouped by the caller via status.
  Stream<List<Event>> watchAll({String? category}) {
    Query<Map<String, dynamic>> q = _events;
    if (category != null && category.isNotEmpty && category != 'all') {
      q = q.where('category', isEqualTo: category);
    }
    return q.orderBy('startAt', descending: true).limit(200).snapshots().map(
          (s) => s.docs.map(Event.fromDoc).toList(),
        );
  }

  /// Full-text-ish search: prefix match on lowercased title/location.
  Future<List<Event>> search(String query, {int limit = 30}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final snapshot = await _events
        .where('searchTerms', arrayContains: normalized)
        .limit(limit)
        .get();
    return snapshot.docs.map(Event.fromDoc).toList();
  }

  Stream<Event> watchEvent(String eventId) {
    return _events.doc(eventId).snapshots().map((s) => Event.fromDoc(s));
  }

  Future<Event> getEvent(String eventId) async {
    final snap = await _events.doc(eventId).get();
    if (!snap.exists) throw StateError('Event $eventId not found');
    return Event.fromDoc(snap);
  }

  // Admin operations (via callables).

  Future<String> createEvent(Event draft) async {
    final res = await _call('adminCreateEvent', {
      ...draft.editableMap(),
      'startAt': draft.startAt.toIso8601String(),
    });
    return (res['eventId'] as String?) ?? '';
  }

  Future<void> updateEvent(String eventId, Event draft) async {
    await _call('adminUpdateEvent', {
      'eventId': eventId,
      ...draft.editableMap(),
      'startAt': draft.startAt.toIso8601String(),
    });
  }

  Future<void> deleteEvent(String eventId) =>
      _call('adminDeleteEvent', {'eventId': eventId});

  Future<void> setEventStatus(String eventId, EventStatus status) =>
      _call('adminSetEventStatus', {'eventId': eventId, 'status': status.wire});

  Future<void> sendReminder(String eventId) =>
      _call('adminSendReminder', {'eventId': eventId});

  Future<void> notifyEventUpdate(String eventId, String body) =>
      _call('adminNotifyUpdate', {'eventId': eventId, 'body': body});

  Future<void> sendAnnouncement(String title, String body) =>
      _call('sendAnnouncement', {'title': title, 'body': body});

  /// Uploads a cover image and returns its public download URL.
  Future<String> uploadCover(String eventId, File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext =
        file.path.split('.').last.toLowerCase().replaceAll('jpg', 'jpeg');
    final ref =
        FirebaseStorage.instance.ref().child('events/$eventId/cover_$ts.$ext');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  // Internal.

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
