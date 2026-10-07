# Evently — Architecture & Design Decisions

This document explains *why* Evently is built the way it is: the data model,
the trust boundaries, the concurrency strategy, and the trade-offs accepted
along the way.

## 1. System overview

Evently is a monorepo with two Flutter applications (attendee and organizer)
sharing one core Dart package, on top of a Firebase backend whose
security-critical logic lives entirely in Cloud Functions.

```
user_app ─┐
          ├─▶ evently_core ─▶ Firebase client SDKs ─▶ Cloud Functions ─▶ Firestore
admin_app ─┘   (Dart models,   (reads only)             (trusted writes,   Storage
                repositories,                           transactions)      FCM
                theme, widgets)
```

Layering rules enforced by convention (and kept honest by tests):

1. **UI widgets never touch Firebase.** Screens talk to repositories and
   render `Stream`s. This is what makes the widget/controller layer testable
   with fakes and keeps Firebase churn out of presentation code.
2. **Repositories are the only Firestore/Functions callers on the client.**
   Mutations go through callables, never document writes.
3. **Cloud Functions are the only writers of protected data.** Firestore
   rules reject those writes outright for clients (defense in depth), and the
   admin SDK inside functions bypasses rules by design.

## 2. Firestore data model

```
users/{uid}                       ← created by auth trigger, role mirror
  displayName, photoUrl, role ('user'|'admin'), fcmToken, timestamps

events/{eventId}
  title, description, coverImageUrl, location, category,
  startAt, endAt, capacity,
  participantsCount,              ← server-owned counter
  checkedInCount,                 ← server-owned counter
  status (UPCOMING|ONGOING|COMPLETED|CANCELED),
  searchTerms: string[],          ← server-computed prefix index
  qrToken: string,                ← HMAC secret, server-only knowledge
  organizerId, createdAt, updatedAt

events/{eventId}/registrations/{uid}     ← doc id IS the user id
  userId, eventId, status ('ACTIVE'), checkedIn (bool),
  registeredAt, reminderSent

events/{eventId}/checkins/{uid}
  userId, eventId, checkedInAt, method ('QR')

notifications/{autoId}
  userId (recipient), title, body, type, data, read, createdAt

announcements/{autoId}
  title, body, createdBy, createdAt
```

### Why this shape

**Registration doc id = user id.** Duplicate prevention is structural: the
register callable uses `tx.create()`, which fails if the doc exists. No
query, no race window.

**Denormalized `participantsCount` on the event.** Capacity must be checked
on every registration attempt. A counter query over registrations would be
O(n) and racy; an increment on the event doc inside the same transaction is
O(1) and consistent. The counter is *only* mutated by functions, and rules
make it unwritable even by admins.

**Registrations as a subcollection + collection-group query.** "My events"
runs `collectionGroup('registrations').where('userId', ==, uid)` — one query
instead of fanning out registration copies into `users/{uid}/…`. The rules
allow listing only docs whose `userId` matches the caller, so the group query
is safe. Cost: the client joins event docs by id (small, cached reads).

**`qrToken` (HMAC secret) lives on the event doc, but never reaches
clients.** The user app renders QR tickets from the signed payload returned
by the `getMyTicket` callable; the admin app only submits scanned payloads to
the `checkInParticipant` callable. Both receive a *derived signature*, never
the secret. If a leak model ever changes, re-issuing is a secret rotation on
one field.

**`searchTerms` computed server-side** in `adminCreateEvent`/`adminUpdateEvent`
from title + location prefixes, so search behavior is identical regardless of
which client wrote the event, and clients cannot poison the index.

## 3. Trust boundaries

| Operation | Client writes allowed? | Enforcement |
| --- | --- | --- |
| Read event catalog | yes (signed-in) | rules: `events` read requires auth |
| Create / edit / delete events | **no** | rules deny; `admin*Event` callables verify the admin claim |
| Change event status | **no** | callable `adminSetEventStatus` + scheduler |
| Register / cancel | **no** | `registerForEvent` / `cancelRegistration` transactions |
| Check in (scan QR) | **no** | `checkInParticipant`, admin claim required |
| Create registration / check-in docs | **no, for everyone incl. admins** | rules deny writes; only the admin SDK (functions) writes |
| Change roles | **no** | `setAdminRole`; bootstrap closes once an admin exists |
| Edit own profile fields | limited | rules: `diff().affectedKeys().hasOnly([...])` |
| Read notifications | own only | rules: `resource.data.userId == auth.uid` |

The admin check in rules uses **only the auth custom claim** (`token.admin`),
which clients cannot forge. Reading `users/{uid}.role` from inside the users
match block would be recursive (a `get()` that re-enters the same match), so
the claim is the single source of truth for rules; the `role` field exists
purely for app UI and is written by the same function that sets the claim.

Disabled or deleted accounts are handled by Firebase Auth itself: tokens stop
validating, so `request.auth` fails and all rules collapse to deny.

## 4. Concurrency: how capacity can never be exceeded

`registerForEvent` runs a single Firestore transaction that:

1. Re-reads the **event** and the caller's **registration** inside the
   transaction (`tx.getAll`).
2. Rejects if the registration doc exists (`tx.create` would also fail),
   the event is canceled/completed, registration is closed (< 10 min to
   start), or `participantsCount >= capacity`.
3. Creates the registration and increments the counter in the same atomic
   write.

Firestore transactions use optimistic concurrency: if two transactions touch
the same event doc, one retries. The test
`handles concurrent registration without exceeding capacity` fires 8
concurrent registrations at a capacity-3 event and asserts exactly 3
successes and a counter of 3 — the property that matters, verified against
the real emulator rather than asserted by construction.

Check-in is the same pattern: `checkInParticipant` verifies the HMAC
signature, event match, registration existence and check-in window, then
creates `checkins/{uid}` and flips `checkedIn` on the registration in one
transaction. A replayed QR hits an existing check-in doc → typed
`ALREADY_CHECKED_IN` error.

## 5. QR ticket design

Payload: `EV1.<eventId>.<userId>.<sig>` where
`sig = HMAC-SHA256(qrToken, "<eventId>.<userId>")` truncated to 24 chars
(base64url). Design points:

- **The secret never leaves the server.** Users and admins both present
  signed payloads; verification happens inside the callable.
- **Truncated signature** keeps payloads ~70 chars so phone cameras scan
  reliably; 192 bits of HMAC remain far beyond brute-force reach, and
  comparison is constant-time.
- **Event binding is structural** — the eventId is inside the signed payload,
  so a ticket for event A cannot be presented to event B even with a shared
  secret.
- **Fail-closed parsing:** version prefix, charset validation on both ids.

Trade-off accepted: the QR is a bearer credential. If a participant shares
their QR string, another person could be checked in under their name — the
same trust model as every commercial ticketing system. The organizer sees the
user id on scan and can decline.

## 6. Event status lifecycle

`UPCOMING → ONGOING → COMPLETED` is derived from `startAt`/`endAt` and
maintained two ways: a **scheduled function every 2 minutes** (authoritative,
works with zero clients online) and an **onDocumentWritten trigger** that
catches races immediately after writes. `CANCELED` is sticky — only an
explicit admin action sets it, and no scheduler will resurrect it.

The client additionally computes a display status locally (so the UI is
correct between scheduler ticks) but never persists it.

## 7. Notifications without spam

Every notify path goes through one helper (`notifyUser`) that:

1. Sends FCM to the user's stored token (transactional pushes always;
   reminders/announcements respect per-topic mute preferences),
2. Writes an inbox copy to `notifications` for the in-app history,
3. Swallows its own failures so a broken push never fails a registration.

Spam controls: reminders deduplicate via the `reminderSent` flag on the
registration doc (hourly scheduler, 23–25 h window); event updates are sent
explicitly by the admin (`adminNotifyUpdate`) instead of on every edit;
cancellation/removal notifications are one-shot per flow.

## 8. Testing strategy

- **Core Dart tests** cover pure logic: capacity math, status derivation,
  serialization, error translation.
- **Functions tests run against the real Auth + Firestore emulators**, calling
  the actual v2 handlers with synthesized `CallableRequest`s (no HTTP
  plumbing, no offline mocking of the SDK). Concurrency, authorization, QR
  validation and admin flows are exercised end-to-end.
- **Rules tests** (`@firebase/rules-unit-testing`) assert the read/write
  matrix for anonymous / user / admin, including the "even admins cannot
  write server-owned fields" cases — the defense-in-depth guarantee.

CI runs all three suites plus analysis and format checks; any failure blocks
the PR.

## 9. Known trade-offs

- **Client-side joins** for "my events" (registration + event doc reads)
  instead of a fan-out — chosen for a single source of truth; revisit if
  lists grow large.
- **Single FCM token per user** — the last device to sign in wins. A token
  map keyed by device id is the extension path.
- **Email/password only** — providers plug into the same repositories.
- **Cover images from the client** — Storage rules constrain path shape,
  size (5 MB) and MIME, but content scanning is out of scope.
- **Bootstrap admin promotion** is a deliberate, closing window: useful for
  solo deployment, safe because it disappears after the first admin exists.
