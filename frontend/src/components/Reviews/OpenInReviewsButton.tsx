import { ClipboardList } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'
import { Button } from '@/components/Shared/Button'
import { useOpenReviews, type ReviewScope } from './useOpenReviews'

/**
 * Contextual entry into the Reviews Work Queue (SoD access reviews) with the current subject scope. Hidden while SoD evidence, the input of
 * access reviews, is turned off. Without `scope` the shared SoD filters (users, groups, risk, activity, role, transaction, business area) are kept.
 */
export function OpenInReviewsButton({ scope, label = 'Open in Reviews', size = 'default' }: { scope?: ReviewScope; label?: string; size?: 'default' | 'compact' }) {
  const configuration = useQuery({ queryKey: ['configuration'], queryFn: fetchConfiguration }),
    open = useOpenReviews()
  if (configuration.data?.settings.features?.sod !== true) return null
  const title = scope ? 'Opens the Reviews Work Queue with the same Functional Group, Manager and exact SAP username scope. The review context is not changed.'
    : 'Opens the Reviews Work Queue with the shared SoD filters of this page. The review context (current evidence or the selected period) is not changed.'
  return <Button size={size} onClick={() => open(scope)} title={title}><ClipboardList size={16} aria-hidden="true" />{label}</Button>
}
