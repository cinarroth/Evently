/**
 * Firestore security rules tests, run against the Firestore emulator via
 * `firebase emulators:exec` (see package.json test script).
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { after, before, beforeEach, describe, it } = require('mocha');

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'evently-rules-test';

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? 'localhost:8080';
const admin = require('firebase-admin');
const adminApp =
  admin.apps.find((a) => a && a.name === 'seed') ||
  admin.initializeApp({ projectId: PROJECT_ID }, 'seed');
const adminDb = adminApp.firestore();

const rules = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

const ALICE = 'alice-uid';
const BOB = 'bob-uid';
const ADMIN = 'admin-uid';
const ADMIN_TOKEN = { admin: true };

describe('firestore security rules', () => {
  let env;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules },
    });
  });

  beforeEach(async () => {
    await env.clearFirestore();
  });

  after(async () => {
    await env.cleanup();
  });

  const alice = () => env.authenticatedContext(ALICE).firestore();
  const bob = () => env.authenticatedContext(BOB).firestore();
  const adminCtx = () => env.authenticatedContext(ADMIN, ADMIN_TOKEN).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

  async function seedDocs() {
    await adminDb.collection('users').doc(ALICE).set({ uid: ALICE, displayName: 'Alice', role: 'user' });
    await adminDb.collection('users').doc(BOB).set({ uid: BOB, displayName: 'Bob', role: 'user' });
    await adminDb.collection('users').doc(ADMIN).set({ uid: ADMIN, displayName: 'Admin', role: 'admin' });
    await adminDb.collection('users').doc('restricted').set({
      uid: 'restricted',
      role: 'user',
      fcmToken: 'tok',
    });
    await adminDb.collection('events').doc('event1').set({
      title: 'Event One',
      description: 'desc',
      location: 'Hall',
      capacity: 10,
      participantsCount: 1,
      status: 'UPCOMING',
      category: 'general',
      organizerId: ADMIN,
      qrToken: 'secret-qr-token',
      startAt: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await adminDb.collection('events').doc('event1').collection('registrations').doc('alice-uid').set({
      userId: ALICE,
      status: 'ACTIVE',
      checkedIn: false,
    });
    await adminDb.collection('notifications').add({ userId: ALICE, title: 't', body: 'b' });
  }

  // ---------------------------------------------------------------
  // users
  // ---------------------------------------------------------------

  it('user reads own profile', async () => {
    await seedDocs();
    await assertSucceeds(alice().doc(`users/${ALICE}`).get());
  });

  it('user cannot read a profile of another user that carries role fields', async () => {
    await seedDocs();
    // Seeded docs include role, which is outside the public subset — only
    // self/admin may read those.
    await assertFails(alice().doc(`users/${BOB}`).get());
  });

  it('user cannot read a profile containing private fields (fcmToken)', async () => {
    await seedDocs();
    await assertFails(alice().doc('users/restricted').get());
  });

  it('admin can read any profile including restricted fields', async () => {
    await seedDocs();
    await assertSucceeds(adminCtx().doc('users/restricted').get());
  });

  it('user cannot change own role', async () => {
    await seedDocs();
    await assertFails(
      alice().doc(`users/${ALICE}`).update({ role: 'admin', displayName: 'Alice' }),
    );
  });

  it('user can edit own displayName but not someone else\u2019s', async () => {
    await seedDocs();
    await assertSucceeds(alice().doc(`users/${ALICE}`).update({ displayName: 'Alice2' }));
    await assertFails(alice().doc(`users/${BOB}`).update({ displayName: 'Hacked' }));
  });

  it('nobody creates or deletes user profiles (role seeding is server-only)', async () => {
    await seedDocs();
    await assertFails(alice().doc('users/newguy').set({ uid: 'newguy', role: 'admin' }));
    await assertFails(alice().doc(`users/${ALICE}`).delete());
    await assertFails(adminCtx().doc(`users/${ALICE}`).delete());
  });

  // ---------------------------------------------------------------
  // events
  // ---------------------------------------------------------------

  it('any signed-in user can read events', async () => {
    await seedDocs();
    await assertSucceeds(alice().doc('events/event1').get());
  });

  it('anonymous users cannot read events', async () => {
    await seedDocs();
    await assertFails(anon().doc('events/event1').get());
  });

  it('clients cannot create, update, or delete events', async () => {
    await seedDocs();
    await assertFails(alice().collection('events').add({ title: 'Sneaky', capacity: 1 }));
    await assertFails(alice().doc('events/event1').update({ capacity: 999999 }));
    await assertFails(alice().doc('events/event1').delete());
  });

  it('even admins cannot touch server-owned event fields', async () => {
    await seedDocs();
    await assertFails(adminCtx().doc('events/event1').update({ participantsCount: 0 }));
    await assertFails(adminCtx().doc('events/event1').update({ qrToken: 'hax' }));
    // Whitelisted fields are fine.
    await assertSucceeds(adminCtx().doc('events/event1').update({ title: 'Renamed' }));
  });

  // ---------------------------------------------------------------
  // registrations
  // ---------------------------------------------------------------

  it('owner reads own registration; others cannot', async () => {
    await seedDocs();
    await assertSucceeds(alice().doc('events/event1/registrations/alice-uid').get());
    await assertFails(bob().doc('events/event1/registrations/alice-uid').get());
  });

  it('nobody writes registrations directly — not even admins', async () => {
    await seedDocs();
    await assertFails(
      alice()
        .doc('events/event1/registrations/alice-uid')
        .set({ userId: ALICE, status: 'ACTIVE' }),
    );
    await assertFails(alice().doc('events/event1/registrations/alice-uid').delete());
    await assertFails(
      adminCtx().doc('events/event1/registrations/bob-uid').set({ userId: BOB, status: 'ACTIVE' }),
    );
  });

  it('admin reads all registrations for participant lists', async () => {
    await seedDocs();
    await assertSucceeds(
      adminCtx().collection('events/event1/registrations').where('userId', '==', ALICE).get(),
    );
  });

  // ---------------------------------------------------------------
  // check-ins
  // ---------------------------------------------------------------

  it('nobody writes check-ins directly (fake check-in prevention)', async () => {
    await seedDocs();
    await assertFails(
      alice().doc('events/event1/checkins/alice-uid').set({ checkedInAt: new Date() }),
    );
    await assertFails(
      adminCtx().doc('events/event1/checkins/alice-uid').set({ checkedInAt: new Date() }),
    );
  });

  it('owner can read own check-in state; others cannot', async () => {
    await seedDocs();
    await adminDb
      .collection('events')
      .doc('event1')
      .collection('checkins')
      .doc('alice-uid')
      .set({ userId: ALICE, method: 'QR' });
    await assertSucceeds(alice().doc('events/event1/checkins/alice-uid').get());
    await assertFails(bob().doc('events/event1/checkins/alice-uid').get());
  });

  // ---------------------------------------------------------------
  // notifications
  // ---------------------------------------------------------------

  it('users read only their own notifications', async () => {
    await seedDocs();
    const inbox = await alice().collection('notifications').where('userId', '==', ALICE).get();
    assert.ok(inbox.size >= 1);
    await assertFails(bob().collection('notifications').where('userId', '==', ALICE).get());
  });

  it('nobody writes notifications directly (spam prevention)', async () => {
    await seedDocs();
    await assertFails(alice().collection('notifications').add({ userId: ALICE, title: 'spam' }));
    await assertFails(adminCtx().collection('notifications').add({ userId: ALICE, title: 'x' }));
  });

  // ---------------------------------------------------------------
  // default deny
  // ---------------------------------------------------------------

  it('unknown collections are fully denied', async () => {
    await seedDocs();
    await assertFails(alice().collection('secrets').doc('x').get());
    await assertFails(alice().collection('secrets').doc('x').set({ a: 1 }));
  });
});
