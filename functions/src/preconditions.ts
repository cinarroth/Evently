import * as admin from 'firebase-admin';
import { ErrorMessages } from './errors';

/** Server-side shape of an event document (subset actually used). */
export interface EventDoc {
  id: string;
  title: string;
  description: string;
  coverImageUrl: string | null;
  location: string;
  startAt: Date;
  endAt: Date | null;
  capacity: number;
  participantsCount: number;
  status: string;
  category: string;
  organizerId: string;
  createdAt?: Date | null;
  updatedAt?: Date | null;
  checkedInCount: number;
  qrToken: string;
}

export function toEventDoc(id: string, data: admin.firestore.DocumentData): EventDoc {
  const startAt = (data['startAt'] as admin.firestore.Timestamp).toDate();
  const endAtRaw = data['endAt'] as admin.firestore.Timestamp | undefined;
  const createdAtRaw = data['createdAt'] as admin.firestore.Timestamp | undefined;
  const updatedAtRaw = data['updatedAt'] as admin.firestore.Timestamp | undefined;
  return {
    id,
    title: (data['title'] as string) ?? '',
    description: (data['description'] as string) ?? '',
    coverImageUrl: (data['coverImageUrl'] as string | null) ?? null,
    location: (data['location'] as string) ?? '',
    startAt,
    endAt: endAtRaw ? endAtRaw.toDate() : null,
    capacity: (data['capacity'] as number) ?? 0,
    participantsCount: (data['participantsCount'] as number) ?? 0,
    status: (data['status'] as string) ?? 'UPCOMING',
    category: (data['category'] as string) ?? 'general',
    organizerId: (data['organizerId'] as string) ?? '',
    createdAt: createdAtRaw ? createdAtRaw.toDate() : null,
    updatedAt: updatedAtRaw ? updatedAtRaw.toDate() : null,
    checkedInCount: (data['checkedInCount'] as number) ?? 0,
    qrToken: (data['qrToken'] as string) ?? '',
  };
}

export const REGISTRATION_CUTOFF_MINUTES = 10;

/**
 * Registration is open when the event is UPCOMING, capacity remains, and the
 * start is more than the cutoff away.
 */
export function canRegister(event: EventDoc, now: Date): boolean {
  return (
    event.status !== 'CANCELED' &&
    event.status !== 'COMPLETED' &&
    event.participantsCount < event.capacity &&
    event.startAt.getTime() - REGISTRATION_CUTOFF_MINUTES * 60 * 1000 > now.getTime()
  );
}

/** Check-in opens 15 minutes before start; blocked for canceled/completed. */
export const CHECKIN_EARLY_MINUTES = 15;

export function canCheckIn(event: EventDoc, now: Date): boolean {
  if (event.status === 'CANCELED' || event.status === 'COMPLETED') return false;
  return now.getTime() >= event.startAt.getTime() - CHECKIN_EARLY_MINUTES * 60 * 1000;
}

/**
 * Typed guards used inside transactions. The caller rethrows them as typed
 * HttpsErrors via mapDbError, so the Flutter client can map onto user-facing
 * messages without parsing prose.
 */
export function assertCanRegister(event: EventDoc, now: Date): void {
  if (event.status === 'CANCELED') throw typed(ErrorMessages.EVENT_CANCELED);
  if (event.status === 'COMPLETED') throw typed(ErrorMessages.EVENT_COMPLETED);
  if (event.participantsCount >= event.capacity) throw typed(ErrorMessages.EVENT_FULL);
  if (event.startAt.getTime() - REGISTRATION_CUTOFF_MINUTES * 60 * 1000 <= now.getTime()) {
    throw typed(ErrorMessages.EVENT_STARTED);
  }
}

function typed(message: string): Error & { code: string } {
  const err = new Error(message) as Error & { code: string };
  err.code = message;
  return err;
}
