import * as crypto from 'crypto';

/**
 * QR tickets are signed server-side. The payload embeds the userId and eventId
 * and is protected by an HMAC using the event's secret `qrToken`, which only
 * Cloud Functions can read (Firestore rules deny clients event writes and the
 * rules-based admin read path excludes qrToken at creation time).
 */
export interface QrPayload {
  eventId: string;
  userId: string;
  sig: string;
}

/**
 * HMAC token signed with the event's secret. sigLength keeps the QR payload
 * compact enough for reliable phone-camera scanning (~70 chars).
 */
export function signQr(eventSecret: string, eventId: string, userId: string): string {
  const payload = `${eventId}.${userId}`;
  const sig = crypto
    .createHmac('sha256', eventSecret)
    .update(payload)
    .digest('base64url')
    .slice(0, 24);
  return `EV1.${payload}.${sig}`;
}

/** Verify structural integrity of a QR string; returns parts or null. */
export function parseQr(raw: string): QrPayload | null {
  const parts = raw.split('.');
  if (parts.length !== 4 || parts[0] !== 'EV1') return null;
  const [, eventId, userId, sig] = parts;
  if (!eventId || !userId || !sig) return null;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(eventId) || !/^[A-Za-z0-9_-]{1,128}$/.test(userId)) {
    return null;
  }
  return { eventId, userId, sig };
}

/** Constant-time comparison so timing attacks cannot recover the secret. */
export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) {
    // Compare anyway to keep timing flat.
    crypto.timingSafeEqual(Buffer.alloc(16), Buffer.alloc(16));
    return false;
  }
  return crypto.timingSafeEqual(ab, bb);
}

export function verifyQr(raw: string, eventSecret: string): QrPayload | null {
  const parsed = parseQr(raw);
  if (parsed == null) return null;
  const expected = signQr(eventSecret, parsed.eventId, parsed.userId).split('.').pop() ?? '';
  return safeEqual(parsed.sig, expected) ? parsed : null;
}
