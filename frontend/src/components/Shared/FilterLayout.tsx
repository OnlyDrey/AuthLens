import { Dialog } from './Dialog'
import { createContext, useCallback, useContext, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { ArrowDownAZ, ArrowUpAZ, ChevronsDownUp, ChevronsUpDown, Eraser, PanelLeftClose, PanelLeftOpen, SlidersHorizontal, X } from 'lucide-react'
import { useAuthentication } from '@/components/Auth/Authentication'
import { SearchInput } from './Controls'
import { DisclosureChevron } from './DisclosureChevron'
import { useLocalPreference } from '@/lib/localPreference'
import { FIELD_ALIASES } from '@/lib/fieldLabels'
import { Button, IconButton } from './Button'
import { Select } from './Select'

const WIDE = '(min-width: 1024px)'
const defaultStorageKey = 'sap-lens-filter-sidebar'

function useWide() {
  const query = () => typeof window !== 'undefined' && window.matchMedia(WIDE).matches
  const [wide, setWide] = useState(query)
  useEffect(() => {
    const media = window.matchMedia(WIDE)
    const update = () => setWide(media.matches)
    media.addEventListener('change', update)
    return () => media.removeEventListener('change', update)
  }, [])
  return wide
}

/** Collapsible left filter sidebar on wide screens, an overlay drawer on narrow ones. Filter state belongs to the caller, so hiding never resets it. */
export function FilterLayout({ activeCount, toolbar, utility, sidebar, children, label = 'Filters', onClear, clearDisabled = false, clearLabel = 'Clear filters', storageKey = defaultStorageKey, defaultOpen = true, workspace }: { /** Key of this workspace's section expansion preference (FLT-02/FLT-04); scoped per user and workspace. */ workspace?: string; activeCount: number; toolbar?: ReactNode; /** Shared utility controls (for example Saved Filters) shown above the filter groups without counting as a collapsible filter group. */ utility?: ReactNode; sidebar: ReactNode; children: ReactNode; label?: string; onClear?: () => void; clearDisabled?: boolean; /** Accessible name of the Clear action where it clears something narrower than every filter of the view. */ clearLabel?: string; /** Remembered open state of the wide sidebar; a view with its own key (Dashboard) does not share the investigation views' preference. */ storageKey?: string; /** Wide-screen state before the user chose one. */ defaultOpen?: boolean }) {
  const wide = useWide(),
    id = useId(),
    [open, setOpen] = useState(() => { try { const stored = localStorage.getItem(storageKey); return stored ? stored !== 'closed' : defaultOpen } catch { return defaultOpen } }),
    [drawer, setDrawer] = useState(false),
    trigger = useRef<HTMLButtonElement>(null),
    filters = useFilterPanel(workspace)
  useEffect(()=>{if(wide)setDrawer(false)},[wide])
  const panelBody = <FilterPanelContext.Provider value={filters.panel}><FilterPanelTools query={filters.query} setQuery={filters.setQuery} setAll={filters.setAll} anyVisible={filters.anyVisible} />{utility && <div className="filter-utility" data-filter-utility>{utility}</div>}{sidebar}</FilterPanelContext.Provider>
  const persist = (value: boolean) => { setOpen(value); try { localStorage.setItem(storageKey, value ? 'open' : 'closed') } catch { /* optional convenience */ } }
  const shown = wide ? open : drawer
  const toggle = () => (wide ? persist(!open) : setDrawer(!drawer))
  const close = () => { if (wide) persist(false); else { setDrawer(false); trigger.current?.focus() } }
  return (
    <div className="filter-layout" data-wide={wide} data-open={shown}>
      <div className="page-toolbar" role="toolbar" aria-label="Page actions">
        <Button ref={trigger} aria-expanded={shown} aria-controls={wide?id:undefined} aria-haspopup={wide?undefined:"dialog"} onClick={toggle}>
          {wide ? (open ? <PanelLeftClose size={16} aria-hidden="true" /> : <PanelLeftOpen size={16} aria-hidden="true" />) : <SlidersHorizontal size={16} aria-hidden="true" />}
          {shown && wide ? `Hide ${label.toLowerCase()}` : label}
          {activeCount > 0 && <span className="ui-tab-count" aria-label={`${activeCount} active`}>{activeCount}</span>}
        </Button>
        {toolbar}
      </div>
      {!wide&&drawer&&<Dialog title={label} presentation="drawer" onClose={close} footer={<Button variant="primary" onClick={close}>Show results</Button>}>
        {onClear&&<Button disabled={clearDisabled} onClick={onClear} aria-label={clearLabel}><Eraser size={16} aria-hidden="true"/>Clear filters</Button>}
        <div className="grid min-w-0 gap-3">{panelBody}</div>
      </Dialog>}
      <div className="filter-layout-body">
        {wide&&<aside id={id} tabIndex={-1} hidden={!shown} aria-label={label} className="filter-sidebar" role="complementary">
          <header>
            <h2>{label}</h2>
            <div className="filter-sidebar-actions">
              {onClear && <Button size="compact" className="filter-clear-all" aria-label={clearLabel} title={clearLabel === 'Clear filters' ? 'Clear all filters in this view' : clearLabel} disabled={clearDisabled} onClick={onClear}><Eraser size={16} aria-hidden="true" />Clear</Button>}
              <IconButton label={`Close ${label.toLowerCase()}`} onClick={close}><X size={16} /></IconButton>
            </div>
          </header>
          <div className="filter-sidebar-body">{panelBody}</div>
        </aside>}
        <div className="filter-layout-main">{children}</div>
      </div>
    </div>
  )
}

/* ---------------------------------------------------------------------------------------------------------------------------------------
 * FLT-02 collapsible filter sections and FLT-03 filter discovery, shared by every FilterLayout.
 * Presentation only: collapsing or searching never changes a filter value, and nothing here issues a request.
 * ------------------------------------------------------------------------------------------------------------------------------------- */
type Panel = {
  query: string
  isOpen: (id: string, fallback: boolean) => boolean
  toggle: (id: string, open: boolean) => void
  reveal: (id: string) => void
  register: (id: string, title: string) => () => void
  report: (id: string, visible: boolean) => void
}
const FilterPanelContext = createContext<Panel | null>(null)
const normalize = (text: string) => text.toLocaleLowerCase().replace(/\s+/g, ' ').trim()
const sectionId = (title: string) => normalize(title).replace(/[^a-z0-9]+/g, '-')
/** A field or section label matches the discovery text directly, partially, or through a canonical terminology alias (TBL-04). */
function matches(label: string, query: string) {
  const text = normalize(label), q = normalize(query)
  if (!q) return true
  if (text.includes(q)) return true
  return Object.entries(FIELD_ALIASES).some(([canonical, aliases]) => text.includes(normalize(canonical)) && aliases.some(alias => alias.includes(q) || q.includes(alias)))
}
/** Labels that name a filter control: labels, legends and accessible names (never the selected values or the result data). */
function fieldLabels(field: Element) {
  const own = [field.getAttribute('aria-label') || '', field.matches('label, legend') ? field.textContent || '' : '']
  for (const node of field.querySelectorAll('label, legend, .ui-field-label, [aria-label]')) own.push(node.matches('[aria-label]') ? node.getAttribute('aria-label') || '' : node.textContent || '')
  return own.filter(Boolean)
}
/** Active filters inside an element: chips (Remove buttons), filled text fields and controls that mark themselves with data-filter-active. */
function activeIn(element: Element) {
  let count = element.querySelectorAll('[data-filter-active="true"], button[aria-label^="Remove "]').length
  for (const input of element.querySelectorAll<HTMLInputElement>('input[type="text"], input[type="search"], input:not([type]), textarea')) if (input.value.trim() && !input.closest('[data-filter-discovery]') && !input.getAttribute('role')) count++
  // a native select away from its first option (the "any" choice) is an active filter
  for (const select of element.querySelectorAll<HTMLSelectElement>('select')) if (select.options.length && select.value !== select.options[0].value && !select.closest('[data-filter-active]')) count++
  return count
}

function useFilterPanel(workspace: string | undefined) {
  const { user } = useAuthentication()
  const userScope = user?.id ? `user:${user.id}` : 'local'
  const [stored, setStored] = useLocalPreference(`authlens.filter-sections.${userScope}.${workspace || 'unnamed'}`, '{}')
  const preferences = useMemo(() => { try { const value = JSON.parse(stored); return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, boolean> : {} } catch { return {} } }, [stored])
  const [revealed, setRevealed] = useState<ReadonlySet<string>>(new Set()), [query, setQuery] = useState('')
  const sections = useRef(new Map<string, string>()), [visible, setVisible] = useState<Record<string, boolean>>({})
  const save = useCallback((next: Record<string, boolean>) => { if (workspace) setStored(JSON.stringify(next)) }, [setStored, workspace])
  const panel: Panel = useMemo(() => ({
    query,
    isOpen: (id, fallback) => revealed.has(id) || (preferences[id] ?? fallback),
    toggle: (id, open) => { setRevealed(previous => { const next = new Set(previous); next.delete(id); return next }); save({ ...preferences, [id]: open }) },
    reveal: id => setRevealed(previous => previous.has(id) ? previous : new Set(previous).add(id)),
    register: (id, title) => { sections.current.set(id, title); return () => { sections.current.delete(id) } },
    report: (id, shown) => setVisible(previous => previous[id] === shown ? previous : { ...previous, [id]: shown }),
  }), [query, revealed, preferences, save])
  const setAll = (open: boolean) => { setRevealed(new Set()); save({ ...preferences, ...Object.fromEntries([...sections.current.keys()].map(id => [id, open])) }) }
  const anyVisible = Object.entries(visible).some(([id, shown]) => shown && sections.current.has(id))
  return { panel, query, setQuery, setAll, anyVisible }
}

/** The discovery field and the Expand all / Collapse all control at the top of a filter panel (FLT-02, FLT-03). */
function FilterPanelTools({ query, setQuery, setAll, anyVisible }: { query: string; setQuery: (value: string) => void; setAll: (open: boolean) => void; anyVisible: boolean }) {
  return (
    <div className="filter-discovery" data-filter-discovery>
      <SearchInput aria-label="Find a filter" placeholder="Find a filter..." value={query} onChange={event => setQuery(event.target.value)} onClear={() => setQuery('')} clearLabel="Clear filter search" />
      <div className="filter-discovery-actions" role="group" aria-label="Filter sections">
        <Button size="compact" variant="ghost" aria-label="Expand all filter groups" onClick={() => setAll(true)} disabled={!!query}><ChevronsUpDown size={14} aria-hidden="true" />Expand all</Button>
        <Button size="compact" variant="ghost" aria-label="Collapse all filter groups" onClick={() => setAll(false)} disabled={!!query}><ChevronsDownUp size={14} aria-hidden="true" />Collapse all</Button>
      </div>
      {query && !anyVisible && <p role="status" className="ui-description">No filters match “{query}”. Active filters stay applied.</p>}
    </div>
  )
}

/**
 * A filter group with an accessible collapsible header (FLT-02): the header shows the number of active filters, collapsing never clears a
 * value, and a section holding restored active filters opens on load. While a filter discovery search runs (FLT-03) matching sections open
 * temporarily and only their matching fields (plus fields with active filters) are shown; the saved expansion returns when the search is
 * cleared. Outside a FilterLayout it is the plain fieldset it always was.
 */
export function FilterSection({ title, children, defaultOpen = true, active }: { title: string; children: ReactNode; /** Expanded before the user chose. */ defaultOpen?: boolean; /** Active filter count when the generic detection does not fit. */ active?: number }) {
  const panel = useContext(FilterPanelContext), id = sectionId(title), contentId = useId()
  const content = useRef<HTMLDivElement>(null), previous = useRef<number | null>(null)
  const [count, setCount] = useState(0), [hit, setHit] = useState(true)
  useEffect(() => panel?.register(id, title), [panel?.register, id, title]) // eslint-disable-line react-hooks/exhaustive-deps
  const query = panel?.query ?? ''
  useLayoutEffect(() => {
    const root = content.current
    if (!root || !panel) return
    const total = active ?? activeIn(root)
    if (total !== count) setCount(total)
    // Restored active filters are revealed: on the first render, and whenever a collapsed section gains active filters it cannot have been edited
    // in (history, a loaded saved filter or a contextual link restored them). A section the user collapses keeps its count and stays collapsed.
    const before = previous.current
    previous.current = total
    if (total > 0 && (before === null || (total > before && !panel.isOpen(id, defaultOpen)))) panel.reveal(id)
    // Discovery: hide fields that neither match nor hold an active filter; a matching section title shows the whole section
    const titleHit = matches(title, query)
    let any = titleHit
    for (const field of root.children) {
      const element = field as HTMLElement
      const match = !!query && !titleHit && fieldLabels(element).some(label => matches(label, query))
      const show = !query || titleHit || match || activeIn(element) > 0 // active filters stay discoverable, but are not a match
      if (match) any = true
      if (element.dataset.filterHidden !== undefined || !show) { element.hidden = !show; if (show) delete element.dataset.filterHidden; else element.dataset.filterHidden = '' }
    }
    const shown = !query || any || total > 0
    if (shown !== hit) setHit(shown)
    panel.report(id, !query || any)
  })
  if (!panel) return <fieldset className="filter-section"><legend>{title}</legend>{children}</fieldset>
  const open = query ? hit : panel.isOpen(id, defaultOpen)
  return (
    <section className="filter-section" data-filter-section={id} aria-labelledby={`${contentId}-label`} hidden={!hit}>
      <h3 className="filter-section-heading">
        <button type="button" className="filter-section-toggle" aria-expanded={open} aria-controls={contentId} id={`${contentId}-label`} disabled={!!query}
          aria-label={count > 0 ? `${title} ${count} active` : title}
          onClick={() => panel.toggle(id, !open)}>
          <DisclosureChevron open={open} />
          <span className="filter-section-title">{title}</span>
          {count > 0 && <span className="ui-tab-count filter-section-count" aria-hidden="true">{count}</span>}
        </button>
      </h3>
      <div id={contentId} ref={content} className="filter-section-body" hidden={!open}>{children}</div>
    </section>
  )
}

/** Consistent action row: view controls on the left, Saved Filters, sort and export grouped on the right. */
export function PageToolbar({ lead, children }: { lead?: ReactNode; children?: ReactNode }) {
  return <div className="page-toolbar-actions">{lead}<div className="page-toolbar-end">{children}</div></div>
}

export function SortControl({ label = 'Sort', value, options, descending, onChange, onDescending }: {
  label?: string; value: string; options: { value: string; label: string }[]; descending: boolean; onChange: (value: string) => void; onDescending: (value: boolean) => void
}) {
  return (
    <div className="sod-sort" role="group" aria-label={`${label} order`}>
      <Select aria-label={label} value={value} onChange={(event) => onChange(event.target.value)}>{options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</Select>
      <IconButton label={descending ? 'Descending order, switch to ascending' : 'Ascending order, switch to descending'} aria-pressed={descending} onClick={() => onDescending(!descending)}>
        {descending ? <ArrowUpAZ size={16} /> : <ArrowDownAZ size={16} />}
      </IconButton>
    </div>
  )
}
