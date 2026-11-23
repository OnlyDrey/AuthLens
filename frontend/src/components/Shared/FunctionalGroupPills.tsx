import { useState } from 'react'
import { UsersRound } from 'lucide-react'
import { Dialog } from './Dialog'
import { Button } from './Button'

export function FunctionalGroupPills({ groups, username }: { groups: { id?: string; name: string; status?: string }[]; username: string }) {
  const [open, setOpen] = useState(false)
  const label = (group: typeof groups[number]) => group.name + (group.status === 'archived' ? ' (archived)' : '')
  if (!groups.length) return <span className="text-muted">Unassigned</span>
  return <span data-export-value={groups.map(label).join('; ')} className="fg-chips" role="list" aria-label={`Functional Groups of ${username}`}>
    <span className="fg-chip-stack">{groups.slice(0, 2).map((group, index) => <span key={group.id || index} role="listitem" className="fg-chip" title={label(group)}>{label(group)}</span>)}</span>
    <span role="listitem" className="fg-group-action"><Button size="compact" variant="ghost" aria-label={`Show all ${groups.length} Functional Groups of ${username}`} onClick={() => setOpen(true)}>{groups.length > 2 ? `+${groups.length - 2} more` : 'View groups'}</Button></span>
    {open && <Dialog title={`Functional Groups of ${username}`} size="narrow" onClose={() => setOpen(false)}><ul className="grid gap-2">{groups.map((group, index) => <li key={group.id || index} className="flex min-w-0 items-start gap-2"><UsersRound size={16} aria-hidden="true" className="mt-1 shrink-0"/><span className="break-words">{label(group)}</span></li>)}</ul></Dialog>}
  </span>
}
