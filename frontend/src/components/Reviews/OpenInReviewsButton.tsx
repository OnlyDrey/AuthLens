import { ClipboardList } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'
import { Button } from '@/components/Shared/Button'
import { useOpenReviews, type ReviewScope } from './useOpenReviews'

/** Contextual entry into the Reviews Work Queue with the current subject scope. Hidden while SoD evidence (the review engine's input) is turned off. */
export function OpenInReviewsButton({ scope, label = 'Open in Reviews', size = 'default' }: { scope: ReviewScope; label?: string; size?: 'default' | 'compact' }) {
  const configuration = useQuery({ queryKey: ['configuration'], queryFn: fetchConfiguration }),
    open = useOpenReviews()
  if (configuration.data?.settings.features?.sod !== true) return null
  return <Button size={size} onClick={() => open(scope)} title="Opens the Reviews Work Queue with the same Functional Group, Manager and exact SAP username scope. The review context is not changed."><ClipboardList size={16} aria-hidden="true" />{label}</Button>
}
