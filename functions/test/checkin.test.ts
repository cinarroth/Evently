import * as assert from 'assert';
import { describe, it, before, beforeEach, after } from 'mocha';

import * as admin from 'firebase-admin';

import { db, makeUser, makeAdmin, makeEvent, cleanupAll, wrapCallable, ALICE, BOB, ADMIN } from './helpers';
import * as index from '../src/index';
import { signQr, verifyQr } from '../src/qr';

const wrappedCheckIn = wrapCallable(index.checkInParticipantHandler);
const wrappedGetTicket = wrapCallable(index.getMyTicketHandler);

/** Check-in tests need events that already started, so seed the registration
 * doc directly (the register callable closes registration at event start). */
async function seedRegistration(eventId: string, uid: string) {
  await db.collection('events').doc(eventId).collection('registrations').doc(uid).set({
    userId: uid,
    eventId,
    status: 'ACTIVE',
    checkedIn: false,
    registeredAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

describe('check-in', () => {
  before(async () => {
    await cleanupAll();
  });

  after(cleanupAll);

  beforeEach(async () => {
    await cleanupAll();
  });

  it('QR signature verifies and rejects tampering', () => {
    const secret = 'event-secret-123';
    const payload = signQr(secret, 'event1', 'user1');
    assert.ok(payload.startsWith('EV1.event1.user1.'));
    assert.ok(verifyQr(payload, secret) != null, 'valid sig must verify');

    const tampered = payload.replace('user1', 'user2');
    assert.strictEqual(verifyQr(tampered, secret), null, 'tampered payload must fail');

    assert.strictEqual(verifyQr('garbage', secret), null);
    assert.strictEqual(verifyQr('EV2.event1.user1.abc', secret), null, 'wrong version');
  });

  it('admin checks in a registered participant via QR', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    // Started 5 minutes ago → check-in window is open.
    const { eventId } = await makeEvent({ capacity: 5, startInMinutes: -5 });
    await seedRegistration(eventId, uid);

    const eventSnap = await db.doc(`events/${eventId}`).get();
    const secret = eventSnap.get('qrToken') as string;
    const qrPayload = signQr(secret, eventId, uid);

    const res = (await wrappedCheckIn(
      { eventId, qrPayload },
      { auth: { uid: adminUid, token: { admin: true } } },
    )) as { ok: boolean };
    assert.strictEqual(res.ok, true);

    const checkin = await db.doc(`events/${eventId}/checkins/${uid}`).get();
    assert.ok(checkin.exists, 'checkin doc stored');
    assert.ok(checkin.get('checkedInAt'), 'check-in timestamp stored');

    const reg = await db.doc(`events/${eventId}/registrations/${uid}`).get();
    assert.strictEqual(reg.get('checkedIn'), true);

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('checkedInCount'), 1);
  });

  it('rejects duplicate check-in with the same QR', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5, startInMinutes: -5 });
    await seedRegistration(eventId, uid);

    const secret = (await db.doc(`events/${eventId}`).get()).get('qrToken') as string;
    const qrPayload = signQr(secret, eventId, uid);
    const ctx = { auth: { uid: adminUid, token: { admin: true } } };

    await wrappedCheckIn({ eventId, qrPayload }, ctx);
    await assert.rejects(
      () => wrappedCheckIn({ eventId, qrPayload }, ctx),
      (err: any) => err.code === 'already-exists' && err.message.includes('ALREADY_CHECKED_IN'),
    );

    const event = await db.doc(`events/${eventId}`).get();
    assert.strictEqual(event.get('checkedInCount'), 1, 'no double count');
  });

  it('rejects a QR signed with the wrong secret', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5, startInMinutes: -5 });
    await seedRegistration(eventId, uid);

    const forged = signQr('attacker-secret', eventId, uid);
    await assert.rejects(
      () => wrappedCheckIn({ eventId, qrPayload: forged }, { auth: { uid: adminUid, token: { admin: true } } }),
      (err: any) => err.message.includes('INVALID_QR'),
    );
  });

  it('rejects a QR for a different event than the scanned one', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId: eventA } = await makeEvent({ capacity: 5 });
    const { eventId: eventB } = await makeEvent({ capacity: 5 });
    await seedRegistration(eventA, uid);

    const secretB = (await db.doc(`events/${eventB}`).get()).get('qrToken') as string;
    const qrForB = signQr(secretB, eventB, uid);

    await assert.rejects(
      () =>
        wrappedCheckIn(
          { eventId: eventA, qrPayload: qrForB },
          { auth: { uid: adminUid, token: { admin: true } } },
        ),
      (err: any) => err.message.includes('INVALID_QR'),
    );
  });

  it('rejects check-in for someone without a registration', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });

    const secret = (await db.doc(`events/${eventId}`).get()).get('qrToken') as string;
    const qrPayload = signQr(secret, eventId, uid);

    await assert.rejects(
      () => wrappedCheckIn({ eventId, qrPayload }, { auth: { uid: adminUid, token: { admin: true } } }),
      (err: any) => err.message.includes('INVALID_QR'),
    );
  });

  it('rejects check-in before the event window opens', async () => {
    const adminUid = await makeAdmin(ADMIN);
    const uid = await makeUser(ALICE);
    // Starts in 2 days — check-in opens only 15 minutes before.
    const { eventId } = await makeEvent({ capacity: 5, startInMinutes: 60 * 48 });
    await seedRegistration(eventId, uid);

    const secret = (await db.doc(`events/${eventId}`).get()).get('qrToken') as string;
    const qrPayload = signQr(secret, eventId, uid);

    await assert.rejects(
      () => wrappedCheckIn({ eventId, qrPayload }, { auth: { uid: adminUid, token: { admin: true } } }),
      (err: any) => err.message.includes('EVENT_STARTED'),
    );
  });

  it('rejects non-admin check-in attempts', async () => {
    const uid = await makeUser(ALICE);
    const attacker = await makeUser(BOB);
    const { eventId } = await makeEvent({ capacity: 5 });
    await seedRegistration(eventId, uid);

    const secret = (await db.doc(`events/${eventId}`).get()).get('qrToken') as string;
    const qrPayload = signQr(secret, eventId, uid);

    await assert.rejects(
      () => wrappedCheckIn({ eventId, qrPayload }, { auth: { uid: attacker, token: {} } }),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('getMyTicket returns a signed payload for registered users only', async () => {
    const uid = await makeUser(ALICE);
    const { eventId } = await makeEvent({ capacity: 5 });

    await assert.rejects(
      () => wrappedGetTicket({ eventId }, { auth: { uid, token: {} } }),
      (err: any) => err.message.includes('NOT_REGISTERED'),
    );

    await seedRegistration(eventId, uid);
    const res = (await wrappedGetTicket({ eventId }, { auth: { uid, token: {} } })) as {
      qrPayload: string;
    };
    assert.ok(res.qrPayload.startsWith('EV1.'), 'ticket payload is signed');
  });
});
