import * as admin from 'firebase-admin';

export const UserTopics = {
  REGISTRATIONS: 'registrations',
  REMINDERS: 'reminders',
  ANNOUNCEMENTS: 'announcements',
} as const;

export type UserTopic = (typeof UserTopics)[keyof typeof UserTopics];

export interface NotifyInput {
  userId: string;
  title: string;
  body: string;
  /** Machine-readable event type, e.g. `registration_created`. */
  type: string;
  data?: Record<string, string>;
  topic: UserTopic;
  /**
   * Transactional pushes (confirmations, cancellations) ignore mute prefs;
   * reminders and announcements respect the user's topic preferences.
   */
  respectPreference?: boolean;
}

/**
 * Sends an FCM push and writes a Firestore inbox copy rendered by the user
 * app's notification screen. All failures are swallowed: a broken push must
 * never fail a registration or check-in transaction.
 */
export async function notifyUser(input: NotifyInput): Promise<void> {
  const db = admin.firestore();

  try {
    const snap = await db.collection('users').doc(input.userId).get();
    const token = snap.get('fcmToken') as string | undefined;

    let prefEnabled = true;
    if (input.respectPreference === true) {
      const topics = (snap.get('notificationTopics') ?? {}) as Record<string, boolean>;
      prefEnabled = topics[input.topic] !== false;
    }

    if (token != null && token.length > 0 && prefEnabled) {
      await admin.messaging().send({
        token,
        notification: { title: input.title, body: input.body },
        data: { type: input.type, ...input.data },
      });
    }
  } catch {
    // Notification failures never affect the business operation.
  }

  try {
    await db.collection('notifications').add({
      userId: input.userId,
      title: input.title,
      body: input.body,
      type: input.type,
      data: input.data ?? {},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch {
    // Inbox copy is best-effort as well.
  }
}

/** Fan-out helper for broadcasts to whole-user sets. */
export async function notifyMany(inputs: NotifyInput[]): Promise<void> {
  await Promise.all(inputs.map(notifyUser));
}
