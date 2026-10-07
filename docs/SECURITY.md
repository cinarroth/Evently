# Security Model

This page is the condensed security reference. Rationale and trade-offs live
in [ARCHITECTURE.md](../ARCHITECTURE.md).

## Principles

1. **Clients are untrusted.** Every mutation that affects money-equivalent
   state (spots, check-ins, roles) is executed by a Cloud Function that
   re-validates everything server-side.
2. **Defense in depth.** Firestore rules reject protected writes for *all*
   clients (including admins) even though functions are the only intended
   writer. A bug in one layer is caught by the other.
3. **Least privilege.** Events readable by any signed-in user; registrations
   and check-ins readable by owner + admins only; notifications readable by
   the recipient only; everything else denied by the catch-all rule.

## Authentication & roles

- Email/password via Firebase Auth.
- `admin` is an **auth custom claim**, set exclusively by the
  `setAdminRole` callable. The claim is what Firestore rules check
  (`request.auth.token.get('admin', false) == true`).
- `users/{uid}.role` mirrors the claim for app UI; it is *not* read by rules
  (a get() inside the users match block would be recursive) and cannot be
  changed by clients — the update rule whitelists `displayName`, `photoUrl`
  and `updatedAt` only.
- Bootstrap: while **zero** admins exist, `setAdminRole` permits a one-time
  promotion; after that the callable requires an existing admin claim.
- Disabled/deleted accounts lose valid tokens automatically → all rules fail
  closed.

## Threat model highlights

| Threat | Mitigation |
| --- | --- |
| Self-promotion to admin | claim-only checks; profile updates cannot touch role; bootstrap window closes |
| Registering full events / oversubscribing | transaction re-reads event + registration; `tx.create` on doc id = uid |
| Duplicate registration | structural (doc id) + pre-check in transaction |
| Registering after start / canceled events | time + status guards inside the transaction |
| Fake check-ins (writing `checkins/*`) | rules deny all client writes; callable requires admin claim |
| Replaying a QR code | check-in doc id = uid, created in the same transaction that flips `checkedIn` |
| Forged QR payloads | HMAC-SHA256 with per-event secret, constant-time compare, event id bound inside the payload |
| Cross-event ticket reuse | eventId is part of the signed data and re-checked against the scanned event |
| Tampering with counters (`participantsCount`, `checkedInCount`, `qrToken`) | not in the rules whitelist for admins, denied for everyone else |
| Reading other users' registrations/notifications | rules filter on doc id / `userId` field |
| Spam notifications | dedupe flags, explicit admin update action, per-topic mute preferences |
| Malicious cover images | Storage rules enforce admin-only writes, path pattern, ≤5 MB, image MIME |

## Reporting

If you find a vulnerability, please open a private security advisory rather
than a public issue.

## Production hardening checklist

- [ ] Enable **Firebase App Check** (Play Integrity / DeviceCheck) and wire
      `firebase_app_check` in both apps.
- [ ] Review Firestore rules in the console against your real data.
- [ ] Rotate the per-event `qrToken` after events complete (field is
      server-owned; rotation is one write).
- [ ] Set Cloud Function `maxInstances` per function to bound abuse.
- [ ] Enable Firestore daily exports as a backup.
- [ ] Configure Cloud Logging alerts on callable error rates.
