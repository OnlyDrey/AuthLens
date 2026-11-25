import { useQuery } from '@tanstack/react-query'
import { ClipboardCheck } from 'lucide-react'
import { emptyFilters, scopeParams, sod, type Subject } from '@/api/sod'
import { Button } from '@/components/Shared/Button'
import { StatusBadge } from '@/components/Shared/Presentation'
import { useSodReviewAction } from '@/hooks/useSodReviewNavigation'
import { useViewHistory } from '@/hooks/useViewHistory'
import { assignmentProgress } from '@/lib/reviewProgress'

/**
 * BUG-07: role review progress on the user profile ("8 of 16 roles reviewed"), from the same subject query and counting rule as the review
 * panel, in the selected review context. Decisions are recorded per assignment (one current decision, whoever made it), so progress is
 * assignment-level. Shown only for users the review supports; it updates after a decision because the panel invalidates the same query.
 */
export function UserReviewProgress({ username }: { username: string }) {
  const review = useSodReviewAction(username)
  const { view } = useViewHistory(), context = view.sodContext || 'current'
  const params = scopeParams(context, emptyFilters, { user: username.trim().toUpperCase() })
  const query = useQuery({ queryKey: ['sod-subject', params.toString()], enabled: !!review, queryFn: () => sod<Subject>('/api/sod/subject', params) })
  if (!review || !query.data?.overview) return null
  const progress = assignmentProgress(query.data.overview.assignments || [])
  const complete = progress.total > 0 && progress.reviewed === progress.total
  return (
    <section aria-label="Role review progress" className="profile-group flex flex-wrap items-center gap-3">
      <h2 className="flex items-center gap-2"><ClipboardCheck size={18} aria-hidden="true" />Role review</h2>
      {progress.total === 0
        ? <span className="ui-description">No role assignments to review in this context.</span>
        : <>
          <StatusBadge tone={complete ? 'success' : 'neutral'}><span aria-label={`${progress.reviewed} of ${progress.total} roles reviewed`}>{progress.reviewed}/{progress.total} roles reviewed</span></StatusBadge>
          <span className="ui-description">{progress.kept} kept · {progress.removal} removal recommended (not yet removed in SAP){progress.investigating ? ` · ${progress.investigating} under investigation` : ''} · {progress.pending} pending</span>
        </>}
      {query.data.frozen && <StatusBadge tone="info">Frozen snapshot</StatusBadge>}
      <Button size="compact" aria-pressed={review.active} onClick={() => review.toggle()}>{review.active ? 'Close review' : 'Open review'}</Button>
    </section>
  )
}
