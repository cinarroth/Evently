# Evently — Event Management Platform

[![CI](https://img.shields.io/badge/CI-github_actions-blue)](.github/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.24+-045bd7)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Auth·Firestore·Storage·FCM·Functions-ffca28)](https://firebase.google.com)

Evently is a production-grade event management platform for schools,
universities, clubs and communities. It ships as **two Flutter apps** backed by
a shared core package and a hardened Firebase backend:

| App | Audience | Purpose |
| --- | --- | --- |
| **`user_app/`** | Attendees | Discover events, register, show QR tickets, manage their profile and notification inbox |
| **`admin_app/`** | Organizers | Create/edit/delete events, manage capacity and participants, run QR check-in at the door, broadcast announcements |

Every security-critical operation — registration, cancellation, capacity
accounting, QR verification and check-in — runs in **Cloud Functions inside
Firestore transactions**. Clients never write protected data directly; the
Firestore rules reject all such writes.

## Features

### User app
- Browse upcoming events with **search** (server-side prefix index) and
  **category filters**
- Event details with live capacity ("n of m spots left") and status
- **Register / cancel** with confirmation dialogs; full events cannot be
  joined (enforced server-side)
- **Unique QR ticket** per registration, signed server-side (HMAC), with
  duplicate check-in protection
- "My events" (upcoming + past) with check-in badges
- In-app **notification inbox** mirroring every push
- Push notifications: registration confirmations, cancellations, 24-hour
  reminders, event updates and announcements

### Admin app
- Full **event CRUD** with cover image upload (5 MB limit, mime-checked)
- Capacity management with a floor: cannot drop below the current count
- **Participant list** with registration time and check-in state; remove
  participants with one tap
- **QR scanner** for door check-in — verifies signature, event match, and
  rejects duplicates; manual code entry fallback
- Status management (UPCOMING / ONGOING / COMPLETED / CANCELED) with
  automatic transitions plus manual override
- Send **reminders**, **event updates** and app-wide **announcements**

### Backend guarantees
- **Capacity is transaction-safe.** Concurrent registrations are serialized by
  Firestore transactions — 8 users racing for 3 spots yields exactly 3
  registrations (covered by a dedicated test).
- **Duplicate registration / check-in is impossible.** The transaction
  re-reads state and the doc id *is* the user id.
- **QR tickets are HMAC-signed** with a per-event secret that clients can
  never read; forged or cross-event QR codes are rejected.
- **Roles cannot be self-granted.** The admin flag is an auth custom claim
  set only by the `setAdminRole` callable; the first admin is created via a
  one-time bootstrap that closes the moment any admin exists.
- **Anti-spam:** reminders deduplicate via a `reminderSent` flag; users can
  mute reminder/announcement topics.

## Screenshots

> Placeholder — run the apps against the emulator suite and drop screenshots
> here (browse, event details, ticket, admin dashboard, scanner).

| User app | Admin app |
| --- | --- |
| _screenshot_ | _screenshot_ |

## Architecture

```
┌────────────────┐   ┌────────────────┐
│   user_app     │   │   admin_app    │        Presentation (screens, widgets)
└───────┬────────┘   └───────┬────────┘
        │    ┌───────────────┘
        ▼    ▼
┌─────────────────────────────┐
│   packages/evently_core     │        Models · Repositories · Services
│   (models, repositories,    │        Theme · Shared widgets
│    services, theme, widgets)│
└───────┬─────────────────────┘
        │  repositories call only:      ← no Firebase calls in UI code
        ▼
┌─────────────────────────────┐     ┌──────────────────────────┐
│  Firebase client SDKs       │────▶│  Cloud Functions (v2)    │
│  Auth · Firestore · Storage │     │  register / cancel /     │
│  FCM                        │     │  check-in / admin ops    │
└─────────────────────────────┘     │  reminders · status jobs │
        ▲                           └───────────┬──────────────┘
        │  Firestore security rules:            │  admin SDK (bypasses rules,
        │  clients read public data only,       │  trusted, transactional)
        │  ALL protected writes denied          ▼
        │                           ┌──────────────────────────┐
        └──────────────────────────▶│  Firestore (source of    │
                                    │  truth) + Storage + FCM  │
                                    └──────────────────────────┘
```

Key decisions (rationale in [ARCHITECTURE.md](ARCHITECTURE.md)):

- **Registration doc id = user id** → duplicates are structurally impossible.
- **Denormalized `participantsCount`** on the event doc maintained inside the
  same transaction as registration writes → capacity checks are O(1) reads.
- **Collection group `registrations`** query powers "my events" without
  fanning out user-side copies.
- **HMAC-signed QR payloads** (`EV1.<eventId>.<userId>.<sig>`) verified with a
  per-event secret; constant-time comparison.
- **Idempotent scheduled jobs** (status updater every 2 min, reminders hourly)
  with sent-flags to prevent notification spam.

## Tech stack

- **Flutter 3.24+** / Dart 3.5+, Material 3
- **Firebase:** Auth (email/password + custom claims), Cloud Firestore,
  Storage, Cloud Messaging, Cloud Functions (Node 22, TypeScript, v2 API)
- **Testing:** `flutter_test`, `mocha` + Firestore/Auth emulators,
  `@firebase/rules-unit-testing`

## Project structure

```
evently/
├── admin_app/               # Organizer application
│   └── lib/screens/         #   auth, events, scanner, announcements
├── user_app/                # Attendee application
│   └── lib/screens/         #   auth, events, notifications, profile
├── packages/
│   └── evently_core/        # Shared package
│       ├── lib/models/      #   Event, Registration, AppUser, Ticket…
│       ├── lib/repositories/#   Auth/Event/Registration/Notifications
│       ├── lib/services/    #   FCM glue, error translation, callables
│       ├── lib/theme/       #   Material 3 design system
│       └── lib/widgets/     #   EventCard, StatusChip, EmptyState…
├── functions/               # Cloud Functions (TypeScript, Node 22)
│   ├── src/                 #   callables, triggers, scheduled jobs
│   ├── test/                #   32 business-logic tests (emulators)
│   └── scripts/seed.ts      #   demo data seeder
├── tests/
│   └── rules/               # 19 Firestore security-rule tests
├── docs/                    # Developer guide
├── firestore.rules          # Security rules (tested)
├── storage.rules            # Storage rules (admin-only covers, own avatars)
├── firestore.indexes.json   # Composite indexes for catalog queries
├── firebase.json            # Emulator suite + deploy config
└── .github/workflows/ci.yml # Flutter + Functions + Rules CI
```

## Firebase setup

1. Create a project at <https://console.firebase.google.com>.
2. Enable **Authentication → Email/Password**.
3. Create a **Firestore** database (production mode).
4. Enable **Storage**.
5. Install the CLI and configure each app:

```bash
npm install -g firebase-tools
flutterfire configure --project=<your-project-id>   # run inside user_app/ and admin_app/
```

Alternatively, pass the config via `--dart-define` — see the header of each
app's `lib/firebase_options.dart`. **No API keys are committed to this repo.**

6. Set your Firebase project for the CLI:

```bash
firebase use --add   # pick your project, alias it (e.g. "prod")
```

## Local development

Full instructions in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Quick start:

```bash
flutter pub get --directory packages/evently_core
flutter pub get --directory user_app
flutter pub get --directory admin_app
(cd functions && npm install)

firebase emulators:start            # Auth 9099, Firestore 8080, UI :4000

# Terminal 2 — apps against the emulators
cd user_app  && flutter run --dart-define=EMULATOR=true
cd admin_app && flutter run --dart-define=EMULATOR=true

# Seed demo data (admin@evently.dev / password123)
(cd functions && npm run seed)
```

### First admin

With emulators running, the `setAdminRole` callable allows **one bootstrap
promotion** while no admin exists:

```bash
curl -s -X POST "http://localhost:5001/<project-id>/us-central1/setAdminRole" \
  -H "Content-Type: application/json" \
  -d '{"data":{"targetUid":"<UID>","role":"admin"}}'
```

In production, prefer the Firebase Console (user → custom claims
`{"admin": true}` + `users/{uid}.role = "admin"`).

## Testing

```bash
# Dart unit tests (models, error translation, widgets)
cd packages/evently_core && flutter test

# Cloud Functions business logic — capacity races, duplicates,
# QR validation, role management (starts emulators automatically)
cd functions && npm test

# Firestore security rules — read/write matrix across roles
cd tests/rules && npm test
```

CI (`.github/workflows/ci.yml`) runs all of the above plus format checks and
static analysis on every push and PR, and fails on any error or formatting
drift.

## Deployment

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
# Apps: build via flutter (appbundle / ipa) and publish through the stores
```

## Security notes

- **Defense in depth:** Firestore rules reject every protected write
  *independently* of the callables; the callable layer enforces business
  rules (capacity, timing, duplicates) that rules cannot express.
- **Server-owned fields:** `participantsCount`, `checkedInCount`, `status`,
  `qrToken` are unwritable even by admins from the client.
- **Role checks use auth custom claims**, which clients cannot alter; the
  Firestore `role` field is a read-only mirror for UI purposes.
- **No secrets in the repo.** Firebase web config is developer-supplied via
  `--dart-define` or `flutterfire configure`; service-account keys are
  git-ignored. App-check integration is a recommended production hardening
  (see below).
- **Registration cutoff:** users cannot register within 10 minutes of start;
  check-in opens 15 minutes before start.

## Known limitations

- Email/password auth only — Google/SSO sign-in is a natural extension.
- Search is prefix-based; semantic/full-text search would need a dedicated
  service (e.g. Typesense/Algolia).
- Cover images upload directly from the admin app; virus/malware scanning of
  uploads is not included.
- Push delivery requires configuring FCM credentials per platform (APNs key,
  `google-services.json` / `GoogleService-Info.plist`) — out of scope for the
  repository.
- Scheduled functions need Cloud Scheduler, which requires a billing account
  even on the Spark plan's free tier.
- Firebase App Check is not yet wired in; recommended before public launch.
- The seed script targets the emulator suite only.

## License

MIT — see [LICENSE](LICENSE).
