import { useViewHistory, type ReviewsView } from '@/hooks/useViewHistory'
import { settingsDirty, DISCARD_PROMPT } from '@/lib/settingsGuard'

export interface ReviewScope { functional_groups?: string[]; managers?: string[]; usernames?: string[]; role?: string }

/**
 * Opens the Reviews workspace with the caller's subject scope. The destination shows exactly the source screen's organizational and exact-username scope
 * (an empty source dimension clears it, as on the Dashboard), so a link never silently broadens or narrows the population. The review context
 * (current evidence or a frozen period), decisions and snapshots are untouched. A role opens the queue for users holding exactly that role.
 */
export function useOpenReviews() {
  const { view, change } = useViewHistory()
  return (scope: ReviewScope, reviewsView: ReviewsView = 'queue') => {
    if (view.settings && settingsDirty() && !window.confirm(DISCARD_PROMPT)) return
    const shared = { ...view.sodFilters?.shared, functional_groups: scope.functional_groups ?? [], managers: scope.managers ?? [], usernames: scope.usernames ?? [],
      ...(scope.role !== undefined ? { role: '', roles: [], role_families: [], role_exact: [scope.role] } : {}) }
    change({ page: 'reviews', reviewsView, settings: false, detailRole: null, sodSubject: null, sodFilters: { ...view.sodFilters, shared } })
  }
}
