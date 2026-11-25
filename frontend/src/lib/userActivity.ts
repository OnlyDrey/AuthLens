/** BUG-04: genuine user input (pointer, keyboard, wheel, touch), as opposed to background work. Requests made without recent input are sent as
 * passive and do not extend the server's inactivity lifetime; the server remains the authority on expiry. */
const ACTIVE_WINDOW_MS = 60_000
let lastInput = 0
let installed = false

export function markUserActivity(now = Date.now()) { lastInput = now }

export function installUserActivityTracking(target: Pick<Window, 'addEventListener'> = window) {
  if (installed) return
  installed = true
  for (const type of ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const) target.addEventListener(type, () => markUserActivity(), { capture: true, passive: true })
}

/** Whether the user interacted within the last minute (or since <code>since</code>). */
export function isUserActive(now = Date.now(), since?: number) {
  return since === undefined ? now - lastInput < ACTIVE_WINDOW_MS : lastInput > since
}

export function lastUserActivity() { return lastInput }

/** Test hook. */
export function resetUserActivity() { lastInput = 0 }
