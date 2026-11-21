import { ArrowDown, ArrowUp, Download } from 'lucide-react'
import { Button, IconButton } from './Button'

/** Reading order, keyboard order and export order use the same ordered list. */
export function ColumnOptions({ items, onToggle, onMove }: { items: { id: string; label: string; checked: boolean; locked?: boolean }[]; onToggle: (id: string) => void; onMove: (id: string, direction: -1 | 1) => void }) {
  return <ol className="table-column-options">{items.map((item, position) => <li key={item.id}>
    <label><input type="checkbox" checked={item.checked} disabled={item.locked || (item.checked && items.filter(entry => entry.checked).length <= 1)} onChange={() => onToggle(item.id)}/><span>{item.label}</span></label>
    <IconButton label={`Move ${item.label} up`} disabled={item.locked || position === 0 || items[position - 1].locked} onClick={() => onMove(item.id, -1)}><ArrowUp size={16}/></IconButton>
    <IconButton label={`Move ${item.label} down`} disabled={item.locked || position === items.length - 1 || items[position + 1].locked} onClick={() => onMove(item.id, 1)}><ArrowDown size={16}/></IconButton>
  </li>)}</ol>
}

/** Keep export/close reachable while a long column list scrolls independently. */
export function ColumnActions({ onExport, onDone, error }: { onExport: (all: boolean) => void; onDone: () => void; error?: string }) {
  return <div className="grid w-full gap-2">
    {error&&<p role="alert">{error}</p>}
    <div className="flex flex-wrap justify-end gap-2"><Button variant="primary" onClick={()=>onExport(false)}><Download size={16} aria-hidden="true"/>Export visible columns</Button><Button onClick={()=>onExport(true)}><Download size={16} aria-hidden="true"/>Export all columns</Button><Button onClick={onDone}>Done</Button></div>
  </div>
}
