import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

/**
 * Every callable validates auth itself: relying on client-side checks is never
 * acceptable for security-critical operations.
 */
export function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  return request.auth.uid;
}

/**
 * Admin check uses the custom claim only. The claim is set exclusively by
 * setAdminRole (which requires an existing admin or the bootstrap case), so a
 * client can never self-promote.
 */
export function requireAdmin(request: CallableRequest): string {
  const uid = requireAuth(request);
  const token = request.auth!.token as Record<string, unknown>;
  if (token['admin'] !== true) {
    throw new HttpsError('permission-denied', 'Admin privileges required.');
  }
  return uid;
}
