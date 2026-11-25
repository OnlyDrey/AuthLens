/** Server view of when this session ends (BUG-04). Unix seconds from the server clock; the server decides expiry. */
export interface SessionTiming { now: number; idle_seconds: number; absolute_seconds: number; warning_seconds: number; idle_expires_at: number; absolute_expires_at: number; expires_at: number; reason: 'inactivity' | 'absolute' }

/** Remaining seconds and whether the warning is due, from a timing read at <code>readAt</code> (local ms). Uses the server's own difference
 * (expires_at - now), so a skewed client clock does not move the deadline. */
export function sessionCountdown(timing: SessionTiming, readAt: number, now: number) {
  const remaining = Math.max(0, Math.round(timing.expires_at - timing.now - (now - readAt) / 1000))
  return { remaining, warning: remaining <= Math.min(timing.warning_seconds, timing.idle_seconds), expired: remaining <= 0 }
}

export const formatRemaining = (seconds: number) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
