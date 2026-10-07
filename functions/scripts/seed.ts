/**
 * Seeds demo data into the local emulator suite.
 *
 * Usage: npm run seed   (from functions/, with `firebase emulators:start`
 * running in another terminal, or via emulators:exec).
 */
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? 'localhost:9099';

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? 'evently-demo' });

const db = admin.firestore();
const auth = admin.auth();

const DEMO_ADMIN = { email: 'admin@evently.dev', password: 'password123', displayName: 'Demo Admin' };
const DEMO_USERS = [
  { email: 'alice@evently.dev', password: 'password123', displayName: 'Alice' },
  { email: 'bob@evently.dev', password: 'password123', displayName: 'Bob' },
];

async function ensureUser(u: { email: string; password: string; displayName: string }) {
  try {
    return await auth.getUserByEmail(u.email);
  } catch {
    return auth.createUser(u);
  }
}

async function main() {
  const adminUser = await ensureUser(DEMO_ADMIN);
  await auth.setCustomUserClaims(adminUser.uid, { admin: true });
  await db.doc(`users/${adminUser.uid}`).set(
    { uid: adminUser.uid, displayName: DEMO_ADMIN.displayName, role: 'admin' },
    { merge: true },
  );

  const uids: string[] = [];
  for (const u of DEMO_USERS) {
    const user = await ensureUser(u);
    uids.push(user.uid);
    await db.doc(`users/${user.uid}`).set(
      { uid: user.uid, displayName: u.displayName, role: 'user' },
      { merge: true },
    );
  }

  const events = [
    { title: 'Campus Hackathon 2026', category: 'technology', days: 3, capacity: 120, location: 'Innovation Lab' },
    { title: 'Spring Orchestra Night', category: 'music', days: 7, capacity: 300, location: 'Grand Auditorium' },
    { title: 'Interfaculty Football Final', category: 'sports', days: 10, capacity: 500, location: 'Central Stadium' },
    { title: 'Volunteer Day — River Cleanup', category: 'community', days: 14, capacity: 60, location: 'Riverside Park' },
  ];

  for (const e of events) {
    const startAt = new Date(Date.now() + e.days * 24 * 60 * 60 * 1000);
    const endAt = new Date(startAt.getTime() + 3 * 60 * 60 * 1000);
    const ref = db.collection('events').doc();
    await ref.set({
      title: e.title,
      description: `${e.title} — organized with Evently. Bring your student ID and good vibes.`,
      location: e.location,
      category: e.category,
      capacity: e.capacity,
      startAt: admin.firestore.Timestamp.fromDate(startAt),
      endAt: admin.firestore.Timestamp.fromDate(endAt),
      coverImageUrl: null,
      searchTerms: e.title.toLowerCase().split(/\s+/).flatMap((w) => {
        const out: string[] = [];
        for (let i = 2; i <= w.length; i++) out.push(w.slice(0, i));
        return out;
      }),
      status: 'UPCOMING',
      participantsCount: 0,
      checkedInCount: 0,
      organizerId: adminUser.uid,
      qrToken: crypto.randomBytes(32).toString('base64url'),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('seeded event', e.title, ref.id);
  }

  console.log('\nDemo accounts (password: password123):');
  console.log('  admin@evently.dev  (admin role)');
  console.log('  alice@evently.dev');
  console.log('  bob@evently.dev');
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
