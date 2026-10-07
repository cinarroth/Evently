/**
 * Canonical error codes surfaced to the Flutter clients. The HttpsError.code
 * carries the gRPC-style category; the message carries a stable machine token
 * (first word) plus a human-readable reason, so Dart can map onto typed
 * failures without string-matching prose.
 */
export const Errors = {
  UNAUTHENTICATED: 'unauthenticated',
  PERMISSION_DENIED: 'permission-denied',
  NOT_FOUND: 'not-found',
  ALREADY_EXISTS: 'already-exists',
  FAILED_PRECONDITION: 'failed-precondition',
  RESOURCE_EXHAUSTED: 'resource-exhausted',
  INVALID_ARGUMENT: 'invalid-argument',
  INTERNAL: 'internal',
} as const;

export type ErrorCode = (typeof Errors)[keyof typeof Errors];

/** Machine tokens sent as the first word of the message. */
export const ErrorMessages = {
  ALREADY_REGISTERED: 'ALREADY_REGISTERED',
  NOT_REGISTERED: 'NOT_REGISTERED',
  EVENT_FULL: 'EVENT_FULL',
  EVENT_CANCELED: 'EVENT_CANCELED',
  EVENT_STARTED: 'EVENT_STARTED',
  EVENT_COMPLETED: 'EVENT_COMPLETED',
  INVALID_QR: 'INVALID_QR',
  ALREADY_CHECKED_IN: 'ALREADY_CHECKED_IN',
  CAPACITY_BELOW_COUNT: 'CAPACITY_BELOW_COUNT',
  REMINDER_WINDOW: 'REMINDER_WINDOW',
  CLOSE_TOO_EARLY: 'CLOSE_TOO_EARLY',
  EVENT_NOT_UPCOMING: 'EVENT_NOT_UPCOMING',
} as const;
