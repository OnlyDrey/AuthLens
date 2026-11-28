import { Building2, CalendarRange, ClipboardCheck, ClipboardList, ListChecks, ShieldCheck, UserCheck, UsersRound, Wrench } from 'lucide-react'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'
import { apiRequest } from '@/api/client'
import { scopeParams, sod, type ContextInfo, type Filters } from '@/api/sod'
import { useHistoryValue, useViewHistory, reviewsHref, type ReviewsView } from '@/hooks/useViewHistory'
import { availableReviewsViews, REVIEWS_VIEWS } from '@/lib/navigationItems'
import { SecondaryNavigation } from '@/components/Shared/Navigation'
import { Card, DataTable, EmptyState, ErrorState, LoadingState, PageHeader, SectionHeader, StatusBadge, Toolbar } from '@/components/Shared/Presentation'
import { InfoList, InfoRow } from '@/components/Shared/InfoList'
import { SortControl } from '@/components/Shared/FilterLayout'
import { FormField } from '@/components/Shared/Controls'
import { Select } from '@/components/Shared/Select'
import { Button } from '@/components/Shared/Button'
import { Kpi } from '@/components/Shared/Kpi'
import { useAuthentication } from '@/components/Auth/Authentication'
import { stateTone } from '@/lib/kpiTone'
import { ContextBar, CoverageNotice, PAGE_FIELDS, readFilters, SodFilters, useSodContext, useSodFilters, writeFilters } from '@/components/Sod/SodShared'
import { SodReviews } from '@/components/Sod/SodReviews'
import { SodPeriods } from '@/components/Sod/SodPeriods'
import { AccountReview } from '@/components/Access/AccountReview'
import { MappingAvailability } from '@/components/Access/MappingAvailability'
import { UserDetails } from '@/components/Access/UserAccess'

/**
 * Application-level review workspace. SoD access reviews (Work Queue, Bulk Review, Remediation, Review Periods) reuse the existing review engine,
 * decisions, periods and frozen evidence unchanged and follow the SoD feature switch. Position Changes and Account Review (NAV-3) are the existing
 * account and license review on their shared implementation; they never depend on the SoD switch and their decisions are never merged with SoD
 * access-review decisions. Reports moved to the Reports module (NAV-4).
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
    sodPage = REVIEWS_VIEWS.find(item => item.value === view)?.sod === true,
    accountPage = view === 'account-review' || view === 'position-changes'
  return (
    <section className="sod-workspace grid min-w-0 gap-3" aria-label="Access reviews">
      <PageHeader title="Reviews" icon={<ClipboardList size={22} aria-hidden="true" />} />
      <SecondaryNavigation label="Review views" items={views.map(({ value, label, icon }) => ({ value, label, icon, href: reviewsHref(value), active: view === value, onSelect: () => change({ reviewsView: value }) }))} />
      {sodEnabled && !accountPage && <ContextBar />}
      {accountPage ? <AccountReviewPage key={view} positions={view === 'position-changes'} />
        : sodPage && !sodEnabled ? <SodReviewsOff /> : view === 'overview' ? <ReviewsOverview sodEnabled={sodEnabled} /> : view === 'queue' || view === 'bulk' || view === 'remediation' ? <SodReviews tab={view} /> : <SodPeriods />}
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

/** Account Review or Position Changes (one shared implementation, NAV-3). Opening an account shows its details here; Back returns to the list. */
function AccountReviewPage({ positions }: { positions: boolean }) {
  const [selected] = useHistoryValue('user'), { change } = useViewHistory()
  const none = { index: -1, total: 0, loading: false, error: null, missing: false, onPrevious: undefined, onNext: undefined }
  // min-w-0: inside the workspace grid the page (and an opened account's details) must not grow wider than the viewport
  return <div className="min-w-0"><MappingAvailability>
    <div hidden={!!selected}><AccountReview onUser={username => change({ user: username, userTrail: [] })} mode={positions ? 'positions' : undefined} /></div>
    {selected && <UserDetails username={selected} parent={positions ? 'Position Changes' : 'Account Review'} navigation={none}
      onBack={() => change({ user: '', userTrail: [] })}
      onCompare={() => change({ page: 'users', accessMode: 'compare', user: '', userContext: {}, userComparison: { a: selected, b: '', validity: 'active', kind: 'roles', difference: '', search: '', areas: [] } })}
      onRole={role => change({ detailRole: role })}
      onRelease={role => change({ page: 'releases', release: { role, status: 'all' }, releaseContext: role, user: '', detailRole: null })} />}
  </MappingAvailability></div>
}

/** Link to Account Review in Reviews (its filters and decisions are unchanged). */
function AccountReviewLink({ primary = false }: { primary?: boolean }) {
  const { change } = useViewHistory()
  return <a className={`ui-button ${primary ? 'ui-button-primary' : 'ui-button-secondary'} ui-button-default`} href={reviewsHref('account-review')} onClick={event => { if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return; event.preventDefault(); change({ page: 'reviews', reviewsView: 'account-review', user: '' }) }}><UserCheck size={16} aria-hidden="true" />Open Account Review</a>
}

type ReviewKind = 'assignment' | 'activity' | 'acceptance'
interface ReviewCoverage { total: number; covered: number; manual: number; derived: number; pending: number; outdated: number; investigate: number; outstanding: number }
interface GroupRow { key: string; label: string; users: number; complete: number; requiring_review: number }
interface ReviewsOverviewData extends ContextInfo {
  progress: { users: number; complete: number; requiring_review: number; partial: number; not_started: number; with_outdated: number; with_removal: number; historical_items: number }
  review_coverage: Record<ReviewKind, ReviewCoverage>
  decisions: Record<ReviewKind, Record<string, number>>
  remediation: { removal_recommended: number; awaiting_action: number; open_actions: number; overdue: number; completed_actions: number; verified_removals: number; investigate: number; compensating_controls: number }
  periods: { scope: 'global'; total: number; open: number; awaiting_approval: number; approved: number; closed: number; rejected: number }
  groups: { group_by: string; available: boolean; reason: string | null; rows: GroupRow[]; distinct_users?: number }
  filtered: boolean
}
/** Review types in the order the Work Queue shows them, with the labels Reports and Evidence uses. */
const KINDS: { kind: ReviewKind; label: string }[] = [{ kind: 'assignment', label: 'Role reviews' }, { kind: 'activity', label: 'Activity reviews' }, { kind: 'acceptance', label: 'Risk reviews' }]
/** Recorded review states per type (the existing decision model; no new states). */
const DECISIONS: Record<ReviewKind, [string, string, 'success' | 'warning' | 'error' | 'neutral'][]> = {
  assignment: [['Keep', 'Keep', 'success'], ['Removal required', 'Removal recommended', 'error'], ['Investigate', 'Investigate (not final)', 'warning']],
  activity: [['Approved', 'Approved', 'success'], ['Conditional', 'Conditional', 'warning'], ['Removal required', 'Removal recommended', 'error'], ['Investigate', 'Investigate (not final)', 'warning']],
  acceptance: [['Accepted', 'Risk accepted', 'success'], ['Rejected', 'Risk rejected', 'error']],
}
const GROUPINGS = [{ value: 'sap_user_group', label: 'SAP user group' }, { value: 'functional_group', label: 'Functional Group' }, { value: 'manager', label: 'Manager' }, { value: 'department', label: 'Department' }, { value: 'site', label: 'Site' }]
const GROUP_SORTS = [{ value: 'name', label: 'Group name' }, { value: 'completion', label: 'Completion' }, { value: 'outstanding', label: 'Users requiring review' }, { value: 'users', label: 'Total users' }]
const percent = (value: number, max: number) => (max ? `${Math.floor((value / max) * 100)}%` : 'No applicable items')

/** Landing page: the SoD access-review dashboard (WP37) and the separate Account Review counters. */
function ReviewsOverview({ sodEnabled }: { sodEnabled: boolean }) {
  return (
    <section className="grid min-w-0 gap-4" aria-label="Reviews overview">
      {sodEnabled ? <AccessReviewsOverview /> : <SodReviewsOff />}
      <AccountReviewsOverview />
    </section>
  )
}

/**
 * WP37: operational SoD access-review dashboard for the selected review context. Every figure comes from /api/sod/reviews/overview, which reuses the
 * Work Queue items, the Remediation rows and the period index; filters are the Work Queue's own filters (shared slot), so a drill-down opens a
 * destination with the same population. Period lifecycle figures are global and say so.
 */
function AccessReviewsOverview() {
  const [context] = useSodContext(),
    [filters, setFilters] = useSodFilters('queue'),
    [stored] = useHistoryValue('sodFilters'),
    { change } = useViewHistory(),
    [groupBy, setGroupBy] = useState('sap_user_group'),
    [groupSort, setGroupSort] = useState('name'),
    [groupDescending, setGroupDescending] = useState(false)
  const params = scopeParams(context, filters, { group_by: groupBy })
  const result = useQuery({ queryKey: ['sod-reviews-overview', params.toString()], queryFn: () => sod<ReviewsOverviewData>('/api/sod/reviews/overview', params) })
  const data = result.data
  // Drill-down keeps the review context and every applied filter, and adds the metric's own constraint.
  const openQueue = (queueProgress: '' | 'outstanding' | 'complete' | 'removal', extra: Filters = {}) =>
    change({ reviewsView: 'queue', queueProgress, ...(Object.keys(extra).length ? { sodFilters: writeFilters(stored, 'queue', PAGE_FIELDS.queue, { ...filters, ...extra }) } : {}) })
  const openRemediation = (tracking: '' | 'untracked' | 'verified') =>
    change({ reviewsView: 'remediation', sodFilters: writeFilters(stored, 'remediation', PAGE_FIELDS.remediation, { ...readFilters(stored, 'remediation'), tracking }) })
  const p = data?.progress, r = data?.remediation, periods = data?.periods
  const rows = (data?.groups.rows ?? []).slice().sort((a, b) => {
    const ratio = (row: GroupRow) => (row.users ? row.complete / row.users : 0)
    const order = groupSort === 'name' ? a.label.localeCompare(b.label) : groupSort === 'completion' ? ratio(a) - ratio(b) : groupSort === 'outstanding' ? a.requiring_review - b.requiring_review : a.users - b.users
    return (groupDescending ? -order : order) || a.label.localeCompare(b.label)
  })
  const groupFilter = (row: GroupRow): Filters | null =>
    groupBy === 'sap_user_group' && row.key ? { group: '', groups: [row.key] }
      : groupBy === 'functional_group' ? { functional_group: '', functional_groups: [row.key] }
      : groupBy === 'manager' ? { manager: '', managers: [row.key] } : null   // department and site have no Work Queue filter
  return (
    <section className="grid min-w-0 gap-4" aria-label="SoD access reviews">
      <SodFilters view="sod_queue" workspace="reviews-overview" filters={filters} setFilters={setFilters} storageKey="authlens-reviews-overview-filter-sidebar" defaultOpen={false}
        fields={['group', 'username', 'risk', 'activity', 'role', 'role_suffix', 'tcode', 'category', 'validity']}
        actions={<Button variant="primary" onClick={() => openQueue('')}>Open Work Queue</Button>}>
        <CoverageNotice info={data} />
        <p className="ui-description" data-testid="access-review-scope">Access Review Progress for SoD access reviews (roles, activities and risks) in the selected review context{data?.filtered ? ' and the applied Work Queue filters' : ''}. {data?.frozen ? 'This period is a frozen snapshot; its population and decisions are read only.' : 'Current evidence is live and changes with imported data.'} Account Review is a separate process and is counted below.</p>
        {result.isError ? <ErrorState error={result.error} onRetry={() => void result.refetch()} title="The Reviews Overview could not be loaded" /> : !data || !p || !r || !periods ? <LoadingState /> : <>
          <div className="dashboard-workspace">
            <div className="dashboard-cards" aria-label="Review key figures">
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Access Review Progress">
                <SectionHeader title="Access Review Progress" icon={<UsersRound size={18} aria-hidden="true" />} />
                <InfoList>
                  <InfoRow primary label="Users in scope" value={p.users.toLocaleString()} onClick={() => openQueue('')} navigates />
                  <InfoRow label="Users requiring review" value={p.requiring_review.toLocaleString()} tone={p.requiring_review ? 'warning' : 'neutral'} onClick={() => openQueue('outstanding')} navigates note={`${p.partial.toLocaleString()} partly reviewed · ${p.not_started.toLocaleString()} not started`} />
                  <InfoRow label="Users with completed reviews" value={p.complete.toLocaleString()} tone={p.complete ? 'success' : 'neutral'} onClick={() => openQueue('complete')} navigates
                    progress={p.users ? { value: p.complete, max: p.users, label: `${p.complete} of ${p.users} users complete`, tone: 'success' } : undefined} />
                  <InfoRow label="Completion" value={percent(p.complete, p.users)} />
                  <InfoRow label="Users with removal recommendations" value={p.with_removal.toLocaleString()} tone={p.with_removal ? 'error' : 'neutral'} onClick={() => openQueue('removal')} navigates note="Overlaps with the counts above: a complete user can have a removal recommendation." />
                  <InfoRow label="Users with outdated decisions" value={p.with_outdated.toLocaleString()} tone={p.with_outdated ? 'warning' : 'neutral'} note="Also counted as requiring review." />
                </InfoList>
              </section>
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Review Coverage">
                <SectionHeader title="Review Coverage" icon={<ShieldCheck size={18} aria-hidden="true" />} />
                <InfoList>
                  {KINDS.map(({ kind, label }) => { const c = data.review_coverage[kind]; return <InfoRow key={kind} label={label} value={c.total ? `${c.covered.toLocaleString()} / ${c.total.toLocaleString()}` : 'No applicable items'}
                    note={c.total ? `${percent(c.covered, c.total)} · ${c.manual.toLocaleString()} recorded, ${c.derived.toLocaleString()} derived` : undefined}
                    progress={c.total ? { value: c.covered, max: c.total, label: `${c.covered} of ${c.total} ${label.toLowerCase()} covered`, tone: 'success' } : undefined} /> })}
                </InfoList>
                <p className="ui-description">Covered means decided by a recorded decision or derived from other decisions (each item once). Risk coverage is not formal risk acceptance, and coverage is not verified remediation. Review types are not combined into one percentage.</p>
              </section>
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Review Workload">
                <SectionHeader title="Review Workload" icon={<ListChecks size={18} aria-hidden="true" />} />
                <InfoList>
                  {KINDS.map(({ kind, label }) => <InfoRow key={kind} label={`Pending ${label.toLowerCase()}`} value={(data.review_coverage[kind].pending + data.review_coverage[kind].investigate).toLocaleString()} onClick={() => openQueue('outstanding')} navigates
                    note={data.review_coverage[kind].investigate ? `${data.review_coverage[kind].investigate.toLocaleString()} under investigation` : undefined} />)}
                  <InfoRow label="Outdated decisions" value={KINDS.reduce((sum, { kind }) => sum + data.review_coverage[kind].outdated, 0).toLocaleString()} tone="warning" onClick={() => openQueue('outstanding')} navigates note="Evidence changed after the decision; review again." />
                  <InfoRow primary label="Outstanding review items" value={KINDS.reduce((sum, { kind }) => sum + data.review_coverage[kind].outstanding, 0).toLocaleString()} note="Pending, under investigation and outdated items, each counted once." />
                </InfoList>
              </section>
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Review Decisions">
                <SectionHeader title="Review Decisions" icon={<ClipboardCheck size={18} aria-hidden="true" />} />
                {KINDS.map(({ kind, label }) => <InfoList key={kind} label={`${label} decisions`}>
                  <li className="ui-description font-semibold">{label}</li>
                  {DECISIONS[kind].map(([state, name, tone]) => <InfoRow key={state} label={name} value={(data.decisions[kind][state] ?? 0).toLocaleString()} tone={data.decisions[kind][state] ? tone : 'neutral'} />)}
                  {data.review_coverage[kind].derived > 0 && <InfoRow label="Derived coverage (no own decision)" value={data.review_coverage[kind].derived.toLocaleString()} />}
                  {data.review_coverage[kind].outdated > 0 && <InfoRow label="Outdated (superseded evidence)" value={data.review_coverage[kind].outdated.toLocaleString()} tone="warning" />}
                </InfoList>)}
              </section>
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Remediation">
                <SectionHeader title="Remediation" icon={<Wrench size={18} aria-hidden="true" />} />
                <InfoList>
                  <InfoRow primary label="Assignments recommended for removal" value={r.removal_recommended.toLocaleString()} tone={r.removal_recommended ? 'error' : 'neutral'} onClick={() => openRemediation('')} navigates note="A recommendation, not proof of removal." />
                  <InfoRow label="Awaiting a remediation action" value={r.awaiting_action.toLocaleString()} tone={r.awaiting_action ? 'warning' : 'neutral'} onClick={() => openRemediation('untracked')} navigates />
                  <InfoRow label="Open remediation actions" value={r.open_actions.toLocaleString()} onClick={() => openRemediation('')} navigates />
                  <InfoRow label="Overdue actions" value={r.overdue.toLocaleString()} tone={r.overdue ? 'error' : 'neutral'} />
                  <InfoRow label="Actions recorded as completed" value={r.completed_actions.toLocaleString()} note="Manually recorded, not proof of removal." />
                  <InfoRow label="Removals confirmed by SAP evidence" value={r.verified_removals.toLocaleString()} tone={r.verified_removals ? 'success' : 'neutral'} onClick={() => openRemediation('verified')} navigates note="Newer imported SAP data no longer contains the assignment." />
                </InfoList>
              </section>
              <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Review Periods">
                <SectionHeader title="Review Periods" icon={<CalendarRange size={18} aria-hidden="true" />} />
                <InfoList>
                  <InfoRow label="Open periods (Draft, In review)" value={periods.open.toLocaleString()} onClick={() => change({ reviewsView: 'periods' })} navigates />
                  <InfoRow label="Awaiting approval" value={periods.awaiting_approval.toLocaleString()} tone={periods.awaiting_approval ? 'warning' : 'neutral'} onClick={() => change({ reviewsView: 'periods' })} navigates />
                  <InfoRow label="Approved" value={periods.approved.toLocaleString()} tone={periods.approved ? 'success' : 'neutral'} />
                  <InfoRow label="Closed" value={periods.closed.toLocaleString()} />
                  {periods.rejected > 0 && <InfoRow label="Rejected (returned for review)" value={periods.rejected.toLocaleString()} tone="warning" />}
                </InfoList>
                <p className="ui-description">Global: every review period you can open, not limited by the review context or filters.</p>
              </section>
            </div>
          </div>
          <section className="dashboard-section min-w-0 rounded-card bg-surface p-4" aria-label="Organizational review progress">
            <SectionHeader title="Organizational review progress" icon={<Building2 size={18} aria-hidden="true" />} />
            <Toolbar aria-label="Organizational grouping">
              <FormField label="Group by"><Select value={groupBy} onChange={(event) => setGroupBy(event.target.value)}>{GROUPINGS.map((g) => <option key={g.value} value={g.value}>{g.label}</option>)}</Select></FormField>
              <SortControl label="Sort groups" value={groupSort} options={GROUP_SORTS} descending={groupDescending} onChange={setGroupSort} onDescending={setGroupDescending} />
            </Toolbar>
            {!data.groups.available ? <p role="status" className="ui-description">{data.groups.reason}</p>
              : !rows.length ? <EmptyState>No SAP users with access-review items match the selected scope.</EmptyState>
              : <>
                <DataTable caption="Users and completed access reviews per group" regionLabel="Organizational review progress table" density="compact">
                    <thead><tr><th scope="col">{GROUPINGS.find((g) => g.value === groupBy)?.label}</th><th scope="col">Users</th><th scope="col">Complete</th><th scope="col">Requiring review</th><th scope="col">Completion</th></tr></thead>
                    <tbody>{rows.map((row) => { const filter = groupFilter(row); return <tr key={row.key || '__none__'}>
                      <th scope="row">{filter ? <button type="button" className="text-link" onClick={() => openQueue('', filter)} aria-label={`Open the Work Queue for ${row.label}`}>{row.label}</button> : row.label}</th>
                      <td>{row.users.toLocaleString()}</td><td>{row.complete.toLocaleString()}</td>
                      <td>{filter && row.requiring_review ? <button type="button" className="text-link" onClick={() => openQueue('outstanding', filter)} aria-label={`Open users requiring review in ${row.label}`}>{row.requiring_review.toLocaleString()}</button> : row.requiring_review.toLocaleString()}</td>
                      <td><progress value={row.complete} max={row.users || 1} aria-label={`${row.complete} of ${row.users} users complete in ${row.label}`} /> {percent(row.complete, row.users)}</td>
                    </tr> })}</tbody>
                </DataTable>
                <p className="ui-description">A user in several groups counts in each group; {(data.groups.distinct_users ?? 0).toLocaleString()} distinct users in total. Users without a value are listed in their own row.{groupBy === 'department' || groupBy === 'site' ? ' Department and site have no Work Queue filter, so their rows do not open the Work Queue.' : ''}</p>
              </>}
          </section>
        </>}
      </SodFilters>
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
      <p className="ui-description" data-testid="account-review-scope">Scope: every SAP account you can access. Filters on the Account Review page do not apply here; Account Review shows its own filtered counters.</p>
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
