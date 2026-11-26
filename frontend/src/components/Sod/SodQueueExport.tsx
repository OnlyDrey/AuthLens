import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ArrowDown, ArrowUp, Download } from 'lucide-react'
import { downloadFile, scopeParams, sod, EXPORT_NAME, type ContextInfo, type Filters } from '@/api/sod'
import { Dialog } from '@/components/Shared/Dialog'
import { Button, IconButton } from '@/components/Shared/Button'
import { Checkbox, FormField } from '@/components/Shared/Controls'
import { Select } from '@/components/Shared/Select'
import { DataTable, EmptyState, ErrorState, LoadingState } from '@/components/Shared/Presentation'
import { announceExport } from '@/lib/exportNotice'
import { useLocalPreference } from '@/lib/localPreference'

type Preset = 'full' | 'role_removal' | 'pending' | 'custom'
type Unit = 'role_removal' | 'review_items'
interface ExportConfig { preset: Preset; scope: 'filtered' | 'all'; unit: Unit; decisions: string[]; kinds: string[]; columns: string[]; delimiter: 'semicolon' | 'comma' }
interface Preview extends ContextInfo { unit: Unit; columns: { key: string; label: string }[]; rows: string[][]; total_rows: number; users: number; excluded_ambiguous: number; identifier_formula_warnings: number }

/** Column labels as the backend writes them (`V1ReviewExport.cs`); the order of the selection is the order in the file. */
const COLUMNS: Record<string, string> = {
  username: 'SAP username', role: 'Role name', role_description: 'Role description', review_type: 'Review type', item: 'Review item', risks: 'Risks',
  employee: 'Employee name', user_group: 'SAP user group', functional_group: 'Functional group', department: 'Department', manager: 'Manager',
  review_status: 'Review status', review_comment: 'Review comment', reviewed_by: 'Reviewed by', review_date: 'Review date',
}
const UNIT_COLUMNS: Record<Unit, string[]> = {
  role_removal: ['username', 'role', 'role_description', 'employee', 'user_group', 'functional_group', 'department', 'manager', 'review_status', 'review_comment', 'reviewed_by', 'review_date'],
  review_items: ['username', 'review_type', 'item', 'risks', 'role_description', 'employee', 'user_group', 'functional_group', 'department', 'manager', 'review_status', 'review_comment', 'reviewed_by', 'review_date'],
}
const DECISIONS: [string, string][] = [['Pending', 'Pending'], ['Outdated', 'Outdated'], ['Investigate', 'Investigate'], ['Keep', 'Keep (role)'], ['Approved', 'Approved (activity)'], ['Conditional', 'Conditional'], ['Removal required', 'Removal recommended'], ['Accepted', 'Risk accepted'], ['Rejected', 'Risk rejected']]
const KINDS: [string, string][] = [['assignment', 'Role reviews'], ['activity', 'Activity reviews'], ['acceptance', 'Risk reviews']]
const PRESETS: Record<Preset, { label: string; description: string; config: Omit<ExportConfig, 'preset' | 'scope' | 'delimiter'> }> = {
  full: { label: 'Full review export', description: 'Every review item of the matching users with its decision, in the existing fixed format.', config: { unit: 'review_items', decisions: [], kinds: [], columns: [] } },
  role_removal: { label: 'Role removal', description: 'Only exact SAP role assignments recommended for removal: one row per user and role.', config: { unit: 'role_removal', decisions: [], kinds: [], columns: ['username', 'role'] } },
  pending: { label: 'Pending review', description: 'Review items that still need a decision (pending, outdated or under investigation).', config: { unit: 'review_items', decisions: ['Pending', 'Outdated', 'Investigate'], kinds: [], columns: ['username', 'review_type', 'item', 'review_status'] } },
  custom: { label: 'Custom', description: 'Review items with the decision states, review types and columns you choose.', config: { unit: 'review_items', decisions: [], kinds: [], columns: ['username', 'review_type', 'item', 'review_status'] } },
}
const DEFAULT: ExportConfig = { preset: 'role_removal', scope: 'filtered', delimiter: 'semicolon', ...PRESETS.role_removal.config }
export const QUEUE_EXPORT_PREFERENCE = 'authlens-queue-export'

function read(text: string): ExportConfig {
  try {
    const value = JSON.parse(text) as Partial<ExportConfig>
    const preset = value.preset && value.preset in PRESETS ? value.preset : DEFAULT.preset
    const unit: Unit = value.unit === 'review_items' ? 'review_items' : 'role_removal'
    return { preset, unit, scope: value.scope === 'all' ? 'all' : 'filtered', delimiter: value.delimiter === 'comma' ? 'comma' : 'semicolon',
      decisions: (value.decisions ?? []).filter(d => DECISIONS.some(([v]) => v === d)), kinds: (value.kinds ?? []).filter(k => KINDS.some(([v]) => v === k)),
      columns: (value.columns ?? []).filter(c => UNIT_COLUMNS[unit].includes(c)) }
  } catch { return DEFAULT }
}

/**
 * Configurable Work Queue export. The server builds every row (all pages) from the review state of the selected review context and, with
 * "Current filtered results", the applied Work Queue filters; the preview uses the same request with preview=true, so preview and file agree.
 * The full export keeps the existing fixed format (/api/sod/queue/export).
 */
export function SodQueueExportDialog({ context, filters, onClose }: { context: string; filters: Filters; onClose: () => void }) {
  const [stored, setStored] = useLocalPreference(QUEUE_EXPORT_PREFERENCE, JSON.stringify(DEFAULT))
  const [config, setConfigState] = useState<ExportConfig>(() => read(stored)), [busy, setBusy] = useState(false)
  const setConfig = (next: ExportConfig) => { setConfigState(next); setStored(JSON.stringify(next)) }
  const choosePreset = (preset: Preset) => setConfig({ ...config, preset, ...PRESETS[preset].config })
  const full = config.preset === 'full'
  const params = useMemo(() => {
    const value = scopeParams(context, config.scope === 'filtered' ? filters : {}, { unit: config.unit, delimiter: config.delimiter })
    config.columns.forEach(column => value.append('columns', column))
    if (config.unit === 'review_items') { config.decisions.forEach(d => value.append('decisions', d)); config.kinds.forEach(k => value.append('kinds', k)) }
    return value
  }, [context, filters, config])
  const previewParams = new URLSearchParams(params); previewParams.set('preview', 'true')
  const preview = useQuery({ queryKey: ['sod-queue-export-preview', previewParams.toString()], queryFn: () => sod<Preview>('/api/sod/queue/export/configured', previewParams), enabled: !full && config.columns.length > 0 })
  const toggle = (list: string[], value: string) => (list.includes(value) ? list.filter(item => item !== value) : [...list, value])
  const move = (index: number, by: number) => { const next = [...config.columns]; const [item] = next.splice(index, 1); next.splice(index + by, 0, item); setConfig({ ...config, preset: config.preset === 'full' ? 'custom' : config.preset, columns: next }) }
  const run = async () => {
    setBusy(true)
    try {
      const name = full
        ? await downloadFile('/api/sod/queue/export', { params: scopeParams(context, config.scope === 'filtered' ? filters : {}), namePattern: EXPORT_NAME })
        : await downloadFile('/api/sod/queue/export/configured', { params, namePattern: EXPORT_NAME })
      announceExport(name ? { kind: 'success', message: `Exported ${name}.` } : { kind: 'info', message: 'Export cancelled.' })
      if (name) onClose()
    } catch (cause) {
      announceExport({ kind: 'error', message: cause instanceof Error ? cause.message : 'Export failed.' })
    } finally { setBusy(false) }
  }
  const data = preview.data
  return (
    <Dialog title="Export review CSV" onClose={onClose} footer={<div className="flex flex-wrap items-center justify-end gap-2">
      <Button variant="ghost" onClick={onClose}>Cancel</Button>
      <Button variant="primary" loading={busy} disabled={busy || (!full && !config.columns.length)} onClick={() => void run()}><Download size={16} aria-hidden="true" />Export</Button>
    </div>}>
      <div className="grid min-w-0 gap-4">
        <FormField label="Export preset">
          <Select value={config.preset} onChange={(event) => choosePreset(event.target.value as Preset)}>{Object.entries(PRESETS).map(([value, preset]) => <option key={value} value={value}>{preset.label}</option>)}</Select>
        </FormField>
        <p className="ui-description">{PRESETS[config.preset].description}</p>
        <fieldset className="grid gap-1"><legend className="font-semibold">Export scope</legend>
          <label className="flex items-center gap-2"><input type="radio" name="queue-export-scope" checked={config.scope === 'filtered'} onChange={() => setConfig({ ...config, scope: 'filtered' })} />Current filtered results (all pages)</label>
          <label className="flex items-center gap-2"><input type="radio" name="queue-export-scope" checked={config.scope === 'all'} onChange={() => setConfig({ ...config, scope: 'all' })} />All results in the current review context</label>
        </fieldset>
        {!full && config.unit === 'review_items' && <>
          <fieldset className="grid gap-1"><legend className="font-semibold">Review types</legend><p className="ui-description">None selected: every type.</p>
            {KINDS.map(([value, label]) => <Checkbox key={value} checked={config.kinds.includes(value)} onChange={() => setConfig({ ...config, preset: 'custom', kinds: toggle(config.kinds, value) })}>{label}</Checkbox>)}
          </fieldset>
          <fieldset className="grid gap-1"><legend className="font-semibold">Review decision</legend><p className="ui-description">Applied to each review item, not to the user. None selected: every state.</p>
            {DECISIONS.map(([value, label]) => <Checkbox key={value} checked={config.decisions.includes(value)} onChange={() => setConfig({ ...config, preset: 'custom', decisions: toggle(config.decisions, value) })}>{label}</Checkbox>)}
          </fieldset>
        </>}
        {!full && config.unit === 'role_removal' && <p className="ui-description" role="note">Eligible: an exact role whose every visible assignment for the user is decided <strong>Remove</strong> in role review. Users' other roles, pending and kept roles, activity and risk decisions and roles with differing decisions are not included.</p>}
        {!full && <fieldset className="grid gap-2"><legend className="font-semibold">Columns</legend>
          <div className="flex flex-wrap gap-2">
            <Button size="compact" onClick={() => setConfig({ ...config, preset: config.preset === 'role_removal' ? 'role_removal' : 'custom', columns: [...UNIT_COLUMNS[config.unit]] })}>Select all</Button>
            <Button size="compact" onClick={() => setConfig({ ...config, columns: [] })}>Clear</Button>
          </div>
          {UNIT_COLUMNS[config.unit].map(column => <Checkbox key={column} checked={config.columns.includes(column)} onChange={() => setConfig({ ...config, columns: toggle(config.columns, column) })}>{COLUMNS[column]}</Checkbox>)}
          {config.columns.length > 0 && <ol className="grid gap-1" aria-label="Column order">{config.columns.map((column, index) => <li key={column} className="flex items-center gap-2">
            <span className="min-w-0 flex-1">{index + 1}. {COLUMNS[column]}</span>
            <IconButton label={`Move ${COLUMNS[column]} up`} disabled={index === 0} onClick={() => move(index, -1)}><ArrowUp size={14} /></IconButton>
            <IconButton label={`Move ${COLUMNS[column]} down`} disabled={index === config.columns.length - 1} onClick={() => move(index, 1)}><ArrowDown size={14} /></IconButton>
          </li>)}</ol>}
          {!config.columns.length && <p role="alert" className="ui-description">Select at least one column to export.</p>}
        </fieldset>}
        {!full && <FormField label="CSV delimiter">
          <Select value={config.delimiter} onChange={(event) => setConfig({ ...config, delimiter: event.target.value === 'comma' ? 'comma' : 'semicolon' })}><option value="semicolon">Semicolon (;)</option><option value="comma">Comma (,)</option></Select>
        </FormField>}
        <section aria-label="Export preview" className="grid gap-2">
          <h3 className="font-semibold">Preview</h3>
          {full ? <p className="ui-description">The existing full review export (fixed columns, one row per review item). Review context: {context === 'current' ? 'current evidence' : 'the selected review period'}.</p>
            : !config.columns.length ? null : preview.isError ? <ErrorState error={preview.error} onRetry={() => void preview.refetch()} title="Preview unavailable" />
            : !data ? <LoadingState /> : <>
              <p role="status" className="ui-description" aria-label="Export preview counts">{data.total_rows.toLocaleString()} {data.unit === 'role_removal' ? 'role assignments' : 'review items'} for {data.users.toLocaleString()} {data.users === 1 ? 'user' : 'users'} · {data.frozen ? 'frozen review period' : 'current evidence'}</p>
              {data.excluded_ambiguous > 0 && <p role="note" className="ui-description">{data.excluded_ambiguous.toLocaleString()} user and role pairs with differing decisions are not included.</p>}
              {data.identifier_formula_warnings > 0 && <p role="note" className="ui-description">{data.identifier_formula_warnings.toLocaleString()} rows contain an identifier that a spreadsheet could read as a formula; identifiers are written exactly.</p>}
              {!data.rows.length ? <EmptyState>No rows match this export.</EmptyState>
                : <DataTable caption="First rows of the export" regionLabel="Export preview rows" density="compact">
                  <thead><tr>{data.columns.map(column => <th key={column.key} scope="col">{column.label}</th>)}</tr></thead>
                  <tbody>{data.rows.map((row, index) => <tr key={index}>{row.map((cell, cellIndex) => <td key={cellIndex}>{cell}</td>)}</tr>)}</tbody>
                </DataTable>}
            </>}
        </section>
      </div>
    </Dialog>
  )
}
