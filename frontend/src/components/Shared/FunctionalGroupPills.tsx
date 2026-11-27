import { lazy, Suspense, useState } from 'react'
import { ChevronRight, UsersRound } from 'lucide-react'
import { Dialog } from './Dialog'
import { useAuthentication } from '@/components/Auth/Authentication'

const GroupMembersDialog = lazy(() => import('@/components/Settings/GroupMembersDialog').then(module => ({ default: module.GroupMembersDialog })))
type Group = { id?: string; name: string; status?: string }

/** BUG-013: one compact line per table cell. The first group (in the order the API returns) is a pill that opens its member list (BUG-03;
 *  read-only without administration; a group without a stable id stays informational); further groups are summarized by a `+X` pill that opens
 *  the full "Functional Groups of" dialog. The named pill truncates with an ellipsis, the `+X` pill never shrinks or wraps (BUG-06 content sizing). */
export function FunctionalGroupPills({ groups, username }: { groups: Group[]; username: string }) {
  const [open, setOpen] = useState(false), [members, setMembers] = useState<Group | null>(null)
  const { canAdmin } = useAuthentication()
  const label = (group: Group) => group.name + (group.status === 'archived' ? ' (archived)' : '')
  if (!groups.length) return <span className="text-muted">Unassigned</span>
  const [first] = groups, additional = groups.length - 1
  return <span data-export-value={groups.map(label).join('; ')} className="fg-chips" role="list" aria-label={`Functional Groups of ${username}`}>
    <span role="listitem" className="fg-chip-item">
      {first.id
        ? <button type="button" className="fg-chip" title={label(first)} aria-label={`Show members of ${label(first)}`} onClick={() => setMembers(first)}><span className="fg-chip-label">{label(first)}</span></button>
        : <span className="fg-chip" title={label(first)}><span className="fg-chip-label">{label(first)}</span></span>}
    </span>
    {additional > 0 && <span role="listitem" className="fg-chip-item fg-chip-item-more">
      <button type="button" className="fg-chip fg-chip-more" title={`${additional} more: ${groups.slice(1).map(label).join(', ')}`} aria-label={`Show all ${groups.length} Functional Groups of ${username}`} onClick={() => setOpen(true)}>+{additional}</button>
    </span>}
    {open && <Dialog title={`Functional Groups of ${username}`} size="narrow" onClose={() => setOpen(false)}><ul className="grid gap-1">{groups.map((group, index) => <li key={group.id || index} className="min-w-0">
      {group.id ? <button type="button" className="fg-group-link" aria-label={`Show members of ${label(group)}`} onClick={() => { setOpen(false); setMembers(group) }}><UsersRound size={16} aria-hidden="true" className="shrink-0"/><span className="fg-group-name">{label(group)}</span><ChevronRight size={16} aria-hidden="true" className="shrink-0"/></button>
        : <span className="flex min-w-0 items-start gap-2 px-2 py-1"><UsersRound size={16} aria-hidden="true" className="mt-1 shrink-0"/><span className="fg-group-name">{label(group)}</span></span>}</li>)}</ul></Dialog>}
    {members?.id && <Suspense fallback={null}><GroupMembersDialog group={{ id: members.id, name: members.name, status: members.status === 'archived' ? 'archived' : 'active' }} readOnly={!canAdmin} onClose={() => setMembers(null)} /></Suspense>}
  </span>
}
