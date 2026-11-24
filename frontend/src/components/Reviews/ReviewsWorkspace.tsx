import type { ReactNode } from 'react'
import { ClipboardList, ShieldCheck } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'
import { scopeParams, sod, type ContextInfo } from '@/api/sod'
import { useHistoryValue, useViewHistory, reviewsHref, userAccessHref, type ReviewsView } from '@/hooks/useViewHistory'
import { REVIEWS_VIEWS } from '@/lib/navigationItems'
import { SecondaryNavigation } from '@/components/Shared/Navigation'
import { Card, ErrorState, LoadingState, PageHeader, StatusBadge, Toolbar } from '@/components/Shared/Presentation'
import { Button } from '@/components/Shared/Button'
import { Kpi } from '@/components/Shared/Kpi'
import { useAuthentication } from '@/components/Auth/Authentication'
import { stateTone } from '@/lib/kpiTone'
import { ContextBar, CoverageNotice, hasStoredFilters, useSodContext, useSodFilters } from '@/components/Sod/SodShared'
import { SodReviews } from '@/components/Sod/SodReviews'
import { SodPeriods } from '@/components/Sod/SodPeriods'
import { SodReports } from '@/components/Sod/SodReports'

/**
 * First-class access-review workspace. It reuses the existing review engine, decisions, periods and frozen evidence unchanged:
 * the review context and filters are the same shared state the SoD pages use, so moving between SoD and Reviews never broadens or changes scope.
 * Analytical visualizations (heatmaps, matrices) stay in SoD so the work queue is reachable without scrolling.
 */
export function ReviewsWorkspace() {
  const configuration = useQuery({ queryKey: ['configuration'], queryFn: fetchConfiguration }),
    { change } = useViewHistory(),
    { canAdmin } = useAuthentication()
  const header = <PageHeader title="Reviews" icon={<ClipboardList size={22} aria-hidden="true" />} />
  // Today every review workflow is backed by the SoD review engine, so the SoD feature switch also governs Reviews.
  if (configuration.data?.settings.features?.sod === false) return (
    <section className="sod-workspace grid min-w-0 gap-3" aria-label="Access reviews">
      {header}
      <Card aria-label="Reviews are turned off">
        <StatusBadge tone="neutral">Turned off</StatusBadge>
        <p>Access reviews use SoD evidence, which is disabled in Features. Review decisions, periods, frozen snapshots and reports are kept and return when it is enabled.</p>
        {canAdmin && <Toolbar><Button variant="primary" onClick={() => change({ settings: true, settingsTarget: 'features' })}>Open Features</Button></Toolbar>}
      </Card>
    </section>
  )
  return <ReviewsContent header={header} />
}

function ReviewsContent({ header }: { header: ReactNode }) {
  const [selected] = useHistoryValue('reviewsView'),
    { change } = useViewHistory(),
    view: ReviewsView = selected || 'overview'
  return (
    <section className="sod-workspace grid min-w-0 gap-3" aria-label="Access reviews">
      {header}
      <SecondaryNavigation label="Review views" items={REVIEWS_VIEWS.map(({ value, label, icon }) => ({ value, label, icon, href: reviewsHref(value), active: view === value, onSelect: () => change({ reviewsView: value }) }))} />
      <ContextBar />
      {view === 'overview' ? <ReviewsOverview /> : view === 'queue' || view === 'bulk' || view === 'remediation' ? <SodReviews tab={view} /> : view === 'periods' ? <SodPeriods /> : <SodReports />}
    </section>
  )
}

interface QueueSummary extends ContextInfo { total: number; counts: Record<string, number> }

/** Landing page: the existing work-queue counters (same endpoint, filters and definitions as the Work Queue), then direct entry points. */
function ReviewsOverview() {
  const [context] = useSodContext(),
    [filters] = useSodFilters('queue'),
    { change } = useViewHistory(),
    { canReview } = useAuthentication(),
    filtered = hasStoredFilters({ queue: filters as Record<string, string | boolean | number | string[]> })
  const params = scopeParams(context, filters, { offset: 0, limit: 1 })
  const summary = useQuery({ queryKey: ['sod-queue', 'users', params.toString()], queryFn: () => sod<QueueSummary>('/api/sod/queue/users', params) })
  const data = summary.data, counts = data?.counts ?? {}
  const all = counts.all ?? 0, complete = counts.complete ?? 0
  const open = (reviewsView: ReviewsView) => change({ reviewsView })
  const entries: { view: ReviewsView; text: string; primary?: boolean; review?: boolean }[] = [
    { view: 'queue', text: 'One row per SAP user with each review type\'s progress. Open a user to record decisions.', primary: true },
    { view: 'bulk', text: 'Record one decision for many matching review items after a preview.', review: true },
    { view: 'remediation', text: 'Track removal recommendations and remediation actions until evidence confirms them.' },
    { view: 'periods', text: 'Formal review periods with frozen evidence snapshots, approval gates and history.' },
    { view: 'reports', text: 'Review reports and evidence rendered from one frozen model with checksums.' },
  ]
  return (
    <section className="grid min-w-0 gap-4" aria-label="Reviews overview">
      <CoverageNotice info={data} />
      {summary.isError ? <ErrorState error={summary.error} onRetry={() => void summary.refetch()} title="Review progress could not be loaded" /> : !data ? <LoadingState /> : <>
        <section className="sod-tiles" aria-label="Review progress">
          <Kpi label="Total users" value={all.toLocaleString()} onClick={() => open('queue')} navigates />
          <Kpi label="Needs review" value={(counts.outstanding ?? 0).toLocaleString()} tone={stateTone('Needs review', counts.outstanding ?? 0)} onClick={() => open('queue')} navigates />
          <Kpi label="Complete" value={complete.toLocaleString()} tone={stateTone('Complete', complete)} onClick={() => open('queue')} navigates />
          <Kpi label="Removal recommended" value={(counts.removal ?? 0).toLocaleString()} tone={stateTone('Removal recommended', counts.removal ?? 0)} onClick={() => open('remediation')} navigates />
          <Kpi label="Completion" value={all ? `${Math.floor((complete / all) * 100)}%` : '–'} progress={{ value: complete, max: all, label: `${complete} of ${all} users complete` }} />
        </section>
        {filtered && <p role="note" className="flex flex-wrap items-center gap-2"><StatusBadge tone="info">Filtered</StatusBadge>Counters follow the active Work Queue filters. <Button size="compact" onClick={() => open('queue')}>Review filters in Work Queue</Button></p>}
        <p className="ui-description">Counters use the Work Queue definitions for the selected review context and the Work Queue filters: a user is complete when every role, activity and risk access-review item in scope is decided. {data.frozen ? 'This period is a frozen snapshot; its population and decisions are read only.' : 'Current evidence is live and changes with imported data.'}</p>
      </>}
      <section className="grid gap-3 md:grid-cols-2 xl:grid-cols-3" aria-label="Review workflows">
        {entries.filter(entry => !entry.review || canReview).map(entry => {
          const item = REVIEWS_VIEWS.find(view => view.value === entry.view)!
          return <Card key={entry.view} aria-label={item.label}>
            <h2 className="flex items-center gap-2 text-base font-semibold">{item.icon}{item.label}</h2>
            <p className="ui-description">{entry.text}</p>
            <Toolbar><Button variant={entry.primary ? 'primary' : 'secondary'} onClick={() => open(entry.view)}>Open {item.label}</Button></Toolbar>
          </Card>
        })}
      </section>
      <Card aria-label="Related analysis">
        <h2 className="flex items-center gap-2 text-base font-semibold"><ShieldCheck size={16} aria-hidden="true" />Related analysis</h2>
        <p className="ui-description">Risk and activity matrices, the SAP User Group heatmap and Access Explorer stay in SoD. Account Review in User Access is a separate account and license review; its decisions are not access-review decisions.</p>
        <Toolbar>
          <Button onClick={() => change({ page: 'sod', sodView: 'overview' })}>Open SoD analysis</Button>
          <a className="ui-button ui-button-secondary ui-button-default" href={userAccessHref('review')} onClick={event => { if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return; event.preventDefault(); change({ page: 'users', accessMode: 'review', user: '' }) }}>Open Account Review</a>
        </Toolbar>
      </Card>
    </section>
  )
}
