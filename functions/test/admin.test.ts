import * as assert from 'assert';
import { describe, it, before, beforeEach, after } from 'mocha';

import {
  db,
  makeUser,
  makeAdmin,
  makeEvent,
  cleanupAll,
  wrapCallable,
  ALICE,
  BOB,
  CAROL,
  ADMIN,
} from './helpers';
import * as index from '../src/index';

const wrappedCreate = wrapCallable(index.adminCreateEventHandler);
const wrappedUpdate = wrapCallable(index.adminUpdateEventHandler);
const wrappedDelete = wrapCallable(index.adminDeleteEventHandler);
const wrappedSetStatus = wrapCallable(index.adminSetEventStatusHandler);
const wrappedSetRole = wrapCallable(index.setAdminRoleHandler);
const wrappedRemoveParticipant = wrapCallable(index.adminRemoveParticipantHandler);
const wrappedRegister = wrapCallable(index.registerForEventHandler);

const adminCtx = (uid: string) => ({ auth: { uid, token: { admin: true } } });
const userCtx = (uid: string) => ({ auth: { uid, token: {} } });

describe('admin event operations', () => {
  before(async () => {
    await cleanupAll();
  });

  after(cleanupAll);

  beforeEach(async () => {
    await cleanupAll();
  });

  it('admin creates an event with server-owned fields initialized', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const res = (await wrappedCreate(
      {
        title: 'Launch Night',
        description: 'Celebration',
        location: 'Main Hall',
        category: 'community',
        capacity: 100,
        startAt: new Date(Date.now() + 86400000).toISOString(),
      },
      adminCtx(adminUid),
    )) as { eventId: string };
    assert.ok(res.eventId, 'returns the new event id');

    const snap = await db.doc(`events/${res.eventId}`).get();
    assert.strictEqual(snap.get('participantsCount'), 0);
    assert.strictEqual(snap.get('status'), 'UPCOMING');
    assert.ok(snap.get('qrToken'), 'qrToken generated');
    assert.strictEqual(snap.get('organizerId'), adminUid);
  });

  it('non-admin cannot create events', async () => {
    const uid = await makeUser(ALICE);
    await assert.rejects(
      () =>
        wrappedCreate(
          {
            title: 'Evil Event',
            description: 'x',
            location: 'x',
            category: 'general',
            capacity: 10,
            startAt: new Date(Date.now() + 86400000).toISOString(),
          },
          userCtx(uid),
        ),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('admin update rejects capacity below the current participant count', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const { eventId } = await makeEvent({ capacity: 10 });
    // Fill 3 spots, then try to squeeze the venue down to 2.
    await wrappedRegister({ eventId }, userCtx(await makeUser(ALICE)));
    await wrappedRegister({ eventId }, userCtx(await makeUser(BOB)));
    await wrappedRegister({ eventId }, userCtx(await makeUser(CAROL)));

    await assert.rejects(
      () => wrappedUpdate({ eventId, capacity: 2 }, adminCtx(adminUid)),
      (err: any) => err.message.includes('CAPACITY_BELOW_COUNT'),
    );
  });

  it('admin update accepts a valid capacity raise', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const { eventId } = await makeEvent({ capacity: 10 });
    await wrappedUpdate({ eventId, capacity: 20 }, adminCtx(adminUid));
    const snap = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(snap.get('capacity'), 20);
  });

  it('admin delete cascades registrations and checkins', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });
    await wrappedRegister({ eventId }, userCtx(uid));

    await wrappedDelete({ eventId }, adminCtx(adminUid));

    const event = await db.doc(`events/${eventId}`).get();
    assert.ok(!event.exists, 'event deleted');
    const reg = await db.doc(`events/${eventId}/registrations/${uid}`).get();
    assert.ok(!reg.exists, 'registration cascaded');
  });

  it('adminSetEventStatus updates status and notifies participants on cancel', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });
    await wrappedRegister({ eventId }, userCtx(uid));

    await wrappedSetStatus({ eventId, status: 'CANCELED' }, adminCtx(adminUid));

    const snap = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(snap.get('status'), 'CANCELED');

    const inbox = await db.collection('notifications').where('userId', '==', uid).get();
    assert.ok(inbox.size >= 1, 'cancellation notification stored');
  });

  it('rejects invalid status values', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const { eventId } = await makeEvent({ capacity: 5 });
    await assert.rejects(
      () => wrappedSetStatus({ eventId, status: 'PAUSED' }, adminCtx(adminUid)),
      (err: any) => err.code === 'invalid-argument',
    );
  });

  it('adminRemoveParticipant frees the spot', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 2 });
    await wrappedRegister({ eventId }, userCtx(uid));

    await wrappedRemoveParticipant({ eventId, userId: uid }, adminCtx(adminUid));

    const reg = await db.doc(`events/${eventId}/registrations/${uid}`).get();
    assert.ok(!reg.exists);
    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 0);
  });

  it('non-admin cannot remove participants', async () => {
    const attacker = await makeUser(BOB);
    const victim = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });
    await wrappedRegister({ eventId }, userCtx(victim));

    await assert.rejects(
      () => wrappedRemoveParticipant({ eventId, userId: victim }, userCtx(attacker)),
      (err: any) => err.code === 'permission-denied',
    );
  });
});

describe('role management', () => {
  before(async () => {
    await cleanupAll();
  });

  after(cleanupAll);

  beforeEach(async () => {
    await cleanupAll();
  });

  it('an existing admin can promote a user', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);

    await wrappedSetRole({ targetUid: uid, role: 'admin' }, adminCtx(adminUid));

    const claims = await (await import('firebase-admin')).auth().getUser(uid);
    assert.strictEqual(claims.customClaims?.admin, true);
    const profile = await db.doc(`users/${uid}`).get();
    assert.strictEqual(profile.get('role'), 'admin');
  });

  it('a non-admin cannot promote anyone once an admin exists', async () => {
    await makeAdmin(ADMIN); // admin exists → bootstrap closed
    const attacker = await makeUser(ALICE);
    const victim = await makeUser(BOB);

    await assert.rejects(
      () => wrappedSetRole({ targetUid: victim, role: 'admin' }, userCtx(attacker)),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('a non-admin cannot demote an admin', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const attacker = await makeUser(ALICE);

    await assert.rejects(
      () => wrappedSetRole({ targetUid: adminUid, role: 'user' }, userCtx(attacker)),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('rejects invalid role values', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    await assert.rejects(
      () => wrappedSetRole({ targetUid: uid, role: 'superadmin' }, adminCtx(adminUid)),
      (err: any) => err.code === 'invalid-argument',
    );
  });
});
