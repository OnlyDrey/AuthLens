import { reportColumnLabel } from '@/lib/fieldLabels'
import { useEffect, useState, type ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Download, Eye, FileText, Settings2 } from 'lucide-react'
import { useHistoryValue, useViewHistory, reportsHref, type ReportsView } from '@/hooks/useViewHistory'
import { REPORTS_NAVIGATION } from '@/lib/navigationItems'
import { SecondaryNavigation } from '@/components/Shared/Navigation'
import { Card, DataTable, EmptyState, LoadingState, PageHeader, SectionHeader, StatusBadge, Toolbar } from '@/components/Shared/Presentation'
import { Button } from '@/components/Shared/Button'
import { Checkbox, FormField, Input } from '@/components/Shared/Controls'
import { Select } from '@/components/Shared/Select'
import { useReportAvailability, type ReportDefinition } from '@/api/reports'
import { apiRequest } from '@/api/client'
import { downloadFile, sod } from '@/api/sod'
import { announceExport } from '@/lib/exportNotice'
import { ContextBar, useSodContext, useSodFilters } from '@/components/Sod/SodShared'
import { SodReports } from '@/components/Sod/SodReports'
import { SodQueueExportDialog } from '@/components/Sod/SodQueueExport'

/** Any AuthLens export file name; the endpoints set the exact name. */
const REPORT_FILE = /^authlens-[A-Za-z0-9._-]+\.(csv|pdf|docx)$/
type Values = Record<string, string | boolean>
type Param = { key: string; label: string; kind: 'text' | 'select' | 'checkbox' | 'context'; options?: [string, string][]; required?: boolean; initial?: string | boolean; description?: string }
/** How a report is generated: its endpoint, its supported parameters (each sent only when set) and fixed query values. */
type Runner = { endpoint: string | ((values: Values) => string); params: Param[]; fixed?: Record<string, string> }

const STATUS: [string, string][] = [['active', 'Currently valid'], ['all', 'All validity states'], ['expired', 'Expired'], ['future', 'Future']]
const RELEASE_TYPE: [string, string][] = [['', 'PR and PO'], ['PR', 'PR'], ['PO', 'PO']]
const CONTEXT: Param = { key: 'context', label: 'Review context', kind: 'context', description: 'Current evidence, or a frozen review period where the report supports it.' }

/** NAV-4: parameters per report. Every report calls the existing export endpoint, so its filter semantics and authorization are those of its source page. */
const RUNNERS: Record<string, Runner> = {
  follow_up_actions: { endpoint: '/api/sod/reviews/actions/export', params: [] },
  account_review: { endpoint: '/api/account-review/export', params: [
    { key: 'search', label: 'SAP user search', kind: 'text' },
    { key: 'review_states', label: 'Review decision', kind: 'select', options: [['', 'All decisions'], ['Needs review', 'Needs review'], ['Investigating', 'Investigating'], ['Approved for deactivation', 'Approved for deactivation'], ['No action required', 'No action required']] },
    { key: 'include_completed', label: 'Include completed reviews', kind: 'checkbox', initial: false },
  ] },
  position_changes: { endpoint: '/api/account-review/positions/export', params: [
    { key: 'position_status', label: 'Review status', kind: 'select', required: true, initial: 'pending', options: [['pending', 'Pending review'], ['reviewed', 'Reviewed'], ['all', 'All position changes']] },
    { key: 'position_type', label: 'Changed field', kind: 'select', options: [['', 'Department or job title'], ['department', 'Department'], ['title', 'Job title'], ['both', 'Both']] },
  ] },
  user_directory: { endpoint: '/api/access/exports/users', params: [
    { key: 'search', label: 'SAP user search', kind: 'text' }, { key: 'role', label: 'Role', kind: 'text' }, { key: 'tcodes', label: 'Transaction code', kind: 'text' },
    { key: 'status', label: 'Assignment validity', kind: 'select', initial: 'active', options: STATUS },
    { key: 'export_scope', label: 'Assignment rows', kind: 'select', initial: 'matching', options: [['matching', 'Matching role assignments'], ['all_assignments', 'All assignments for matching users']],
      description: 'Matching: only assignments within the role filter. All: every assignment of the users the filters match.' },
  ] },
  compare_users: { endpoint: '/api/user-comparison/export', params: [
    { key: 'user_a', label: 'User A', kind: 'text', required: true }, { key: 'user_b', label: 'User B', kind: 'text', required: true },
    { key: 'kind', label: 'Compare', kind: 'select', initial: 'roles', options: [['roles', 'Roles'], ['transactions', 'Transactions']] },
    { key: 'validity', label: 'Assignment validity', kind: 'select', initial: 'active', options: STATUS },
    { key: 'difference', label: 'Difference', kind: 'select', options: [['', 'All'], ['shared', 'Shared'], ['a', 'Only User A'], ['b', 'Only User B']] },
  ] },
  release_roles: { endpoint: '/api/access/exports/release-roles', params: [{ key: 'document_type', label: 'PR/PO', kind: 'select', options: RELEASE_TYPE }, { key: 'status', label: 'Assignment validity', kind: 'select', initial: 'active', options: STATUS }] },
  release_assignments: { endpoint: '/api/access/exports/releases', params: [{ key: 'document_type', label: 'PR/PO', kind: 'select', options: RELEASE_TYPE }, { key: 'status', label: 'Assignment validity', kind: 'select', initial: 'active', options: STATUS }] },
  risk_matrix: { endpoint: '/api/sod/explorer/user_risk/export', params: [CONTEXT] },
  activity_matrix: { endpoint: '/api/sod/explorer/user_activity/export', params: [CONTEXT] },
  heatmap: { endpoint: values => `/api/sod/matrix/${values.heatmap === 'activity' ? 'activity' : 'risk'}/group-export`, params: [{ key: 'heatmap', label: 'Heatmap', kind: 'select', initial: 'risk', options: [['risk', 'Risks'], ['activity', 'Activities']] }, CONTEXT], fixed: { group_by: 'group' } },
  explorer: { endpoint: values => `/api/sod/explorer/${values.table === 'lookup' ? 'lookup' : 'access_list'}/export`, params: [{ key: 'table', label: 'Access Explorer view', kind: 'select', initial: 'access_list', options: [['access_list', 'Assignments'], ['lookup', 'Roles']] }, CONTEXT] },
  analysis: { endpoint: '/api/sod/analysis/export', params: [] },
  remediation: { endpoint: '/api/sod/remediation/export', params: [CONTEXT] },
  ruleset: { endpoint: '/api/sod/catalogue/export', params: [] },
}
/** Reports that keep their own dedicated generator: the formal review and access removal reports (SodReports) and the Work Queue export dialog. */
/** Review period states with frozen evidence (SodScope.FrozenStates). */
const FROZEN = ['Approved', 'Closed', 'Approved / closed']
const DEDICATED = new Set(['formal_review', 'access_removal', 'work_queue', 'evidence_periods'])

/**
 * Reports module (NAV-1, NAV-4). Without a page in the route it opens the first report page the account may use (Review Reports when available),
 * and a page the account may not use resolves to an authorized one, so the navigation never leads to an empty or inaccessible destination. Report
 * generation reuses the existing export endpoints and report builders; nothing here stores generated files.
 */
export function ReportsWorkspace() {
  const [selected] = useHistoryValue('reportsView'), { change } = useViewHistory()
  const { pages, reports, loading } = useReportAvailability()
  const view: ReportsView | undefined = selected && pages.includes(selected) ? selected : pages[0]
  useEffect(() => { if (!loading && view && view !== selected) change({ reportsView: view }, true) }, [loading, view, selected, change])
  const onPage = reports.filter(report => report.page === view)
  return (
    <section className="sod-workspace grid min-w-0 gap-3" aria-label="Reports">
      <PageHeader title="Reports" icon={<FileText size={22} aria-hidden="true" />} />
      {loading ? <LoadingState /> : !view ? <EmptyState>No reports are available for this account with the current features and data.</EmptyState> : <>
        <SecondaryNavigation label="Report views" items={REPORTS_NAVIGATION.filter(item => pages.includes(item.value)).map(({ value, label, icon }) => ({ value, label, icon, href: reportsHref(value), active: view === value, onSelect: () => change({ reportsView: value }) }))} />
        {(view === 'sod' || view === 'evidence' || onPage.some(r => r.id === 'formal_review')) && <ContextBar />}
        {view === 'review' && onPage.some(r => r.id === 'formal_review' && r.available) && <SodReports />}
        {view === 'review' && onPage.some(r => r.id === 'work_queue' && r.available) && <WorkQueueReport report={onPage.find(r => r.id === 'work_queue')!} />}
        {view === 'evidence' ? <EvidencePage /> : onPage.filter(r => !DEDICATED.has(r.id)).map(report => <ReportCard key={report.id} report={report} />)}
      </>}
    </section>
  )
}

function ReportFrame({ report, children }: { report: ReportDefinition; children: ReactNode }) {
  return (
    <Card className="min-w-0" aria-label={`${report.title} report`}>
      <SectionHeader title={report.title} icon={<FileText size={18} aria-hidden="true" />}>
        <span className="ui-description">{report.formats.map(f => f.toUpperCase()).join(', ')}{report.contexts.includes('period') ? ' · current or frozen period' : ' · current data'}</span>
      </SectionHeader>
      <p className="ui-description">{report.description}</p>
      {report.available ? children : <p className="ui-description"><StatusBadge tone="neutral">Not available</StatusBadge> {report.reason}</p>}
    </Card>
  )
}

/** The Work Queue export keeps its existing configuration dialog (presets, columns, decision and type filters, preview), on the Work Queue population. */
function WorkQueueReport({ report }: { report: ReportDefinition }) {
  const [open, setOpen] = useState(false), [context] = useSodContext(), [filters] = useSodFilters('queue')
  return <ReportFrame report={report}>
    <p className="ui-description">Uses the current Work Queue filters and the review context above.</p>
    <Toolbar><Button variant="primary" onClick={() => setOpen(true)}><Settings2 size={16} aria-hidden="true" />Configure and export</Button></Toolbar>
    {open && <SodQueueExportDialog context={context} filters={filters} onClose={() => setOpen(false)} />}
  </ReportFrame>
}

/** A generic report form: the report's parameters, its columns and delimiter (configurable CSV reports), a preview of the matching rows and download. */
function ReportCard({ report }: { report: ReportDefinition }) {
  const runner = RUNNERS[report.id]
  const [context] = useSodContext()
  const periods = useQuery({ queryKey: ['sod-periods', false], queryFn: () => sod<{ items: { id: string; name: string; state: string }[] }>('/api/sod/periods'), enabled: !!runner?.params.some(p => p.kind === 'context') })
  const [values, setValues] = useState<Values>(() => Object.fromEntries((runner?.params || []).map(p => [p.key, p.kind === 'context' ? context : p.initial ?? (p.kind === 'checkbox' ? false : '')])))
  const [columns, setColumns] = useState<string[]>(() => (report.columns || []).filter(c => c.default).map(c => c.key))
  const [delimiter, setDelimiter] = useState('')
  const [preview, setPreview] = useState<{ columns: { key: string; label: string }[]; rows: string[][]; total_rows: number } | null>(null)
  const [busy, setBusy] = useState(false), [error, setError] = useState('')
  useEffect(() => setPreview(null), [values, columns, delimiter])
  if (!runner) return null
  const missing = runner.params.filter(p => p.required && !String(values[p.key] ?? '').trim()).map(p => p.label)
  const query = (extra: Record<string, string> = {}) => {
    const params = new URLSearchParams(runner.fixed || {})
    for (const p of runner.params) { const value = values[p.key]; if (p.key === 'heatmap' || p.key === 'table') continue; if (value === true) params.set(p.key, 'true'); else if (typeof value === 'string' && value.trim()) params.set(p.key, value.trim()) }
    if (report.columns) { columns.forEach(c => params.append('columns', c)); if (delimiter) params.set('delimiter', delimiter) }
    for (const [k, v] of Object.entries(extra)) params.set(k, v)
    return params
  }
  const endpoint = typeof runner.endpoint === 'function' ? runner.endpoint(values) : runner.endpoint
  const run = async (kind: 'preview' | 'download') => {
    setBusy(true); setError('')
    try {
      if (kind === 'preview') setPreview(await apiRequest(`${endpoint}?${query({ preview: 'true' })}`))
      else { const name = await downloadFile(endpoint, { params: query(), namePattern: REPORT_FILE }); announceExport({ kind: 'success', message: `Exported ${name}.` }) }
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'The report could not be generated.') }
    finally { setBusy(false) }
  }
  const toggle = (key: string) => setColumns(previous => previous.includes(key) ? previous.filter(c => c !== key) : (report.columns || []).map(c => c.key).filter(c => c === key || previous.includes(c)))
  return <ReportFrame report={report}>
    {runner.params.length > 0 && <div className="grid gap-3 sm:grid-cols-2">{runner.params.map(p => p.kind === 'checkbox'
      ? <Checkbox key={p.key} checked={values[p.key] === true} onChange={event => setValues({ ...values, [p.key]: event.target.checked })}>{p.label}</Checkbox>
      : <FormField key={p.key} label={p.label} description={p.description}>{p.kind === 'text'
        ? <Input value={String(values[p.key] ?? '')} onChange={event => setValues({ ...values, [p.key]: event.target.value })} />
        : <Select value={String(values[p.key] ?? '')} onChange={event => setValues({ ...values, [p.key]: event.target.value })}>
          {(p.kind === 'context' ? [['current', 'Current evidence'] as [string, string], ...(periods.data?.items || []).filter(() => report.contexts.includes('period')).map(item => [item.id, `${item.name} · ${item.state}`] as [string, string])] : p.options || []).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </Select>}</FormField>)}</div>}
    {report.columns && <fieldset className="min-w-0"><legend className="mb-1 text-sm font-semibold">Columns</legend>
      <div className="flex flex-wrap gap-x-4 gap-y-1">{report.columns.map(c => <Checkbox key={c.key} checked={columns.includes(c.key)} disabled={c.required} onChange={() => toggle(c.key)}>{reportColumnLabel(c.key, c.label)}{c.required ? ' (required)' : ''}</Checkbox>)}</div>
    </fieldset>}
    {report.columns && <FormField label="Delimiter"><Select value={delimiter} onChange={event => setDelimiter(event.target.value)}><option value="">Report default</option><option value="semicolon">Semicolon (;)</option><option value="comma">Comma (,)</option></Select></FormField>}
    {missing.length > 0 && <p className="ui-description">Required: {missing.join(', ')}.</p>}
    {error && <p role="alert">{error}</p>}
    <Toolbar>
      {report.columns && <Button disabled={busy || missing.length > 0 || columns.length === 0} onClick={() => void run('preview')}><Eye size={16} aria-hidden="true" />Preview</Button>}
      <Button variant="primary" loading={busy} disabled={missing.length > 0 || (!!report.columns && columns.length === 0)} onClick={() => void run('download')}><Download size={16} aria-hidden="true" />Generate {report.formats[0]?.toUpperCase() || 'CSV'}</Button>
    </Toolbar>
    {preview && <>
      <p role="status">{preview.total_rows.toLocaleString()} {preview.total_rows === 1 ? 'row' : 'rows'} match{preview.total_rows > preview.rows.length ? `; the first ${preview.rows.length} are shown` : ''}.</p>
      {preview.rows.length > 0 && <DataTable caption={`${report.title} preview`} regionLabel={`${report.title} preview`} density="compact">
        <thead><tr>{preview.columns.map(c => <th key={c.key} title={`CSV header: ${c.label}`}>{reportColumnLabel(c.key, c.label)}</th>)}</tr></thead>
        <tbody>{preview.rows.map((row, index) => <tr key={index}>{row.map((cell, i) => <td key={i}>{cell}</td>)}</tr>)}</tbody>
      </DataTable>}
    </>}
  </ReportFrame>
}

/** Evidence: frozen review periods and what can be regenerated from them. Generated documents are not stored; nothing here implies an archive. */
function EvidencePage() {
  const periods = useQuery({ queryKey: ['sod-periods', false], queryFn: () => sod<{ items: { id: string; name: string; state: string; snapshot?: string }[] }>('/api/sod/periods') })
  const { change } = useViewHistory()
  const items = periods.data?.items || []
  return <Card aria-label="Review evidence">
    <SectionHeader title="Review periods and frozen evidence" icon={<FileText size={18} aria-hidden="true" />} />
    <p className="ui-description">A review period freezes its evidence when it is approved; the formal review and access removal reports are regenerated from that frozen model and carry its checksum. Reports are generated on request; AuthLens does not keep copies of generated files.</p>
    {periods.isLoading ? <LoadingState /> : !items.length ? <EmptyState>No review periods exist yet.</EmptyState> : <DataTable caption="Review periods" density="compact">
      <thead><tr><th>Review period</th><th>State</th><th>Evidence</th><th>Integrity checksum</th></tr></thead>
      <tbody>{items.map(item => { const frozen = FROZEN.includes(item.state) && !!item.snapshot; return <tr key={item.id}><td>{item.name}</td><td>{item.state}</td><td>{frozen ? 'Frozen snapshot' : 'Not frozen (current evidence)'}</td><td>{frozen ? <code title={item.snapshot}>{item.snapshot!.slice(0, 16)}…</code> : '—'}</td></tr> })}</tbody>
    </DataTable>}
    <Toolbar><Button onClick={() => change({ reportsView: 'review' })}>Regenerate reports in Review Reports</Button></Toolbar>
  </Card>
}
