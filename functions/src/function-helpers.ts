import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';

export function nowTs(): admin.firestore.FieldValue {
  return admin.firestore.FieldValue.serverTimestamp();
}

export function tsOf(value: unknown): Date | null {
  if (value == null) return null;
  if (typeof value === 'number') return new Date(value);
  const ts = value as admin.firestore.Timestamp;
  if (ts != null && typeof ts.toDate === 'function') return ts.toDate();
  return null;
}

/** Narrow-out HttpsError so catch blocks can distinguish typed failures. */
export function isHttpsError(err: unknown): err is HttpsError {
  return err instanceof HttpsError;
}

/**
 * Convert a typed domain Error (code set by preconditions.ts) into a proper
 * HttpsError the Flutter client can map onto a user-facing message.
 * HttpsErrors pass through untouched; anything else becomes an internal error.
 */
export function throwMapped(err: unknown): never {
  if (isHttpsError(err)) throw err;
  const typed = err as { code?: string; message?: string };
  switch (typed.code) {
    case 'ALREADY_REGISTERED':
      throw new HttpsError('already-exists', 'ALREADY_REGISTERED You are already registered.');
    case 'NOT_REGISTERED':
      throw new HttpsError('failed-precondition', 'NOT_REGISTERED No active registration found.');
    case 'EVENT_FULL':
      throw new HttpsError('resource-exhausted', 'EVENT_FULL The event is at full capacity.');
    case 'EVENT_CANCELED':
      throw new HttpsError('failed-precondition', 'EVENT_CANCELED The event was canceled.');
    case 'EVENT_STARTED':
      throw new HttpsError('failed-precondition', 'EVENT_STARTED Registration is closed; the event already started.');
    case 'EVENT_COMPLETED':
      throw new HttpsError('failed-precondition', 'EVENT_COMPLETED The event has already completed.');
    case 'INVALID_QR':
      throw new HttpsError('failed-precondition', 'INVALID_QR The QR code is invalid for this event.');
    case 'ALREADY_CHECKED_IN':
      throw new HttpsError('already-exists', 'ALREADY_CHECKED_IN This participant already checked in.');
    default:
      throw new HttpsError('internal', 'Unexpected backend error.', typed.message);
  }
}

export function ensureString(
  value: unknown,
  field: string,
  { max = 5000, min = 1, allowEmpty = false } = {},
): string | null {
  if (value == null) return null;
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', `'${field}' must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < min) {
    if (allowEmpty) return null;
    throw new HttpsError('invalid-argument', `'${field}' must be at least ${min} characters.`);
  }
  if (trimmed.length > max) {
    throw new HttpsError('invalid-argument', `'${field}' must be at most ${max} characters.`);
  }
  return trimmed;
}

export function ensureStringStrict(value: unknown, field: string, opts?: { max?: number; min?: number }): string {
  const out = ensureString(value, field, opts);
  if (out == null) {
    throw new HttpsError('invalid-argument', `'${field}' is required.`);
  }
  return out;
}

export function ensureDate(value: unknown, field: string): Date {
  let d: Date | null = null;
  if (typeof value === 'number') d = new Date(value);
  else if (typeof value === 'string') {
    let s = value;
    const dMatch = /^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2})$/.exec(s);
    if (dMatch != null) {
      s = `${dMatch[3]}-${dMatch[2]}-${dMatch[1]}T${dMatch[4]}:${dMatch[5]}:00`;
    }
    d = new Date(s);
  }
  if (d == null || Number.isNaN(d.getTime())) {
    throw new HttpsError('invalid-argument', `'${field}' is not a valid date.`);
  }
  return d;
}

export function ensureCapacity(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 100000) {
    throw new HttpsError('invalid-argument', `'capacity' must be an integer between 1 and 100000.`);
  }
  return value;
}

export function ensureEventId(request: CallableRequest): string {
  const eventId = (request.data as { eventId?: unknown } | null)?.eventId;
  return ensureStringStrict(eventId, 'eventId', { max: 128 });
}
