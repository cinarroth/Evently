export type EventStatus = 'UPCOMING' | 'ONGOING' | 'COMPLETED' | 'CANCELED';

/** Grace margin (minutes) shared by scheduler and callables. */
export const STATUS_MARGIN_MINUTES = 2;

/**
 * Derive the natural status from wall-clock time. CANCELED is sticky:
 * cancellation is always an explicit human action.
 */
export function deriveStatus(
  startAt: Date,
  endAt: Date | null,
  now: Date,
  current: EventStatus,
): EventStatus {
  if (current === 'CANCELED') return 'CANCELED';
  if (now < startAt) return 'UPCOMING';
  if (endAt != null && now > endAt) return 'COMPLETED';
  return 'ONGOING';
}

/** FCM data payloads are typed once so Dart and TS agree. */
export function buildPayload(type: string, data: Record<string, string>): Record<string, string> {
  return { type, ...data };
}

/**
 * Search index terms for prefix matching on title + location. Computed
 * server-side so client search stays consistent no matter which app wrote
 * the event.
 */
export function buildSearchTerms(title: string, location: string): string[] {
  const terms = new Set<string>();
  for (const source of [title, location]) {
    const normalized = source.trim().toLowerCase();
    if (normalized.length === 0) continue;
    for (const word of normalized.split(/\s+/)) {
      const clean = word.replace(/[^\w]/g, '');
      if (clean.length < 2) continue;
      for (let i = 2; i <= clean.length && i <= 20; i++) {
        terms.add(clean.slice(0, i));
      }
    }
  }
  return [...terms];
}
