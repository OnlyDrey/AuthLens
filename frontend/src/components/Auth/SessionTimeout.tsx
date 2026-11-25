import { useCallback, useEffect, useRef, useState } from 'react'
import { Clock, LogOut } from 'lucide-react'
import { apiRead, apiRequest, ApiError } from '@/api/client'
import { Button } from '@/components/Shared/Button'
import { Dialog } from '@/components/Shared/Dialog'
import { isUserActive } from '@/lib/userActivity'
import { formatRemaining, sessionCountdown, type SessionTiming } from '@/lib/sessionTiming'

export const SESSION_CHANNEL = 'authlens-session'
const POLL_MS = 30_000

export function expireSession(reason: 'inactivity' | 'absolute' | 'signed-out') {
  window.dispatchEvent(new CustomEvent('authlens-sign-in-required', { detail: { reason } }))
}

/**
 * BUG-04: the inactivity warning for signed-in (Accounts mode) sessions. Expiry is enforced by the server; this only shows it in time.
 * It reads the session timing passively every 30 s (as active only when the user interacted since the last read, so working in a form without
 * requests still counts), warns before the end, continues explicitly on request, and on expiry hands over to sign-in, which clears every
 * cached query. Other tabs follow through a BroadcastChannel. Nothing pending (an open review decision) is ever submitted automatically.
 */
export function SessionTimeout({ onSignOut }: { onSignOut: () => Promise<void> }) {
  const [timing, setTiming] = useState<{ value: SessionTiming; readAt: number } | null>(null)
  const [now, setNow] = useState(() => Date.now())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const lastRead = useRef(Date.now())
  const channel = useRef<BroadcastChannel | null>(null)

  const read = useCallback(async () => {
    const activity = isUserActive(Date.now(), lastRead.current) ? 'active' : 'passive'
    lastRead.current = Date.now()
    try { setTiming({ value: await apiRead<SessionTiming>('/api/auth/session', activity), readAt: Date.now() }) }
    catch (cause) { if (cause instanceof ApiError && cause.status === 401) expireSession('inactivity') }
  }, [])

  useEffect(() => {
    void read()
    const poll = window.setInterval(() => void read(), POLL_MS)
    const tick = window.setInterval(() => setNow(Date.now()), 1000)
    try {
      channel.current = new BroadcastChannel(SESSION_CHANNEL)
      channel.current.onmessage = event => { if (event.data?.type === 'continued') void read(); if (event.data?.type === 'signed-out') expireSession('signed-out') }
    } catch { channel.current = null }
    return () => { window.clearInterval(poll); window.clearInterval(tick); channel.current?.close() }
  }, [read])

  const state = timing ? sessionCountdown(timing.value, timing.readAt, now) : null
  useEffect(() => {
    if (!state?.expired || !timing) return
    // Confirm with the server before signing out locally: another tab may have continued the session a moment ago.
    void apiRead<SessionTiming>('/api/auth/session', 'passive').then(value => setTiming({ value, readAt: Date.now() }))
      .catch(() => expireSession(timing.value.reason))
  }, [state?.expired, timing])

  if (!timing || !state?.warning || state.expired) return null
  const absolute = timing.value.reason === 'absolute'
  const cont = async () => {
    setBusy(true); setError('')
    try { setTiming({ value: await apiRequest<SessionTiming>('/api/auth/session/continue', 'POST'), readAt: Date.now() }); channel.current?.postMessage({ type: 'continued' }) }
    catch (cause) { if (cause instanceof ApiError && cause.status === 401) expireSession('inactivity'); else setError('The session could not be continued. Sign in again if this repeats.') }
    finally { setBusy(false) }
  }
  const signOut = async () => { setBusy(true); try { channel.current?.postMessage({ type: 'signed-out' }); await onSignOut() } finally { setBusy(false) } }
  return (
    <Dialog size="narrow" title={absolute ? 'Session ends soon' : 'Are you still there?'} onClose={() => { if (!absolute) void cont() }}
      description={absolute ? 'This session reaches its maximum length and cannot be extended.' : 'You will be signed out because of inactivity.'}
      footer={<>
        <Button variant="ghost" disabled={busy} onClick={() => void signOut()}><LogOut size={16} aria-hidden="true" />Sign out</Button>
        {!absolute && <Button variant="primary" loading={busy} onClick={() => void cont()}>Continue session</Button>}
      </>}>
      <p className="flex items-center gap-2 text-base" role="timer" aria-live="polite"><Clock size={16} aria-hidden="true" />Signing out in <strong>{formatRemaining(state.remaining)}</strong></p>
      <p className="ui-description">{absolute ? 'Sign in again afterwards to continue.' : 'Unsaved changes, such as an open review decision, are not submitted automatically.'}</p>
      {error && <p role="alert">{error}</p>}
    </Dialog>
  )
}
