import { ClipboardList, ShieldCheck, UserCheck } from 'lucide-react'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'
import { apiRequest } from '@/api/client'
import { scopeParams, sod, type ContextInfo } from '@/api/sod'
import { useHistoryValue, useViewHistory, reviewsHref, userAccessHref, type ReviewsView } from '@/hooks/useViewHistory'
import { availableReviewsViews, REVIEWS_VIEWS } from '@/lib/navigationItems'
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
 * Application-level review workspace. SoD access reviews (Work Queue, Bulk Review, Remediation, Review Periods, Reports and Evidence) reuse the
 * existing review engine, decisions, periods and frozen evidence unchanged and follow the SoD feature switch. Account Review is a separate
 * account and license review in User Access; the Overview links to it and shows its counters but never merges its decisions.
 * The review context and filters are the same shared state the SoD pages use, so moving between SoD and Reviews never broadens or changes scope.
 */
export function ReviewsWorkspace() {
  const configuration = useQuery({ queryKey: ['configuration'], queryFn: fetchConfiguration }),
    [selected] = useHistoryValue('reviewsView'),
    { change } = useViewHistory(),
    // Unknown (still loading or unreadable) keeps SoD reviews; only an explicit saved "off" turns them off, as in the main navigation.
    sodEnabled = configuration.data?.settings.features?.sod !== false,
    views = availableReviewsViews(sodEnabled),
    view: ReviewsView = selected || 'overview',
    sodPage = REVIEWS_VIEWS.find(item => item.value === view)?.sod === true
  return (
    <section className="sod-workspace grid min-w-0 gap-3" aria-label="Access reviews">
      <PageHeader title="Reviews" icon={<ClipboardList size={22} aria-hidden="true" />} />
      <SecondaryNavigation label="Review views" items={views.map(({ value, label, icon }) => ({ value, label, icon, href: reviewsHref(value), active: view === value, onSelect: () => change({ reviewsView: value }) }))} />
      {sodEnabled && <ContextBar />}
      {sodPage && !sodEnabled ? <SodReviewsOff /> : view === 'overview' ? <ReviewsOverview sodEnabled={sodEnabled} /> : view === 'queue' || view === 'bulk' || view === 'remediation' ? <SodReviews tab={view} /> : view === 'periods' ? <SodPeriods /> : <SodReports />}
    </section>
  )
}

/** SoD access reviews are turned off: decisions, periods, frozen snapshots and reports are kept; nothing is enabled from here. */
function SodReviewsOff() {
  const { change } = useViewHistory(), { canAdmin } = useAuthentication()
  return (
    <Card aria-label="SoD access reviews are turned off">
      <StatusBadge tone="neutral">Turned off</StatusBadge>
      <p>SoD access reviews use SoD evidence, which is turned off in Features. Review decisions, periods, frozen snapshots and reports are kept and return when it is turned on. Account Review is not affected.</p>
      <Toolbar>
        <AccountReviewLink />
        {canAdmin && <Button onClick={() => change({ settings: true, settingsTarget: 'features' })}>Open Features</Button>}
      </Toolbar>
    </Card>
  )
}

/** Link to the existing Account Review in User Access (its route, filters and decisions are unchanged). */
function AccountReviewLink({ primary = false }: { primary?: boolean }) {
  const { change } = useViewHistory()
  return <a className={`ui-button ${primary ? 'ui-button-primary' : 'ui-button-secondary'} ui-button-default`} href={userAccessHref('review')} onClick={event => { if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return; event.preventDefault(); change({ page: 'users', accessMode: 'review', user: '', settings: false, detailRole: null }) }}><UserCheck size={16} aria-hidden="true" />Open Account Review</a>
}

interface QueueSummary extends ContextInfo { total: number; counts: Record<string, number> }

/** Landing page: the existing work-queue counters (same endpoint, filters and definitions as the Work Queue), then direct entry points. */
function ReviewsOverview({ sodEnabled }: { sodEnabled: boolean }) {
  return (
    <section className="grid min-w-0 gap-4" aria-label="Reviews overview">
      {sodEnabled ? <AccessReviewsOverview /> : <SodReviewsOff />}
      <AccountReviewsOverview />
    </section>
  )
}

/** SoD access reviews: the Work Queue counters and workflow entry points. */
function AccessReviewsOverview() {
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
    <section className="grid min-w-0 gap-4" aria-label="SoD access reviews">
      <h2 className="flex items-center gap-2 text-base font-semibold"><ShieldCheck size={16} aria-hidden="true" />SoD access reviews</h2>
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
        <p className="ui-description">Risk and activity matrices, the SAP User Group heatmap and Access Explorer stay in SoD.</p>
        <Toolbar><Button onClick={() => change({ page: 'sod', sodView: 'overview' })}>Open SoD analysis</Button></Toolbar>
      </Card>
    </section>
  )
}

interface AccountReviewSummary { loaded: boolean; summary: Record<string, number | null> }

/**
 * Account Review counters for the whole SAP account population (Account Review page filters do not apply here). Account Review records account
 * and license findings; its decisions are separate from SoD access-review decisions and are counted separately.
 */
function AccountReviewsOverview() {
  const result = useQuery({ queryKey: ['account-review', 'reviews-overview'], queryFn: () => apiRequest<AccountReviewSummary>('/api/account-review?limit=1') })
  const data = result.data, value = (key: string) => (data?.summary[key] ?? 0).toLocaleString()
  return (
    <Card aria-label="Account reviews">
      <h2 className="flex items-center gap-2 text-base font-semibold"><UserCheck size={16} aria-hidden="true" />Account reviews</h2>
      <p className="ui-description">Account Review in User Access checks SAP accounts against Employee Directory and license evidence (validity, locks, technical users, position changes). Its decisions are account findings, separate from SoD access-review decisions on roles, activities and risks, and are not included in the access-review counters.</p>
      {result.isError ? <ErrorState error={result.error} onRetry={() => void result.refetch()} title="Account Review progress could not be loaded" />
        : !data ? <LoadingState />
        : !data.loaded ? <p className="ui-description" role="status">No SAP user data is loaded yet.</p>
        : <section className="sod-tiles" aria-label="Account review progress">
          <Kpi label="SAP accounts" value={value('total')} />
          <Kpi label="Requiring review" value={value('requiring_review')} tone={stateTone('Needs review', data.summary.requiring_review ?? 0)} />
          <Kpi label="Completed" value={value('completed')} tone={stateTone('Complete', data.summary.completed ?? 0)} />
        </section>}
      <Toolbar><AccountReviewLink primary /></Toolbar>
    </Card>
  )
}
