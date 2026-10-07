# Notifications & Reminders

## Channels

Every notification flows through the `notifyUser` helper in
`functions/src/notifications.ts` and produces two artifacts:

1. **FCM push** to the user's stored token (`users/{uid}.fcmToken`).
2. **Inbox copy** in `notifications/`, rendered by the user app's Alerts tab.

Failures in either channel are swallowed — a push outage must never fail a
registration or check-in transaction.

## Catalog

| Type (`data.type`) | Trigger | Audience | Mute-able |
| --- | --- | --- | --- |
| `registration_created` | successful register | the user | no (transactional) |
| `registration_canceled` | user cancels | the user | no |
| `registration_removed` | admin removes participant | the user | no |
| `checked_in` | QR scan accepted | the user | no |
| `event_updated` | admin taps "notify participants" | registered users | no |
| `event_canceled` | admin cancels or deletes event | registered users | no |
| `event_status` | admin marks COMPLETED | registered users | no |
| `event_reminder` | scheduled (24 h window) or admin "remind all" | registered users | **yes** |
| `announcement` | admin broadcast | all users (topic) | **yes** |
| `role_changed` | admin promotes/demotes | affected user | no |

## Anti-spam design

- **Reminders deduplicate** with a `reminderSent` flag on each registration
  doc; the hourly scheduler scans a 23–25 h window and only notifies
  registrations without the flag.
- **Event updates are explicit.** Editing an event does not auto-notify —
  the admin chooses "Notify event participants" with a custom message, so
  trivial edits never wake anyone up.
- **Topic preferences.** Users can mute the `reminders` and `announcements`
  topics; transactional confirmations are always delivered.
- **Inbox-only backstop.** Even if FCM is unreachable (no token, simulator),
  the inbox copy still lands so nothing is silently lost.

## Local testing

The emulator suite does not deliver real pushes. All flows are still
exercisable because the inbox copy is written to the emulated Firestore and
the push send failure is caught. The Functions tests assert on the inbox
documents.
