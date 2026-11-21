import {ColumnOptions,ColumnActions} from './ColumnOptions'
import { Children, Fragment, cloneElement, isValidElement, useRef, useState, type HTMLAttributes, type ReactElement, type ReactNode } from 'react'
import { Columns3, RotateCcw } from 'lucide-react'
import { Button } from './Button'
import { Dialog } from './Dialog'
import { buildTableCSV } from '@/lib/csv'

type Node = ReactElement<{ children?: ReactNode; colSpan?: number; className?: string; 'aria-label'?: string; label?: string; title?: string; value?: string }>
function elements(children: ReactNode): Node[] {
  return Children.toArray(children).flatMap(child => isValidElement(child) ? child.type === Fragment ? elements((child as Node).props.children) : [child as Node] : [])
}
function text(children: ReactNode): string {
  return Children.toArray(children).map(child => typeof child === 'string' || typeof child === 'number' ? String(child) : isValidElement(child) ? text((child as Node).props.children) || (child as Node).props.label || (child as Node).props.value || (child as Node).props.title || (child as Node).props['aria-label'] || '' : '').join(' ').replace(/\s+/g, ' ').trim()
}

/** Column order is rendered in DOM order. Hidden cells remain available for explicit all-column exports, never duplicated. */
export function ConfigurableTable({ children, ...props }: HTMLAttributes<HTMLTableElement>) {
  const head = elements(children).find(child => child.type === 'thead')
  const headings = elements(elements(head?.props.children)[0]?.props.children)
  const columns = headings.map((cell, index) => ({ index, label: cell.props.className?.includes('col-select') ? 'Selection' : text(cell.props.children) || cell.props['aria-label'] || `Column ${index + 1}`, locked: /ud-sticky|col-select/.test(cell.props.className || '') }))
  const simple = !props.className?.includes('matrix-grid') && headings.length > 1 && !headings.some(cell => (cell.props.colSpan || 1) > 1) && elements(head?.props.children).length === 1
  const key = `authlens.table-columns.${columns.map(column => column.label).join('|')}`
  const [preferences, setPreferences] = useState<Record<string, { order: number[]; hidden: number[]; nowrap: boolean }>>(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('authlens.table-columns') || '{}')
      if (!saved || typeof saved !== 'object' || Array.isArray(saved)) return {}
      return Object.fromEntries(Object.entries(saved).filter(([, value]) => {
        const entry = value as { order?: unknown; hidden?: unknown; nowrap?: unknown }
        return entry && Array.isArray(entry.order) && Array.isArray(entry.hidden) && [...entry.order, ...entry.hidden].every(index => Number.isInteger(index) && index >= 0) && typeof entry.nowrap === 'boolean'
      })) as Record<string, { order: number[]; hidden: number[]; nowrap: boolean }>
    } catch { return {} }
  })
  const current = simple ? preferences[key] : undefined
  const order = [...new Set([...(current?.order || []), ...columns.map(column => column.index)])].filter(index => columns[index])
  const hidden = (current?.hidden || []).filter(index => columns[index] && !columns[index].locked), nowrap = current?.nowrap !== false
  const [exportError,setExportError]=useState('')
  const [open, setOpen] = useState(false), table = useRef<HTMLTableElement>(null)
  const caption = text(elements(children).find(child => child.type === 'caption')?.props.children) || props['aria-label'] || 'table'
  const save = (patch: Partial<NonNullable<typeof current>>) => setPreferences(previous => {
    let stored = previous
    try { const value = JSON.parse(localStorage.getItem('authlens.table-columns') || '{}'); if (value && typeof value === 'object' && !Array.isArray(value)) stored = value } catch { /* retain current preferences */ }
    const next = { ...stored, [key]: { order, hidden, nowrap, ...patch } }
    try { localStorage.setItem('authlens.table-columns', JSON.stringify(next)) } catch { /* optional local preference */ }
    return next
  })
  const rendered = (() => {
    function visit(nodes: ReactNode): ReactNode {
      return Children.map(nodes, child => {
        if (!isValidElement(child)) return child
        const node = child as Node
        if (node.type === 'tr') {
          const cells = elements(node.props.children)
          if (cells.length !== columns.length || cells.some(cell => (cell.props.colSpan || 1) > 1)) return child
          return cloneElement(node, {}, order.map(index => cloneElement(cells[index] as ReactElement<Record<string, unknown>>, {
            key: index, hidden: simple && hidden.includes(index), 'data-column-index': index,
            'data-wrap': /functional group/i.test(columns[index].label) ? 'groups' : undefined,
          })))
        }
        return ['thead', 'tbody', 'tfoot'].includes(String(node.type)) || node.type === Fragment ? cloneElement(node, {}, visit(node.props.children)) : child
      })
    }
    return visit(children)
  })()
  const exportCSV = (all: boolean) => {
    setExportError('')
    try {
      const selected = order.filter(index => (all || !hidden.includes(index)) && !/col-select/.test(headings[index].props.className || ''))
      const rows = [...(table.current?.tBodies || [])].flatMap(body => [...body.rows]).filter(row => row.cells.length === columns.length)
      const content = buildTableCSV(selected.map(index => columns[index].label), rows.map(row => selected.map(index => {
        const cell = row.querySelector<HTMLElement>(`[data-column-index="${index}"]`)
        return cell?.querySelector('[data-export-value]')?.getAttribute('data-export-value') ?? cell?.innerText ?? cell?.textContent ?? ''
      })))
      const url = URL.createObjectURL(new Blob([content], { type: 'text/csv;charset=utf-8' }))
      const link = document.createElement('a'); link.href = url; link.download = 'AuthLens-table.csv'; link.click(); URL.revokeObjectURL(url)
    } catch(error) { setExportError(error instanceof Error?error.message:'Export failed.') }
  }
  return <>
    {simple && <div className="table-presentation-controls"><Button size="compact" aria-label={`Columns for ${caption}`} onClick={() => setOpen(true)}><Columns3 size={16} aria-hidden="true"/>Columns</Button></div>}
    <table {...props} ref={table} data-nowrap={nowrap || undefined}>{rendered}</table>
    {simple && open && <Dialog title={`Columns for ${caption}`} size="medium" onClose={() => setOpen(false)} footer={<ColumnActions onExport={exportCSV} onDone={()=>setOpen(false)} error={exportError}/>}>
      <p className="ui-description">Choose visible columns and their reading/export order. Exports contain only rows currently displayed, not other pages. Existing full-result and evidence exports remain separate.</p>
      <label className="flex min-h-11 items-center gap-2"><input type="checkbox" checked={nowrap} onChange={event => save({ nowrap: event.target.checked })}/>Keep column values on one line (Functional Groups can wrap)</label>
      <ColumnOptions items={order.map(index=>({id:String(index),label:columns[index].label,checked:!hidden.includes(index),locked:columns[index].locked}))} onToggle={id=>{const index=Number(id);save({hidden:hidden.includes(index)?hidden.filter(value=>value!==index):[...hidden,index]})}} onMove={(id,direction)=>{const position=order.indexOf(Number(id)),next=[...order];[next[position],next[position+direction]]=[next[position+direction],next[position]];save({order:next})}}/>
      <Button size="compact" onClick={() => save({ order: columns.map(column => column.index), hidden: [], nowrap: true })}><RotateCcw size={16} aria-hidden="true"/>Reset columns</Button>
    </Dialog>}
  </>
}
