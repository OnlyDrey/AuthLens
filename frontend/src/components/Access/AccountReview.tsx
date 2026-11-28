import { usePageSize } from '@/lib/pageSize'
import { TableRegion } from '@/components/Shared/TableRegion'
import { OpenInReviewsButton } from '@/components/Reviews/OpenInReviewsButton'
import {FunctionalGroupPills} from '@/components/Shared/FunctionalGroupPills'
import {ExactUsernameFilter} from '@/components/Shared/ExactUsernameFilter'
import {ConfigurableTable} from '@/components/Shared/ConfigurableTable'
import {useReviewerName} from '@/hooks/useReviewerIdentity'
import { Dialog } from '@/components/Shared/Dialog'
import { type ReviewEvidence } from '@/components/Shared/ReviewFindings'
import { PageHeader, MetadataList } from '@/components/Shared/Presentation'
import { ClipboardCheck as PageIcon } from 'lucide-react'
import { Kpi } from '@/components/Shared/Kpi'
import { kpiTone } from '@/lib/kpiTone'
import { InfoTip } from '@/components/Shared/InfoTip'
import { StackedBar } from '@/components/Shared/Charts'
import { FilterLayout, FilterSection, PageToolbar, SortControl } from '@/components/Shared/FilterLayout'
import { Checkbox, FormField } from '@/components/Shared/Controls'
import { SearchInput } from '@/components/Shared/Controls'
import { Button } from '@/components/Shared/Button'
import { SavedFilters } from '@/components/Shared/SavedFilters'
import { useApplicationData } from '@/state/ApplicationData'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowRightLeft, ArrowUpRight, ClipboardCheck, ClipboardList, Download, History, Save, SearchX, UserMinus } from 'lucide-react'
import { apiRequest } from '@/api/client'
import { useHistoryValue, useViewHistory } from '@/hooks/useViewHistory'
import { AccountStatus } from '@/components/Shared/AccountStatus'
import { FilterChip } from '@/components/Shared/FilterChip'
import { SAPUserLink } from '@/components/Shared/SAPUserLink'
import { Select } from '@/components/Shared/Select'
import { MultiSelectFilter } from '@/components/Shared/MultiSelectFilter'
import { ClassificationPill, FunctionalGroupReview } from './FunctionalGroupPanel'
import type { ClassificationStatus } from '@/api/functionalGroups'
import { formatTimestamp } from '@/lib/dateFormat'
import { Filter, PageSizeControl, Pagination, QueryState, inputClass } from './Shared'
import { downloadFile } from '@/api/sod'
interface Decision {
  state: string
  reviewer: string
  rationale: string
  timestamp: string
  evidence_version: string
}
interface PositionChange {
  id: string
  open: boolean
  fields: ('department' | 'title')[]
  previous_department: string
  current_department: string
  previous_title: string
  current_title: string
  detected_at: string
  source_generation: string
  previous_imported_at?: string | null
  current_imported_at?: string | null
}
interface ManagerChange { id: string; open: boolean; previous_manager: string; current_manager: string; previous_manager_email: string; current_manager_email: string; detected_at: string }
interface Row {
  functional_group: { id: string; name: string; status: string } | null
  functional_groups?: { id: string; name: string; status: string }[]
  classification: { status: ClassificationStatus; revision: number; review: { change_id: string; reason: string; required_since: string } | null; confirmed_at: string | null }
  classification_review: boolean
  manager: { name: string; email: string; status: string } | null
  manager_change: ManagerChange | null
  username: string
  name: string
  groups: string[]
  sap_validity: string
  lock_status: string
  ad_status: string
  match_status: string
  findings: string[]
  unlicensed: boolean
  evidence_version: string
  decision: Decision | null
  stale: boolean
  review_state: string
  needs_review: boolean
  workflow_status: 'open' | 'completed'
  priority: 'High' | 'Normal' | 'None'
  position_change: PositionChange | null
  evidence?:ReviewEvidence
  history_count?:number
}
interface Results {
  items: Row[]
  total: number
  loaded: boolean
  directory_available: boolean
  data_revision: string
  summary: Record<string, number | null>
  finding_labels: Record<string, string>
  completed_hidden?: number
  review_states: string[]
  functional_group_options: { value: string; label: string }[]
  manager_options: { value: string; label: string; count: number }[]
}
const SORTS = [{ value: 'username', label: 'SAP username' }, { value: 'name', label: 'Employee' }, { value: 'sap_validity', label: 'SAP validity' }, { value: 'lock_status', label: 'SAP lock status' }, { value: 'ad_status', label: 'AD status' }, { value: 'review_state', label: 'Review state' }, { value: 'priority', label: 'Priority' }]
const matchLabel = (status: string) => ({matched:'Matched',duplicate_email:'Duplicate Email',missing_email:'Missing Email',ambiguous:'Ambiguous Match',unmatched:'Unmatched',disabled:'Disabled',unavailable:'Unavailable'} as Record<string,string>)[status] || status.replace(/_/g,' ').replace(/\b\w/g,c=>c.toUpperCase())
const changeText = (change: PositionChange) => [
  change.fields.includes('department') && `Department ${change.previous_department} → ${change.current_department}`,
  change.fields.includes('title') && `Job title ${change.previous_title} → ${change.current_title}`,
].filter(Boolean).join(' · ')

/** Review attention: each KPI applies its finding to the list. Review progress (completed and pending) is the separate panel beside it. */
const ATTENTION_TILES: [string, string, ReactNode, { finding: string }][] = [
  ['requiring_review', 'Accounts requiring review', <ClipboardList size={16} />, { finding: 'any' }],
  ['missing', 'Missing or ambiguous directory matches', <SearchX size={16} />, { finding: 'directory_match' }],
  ['position_changes', 'Position changes', <ArrowRightLeft size={16} />, { finding: 'position_change' }],
  ['outdated', 'Outdated reviews', <History size={16} />, { finding: 'stale' }],
]
/** The fifth attention KPI; like the others it occupies one grid cell, so the last cell on the right stays empty. */
const FINAL_TILE: [string, string, ReactNode, { finding: string }] = ['mismatch', 'AD disabled / SAP valid and unlocked', <UserMinus size={16} />, { finding: 'ad_disabled_open' }]
const FINDING_NAMES: Record<string, string> = { manager_change: 'Manager changes', functional_group_review: 'Functional Group reconfirmation', any: 'Accounts requiring review', matched: 'Reliably matched identities', directory_missing: 'Missing directory matches', directory_ambiguous: 'Ambiguous directory matches', reviewed: 'Completed reviews', pending: 'Pending reviews', position_change: 'Position changes', stale: 'Outdated reviews' }

/** Department and job title together, labelled so the two are never confused. Changed values are emphasized; unchanged ones are muted. */
function PositionCell({ department, title, changed }: { department?: string | null; title?: string | null; changed?: string[] }) {
  const line = (label: string, value: string | null | undefined, field: string) => (
    <p className="position-line" data-changed={changed?.includes(field) || undefined}><span className="position-label">{label}</span><span className="position-value">{value || '—'}</span></p>
  )
  return <div className="position-cell">{line('Department', department, 'department')}{line('Job title', title, 'title')}</div>
}

/** Account Review, and with `mode="positions"` the dedicated Position Changes page: the same rows, decisions, history and review dialog,
 *  filtered to detected position changes (no separate review records). */
export function AccountReview({ onUser, mode = 'review' }: { onUser: (name: string) => void; mode?: 'review' | 'positions' }) {
  const positions = mode === 'positions'
  const { loading: dataLoading } = useApplicationData()
  const [retainedFindings, setFindings] = useHistoryValue('reviewFindings')
  const findings = retainedFindings ?? []
  const {view,change}=useViewHistory()
  const retained=view.accountReviewFilters
  const [search, setSearch] = useState(retained?.search||''),
    [licenses, setLicenses] = useState<string[]>(retained?.licenses||[]),
    [states, setStates] = useState<string[]>(retained?.states||[]),
    [includeCompleted, setIncludeCompleted] = useState(false),
    [groupFilter, setGroupFilter] = useState<string[]>(retained?.groups||[]),
    [managerFilter, setManagerFilter] = useState<string[]>(retained?.managers||[]),
    [usernames, setUsernames] = useState<string[]>(retained?.usernames||[]),
    [sort, setSort] = useState(positions ? 'priority' : retained?.sort||'username'),
    [descending, setDescending] = useState(retained?.descending||false),
    [offset, setOffset] = useState(0),
    [positionStatus, setPositionStatus] = useState<'pending' | 'reviewed' | 'all'>('pending'),
    [positionType, setPositionType] = useState<'' | 'department' | 'title' | 'both'>('')
  useEffect(()=>{if(!positions)change({accountReviewFilters:{search,licenses,states,sort,descending,groups:groupFilter,managers:managerFilter,usernames}},true)},[positions,search,licenses,states,sort,descending,groupFilter,managerFilter,usernames,change])
  const [term, setTerm] = useState(''),
    [feedback, setFeedback] = useState(''),
    [busy, setBusy] = useState(false),
    [editing, setEditing] = useState<Row | null>(null),
    [actionError, setActionError] = useState(false)
  const returnUser = useRef(''),
    wasEditing = useRef(false)
  useEffect(() => {
    if (editing) {
      wasEditing.current = true

    }
  }, [editing])
  const [reviewer, setReviewer,reviewIdentity] = useReviewerName(),
    [rationale, setRationale] = useState(''),
    [decision, setDecision] = useState('Needs review')
  useEffect(() => {
    const timer = setTimeout(() => setTerm(search), 250)
    return () => clearTimeout(timer)
  }, [search])
  useEffect(
    () => setOffset(0),
    [term, findings.join('|'), licenses.join('|'), states.join('|'), groupFilter.join('|'), managerFilter.join('|'), usernames.join('|'), includeCompleted, sort, descending, positionStatus, positionType],
  )
  const params = new URLSearchParams({
    search: term,
    sort,
    descending: String(descending),
  })
  if (positions) {
    params.set('position_status', positionStatus)
    if (positionType) params.set('position_type', positionType)
  } else {
    findings.forEach(value => params.append('findings', value))
    licenses.forEach(value => params.append('license_groups', value))
    states.forEach(value => params.append('review_states', value))
    if (includeCompleted) params.set('include_completed', 'true')
  }
  groupFilter.forEach(value => params.append('functional_groups', value))
  managerFilter.forEach(value => params.append('managers', value))
  usernames.forEach(value=>params.append('usernames',value))
  const generation = useRef(0)
  useEffect(() => {
    generation.current++
    return () => {
      generation.current++
    }
  }, [params.toString()])
  const qc = useQueryClient()
  const [pageSize, storePageSize] = usePageSize(positions ? 'position-changes' : 'account-review') // TBL-03
  const setPageSize = (size: number) => { storePageSize(size); setOffset(0) }
  const result = useQuery({
    queryKey: ['account-review', params.toString(), offset, pageSize],
    queryFn: () =>
      apiRequest<Results>(
        `/api/account-review?${params}&offset=${offset}&limit=${pageSize}`,
      ),
  })
  const data = result.data
  const [historyOffset,setHistoryOffset]=useState(0)
  useEffect(()=>setHistoryOffset(0),[editing?.username])
  const history=useQuery({queryKey:['review-history',editing?.username,historyOffset],queryFn:()=>apiRequest<{items:Decision[];total:number}>(`/api/account-review/history/${encodeURIComponent(editing!.username)}?offset=${historyOffset}`),enabled:!!editing})
  const startReview = (row: Row) => {
    returnUser.current = row.username
    setEditing(row)
    setReviewer(row.decision?.reviewer || '')
    setRationale(row.decision?.rationale || '')
    setDecision(row.review_state)
  }
  /** Tiles toggle: a finding joins the finding filter (OR), the classification tile joins the classification filter (AND with findings). The first tile clears both. */
  const toggleTile = (target: { finding: string; license?: string }) => {
    if (target.license) setLicenses(list => list.includes(target.license!) ? list.filter(item => item !== target.license) : [...list, target.license!])
    else if (target.finding) setFindings(list => (list ?? []).includes(target.finding) ? (list ?? []).filter(item => item !== target.finding) : [...(list ?? []), target.finding])
    else { setFindings([]); setLicenses([]) }
  }
  /** Review progress (about one third) beside review attention (about two thirds); no account is counted twice in the progress. */
  const renderOverview = () => {
    if (!data) return null
    const { total, reviewed, pending } = data.summary
    const known = total != null && reviewed != null && pending != null
    const percent = known && total ? (reviewed! / total) * 100 : 0
    const activeFinding = (name: string) => findings.includes(name)
    const tile = ([key, label, icon, target]: [string, string, ReactNode, { finding: string }], extra = '') => {
      const value = data.summary[key]
      if (key === 'position_changes') return <Kpi key={key} className={extra} icon={icon} label={label} value={value?.toLocaleString() ?? 'Unavailable'} tone={kpiTone(key, value)} title="Opens the Position Changes page" onClick={() => change({ page: 'reviews', reviewsView: 'position-changes', user: '' })} />   // same geometry as the other tiles
      return <Kpi key={key} className={extra} icon={icon} label={label} value={value?.toLocaleString() ?? 'Unavailable'} tone={kpiTone(key, value)} active={activeFinding(target.finding)} onClick={() => toggleTile(target)} />
    }
    return (
      <div className="review-overview">
        <section aria-label="Account review progress" className="review-progress" data-primary="true">
          <div className="review-progress-head">
            <h2>Account review progress</h2>
            <InfoTip label="About account review progress">Completed and pending partition the selected population, so no account is counted twice. Finding and completion filters narrow the work table; outdated reviews count as pending until reviewed again.</InfoTip>
          </div>
          {known && <p className="progress-summary"><strong className="progress-summary-value">{percent.toFixed(1)}%</strong><span className="progress-summary-caption">{reviewed!.toLocaleString()} of {total!.toLocaleString()} SAP users reviewed</span></p>}
          {known ? <StackedBar inline label="Account review progress" total={total!} segments={[
              { key: 'completed', label: 'Completed reviews', value: reviewed!, tone: 'success', active: activeFinding('reviewed'), onOpen: () => toggleTile({ finding: 'reviewed' }) },
              { key: 'pending', label: 'Pending reviews', value: pending!, tone: 'neutral', active: activeFinding('pending'), title: 'Accounts without a current completed review, including outdated reviews', onOpen: () => toggleTile({ finding: 'pending' }) },
            ]} />
            : <p className="ui-description">Review progress is unavailable until the User Access data and the review annotations are loaded.</p>}
        </section>
        <section aria-label="Review attention" className="review-attention">
          <h2>Review attention</h2>
          <div className="review-kpis">
            {ATTENTION_TILES.filter(([key]) => key !== 'outdated' || data.summary.outdated != null).map((entry) => tile(entry))}
            {tile(FINAL_TILE)}
          </div>
        </section>
      </div>
    )
  }
  const findingOptions = ['any', 'matched', 'directory_missing', 'directory_ambiguous', 'reviewed', 'pending', 'position_change', 'manager_change', 'functional_group_review', ...Object.keys(data?.finding_labels || {}), 'stale']
  const findingLabel = (key: string) => FINDING_NAMES[key] || data?.finding_labels[key] || key
  const clearAll = () => { setOffset(0); setSearch(''); setTerm(''); setFindings([]); setLicenses([]); setStates([]); setGroupFilter([]); setManagerFilter([]); setUsernames([]); setIncludeCompleted(false); setSort('username'); setDescending(false) }
  const closeEditor=()=>{
    if(busy)return
    const dirty=editing&&(rationale!==(editing.decision?.rationale||'')||decision!==editing.review_state)
    if(dirty&&!window.confirm('Discard unsaved review changes?'))return
    setEditing(null)
  }
  useEffect(() => {
    if (editing || busy || result.isFetching || !wasEditing.current) return
    wasEditing.current = false
    const button = [
      ...document.querySelectorAll<HTMLButtonElement>('[data-review-user]'),
    ].find((el) => el.dataset.reviewUser === returnUser.current)
    if (button) button.focus()
    else
      document
        .querySelector<HTMLInputElement>('input[aria-label="Review finding"]')
        ?.focus()
  }, [editing, busy, result.isFetching])

  useEffect(() => {
    if (data && offset >= data.total && offset)
      setOffset(Math.max(0, Math.floor((data.total - 1) / 25) * 25))
  }, [data?.total, offset])
  const action = async (fn: () => Promise<void>) => {
    setBusy(true)
    setFeedback('')
    setActionError(false)
    try {
      await fn()
    } catch (e) {
      setActionError(true)
      setFeedback(e instanceof Error ? e.message : 'Review action failed.')
    } finally {
      setBusy(false)
    }
  }
  /** NAV-4: the review CSV is generated by the backend (GET /api/account-review/export) from the same query as this list, the implementation Reports
   *  uses too; its default columns and comma format are those of the earlier browser export. Position Changes exports its own report. */
  const exportCSV = () =>
    action(async () => {
      if (!data) return
      const started = generation.current
      const name = await downloadFile(positions ? '/api/account-review/positions/export' : '/api/account-review/export', { params: new URLSearchParams(params), namePattern: /^authlens-(account-review-review|position-changes)-\d{4}-\d{2}-\d{2}\.csv$/, isCurrent: () => generation.current === started })
      setFeedback(!name ? 'Export cancelled because the filters changed.' : positions ? `Position changes exported to ${name}.` : 'Review CSV exported.')
    })
  const editor = editing ? (
        <Dialog title={`Review account · ${editing.username}`} onClose={closeEditor}><section
          className="review-dialog"
          aria-label={`Review decision for ${editing.username}`}
        >
          <section aria-label="SAP identity" className="review-dialog-section"><h3>SAP identity</h3>
            <MetadataList items={[
              {label:'SAP username',value:<SAPUserLink reviewSupported={false} username={editing.username} copyLabel="username"/>},
              {label:'Employee',value:editing.name||'Name unavailable'},
              {label:'SAP user group',value:editing.groups.join(', ')||'Group unavailable'},
              {label:'Directory match',value:matchLabel(editing.match_status)},
            ]}/>
            <div className="ui-toolbar"><Button onClick={()=>{if(rationale!==(editing.decision?.rationale||'')||decision!==editing.review_state){if(!window.confirm('Discard unsaved review changes and investigate this user?'))return}setEditing(null);onUser(editing.username)}}><ArrowUpRight size={16} aria-hidden="true"/>Investigate SAP user</Button></div>
          </section>
          {editing.classification.status !== 'Unassigned' && <FunctionalGroupReview username={editing.username}
            department={editing.position_change?.fields.includes('department') ? { previous: editing.position_change.previous_department, current: editing.position_change.current_department } : undefined}
            title={editing.position_change?.fields.includes('title') ? { previous: editing.position_change.previous_title, current: editing.position_change.current_title } : undefined}
            manager={editing.manager_change ? { previous: editing.manager_change.previous_manager, current: editing.manager_change.current_manager } : null}
            detectedAt={editing.position_change?.detected_at ?? editing.manager_change?.detected_at} />}
          {editing.position_change&&<section aria-label="Position change that triggered this review" className="review-dialog-section review-dialog-trigger"><h3>Organizational position changes</h3>
            <ConfigurableTable aria-label="Position change comparison" className="review-change-table"><thead><tr><th scope="col"><span className="sr-only">Field</span></th><th scope="col" data-wrap="text">Previous (last known)</th><th scope="col" data-wrap="text">Current</th></tr></thead><tbody>
              <tr><th scope="row">Department</th><td>{editing.position_change.previous_department||'—'}</td><td data-changed={editing.position_change.fields.includes('department')||undefined}>{editing.position_change.current_department||'—'}</td></tr>
              <tr><th scope="row">Job title</th><td>{editing.position_change.previous_title||'—'}</td><td data-changed={editing.position_change.fields.includes('title')||undefined}>{editing.position_change.current_title||'—'}</td></tr>
              <tr><th scope="row">Employee Directory snapshot</th><td>{editing.position_change.previous_imported_at?`Imported ${formatTimestamp(editing.position_change.previous_imported_at)}`:'Import time not recorded'}</td><td>First detected {formatTimestamp(editing.position_change.detected_at)}</td></tr>
            </tbody></ConfigurableTable>
            <p className="ui-description">The organizational change itself happened at an unknown time between the two imports. A position change prompts a review; it is not evidence that access is inappropriate.</p></section>}
          {actionError&&feedback&&<p role="alert">{feedback}</p>}
          <section aria-label="Review decision" className="review-dialog-section"><h3>Review decision</h3>
          <div className="review-dialog-fields">
          <Filter label="Reviewer">
            <input
              className={inputClass}
              disabled={busy}
              maxLength={120}
              readOnly
              value={reviewer}
              onChange={(e) => setReviewer(e.target.value)}
            />
          </Filter>
          <Filter label="Decision">
            <Select
              className={inputClass}
              aria-label="Decision"
              disabled={busy}
              value={decision}
              onChange={(e) => setDecision(e.target.value)}
            >
              {data?.review_states.map((s) => (
                <option key={s}>{s}</option>
              ))}
            </Select>
          </Filter>
          </div>
          <Filter label="Rationale">
            <textarea
              className={inputClass}
              disabled={busy}
              maxLength={2000}
              rows={4}
              placeholder="Why this decision follows from the current evidence"
              value={rationale}
              onChange={(e) => setRationale(e.target.value)}
            />
          </Filter>
          <p className="text-xs">
            Review decisions are application annotations. Identity provenance is recorded; Desktop profiles are
            self-declared, not an authenticated approval, and nothing is sent to
            or changed in SAP or Active Directory.
          </p>
          <div className="review-decision-actions"><Button
            variant="primary"
            disabled={!reviewIdentity.canReview || reviewIdentity.loading || busy || !reviewer.trim() || !rationale.trim()}
            onClick={() =>
              void action(async () => {
                await apiRequest(
                  `/api/account-review/decision/${encodeURIComponent(editing.username)}`,
                  'POST',
                  {
                    state: decision,
                    reviewer: reviewer.trim(),
                    rationale: rationale.trim(),
                    evidence_version: editing.evidence_version,
                    expected_decision: editing.decision?.timestamp ?? '',
                  },
                )
                await qc.invalidateQueries({
                  predicate: (q) =>
                    ['account-review', 'review-history', 'dashboard'].includes(
                      String(q.queryKey[0]),
                    ),
                })
                setEditing(null)
                setFeedback('Review decision saved locally.')
              })
            }
          >
            <Save size={16} />
            Save review decision
          </Button>
          <Button
            className="settings-secondary-button"
            disabled={busy}
            onClick={closeEditor}
          >
            Cancel review changes
          </Button></div>
          </section>
          <section aria-label="Review history" className="review-dialog-section"><h3>Previous decisions</h3>{history.isError&&<p role="alert">Review history could not be loaded. Existing annotations are retained.</p>}{history.isLoading&&<p role="status">Loading review history…</p>}{history.data&&!history.data.total&&<p>No previous decisions recorded.</p>}{history.data?.items.map((event,index)=><article key={`${event.timestamp}-${index}`} className="review-history-entry"><div><strong>{event.state}</strong><span>{event.reviewer} · {formatTimestamp(event.timestamp)}</span></div><p>{event.rationale}</p></article>)}<Pagination label="Review history pages" offset={historyOffset} total={history.data?.total||0} limit={25} onChange={setHistoryOffset}/></section>
        </section></Dialog>
  ) : null
  if (positions) {
    const summary = data?.summary
    const value = (key: string) => (summary?.[key] ?? null)
    const show = (status: 'pending' | 'reviewed' | 'all', type: '' | 'department' | 'title' | 'both') => { setPositionStatus(status); setPositionType(type) }
    const changeType = (change: PositionChange) => change.fields.length === 2 ? 'Department and job title' : change.fields[0] === 'department' ? 'Department' : 'Job title'
    const active = (search ? 1 : 0) + (positionStatus !== 'pending' ? 1 : 0) + (positionType ? 1 : 0) + groupFilter.length + managerFilter.length + usernames.length
    const clearPositions = () => { setSearch(''); setTerm(''); show('pending', ''); setGroupFilter([]); setManagerFilter([]); setUsernames([]) }
    return (
      <section aria-label="Position Changes" className="space-y-4">
        <PageHeader title="Position Changes" level={2} icon={<ArrowRightLeft size={22} aria-hidden="true" />} titleAction={<InfoTip label="About position changes">
          Department or job title differs between two Employee Directory imports. The previous values are the last known before the replacement and the current values were first seen when it was published; the real date of the change is unknown. A position change is a prompt to review, not evidence that access is inappropriate. Reviews use the Account Review decision and history.
        </InfoTip>} />
        {data && !data.directory_available && <p role="status">Directory enrichment unavailable. Enable and import Employee Directory to detect position changes.</p>}
        {summary && <section className="sod-tiles" aria-label="Position change key figures">
          <Kpi icon={<ArrowRightLeft size={16} />} label="Position changes" value={value('position_total')?.toLocaleString() ?? 'Unavailable'} active={positionStatus === 'all' && !positionType} onClick={() => show('all', '')} />
          <Kpi label="Department changes" value={value('position_department')?.toLocaleString() ?? 'Unavailable'} active={positionStatus === 'all' && positionType === 'department'} onClick={() => show('all', 'department')} />
          <Kpi label="Job title changes" value={value('position_title')?.toLocaleString() ?? 'Unavailable'} active={positionStatus === 'all' && positionType === 'title'} onClick={() => show('all', 'title')} />
          <Kpi label="Pending review" value={value('position_changes')?.toLocaleString() ?? 'Unavailable'} tone={kpiTone('position_changes', value('position_changes'))} active={positionStatus === 'pending' && !positionType} onClick={() => show('pending', '')} />
        </section>}
        {summary && <p className="ui-description">Department and job title changes overlap: {(value('position_both') ?? 0).toLocaleString()} changed both. Figures cover the selected population; status and change type narrow the table.</p>}
        <FilterLayout workspace="position-changes" label="Filters" activeCount={active} onClear={clearPositions} clearDisabled={!active}
          toolbar={<PageToolbar><SortControl label="Sort position changes" value={sort} options={SORTS} descending={descending} onChange={setSort} onDescending={setDescending} />
            <Button className="settings-secondary-button" disabled={busy || !data?.loaded || !data?.directory_available} onClick={() => void exportCSV()}><Download size={16} />Export position changes CSV</Button></PageToolbar>}
          sidebar={<div className="grid min-w-0 gap-3" role="search" aria-label="Position change filters">
            <FilterSection title="Search">
              <SearchInput className={inputClass} aria-label="Search position changes" placeholder="SAP username or employee" value={search} onChange={(e) => setSearch(e.target.value)} onClear={() => setSearch('')} />
            </FilterSection>
            
            <FilterSection title="Population">
              <ExactUsernameFilter values={usernames} onChange={setUsernames} max={500} />
            </FilterSection>
            <FilterSection title="Organization">
              <FormField label="Functional Group">
                <MultiSelectFilter label="Functional Group" values={groupFilter} options={(data?.functional_group_options || []).map(o => o.value)} optionLabel={item => data?.functional_group_options.find(o => o.value === item)?.label ?? item} onChange={setGroupFilter} placeholder="All Functional Groups" />
              </FormField>
              <FormField label="Manager">
                <MultiSelectFilter label="Manager" values={managerFilter} options={(data?.manager_options || []).map(o => o.value)} optionLabel={item => { const o = data?.manager_options.find(entry => entry.value === item); return o ? `${o.label} (${o.count})` : item }} onChange={setManagerFilter} placeholder="All managers" />
              </FormField>
            </FilterSection>
            <FilterSection title="Change">
              <FormField label="Change type">
                <Select value={positionType} onChange={(event) => setPositionType(event.target.value as typeof positionType)}>
                  <option value="">All</option><option value="department">Department</option><option value="title">Job title</option><option value="both">Department and job title</option>
                </Select>
              </FormField>
              <FormField label="Review status">
                <Select value={positionStatus} onChange={(event) => setPositionStatus(event.target.value as typeof positionStatus)}>
                  <option value="pending">Pending review</option><option value="reviewed">Reviewed</option><option value="all">All</option>
                </Select>
              </FormField>
            </FilterSection>
          </div>}>
          {result.isError ? <p role="alert">Position changes could not be loaded.</p> : !data ? <p role="status">Loading position changes…</p> : !data.items.length
            ? <p role="status" className="ui-description">{positionStatus === 'pending' && !positionType && !active ? 'No position change is waiting for review.' : 'No position changes match the selected filters.'}</p>
            : <>
              <TableRegion className="access-table" role="region" aria-label="Position change review queue" tabIndex={0} toolbar={<PageSizeControl label="Position change pages" limit={pageSize} onPageSize={setPageSize} />}>
                <ConfigurableTable aria-label="Position changes">
                  <thead><tr><th>SAP username</th><th>Employee</th><th>Change type</th><th data-wrap="text">Previous position</th><th data-wrap="text">Current position</th><th>Priority</th><th>Review status</th><th className="col-actions"><span className="sr-only">Review action</span></th></tr></thead>
                  <tbody>
                    {data.items.map((row) => {
                      const change = row.position_change as PositionChange
                      return (
                        <tr key={row.username}>
                          <td><SAPUserLink username={row.username} copyLabel="username" onOpen={() => onUser(row.username)} /></td>
                          <td>{row.name || 'Unknown'}</td>
                          <td>{changeType(change)}</td>
                          <td><PositionCell department={change.previous_department} title={change.previous_title} /></td>
                          <td><PositionCell department={change.current_department} title={change.current_title} changed={change.fields} /></td>
                          <td><span className={`evidence-badge ${row.priority === 'High' ? 'evidence-warning' : ''}`.trim()}>{row.priority}</span></td>
                          <td>{change.open ? 'Pending review' : 'Reviewed'}</td>
                          <td className="col-actions"><Button size="compact" className="settings-secondary-button" disabled={busy} onClick={() => startReview(row)} aria-label={`Review position change for ${row.username}`}><ClipboardCheck size={14} aria-hidden="true" />Review</Button></td>
                        </tr>
                      )
                    })}
                  </tbody>
                </ConfigurableTable>
              </TableRegion>
              <Pagination offset={offset} total={data.total} limit={pageSize} alwaysShow onChange={setOffset} label="Position change pages" />
            </>}
        </FilterLayout>
        {editor}
      </section>
    )
  }
  return (
    <section aria-label="Account Review" className="space-y-4">
      <PageHeader title="Account Review" level={2} icon={<PageIcon size={22} aria-hidden="true"/>} titleAction={<InfoTip label="About Account Review">Investigation evidence only. No SAP accounts are modified. Configured unlicensed groups do not prove license entitlement or savings.</InfoTip>}/>
      {data && (
        <>
          {renderOverview()}
          {!data.directory_available && (
            <p role="status">
              Directory enrichment unavailable. Enable and import Employee
              Directory to evaluate AD status and email matching; SAP-only
              review remains available.
            </p>
          )}
        </>
      )}
      <FilterLayout workspace="account-review" label="Filters" activeCount={(includeCompleted ? 1 : 0) + findings.length + licenses.length + states.length + groupFilter.length + managerFilter.length + (search ? 1 : 0)} onClear={clearAll} clearDisabled={!(includeCompleted || findings.length || licenses.length || states.length || groupFilter.length || managerFilter.length || search) && sort === 'username' && !descending}
        utility={<SavedFilters showClear={false} view="review" state={{search,findings,licenses,states,groups:groupFilter,managers:managerFilter,usernames,includeCompleted,sort,descending}} apply={s=>{if(Array.isArray(s.usernames))setUsernames(s.usernames);setIncludeCompleted(s.includeCompleted===true);if(Array.isArray(s.groups))setGroupFilter(s.groups.filter((item:string)=>typeof item==='string'));if(Array.isArray(s.managers))setManagerFilter(s.managers.filter((item:string)=>typeof item==='string'));if(typeof s.search==='string')setSearch(s.search);if(Array.isArray(s.findings))setFindings(s.findings.filter(item=>findingOptions.includes(item)));if(Array.isArray(s.licenses))setLicenses(s.licenses.filter(item=>['classified','exclude'].includes(item)));if(Array.isArray(s.states))setStates(s.states.filter(item=>(data?.review_states||[]).includes(item)));if(['username','name','sap_validity','lock_status','ad_status','review_state'].includes(String(s.sort)))setSort(String(s.sort));if(typeof s.descending==='boolean')setDescending(s.descending)}} clear={()=>{setSearch('');setFindings([]);setLicenses([]);setStates([]);setSort('username');setDescending(false)}}/>}
        toolbar={<PageToolbar>
          <SortControl label="Sort account reviews" value={sort} options={SORTS} descending={descending} onChange={setSort} onDescending={setDescending} />
          <Button className="settings-secondary-button" disabled={busy || !data?.loaded} onClick={() => void exportCSV()}>
            <Download size={16} />
            Export review CSV
          </Button>
          <OpenInReviewsButton scope={{ functional_groups: groupFilter, managers: managerFilter, usernames }} label="Open access reviews" />
        </PageToolbar>}
        sidebar={<div className="grid min-w-0 gap-3" role="search" aria-label="Review filters">
          <FilterSection title="Search">
            <SearchInput className={inputClass} aria-label="Search account reviews" placeholder="Search" value={search} onChange={(e) => setSearch(e.target.value)} onClear={() => setSearch('')} />
          </FilterSection>
          
          <FilterSection title="Population">
            <p className="ui-description">Progress and tiles cover the selected population, including completed reviews. Finding, classification, decision and completion filters narrow the work table.</p>
            <ExactUsernameFilter values={usernames} onChange={setUsernames} max={500}/>
          </FilterSection>
          <FilterSection title="Organization">
            <FormField label="Functional Group">
              <MultiSelectFilter label="Functional Group" values={groupFilter} options={(data?.functional_group_options || []).map(o => o.value)} optionLabel={value => data?.functional_group_options.find(o => o.value === value)?.label ?? value} onChange={setGroupFilter} placeholder="All Functional Groups" />
            </FormField>
            <FormField label="Manager">
              <MultiSelectFilter label="Manager" values={managerFilter} options={(data?.manager_options || []).map(o => o.value)} optionLabel={value => { const o = data?.manager_options.find(item => item.value === value); return o ? `${o.label} (${o.count})` : value }} onChange={setManagerFilter} placeholder="All managers" />
            </FormField>
          </FilterSection>
          <FilterSection title="Review">
            <FormField label="Review finding">
              <MultiSelectFilter label="Review finding" values={findings} options={findingOptions} optionLabel={findingLabel} onChange={setFindings} placeholder="All accounts · type to search" />
            </FormField>
            <FormField label="License group classification">
              <MultiSelectFilter label="License group classification" values={licenses} options={['classified', 'exclude']} optionLabel={value => value === 'classified' ? 'Configured unlicensed groups' : 'Exclude unlicensed groups'} onChange={setLicenses} placeholder="All classifications" />
            </FormField>
            <FormField label="Review decision">
              <MultiSelectFilter label="Review decision" values={states} options={data?.review_states || []} onChange={setStates} placeholder="All decisions" />
            </FormField>
            <div data-filter-active={includeCompleted ? 'true' : undefined}>
              <Checkbox checked={includeCompleted} onChange={event => setIncludeCompleted(event.target.checked)}>Include completed reviews</Checkbox>
            </div>
          </FilterSection>
        </div>}>
      {(findings.length > 0 || licenses.length > 0 || states.length > 0 || groupFilter.length > 0 || managerFilter.length > 0 || usernames.length > 0 || search) && <div className="active-filter-row" aria-label="Active review filters">
        {findings.map(value => <FilterChip key={`finding-${value}`} removeLabel={`Remove review finding ${findingLabel(value)}`} onRemove={() => setFindings(findings.filter(item => item !== value))}>Finding: {findingLabel(value)}</FilterChip>)}
        {licenses.map(value => <FilterChip key={`license-${value}`} removeLabel={`Remove license classification ${value === 'classified' ? 'Configured unlicensed groups' : 'Exclude unlicensed groups'}`} onRemove={() => setLicenses(licenses.filter(item => item !== value))}>{value === 'classified' ? 'Configured unlicensed groups' : 'Excluding unlicensed groups'}</FilterChip>)}
        {states.map(value => <FilterChip key={`state-${value}`} removeLabel={`Remove review decision ${value}`} onRemove={() => setStates(states.filter(item => item !== value))}>Decision: {value}</FilterChip>)}
        {groupFilter.map(value => <FilterChip key={`group-${value}`} removeLabel={`Remove Functional Group ${data?.functional_group_options.find(o => o.value === value)?.label ?? value}`} onRemove={() => setGroupFilter(groupFilter.filter(item => item !== value))}>Functional Group: {data?.functional_group_options.find(o => o.value === value)?.label ?? value}</FilterChip>)}
        {managerFilter.map(value => <FilterChip key={`manager-${value}`} removeLabel={`Remove manager ${data?.manager_options.find(o => o.value === value)?.label ?? value}`} onRemove={() => setManagerFilter(managerFilter.filter(item => item !== value))}>Manager: {data?.manager_options.find(o => o.value === value)?.label ?? value}</FilterChip>)}
        {search && <FilterChip removeLabel="Remove account search filter" onRemove={() => { setSearch(''); setTerm('') }}>Search: {search}</FilterChip>}
        {!!usernames.length&&<FilterChip removeLabel="Remove exact username filter" onRemove={()=>setUsernames([])}>Exact usernames: {usernames.length}</FilterChip>}
      </div>}
      <div className="results-toolbar ui-toolbar"><strong>{data?.total.toLocaleString() ?? '…'} accounts</strong>{!!data?.completed_hidden && <span className="ui-description" role="status"> · {data.completed_hidden.toLocaleString()} completed review{data.completed_hidden === 1 ? '' : 's'} hidden · <Button size="compact" variant="ghost" onClick={() => setIncludeCompleted(true)}>Show reviewed</Button></span>}</div>
      <QueryState
        loading={result.isLoading || (dataLoading && !data?.loaded)}
        error={result.error}
      />
      {feedback && (
        <p
          role={actionError ? 'alert' : 'status'}
          className={actionError ? 'text-[var(--error)]' : undefined}
        >
          {feedback}
        </p>
      )}
      {data && !data.loaded && !dataLoading && (
        <p>No User Access CSV loaded. Configure the source in Settings.</p>
      )}
      {data?.loaded && (
        <>
          <TableRegion
            className="access-table review-table"
            tabIndex={0}
            role="region"
            toolbar={<PageSizeControl label="Account review pages" limit={pageSize} onPageSize={setPageSize} />}
            aria-label="Account review results"
          >
            <ConfigurableTable aria-label="Account Review results">
              <thead>
                <tr>
                  {([
                    'SAP username',
                    ['Employee', 'Name'],
                    ['SAP user group', 'SAP User Group'],
                    'Functional Group',
                    'Manager',
                    'SAP validity',
                    'SAP lock status',
                    'AD account status',
                    'Directory match',
                    'Review classification & evidence',
                    'Decision',
                  ] as (string | [string, string])[]).map((h) => {
                    const [label, key] = typeof h === 'string' ? [h, h] : h // TBL-04 label; the earlier header stays the column key
                    return <th key={key} data-column-key={key === label ? undefined : key} data-wrap={key === 'Review classification & evidence' ? 'text' : undefined}>{label}</th>
                  })}
                </tr>
              </thead>
              <tbody>
                {data.items.map((row) => (
                  <tr key={row.username}>
                    <td>
                      <SAPUserLink
                        username={row.username}
                        copyLabel="username"
                        onOpen={() => onUser(row.username)}
                        openLabel={row.username}
                        openButtonProps={{
                          disabled: busy,
                          'data-user': row.username,
                        }}
                      />
                    </td>
                    <td>{row.name || 'Unknown'}</td>
                    <td>{row.groups.join(', ') || 'Unknown'}</td>
                    <td>
                      <FunctionalGroupPills groups={row.functional_groups?.length?row.functional_groups:row.functional_group?[row.functional_group]:[]} username={row.username}/>
                      {row.classification.status === 'Needs review' && <> <ClassificationPill status="Needs review" /></>}

                    </td>
                    <td>{row.manager?.name || <span className="text-muted">Not recorded</span>}</td>
                    <td>
                      <AccountStatus value={row.sap_validity} />
                      {row.evidence&&row.evidence.account_total>row.evidence.accounts.length&&<small>More source intervals in User Details</small>}
                    </td>
                    <td>
                      <AccountStatus kind="lock" value={row.lock_status} />
                    </td>
                    <td>
                      <AccountStatus kind="ad" value={row.ad_status} />
                    </td>
                    <td>{matchLabel(row.match_status)}</td>
                    <td>
                      {row.findings.map((f) => (
                        <p key={f}>{data.finding_labels[f]}</p>
                      ))}
                      {row.unlicensed && (
                        <p className="evidence-badge evidence-neutral">
                          Configured unlicensed group
                        </p>
                      )}
                      {row.position_change && <p><strong>Position change{row.position_change.open ? '' : ' (reviewed)'}:</strong> {changeText(row.position_change)}</p>}
                      {row.manager_change && <p><strong>Manager change{row.manager_change.open ? '' : ' (reviewed)'}:</strong> {row.manager_change.previous_manager || 'unknown'} → {row.manager_change.current_manager || 'unknown'}</p>}
                      {row.classification_review && <p><strong>Functional Group:</strong> reconfirmation required</p>}
                      {!row.findings.length && !row.position_change && !row.manager_change && !row.classification_review && <p>No automated findings</p>}
                    </td>
                    <td>
                      <Button
                        className="settings-secondary-button"
                        disabled={busy}
                        data-review-user={row.username}
                        onClick={() => startReview(row)}
                      >
                        {row.review_state}
                      </Button>
                      {row.workflow_status === 'completed' && <p className="ui-description">Review completed</p>}
                      {row.stale && (
                        <p className="text-[var(--warning)]">
                          Evidence changed — review again
                        </p>
                      )}
                      {row.decision && (
                        <small>
                          {row.decision.reviewer} ·{' '}
                          {formatTimestamp(row.decision.timestamp)}
                        </small>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </ConfigurableTable>
          </TableRegion>
          {!data.items.length && <p>No accounts match these review filters.</p>}
          <Pagination
            offset={offset}
            total={data.total}
            limit={pageSize}
            alwaysShow
            onChange={setOffset}
            label="Account review pages"
          />
        </>
      )}
      </FilterLayout>
      {editor}
    </section>
  )
}
