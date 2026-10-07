/**
 * Centralises all Firestore paths so there is exactly one source of truth for
 * the database layout across Cloud Functions and tests.
 */
export const Paths = {
  usersCol: 'users',
  user: (uid: string) => `users/${uid}`,
  eventsCol: 'events',
  event: (eventId: string) => `events/${eventId}`,
  registrations: (eventId: string) => `events/${eventId}/registrations`,
  registration: (eventId: string, uid: string) => `events/${eventId}/registrations/${uid}`,
  checkins: (eventId: string) => `events/${eventId}/checkins`,
  checkin: (eventId: string, uid: string) => `events/${eventId}/checkins/${uid}`,
  notificationsCol: 'notifications',
  announcementsCol: 'announcements',
};
