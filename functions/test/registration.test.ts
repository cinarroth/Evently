import * as assert from 'assert';
import { describe, it, before, after, beforeEach } from 'mocha';

import { db, makeUser, makeEvent, cleanupAll, wrapCallable, ALICE, BOB, CAROL } from './helpers';
import * as index from '../src/index';

const wrappedRegister = wrapCallable(index.registerForEventHandler);
const wrappedCancel = wrapCallable(index.cancelRegistrationHandler);

describe('registration', () => {
  before(async () => {
    await cleanupAll();
  });

  after(cleanupAll);

  beforeEach(async () => {
    await cleanupAll();
  });

  it('rejects unauthenticated calls', async () => {
    await assert.rejects(
      () => wrappedRegister({ eventId: 'nope' }),
      (err: any) => err.code === 'unauthenticated',
    );
  });

  it('registers a user and increments participantsCount', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 10 });

    await wrappedRegister({ eventId }, { auth: { uid, token: {} } });

    const reg = await db.doc(`events/${eventId}/registrations/${uid}`).get();
    assert.ok(reg.exists, 'registration doc should exist');
    assert.strictEqual(reg.get('status'), 'ACTIVE');

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 1);
  });

  it('rejects duplicate registration for the same event', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 10 });
    await wrappedRegister({ eventId }, { auth: { uid, token: {} } });

    await assert.rejects(
      () => wrappedRegister({ eventId }, { auth: { uid, token: {} } }),
      (err: any) => err.code === 'already-exists' && err.message.includes('ALREADY_REGISTERED'),
    );

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 1, 'count must not double-increment');
  });

  it('rejects registration when the event is full', async () => {
    const alice = await makeUser(ALICE);
    const bob = await makeUser(BOB);
    const carol = await makeUser(CAROL);
    const { eventId } = await makeEvent({ capacity: 2 });

    await wrappedRegister({ eventId }, { auth: { uid: alice, token: {} } });
    await wrappedRegister({ eventId }, { auth: { uid: bob, token: {} } });

    await assert.rejects(
      () => wrappedRegister({ eventId }, { auth: { uid: carol, token: {} } }),
      (err: any) => err.code === 'resource-exhausted' && err.message.includes('EVENT_FULL'),
    );

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 2, 'capacity enforced exactly');
  });

  it('handles concurrent registration without exceeding capacity', async () => {
    const uids = await Promise.all(
      Array.from({ length: 8 }, (_, i) =>
        makeUser({ email: `user${i}@test.dev`, password: 'supersecret1', displayName: `U${i}` }),
      ),
    );
    const { eventId } = await makeEvent({ capacity: 3 });

    const results = await Promise.allSettled(
      uids.map((uid) => wrappedRegister({ eventId }, { auth: { uid, token: {} } })),
    );
    const succeeded = results.filter((r) => r.status === 'fulfilled').length;
    const failed = results.filter((r) => r.status === 'rejected').length;

    assert.strictEqual(succeeded, 3, 'exactly capacity registrations succeed');
    assert.strictEqual(failed, 5, 'the rest are rejected');

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 3);
  });

  it('cancels a registration and frees the spot', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 1 });
    await wrappedRegister({ eventId }, { auth: { uid, token: {} } });

    await wrappedCancel({ eventId }, { auth: { uid, token: {} } });

    const reg = await db.doc(`events/${eventId}/registrations/${uid}`).get();
    assert.ok(!reg.exists, 'registration deleted');

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('participantsCount'), 0, 'spot freed');
  });

  it('rejects cancellation when not registered', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });

    await assert.rejects(
      () => wrappedCancel({ eventId }, { auth: { uid, token: {} } }),
      (err: any) => err.code === 'failed-precondition' && err.message.includes('NOT_REGISTERED'),
    );
  });

  it('rejects registration for canceled events', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5, status: 'CANCELED' });

    await assert.rejects(
      () => wrappedRegister({ eventId }, { auth: { uid, token: {} } }),
      (err: any) => err.message.includes('EVENT_CANCELED'),
    );
  });

  it('rejects registration for already-started events', async () => {
    const uid = await makeUser(ALICE);
    // Started 2 hours ago → registration cutoff passed.
    const { eventId } = await makeEvent({ capacity: 5, startInMinutes: -120 });

    await assert.rejects(
      () => wrappedRegister({ eventId }, { auth: { uid, token: {} } }),
      (err: any) => err.message.includes('EVENT_STARTED'),
    );
  });

  it('rejects registration for a nonexistent event', async () => {
    const uid = await makeUser(ALICE);
    await assert.rejects(
      () => wrappedRegister({ eventId: 'does-not-exist' }, { auth: { uid, token: {} } }),
      (err: any) => err.code === 'not-found',
    );
  });
});
