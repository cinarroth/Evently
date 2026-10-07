import * as admin from 'firebase-admin';

/**
 * Test harness: point the real admin SDK at the local emulators and invoke
 * the actual v2 onCall handlers directly with synthesized CallableRequests.
 * No firebase-functions-test offline mocking — business logic runs against
 * the real Firestore/Auth emulator implementations.
 */
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? 'localhost:9099';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? 'evently-test';

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
}

export const db = admin.firestore();
export const auth = admin.auth();

export const ALICE = { email: 'alice@test.dev', password: 'supersecret1', displayName: 'Alice' };
export const BOB = { email: 'bob@test.dev', password: 'supersecret1', displayName: 'Bob' };
export const CAROL = { email: 'carol@test.dev', password: 'supersecret1', displayName: 'Carol' };
export const DAVE = { email: 'dave@test.dev', password: 'supersecret1', displayName: 'Dave' };
export const ADMIN = { email: 'admin@test.dev', password: 'supersecret1', displayName: 'Admin' };

export async function makeUser(info: { email: string; password: string; displayName: string }) {
  const user = await auth.createUser({
    email: info.email,
    password: info.password,
    displayName: info.displayName,
  });
  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    displayName: info.displayName,
    role: 'user',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return user.uid;
}

export async function makeAdmin(info: { email: string; password: string; displayName: string }) {
  const uid = await makeUser(info);
  await auth.setCustomUserClaims(uid, { admin: true });
  await db.collection('users').doc(uid).update({ role: 'admin' });
  return uid;
}

export interface EventFixture {
  eventId: string;
  title: string;
  capacity: number;
}

export async function makeEvent(opts: {
  capacity: number;
  startInMinutes?: number;
  durationMinutes?: number;
  status?: string;
  organizerId?: string;
}): Promise<EventFixture> {
  const startInMinutes = opts.startInMinutes ?? 60 * 24 * 7; // a week out
  const startAt = new Date(Date.now() + startInMinutes * 60 * 1000);
  const endAt = new Date(startAt.getTime() + (opts.durationMinutes ?? 120) * 60 * 1000);

  const ref = await db.collection('events').add({
    title: `Test event ${Math.random().toString(36).slice(2, 8)}`,
    description: 'A fixture event',
    location: 'Test Hall',
    category: 'general',
    capacity: opts.capacity,
    startAt: admin.firestore.Timestamp.fromDate(startAt),
    endAt: admin.firestore.Timestamp.fromDate(endAt),
    coverImageUrl: null,
    searchTerms: ['test'],
    status: opts.status ?? 'UPCOMING',
    participantsCount: 0,
    checkedInCount: 0,
    organizerId: opts.organizerId ?? 'test-organizer',
    qrToken: 'unit-test-secret-qr-token-0123456789abcdef',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { eventId: ref.id, title: 'fixture', capacity: opts.capacity };
}

/**
 * Invoke a v2 onCall handler with a synthesized CallableRequest.
 * v2 handlers receive a single Request ({data, auth}) — call the real one.
 */
export function wrapCallable(fn: unknown) {
  return (data: unknown, ctx?: { auth?: { uid: string; token: Record<string, unknown> } }) =>
    (fn as (req: unknown) => Promise<unknown>)({
      data,
      auth: ctx?.auth ? { uid: ctx.auth.uid, token: ctx.auth.token } : undefined,
    });
}

export async function cleanupAll() {
  await Promise.all([
    wipeCollection('events', true),
    wipeCollection('users'),
    wipeCollection('notifications'),
    wipeCollection('announcements'),
  ]);
  const users = await auth.listUsers(1000);
  await Promise.all(users.users.map((u) => auth.deleteUser(u.uid)));
}

async function wipeCollection(name: string, subcollections = false) {
  const snap = await db.collection(name).get();
  for (const doc of snap.docs) {
    if (subcollections) {
      for (const sub of ['registrations', 'checkins']) {
        const subSnap = await doc.ref.collection(sub).get();
        const batch = db.batch();
        subSnap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    }
    await doc.ref.delete();
  }
}
