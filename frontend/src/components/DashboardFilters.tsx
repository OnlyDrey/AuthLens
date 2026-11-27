import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Check } from 'lucide-react'
import { dashboardFilterOptionsKey, fetchDashboardFilterOptions, type DashboardFilterOptions } from '@/api/dashboard'
import { SubjectFilters, subjectFilterParams, useOrganizationLabel, type SubjectFiltersValue } from '@/components/Shared/OrganizationFilter'
import { MultiSelectFilter } from '@/components/Shared/MultiSelectFilter'
import { FormField } from '@/components/Shared/Controls'
import { Button } from '@/components/Shared/Button'
import { FilterSection } from '@/components/Shared/FilterLayout'
import { SavedFilters } from '@/components/Shared/SavedFilters'
import { FilterChip } from '@/components/Shared/FilterChip'

/** Dashboard population dimensions sent to the shared server resolver (SubjectSelection): OR within a dimension, AND between dimensions. */
export const DIMENSIONS = [
  { key: 'user_groups', label: 'SAP user group', area: 'sap' },
  { key: 'user_types', label: 'User type', area: 'sap' },
  { key: 'account_states', label: 'Account validity', area: 'sap' },
  { key: 'lock_states', label: 'Account status', area: 'sap' },
  { key: 'departments', label: 'Department', area: 'organization' },
  { key: 'sites', label: 'Site', area: 'organization' },
  { key: 'titles', label: 'Job title', area: 'organization' },
  { key: 'ad_states', label: 'Directory account status', area: 'organization' },
  { key: 'roles', label: 'Role name', area: 'access' },
  { key: 'tcodes', label: 'Assigned transaction', area: 'access' },
  { key: 'role_types', label: 'Role type', area: 'access' },
  { key: 'org_suffixes', label: 'Organizational suffix', area: 'access' },
  { key: 'sod_risks', label: 'SoD risk', area: 'governance' },
  { key: 'review_states', label: 'Review status', area: 'governance' },
] as const
export type DimensionKey = (typeof DIMENSIONS)[number]['key']
/** `access_scope` 'matching' counts only assignments that match every access filter at once; the default is the user population. */
export type DashboardFilterValue = SubjectFiltersValue & Record<DimensionKey, string[]> & { access_scope?: 'matching' }
const ORGANIZATION_KEYS = ['functional_groups', 'managers', 'usernames'] as const
const MAX_VALUES = 200
const VALUE_LABELS: Partial<Record<DimensionKey, Record<string, string>>> = {
  account_states: { valid: 'Valid', future: 'Not yet valid', expired: 'Expired', unknown: 'Unknown validity' },
  lock_states: { locked: 'Locked', unlocked: 'Unlocked', unknown: 'Unknown lock status' },
  role_types: { business: 'Business role (ZC)', release: 'Release role (ZO)', other: 'Other role' },
  review_states: { completed: 'Completed', pending: 'Pending', outdated: 'Outdated' },
}
const ACCESS_KEYS: DimensionKey[] = ['roles', 'tcodes', 'role_types', 'org_suffixes']

export const emptyDashboardFilters = (): DashboardFilterValue =>
  ({ functional_groups: [], managers: [], usernames: [], ...Object.fromEntries(DIMENSIONS.map(d => [d.key, []])) }) as unknown as DashboardFilterValue
export function dashboardFilterParams(value: DashboardFilterValue) {
  const parameters = subjectFilterParams(value)
  for (const { key } of DIMENSIONS) for (const item of value[key]) parameters.append(key, item)
  if (value.access_scope === 'matching' && ACCESS_KEYS.some(key => value[key].length)) parameters.append('access_scope', 'matching')
  return parameters
}
export const activeFilterCount = (value: DashboardFilterValue) => [...ORGANIZATION_KEYS, ...DIMENSIONS.map(d => d.key)].reduce((sum, key) => sum + value[key].length, 0)
/** True when a dimension is active that other user views cannot express; drill-down then carries the resolved usernames. */
export const usesDashboardOnlyDimensions = (value: DashboardFilterValue) => DIMENSIONS.some(d => value[d.key].length > 0)
/** Saved definitions are validated value by value: unknown keys and non-string items are dropped. */
function sanitize(state: Record<string, unknown>): DashboardFilterValue {
  const next = emptyDashboardFilters()
  for (const key of [...ORGANIZATION_KEYS, ...DIMENSIONS.map(d => d.key)] as (typeof ORGANIZATION_KEYS[number] | DimensionKey)[]) {
    const items = state[key]
    if (Array.isArray(items)) next[key] = items.filter((item): item is string => typeof item === 'string').slice(0, key === 'usernames' ? 500 : MAX_VALUES)
  }
  if (state.access_scope === 'matching') next.access_scope = 'matching'
  return next
}
const optionLabel = (key: DimensionKey, options?: DashboardFilterOptions) => (value: string) => {
  const name = VALUE_LABELS[key]?.[value] ?? value
  const count = options?.[key].find(option => option.value === value)?.count
  return count === undefined ? name : `${name} (${count})`
}

function Dimension({ dimension, value, onChange, options, loading }: { dimension: (typeof DIMENSIONS)[number]; value: DashboardFilterValue; onChange: (value: DashboardFilterValue) => void; options?: DashboardFilterOptions; loading: boolean }) {
  const items = options?.[dimension.key] ?? []
  return <FormField label={dimension.label}>
    <MultiSelectFilter label={dimension.label} values={value[dimension.key]} options={items.map(item => item.value)} maxSelected={MAX_VALUES} loading={loading}
      optionLabel={optionLabel(dimension.key, options)} placeholder={items.length ? 'All' : 'No values in the current data'}
      onChange={values => onChange({ ...value, [dimension.key]: values })} />
  </FormField>
}

/** BUG-014: the contents of the integrated left filter sidebar (shared FilterLayout, as in User Access). Edits a draft; nothing changes on the
 *  dashboard until Apply. Clearing (the sidebar's Clear, or Reset filters in the toolbar) resets the draft and the applied filters. Hiding the
 *  sidebar keeps the draft and the applied filters. */
export function DashboardFilterControls({ value, onApply }: { value: DashboardFilterValue; onApply: (value: DashboardFilterValue) => void }) {
  const [draft, setDraft] = useState(value)
  // Applied filters can change outside the sidebar (chip removal, Reset filters); the draft follows them so Apply compares against what is shown.
  useEffect(() => setDraft(value), [value])
  const options = useQuery({ queryKey: dashboardFilterOptionsKey, queryFn: fetchDashboardFilterOptions, staleTime: 15_000 })
  const loading = options.isFetching && !options.data, directory = options.data?.directory_available ?? false
  const changed = JSON.stringify(draft) !== JSON.stringify(value)
  const section = (area: string, title: string, note?: string) => <FilterSection title={title}>
    {note && <p className="ui-description">{note}</p>}
    {area === 'organization' && <SubjectFilters compact value={draft} onChange={subject => setDraft({ ...draft, ...subject })} />}
    {DIMENSIONS.filter(d => d.area === area && (area !== 'organization' || directory || draft[d.key].length)).map(d => <Dimension key={d.key} dimension={d} value={draft} onChange={setDraft} options={options.data} loading={loading} />)}
  </FilterSection>
  const apply = <div className="dashboard-filter-apply"><Button variant="primary" disabled={!changed} onClick={() => onApply(draft)}><Check size={14} aria-hidden="true" />Apply filters</Button></div>
  return <div className="grid min-w-0 gap-3" role="group" aria-label="Dashboard filters">
    <p className="ui-description">Values combine with OR inside a filter and AND between filters. Only values present in the validated data are listed. Changes take effect on Apply.</p>
    {apply}
    <SavedFilters showClear={false} view="dashboard" state={{ ...draft }} apply={state => { const next = sanitize(state); setDraft(next); onApply(next) }} clear={() => setDraft(emptyDashboardFilters())} />
    {section('organization', 'Organization', directory ? `Department, site, title and directory status come from ${options.data?.matched_identities.toLocaleString()} matched Employee Directory identities.` : 'Department, site, title and directory status need an enabled Employee Directory with matched identities.')}
    {section('sap', 'SAP account')}
    {section('access', 'Access', 'Only currently valid assignments are considered. Organizational suffixes are final role-name segments used under at least two business-role stems.')}
    <FilterSection title="Access matching">
      <label className="flex items-start gap-2"><input type="radio" name="dashboard-access-scope" checked={draft.access_scope !== 'matching'} onChange={() => setDraft({ ...draft, access_scope: undefined })} />
        <span><strong>User population</strong> (default): users who hold the role or code through any current assignment; access metrics show their complete current access. Role and code may come from different assignments.</span></label>
      <label className="flex items-start gap-2"><input type="radio" name="dashboard-access-scope" checked={draft.access_scope === 'matching'} onChange={() => setDraft({ ...draft, access_scope: 'matching' })} />
        <span><strong>Matching access</strong>: one current assignment must match every access filter, and access metrics count only those assignments. SoD conflicts are still evaluated over the users' complete access.</span></label>
    </FilterSection>
    {section('governance', 'Governance', options.data && !options.data.sod_available ? 'SoD risk values need enabled SoD with a loaded SoD matrix. Review status is the current Account Review state; outdated reviews are also pending.' : 'SoD risk selects users with a current finding for the risk. Review status is the current Account Review state; outdated reviews are also pending.')}
    {apply}
  </div>
}

/** Removable chips for the applied filters, shown on the dashboard so the active population is always visible. */
export function DashboardFilterSummary({ value, onChange }: { value: DashboardFilterValue; onChange: (value: DashboardFilterValue) => void }) {
  const organization = useOrganizationLabel()
  const options = useQuery({ queryKey: dashboardFilterOptionsKey, queryFn: fetchDashboardFilterOptions, staleTime: 15_000, enabled: usesDashboardOnlyDimensions(value) })
  const chips = [
    ...value.functional_groups.map(item => ({ key: 'functional_groups' as const, item, text: `Functional Group: ${organization('functional_group', item)}` })),
    ...value.managers.map(item => ({ key: 'managers' as const, item, text: `Manager: ${organization('manager', item)}` })),
    ...(value.usernames.length ? [{ key: 'usernames' as const, item: '', text: `Exact usernames: ${value.usernames.length}` }] : []),
    ...DIMENSIONS.flatMap(d => value[d.key].map(item => ({ key: d.key, item, text: `${d.label}: ${optionLabel(d.key, options.data)(item)}` }))),
  ]
  if (!chips.length) return null
  return <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Applied dashboard filters">
    {chips.map(chip => <FilterChip key={`${chip.key}:${chip.item}`} removeLabel={`Remove ${chip.text}`}
      onRemove={() => onChange({ ...value, [chip.key]: chip.key === 'usernames' ? [] : value[chip.key].filter(item => item !== chip.item) })}>{chip.text}</FilterChip>)}
  </div>
}
