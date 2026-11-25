import { lazy, Suspense, useState } from 'react'
import { ChevronRight, UsersRound } from 'lucide-react'
import { Dialog } from './Dialog'
import { Button } from './Button'
import { useAuthentication } from '@/components/Auth/Authentication'

const GroupMembersDialog = lazy(() => import('@/components/Settings/GroupMembersDialog').then(module => ({ default: module.GroupMembersDialog })))
type Group = { id?: string; name: string; status?: string }

/** BUG-03: every group with a stable id opens its member list (read-only without administration); a group without an id stays informational. */
export function FunctionalGroupPills({ groups, username }: { groups: Group[]; username: string }) {
  const [open, setOpen] = useState(false), [members, setMembers] = useState<Group | null>(null)
  const { canAdmin } = useAuthentication()
  const label = (group: typeof groups[number]) => group.name + (group.status === 'archived' ? ' (archived)' : '')
  if (!groups.length) return <span className="text-muted">Unassigned</span>
  return <span data-export-value={groups.map(label).join('; ')} className="fg-chips" role="list" aria-label={`Functional Groups of ${username}`}>
    <span className="fg-chip-stack">{groups.slice(0, 2).map((group, index) => <span key={group.id || index} role="listitem" className="fg-chip" title={label(group)}>{label(group)}</span>)}</span>
    <span role="listitem" className="fg-group-action"><Button size="compact" variant="ghost" aria-label={`Show all ${groups.length} Functional Groups of ${username}`} onClick={() => setOpen(true)}>{groups.length > 2 ? `+${groups.length - 2} more` : 'View groups'}</Button></span>
    {open && <Dialog title={`Functional Groups of ${username}`} size="narrow" onClose={() => setOpen(false)}><ul className="grid gap-1">{groups.map((group, index) => <li key={group.id || index} className="min-w-0">
      {group.id ? <button type="button" className="fg-group-link" aria-label={`Show members of ${label(group)}`} onClick={() => { setOpen(false); setMembers(group) }}><UsersRound size={16} aria-hidden="true" className="shrink-0"/><span className="fg-group-name">{label(group)}</span><ChevronRight size={16} aria-hidden="true" className="shrink-0"/></button>
        : <span className="flex min-w-0 items-start gap-2 px-2 py-1"><UsersRound size={16} aria-hidden="true" className="mt-1 shrink-0"/><span className="fg-group-name">{label(group)}</span></span>}</li>)}</ul></Dialog>}
    {members?.id && <Suspense fallback={null}><GroupMembersDialog group={{ id: members.id, name: members.name, status: members.status === 'archived' ? 'archived' : 'active' }} readOnly={!canAdmin} onClose={() => setMembers(null)} /></Suspense>}
  </span>
}
