import { setGlobalOptions } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { Paths } from './paths';
import { requireAuth, requireAdmin } from './auth';
import { EventStatus, deriveStatus, STATUS_MARGIN_MINUTES, buildSearchTerms } from './events';
import { EventDoc, canCheckIn, assertCanRegister, toEventDoc } from './preconditions';
import { notifyUser, UserTopics, NotifyInput } from './notifications';
import { verifyQr, parseQr, signQr } from './qr';
import {
  ensureDate,
  ensureStringStrict,
  ensureCapacity,
  ensureEventId,
  throwMapped,
  nowTs,
  tsOf,
} from './function-helpers';

setGlobalOptions({ region: 'us-central1' });

// Idempotent: safe under firebase-functions-test which may initialize first.
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

/***********************************************
 * Types
 ***********************************************/

interface EventIdPayload {
  eventId?: string;
}

interface EventDraft {
  title?: string;
  description?: string;
  location?: string;
  category?: string;
  capacity?: unknown;
  startAt?: string;
  endAt?: string | null;
  coverImageUrl?: string | null;
}

interface SetRolePayload {
  targetUid?: string;
  role?: string;
}

interface StatusPayload {
  eventId?: string;
  status?: string;
}

interface CheckInPayload {
  eventId?: string;
  qrPayload?: string;
}

interface UpdatesPayload {
  eventId?: string;
  title?: string;
  body?: string;
}

interface AnnouncementPayload {
  title?: string;
  body?: string;
}

/***********************************************
 * Validation helpers
 ***********************************************/

const COVER_URL_PATTERN = /^https:\/\/firebasestorage\.googleapis\.com\/.+$/;

function validateDraft(data: EventDraft): {
  title: string;
  description: string;
  location: string;
  category: string;
  capacity: number;
  startAt: Date;
  endAt: Date | null;
  coverImageUrl: string | null;
} {
  const title = ensureStringStrict(data.title, 'title', { max: 200 });
  const description = ensureStringStrict(data.description, 'description', { max: 5000 });
  const location = ensureStringStrict(data.location, 'location', { max: 300 });
  const category = ensureStringStrict(data.category, 'category', { max: 60 });
  const capacity = ensureCapacity(data.capacity);
  const startAt = ensureDate(data.startAt, 'startAt');
  const endAtRaw = data.endAt;
  const endAt = endAtRaw == null || endAtRaw === '' ? null : ensureDate(endAtRaw, 'endAt');
  if (endAt != null && endAt.getTime() <= startAt.getTime()) {
    throw new HttpsError('invalid-argument', 'endAt must be after startAt.');
  }
  if (startAt.getTime() < Date.now() - 24 * 60 * 60 * 1000) {
    throw new HttpsError('invalid-argument', 'startAt cannot be more than a day in the past.');
  }
  const coverImageUrlRaw = data.coverImageUrl;
  const coverImageUrl =
    typeof coverImageUrlRaw === 'string' && coverImageUrlRaw.trim().length > 0
      ? coverImageUrlRaw.trim()
      : null;
  if (coverImageUrl != null && !COVER_URL_PATTERN.test(coverImageUrl)) {
    throw new HttpsError('invalid-argument', 'coverImageUrl must be a Firebase Storage URL.');
  }
  return { title, description, location, category, capacity, startAt, endAt, coverImageUrl };
}

async function getEventOrThrow(eventId: string): Promise<{ ref: admin.firestore.DocumentReference; doc: EventDoc }> {
  const ref = db.doc(Paths.event(eventId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Event not found.');
  return { ref, doc: toEventDoc(eventId, snap.data() ?? {}) };
}

async function notify(input: Omit<NotifyInput, 'topic'> & { topic?: NotifyInput['topic'] }): Promise<void> {
  await notifyUser({ ...input, topic: input.topic ?? UserTopics.REGISTRATIONS });
}

/***********************************************
 * Event management (admin-only callables)
 ***********************************************/

/**
 * The single trusted entry point for event creation. Writing events from the
 * client is impossible (rules deny it); this callable initialises the server-
 * owned fields (counters, qrToken, timestamps) and ignores everything else.
 */
/** Raw handler — exported for direct test invocation. */
export async function adminCreateEventHandler(request: CallableRequest<EventDraft>) {
const adminUid = requireAdmin(request);
const v = validateDraft(request.data ?? {});

const ref = db.collection(Paths.eventsCol).doc();
await ref.set({
  ...v,
  searchTerms: buildSearchTerms(v.title, v.location),
  startAt: admin.firestore.Timestamp.fromDate(v.startAt),
  endAt: v.endAt == null ? null : admin.firestore.Timestamp.fromDate(v.endAt),
  status: 'UPCOMING' satisfies EventStatus,
  participantsCount: 0,
  checkedInCount: 0,
  organizerId: adminUid,
  qrToken: crypto.randomBytes(32).toString('base64url'),
  createdAt: nowTs(),
  updatedAt: nowTs(),
});
return { eventId: ref.id };
}

export const adminCreateEvent = onCall(adminCreateEventHandler);

/**
 * Admin edit. Whitelisted fields only; counters, status, qrToken remain
 * server-owned. Capacity may never drop below the current participant count.
 */
export const adminUpdateEvent = onCall(adminUpdateEventHandler);

/** Raw handler — exported for direct test invocation. */
export async function adminUpdateEventHandler(
  request: CallableRequest<EventDraft & EventIdPayload>,
) {
  {
    requireAdmin(request);
    const eventId = ensureEventId(request);
    const data = request.data ?? {};

    const patch: Record<string, unknown> = { updatedAt: nowTs() };

    if (data.title !== undefined) patch['title'] = ensureStringStrict(data.title, 'title', { max: 200 });
    if (data.description !== undefined) {
      patch['description'] = ensureStringStrict(data.description, 'description', { max: 5000 });
    }
    if (data.location !== undefined) patch['location'] = ensureStringStrict(data.location, 'location', { max: 300 });
    if (data.category !== undefined) patch['category'] = ensureStringStrict(data.category, 'category', { max: 60 });
    if (data.startAt !== undefined) {
      patch['startAt'] = admin.firestore.Timestamp.fromDate(ensureDate(data.startAt, 'startAt'));
    }
    if (data.endAt !== undefined) {
      const endAt = data.endAt == null || data.endAt === '' ? null : ensureDate(data.endAt, 'endAt');
      patch['endAt'] = endAt == null ? null : admin.firestore.Timestamp.fromDate(endAt);
      const startTs = tsOf((await db.doc(Paths.event(eventId)).get()).get('startAt'));
      if (startTs != null && endAt != null && endAt.getTime() <= startTs.getTime()) {
        throw new HttpsError('invalid-argument', 'endAt must be after startAt.');
      }
    }
    if (data.capacity !== undefined) {
      const capacity = ensureCapacity(data.capacity);
      const snap = await db.doc(Paths.event(eventId)).get();
      if (!snap.exists) throw new HttpsError('not-found', 'Event not found.');
      const participants = (snap.get('participantsCount') as number) ?? 0;
      if (capacity < participants) {
        throw new HttpsError(
          'failed-precondition',
          `CAPACITY_BELOW_COUNT Capacity cannot be lower than the current participant count (${participants}).`,
        );
      }
      patch['capacity'] = capacity;
    }
    if (data.coverImageUrl !== undefined) {
      const cover = data.coverImageUrl;
      const coverStr =
        cover == null || (typeof cover === 'string' && cover.trim().length === 0)
          ? null
          : String(cover).trim();
      if (coverStr != null && !COVER_URL_PATTERN.test(coverStr)) {
        throw new HttpsError('invalid-argument', 'coverImageUrl must be a Firebase Storage URL.');
      }
      patch['coverImageUrl'] = coverStr;
    }

    await getEventOrThrow(eventId); // 404 control
    if (patch['title'] !== undefined || patch['location'] !== undefined) {
      const snap = await db.doc(Paths.event(eventId)).get();
      const cur = toEventDoc(eventId, snap.data() ?? {});
      patch['searchTerms'] = buildSearchTerms(
        (patch['title'] as string) ?? cur.title,
        (patch['location'] as string) ?? cur.location,
      );
    }
    await db.doc(Paths.event(eventId)).update(patch);
    return { ok: true };
  }
}

/**
 * Delete an event and cascade its registrations + check-ins, notifying all
 * registered users first. Runs in chunks of <=450 ops to respect the 500-op
 * batch limit.
 */
/** Raw handler — exported for direct test invocation. */
export async function adminDeleteEventHandler(request: CallableRequest<EventIdPayload>) {
requireAdmin(request);
const eventId = ensureEventId(request);

const eventSnap = await db.doc(Paths.event(eventId)).get();
if (!eventSnap.exists) throw new HttpsError('not-found', 'Event not found.');
const event = toEventDoc(eventId, eventSnap.data() ?? {});

const regs = await db.collection(Paths.registrations(eventId)).get();
for (const reg of regs.docs) {
  await notifyUser({
    userId: reg.id,
    title: 'Event canceled',
    body: `"${event.title}" has been canceled by the organizer.`,
    type: 'event_canceled',
    data: { eventId },
    topic: UserTopics.REGISTRATIONS,
  });
}

const refs: admin.firestore.DocumentReference[] = [eventSnap.ref];
regs.docs.forEach((d) => refs.push(d.ref));
const checkins = await db.collection(Paths.checkins(eventId)).get();
checkins.docs.forEach((d) => refs.push(d.ref));

for (let i = 0; i < refs.length; i += 450) {
  const batch = db.batch();
  refs.slice(i, i + 450).forEach((ref) => batch.delete(ref));
  await batch.commit();
}
return { ok: true };
}

export const adminDeleteEvent = onCall(adminDeleteEventHandler);

/** Explicit admin status override; approving statuses fan out notifications. */
/** Raw handler — exported for direct test invocation. */
export async function adminSetEventStatusHandler(request: CallableRequest<StatusPayload>) {
requireAdmin(request);
const eventId = ensureEventId(request);
const status = (request.data?.status ?? '') as string;
const allowed: EventStatus[] = ['UPCOMING', 'ONGOING', 'COMPLETED', 'CANCELED'];
if (!allowed.includes(status as EventStatus)) {
  throw new HttpsError('invalid-argument', `status must be one of ${allowed.join(', ')}.`);
}

const { ref, doc } = await getEventOrThrow(eventId);
if (doc.status !== status) {
  await ref.update({ status, updatedAt: nowTs() });
}

if ((status === 'CANCELED' || status === 'COMPLETED') && doc.status !== status) {
  const regs = await db.collection(Paths.registrations(eventId)).get();
  await Promise.all(
    regs.docs.map((reg) =>
      notifyUser({
        userId: reg.id,
        title: status === 'CANCELED' ? 'Event canceled' : 'Event completed',
        body: `"${doc.title}" was marked ${status.toLowerCase()} by the organizer.`,
        type: 'event_status',
        data: { eventId, status },
        topic: UserTopics.REGISTRATIONS,
      }),
    ),
  );
}
return { ok: true };
}

export const adminSetEventStatus = onCall(adminSetEventStatusHandler);

/** Manual "reminder now" push to every registered participant. */
/** Raw handler — exported for direct test invocation. */
export async function adminSendReminderHandler(request: CallableRequest<EventIdPayload>) {
requireAdmin(request);
const eventId = ensureEventId(request);

const { doc } = await getEventOrThrow(eventId);
if (doc.status !== 'UPCOMING') {
  throw new HttpsError('failed-precondition', 'EVENT_NOT_UPCOMING Reminders can only be sent for upcoming events.');
}

const regs = await db.collection(Paths.registrations(eventId)).get();
let count = 0;
for (const reg of regs.docs) {
  await notifyUser({
    userId: reg.id,
    title: `Reminder: ${doc.title}`,
    body: `Starts ${doc.startAt.toISOString()}. Don't forget!`,
    type: 'event_reminder',
    data: { eventId },
    topic: UserTopics.REGISTRATIONS,
  });
  count++;
}
return { ok: true, notified: count };
}

export const adminSendReminder = onCall(adminSendReminderHandler);

/** Broadcast an important announcement to all app users (topic-based). */
/** Raw handler — exported for direct test invocation. */
export async function sendAnnouncementHandler(request: CallableRequest<AnnouncementPayload>) {
requireAdmin(request);
const title = ensureStringStrict(request.data?.title, 'title', { max: 120 });
const body = ensureStringStrict(request.data?.body, 'body', { max: 1000 });

const annRef = await db.collection(Paths.announcementsCol).add({
  title,
  body,
  createdAt: nowTs(),
  createdBy: request.auth!.uid,
});

await admin
  .messaging()
  .send({
    topic: UserTopics.ANNOUNCEMENTS,
    notification: { title, body },
    data: { type: 'announcement', announcementId: annRef.id },
  })
  .catch(() => {
    // Emulator / first-run: topic may not exist; harmless.
  });
return { ok: true, announcementId: annRef.id };
}

export const sendAnnouncement = onCall(sendAnnouncementHandler);

/**
 * Push an "event update" notification to registered participants after an
 * admin edit (avoids spamming on every tiny edit — the admin app calls this
 * explicitly when the change is meaningful).
 */
/** Raw handler — exported for direct test invocation. */
export async function adminNotifyUpdateHandler(request: CallableRequest<UpdatesPayload>) {
requireAdmin(request);
const eventId = ensureEventId(request);
const { doc } = await getEventOrThrow(eventId);
const body = ensureStringStrict(request.data?.body, 'body', { max: 500 });

const regs = await db.collection(Paths.registrations(eventId)).get();
await Promise.all(
  regs.docs.map((reg) =>
    notifyUser({
      userId: reg.id,
      title: `Update: ${doc.title}`,
      body,
      type: 'event_updated',
      data: { eventId },
      topic: UserTopics.REGISTRATIONS,
    }),
  ),
);
return { ok: true, notified: regs.size };
}

export const adminNotifyUpdate = onCall(adminNotifyUpdateHandler);

/***********************************************
 * Registration (user callables)
 ***********************************************/

/**
 * Transaction-safe registration. Reads the event and the user's registration
 * inside one transaction and enforces:
 *   - event exists & is open for registration (not canceled/started/full)
 *   - the user has no existing registration for this event
 * Firestore optimistic concurrency guarantees no oversubscription even with
 * many simultaneous registers.
 */
/** Raw handler — exported for direct test invocation. */
export async function registerForEventHandler(request: CallableRequest<EventIdPayload>) {
const uid = requireAuth(request);
const eventId = ensureEventId(request);

try {
  const event = await db.runTransaction(async (tx) => {
    const eventRef = db.doc(Paths.event(eventId));
    const regRef = db.doc(Paths.registration(eventId, uid));
    const [eventSnap, regSnap] = await tx.getAll(eventRef, regRef);

    if (!eventSnap.exists) throw new HttpsError('not-found', 'Event not found.');
    const eventDoc = toEventDoc(eventId, eventSnap.data() ?? {});
    if (regSnap.exists) {
      const err = new Error('already registered') as Error & { code: string };
      err.code = 'ALREADY_REGISTERED';
      throw err;
    }
    // Capacity / status / time guards; throws typed Errors on violation.
    assertCanRegister(eventDoc, new Date());

    tx.create(regRef, {
      userId: uid,
      eventId,
      registeredAt: nowTs(),
      status: 'ACTIVE',
      checkedIn: false,
    });
    tx.update(eventRef, { participantsCount: admin.firestore.FieldValue.increment(1) });
    return eventDoc;
  });

  await notify({
    userId: uid,
    title: 'Registration confirmed',
    body: `You are registered for "${event.title}".`,
    type: 'registration_created',
    data: { eventId },
  });
  return { ok: true };
} catch (err) {
  throwMapped(err);
}
}

export const registerForEvent = onCall(registerForEventHandler);

/**
 * Cancel the caller's registration. Checks that the event has not started yet
 * (cancellation closes at start) and that the registration is ACTIVE.
 */
/** Raw handler — exported for direct test invocation. */
export async function cancelRegistrationHandler(request: CallableRequest<EventIdPayload>) {
const uid = requireAuth(request);
const eventId = ensureEventId(request);

try {
  const event = await db.runTransaction(async (tx) => {
    const eventRef = db.doc(Paths.event(eventId));
    const regRef = db.doc(Paths.registration(eventId, uid));
    const [eventSnap, regSnap] = await tx.getAll(eventRef, regRef);

    const eventDoc = eventSnap.exists ? toEventDoc(eventId, eventSnap.data() ?? {}) : null;
    if (!regSnap.exists) {
      const err = new Error('not registered') as Error & { code: string };
      err.code = 'NOT_REGISTERED';
      throw err;
    }
    if ((regSnap.get('status') ?? 'ACTIVE') !== 'ACTIVE') {
      const err = new Error('not registered') as Error & { code: string };
      err.code = 'NOT_REGISTERED';
      throw err;
    }
    if (eventDoc != null && eventDoc.startAt.getTime() <= Date.now()) {
      const err = new Error('event started') as Error & { code: string };
      err.code = 'EVENT_STARTED';
      throw err;
    }

    tx.delete(regRef);
    if (eventDoc != null) {
      tx.update(eventRef, { participantsCount: admin.firestore.FieldValue.increment(-1) });
    }
    return eventDoc;
  });

  if (event != null) {
    await notify({
      userId: uid,
      title: 'Registration canceled',
      body: `Your registration for "${event.title}" was canceled.`,
      type: 'registration_canceled',
      data: { eventId },
    });
  }
  return { ok: true };
} catch (err) {
  throwMapped(err);
}
}

export const cancelRegistration = onCall(cancelRegistrationHandler);

/**
 * Return the caller's signed QR ticket payload for an event. Throws if the
 * user has no ACTIVE registration. The QR string embeds eventId, userId and an
 * HMAC signature generated with the event's server-only qrToken secret.
 */
/** Raw handler — exported for direct test invocation. */
export async function getMyTicketHandler(request: CallableRequest<EventIdPayload>) {
const uid = requireAuth(request);
const eventId = ensureEventId(request);

const [eventSnap, regSnap] = await Promise.all([
  db.doc(Paths.event(eventId)).get(),
  db.doc(Paths.registration(eventId, uid)).get(),
]);
if (!eventSnap.exists) throw new HttpsError('not-found', 'Event not found.');
if (!regSnap.exists) throw new HttpsError('failed-precondition', 'NOT_REGISTERED No registration for this event.');

const event = toEventDoc(eventId, eventSnap.data() ?? {});
return {
  eventId,
  userId: uid,
  qrPayload: signQr(event.qrToken, eventId, uid),
  status: regSnap.get('status') ?? 'ACTIVE',
  checkedIn: regSnap.get('checkedIn') === true,
};
}

export const getMyTicket = onCall(getMyTicketHandler);

/***********************************************
 * Check-in (admin callables)
 ***********************************************/

/**
 * Admin scans a QR string. The full signed payload (EV1.<eventId>.<userId>.<sig>)
 * is verified against the event secret; then the registration must exist for
 * THAT event, must not be checked in yet, and the event must be check-in open.
 * Writes checkins/{uid} + flips the registration flag inside one transaction.
 */
/** Raw handler — exported for direct test invocation. */
export async function checkInParticipantHandler(request: CallableRequest<CheckInPayload>) {
requireAdmin(request);
const eventId = ensureEventId(request);
const qrRaw = ensureStringStrict(request.data?.qrPayload, 'qrPayload', { max: 256 });

const parsed = parseQr(qrRaw);
if (parsed == null || parsed.eventId !== eventId) {
  throw new HttpsError('failed-precondition', 'INVALID_QR This QR code is not valid for this event.');
}

try {
  const { userId, title } = await db.runTransaction(async (tx) => {
    const eventRef = db.doc(Paths.event(eventId));
    const regRef = db.doc(Paths.registration(eventId, parsed.userId));
    const [eventSnap, regSnap] = await tx.getAll(eventRef, regRef);

    if (!eventSnap.exists) throw new HttpsError('not-found', 'Event not found.');
    const eventDoc = toEventDoc(eventId, eventSnap.data() ?? {});
    const secret = eventDoc.qrToken;
    if (secret.length === 0 || verifyQr(qrRaw, secret) == null) {
      const err = new Error('bad sig') as Error & { code: string };
      err.code = 'INVALID_QR';
      throw err;
    }
    if (!regSnap.exists) {
      const err = new Error('no registration') as Error & { code: string };
      err.code = 'INVALID_QR';
      throw err;
    }
    if (!canCheckIn(eventDoc, new Date())) {
      const err = new Error('check-in closed') as Error & { code: string };
      err.code = 'EVENT_STARTED';
      throw err;
    }
    if (regSnap.get('checkedIn') === true) {
      const err = new Error('already checked in') as Error & { code: string };
      err.code = 'ALREADY_CHECKED_IN';
      throw err;
    }

    tx.set(db.doc(Paths.checkin(eventId, parsed.userId)), {
      userId: parsed.userId,
      eventId,
      checkedInAt: nowTs(),
      method: 'QR',
    });
    tx.update(regRef, { checkedIn: true });
    tx.update(eventRef, { checkedInCount: admin.firestore.FieldValue.increment(1) });
    return { userId: parsed.userId, title: eventDoc.title };
  });

  await notify({
    userId,
    title: 'Checked in',
    body: `Welcome to "${title}". Enjoy!`,
    type: 'checked_in',
    data: { eventId },
  });
  return { ok: true, userId };
} catch (err) {
  throwMapped(err);
}
}

export const checkInParticipant = onCall(checkInParticipantHandler);

/**
 * Admin removes a participant (e.g. no-show policy violation). Deletes the
 * registration and decrements the counter so the spot frees up.
 */
export const adminRemoveParticipant = onCall(adminRemoveParticipantHandler);

/** Raw handler — exported for direct test invocation. */
export async function adminRemoveParticipantHandler(
  request: CallableRequest<{ eventId?: string; userId?: string }>,
) {
  {
    requireAdmin(request);
    const eventId = ensureEventId(request);
    const userId = ensureStringStrict(request.data?.userId, 'userId', { max: 128 });

    try {
      await db.runTransaction(async (tx) => {
        const eventRef = db.doc(Paths.event(eventId));
        const regRef = db.doc(Paths.registration(eventId, userId));
        const [eventSnap, regSnap] = await tx.getAll(eventRef, regRef);
        if (!regSnap.exists) {
          const err = new Error('not registered') as Error & { code: string };
          err.code = 'NOT_REGISTERED';
          throw err;
        }
        tx.delete(regRef);
        if (eventSnap.exists) {
          tx.update(eventRef, { participantsCount: admin.firestore.FieldValue.increment(-1) });
        }
      });
    } catch (err) {
      throwMapped(err);
    }

    await notify({
      userId,
      title: 'Registration removed',
      body: 'Your registration was removed by the organizer.',
      type: 'registration_removed',
      data: { eventId },
    });
    return { ok: true };
  }
}

/***********************************************
 * Profile, roles, tokens (mixed callables)
 ***********************************************/

/** Server-side profile update; displayName/photoUrl only, never role. */
export const updateProfile = onCall(updateProfileHandler);

/** Raw handler — exported for direct test invocation. */
export async function updateProfileHandler(
  request: CallableRequest<{ displayName?: string; photoUrl?: string | null }>,
) {
  {
    const uid = requireAuth(request);
    const data = request.data ?? {};
    const patch: Record<string, unknown> = {};
    if (data.displayName !== undefined) {
      patch['displayName'] = ensureStringStrict(data.displayName, 'displayName', { max: 80 });
    }
    if (data.photoUrl !== undefined) {
      patch['photoUrl'] = data.photoUrl == null ? null : ensureStringStrict(data.photoUrl, 'photoUrl', { max: 500 });
    }
    if (Object.keys(patch).length === 0) {
      throw new HttpsError('invalid-argument', 'Nothing to update.');
    }
    patch['updatedAt'] = nowTs();
    await db.doc(Paths.user(uid)).set(patch, { merge: true });
    return { ok: true };
  }
}

/**
 * Save the FCM registration token so server flows can target this device.
 * Users may only ever write their own token.
 */
/** Raw handler — exported for direct test invocation. */
export async function saveFcmTokenHandler(request: CallableRequest<{ token?: string }>) {
const uid = requireAuth(request);
const token = ensureStringStrict(request.data?.token, 'token', { max: 4096 });
await db.doc(Paths.user(uid)).set({ fcmToken: token, updatedAt: nowTs() }, { merge: true });
return { ok: true };
}

export const saveFcmToken = onCall(saveFcmTokenHandler);

/** Bulk-mark the caller's OWN inbox entries as read. */
/** Raw handler — exported for direct test invocation. */
export async function markNotificationsReadHandler(request: CallableRequest<{ ids?: string[] }>) {
requireAuth(request);
const uid = request.auth!.uid;
const ids = Array.isArray(request.data?.ids) ? request.data!.ids! : [];
const valid = ids.filter((id): id is string => typeof id === 'string' && id.length > 0).slice(0, 450);
if (valid.length > 0) {
  // Query with userId filter so users can never flip someone else's docs.
  const snap = await db
    .collection(Paths.notificationsCol)
    .where(admin.firestore.FieldPath.documentId(), 'in', valid)
    .where('userId', '==', uid)
    .get();
  if (!snap.empty) {
    const batch = db.batch();
    snap.docs.forEach((d) => batch.update(d.ref, { read: true, readAt: nowTs() }));
    await batch.commit();
  }
}
return { ok: true };
}

export const markNotificationsRead = onCall(markNotificationsReadHandler);

/**
 * Role management. An existing admin can promote/demote anyone. On a fresh
 * project with zero admins, the first caller may bootstrap themselves (this
 * is also possible via the Firebase Console). The role lives both on the user
 * doc (used by rules) and as an auth custom claim (used by callables).
 */
/** Raw handler — exported for direct test invocation. */
export async function setAdminRoleHandler(request: CallableRequest<SetRolePayload>) {
const data = request.data ?? {};
const targetUid = ensureStringStrict(data.targetUid, 'targetUid', { max: 128 });
const role = data.role === 'admin' || data.role === 'user' ? data.role : null;
if (role == null) throw new HttpsError('invalid-argument', `role must be 'admin' or 'user'.`);

const callerIsAdmin = request.auth?.token?.['admin'] === true;
if (!callerIsAdmin) {
  const admins = await db.collection(Paths.usersCol).where('role', '==', 'admin').limit(1).get();
  if (!admins.empty) {
    throw new HttpsError('permission-denied', 'Only admins can change roles.');
  }
}

await db.doc(Paths.user(targetUid)).set({ role, updatedAt: nowTs() }, { merge: true });
await admin.auth().setCustomUserClaims(targetUid, { admin: role === 'admin' });

if (request.auth != null && targetUid !== request.auth.uid) {
  await notifyUser({
    userId: targetUid,
    title: role === 'admin' ? 'You are now an admin' : 'Admin access revoked',
    body: role === 'admin' ? 'You now have admin access to Evently.' : 'Your admin access was removed.',
    type: 'role_changed',
    data: { role },
    topic: UserTopics.ANNOUNCEMENTS,
  });
}
return { ok: true };
}

export const setAdminRole = onCall(setAdminRoleHandler);

/***********************************************
 * Firestore triggers
 ***********************************************/

/**
 * Version-stamp guard: onEventWritten recomputes status on writes it did not
 * cause, to catch races the 5-minute scheduler misses. A sentinel field stops
 * the infinite loop (trigger -> write -> trigger ...).
 */
const STATUS_TOUCH = 'statusTouchedAt';

export const onEventWritten = onDocumentWritten(
  { document: 'events/{eventId}', retry: false },
  async (event) => {
    const after = event.data?.after;
    const before = event.data?.before;
    if (after == null) return;
    const data = after.data() ?? {};
    const startAt = tsOf(data['startAt']);
    if (startAt == null) return;

    // Skip writes that were themselves status updates from this trigger.
    const beforeStatus = (before?.data()?.['status'] as string | undefined) ?? null;
    const afterStatus = (data['status'] as string | undefined) ?? null;
    if (beforeStatus != null && afterStatus != null && beforeStatus === afterStatus) return;

    const next = deriveStatus(
      startAt,
      tsOf(data['endAt']),
      new Date(),
      (afterStatus as EventStatus) ?? 'UPCOMING',
    );
    if (next !== afterStatus) {
      await after.ref.update({ status: next, [STATUS_TOUCH]: nowTs() });
    }
  },
);

/**
 * Scheduled status updater every 2 minutes — keeps the catalog accurate even
 * when no client is interacting with an event.
 */
export const eventStatusScheduler = onSchedule(
  { schedule: 'every 2 minutes', timeoutSeconds: 120, memory: '256MiB' },
  async () => {
    const now = new Date();
    const marginMs = STATUS_MARGIN_MINUTES * 60 * 1000;

    const snap = await db
      .collection(Paths.eventsCol)
      .where('status', 'in', ['UPCOMING', 'ONGOING'])
      .get();

    const batch = db.batch();
    let changed = 0;
    snap.docs.forEach((doc) => {
      const startAt = tsOf(doc.get('startAt'));
      const endAt = tsOf(doc.get('endAt'));
      const current = (doc.get('status') as EventStatus) ?? 'UPCOMING';
      if (startAt == null) return;
      const next = deriveStatus(startAt, endAt, new Date(now.getTime() + marginMs), current);
      if (next !== current) {
        batch.update(doc.ref, { status: next, [STATUS_TOUCH]: nowTs() });
        changed++;
      }
    });
    if (changed > 0) await batch.commit();
  },
);

/**
 * 24-hour reminder fan-out. Runs hourly; events in the 23–25 h window are
 * picked up and each ACTIVE registration gets exactly one reminder
 * (reminderSent flag on the registration doc prevents duplicates).
 */
export const sendEventReminders = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 540, memory: '256MiB' },
  async () => {
    const windowStart = new Date(Date.now() + 23 * 60 * 60 * 1000);
    const windowEnd = new Date(Date.now() + 25 * 60 * 60 * 1000);

    const snap = await db
      .collection(Paths.eventsCol)
      .where('status', '==', 'UPCOMING')
      .where('startAt', '>=', admin.firestore.Timestamp.fromDate(windowStart))
      .where('startAt', '<=', admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    for (const doc of snap.docs) {
      const eventId = doc.id;
      const title = (doc.get('title') as string) ?? 'Event';
      const startAt = tsOf(doc.get('startAt'));
      const regs = await db.collection(Paths.registrations(eventId)).get();
      for (const reg of regs.docs) {
        if (reg.get('reminderSent') === true) continue;
        await notifyUser({
          userId: reg.id,
          title: `Tomorrow: ${title}`,
          body:
            startAt != null
              ? `Starts ${startAt.toLocaleString('en-US')}. See you there!`
              : 'See you there!',
          type: 'event_reminder',
          data: { eventId },
          topic: UserTopics.REGISTRATIONS,
          respectPreference: true,
        });
        await reg.ref.update({ reminderSent: true });
      }
    }
  },
);
