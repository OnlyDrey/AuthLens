import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowUp, ChevronRight, FileSpreadsheet, FileX, Folder, FolderCheck, HardDrive, Network, RefreshCw, Server, Trash2 } from 'lucide-react'
import { ApiError } from '@/api/client'
import { approveFolder, approvedFolders, browseHost, hostLocations, isNetworkPath, parentFolder, revokeFolder, type HostEntry, type HostListing } from '@/api/hostFiles'
import { Button, IconButton } from '@/components/Shared/Button'
import { Checkbox, FormField, Input, SearchInput } from '@/components/Shared/Controls'
import { Dialog } from '@/components/Shared/Dialog'
import { EmptyState, LoadingState, StatusBadge } from '@/components/Shared/Presentation'
import { formatTimestamp } from '@/lib/dateFormat'

type Sort = 'name' | 'size' | 'modified'
const size = (bytes: number | null) => bytes === null ? '' : bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1048576).toFixed(1)} MB`
/** The refusal category the browse API returns (not_approved, access_denied, missing, network_unavailable, unsafe_path, invalid_path). */
const category = (error: unknown) => error instanceof ApiError ? (error.body as { category?: string } | undefined)?.category : undefined

/**
 * WP33 (FILE-003, FILE-003A): Open-dialog style picker for files on the AuthLens HOST, not on the device running the browser. Lists only approved
 * folders, as the AuthLens service identity (the backend enforces approval, links and private locations). Local and network (UNC) folders use one
 * experience. Selecting returns the persistent host path; nothing is read or imported here, and nothing can be deleted, renamed or moved.
 */
export function HostFilePicker({ initialPath = '', onSelect, onCancel }: { initialPath?: string; onSelect: (path: string) => void; onCancel: () => void }) {
  const client = useQueryClient()
  const start = initialPath ? (initialPath.toLowerCase().endsWith('.csv') ? parentFolder(initialPath) : initialPath) : ''
  const [folder, setFolder] = useState(start), [typed, setTyped] = useState(start), [query, setQuery] = useState(''), [sort, setSort] = useState<Sort>('name'), [descending, setDescending] = useState(false)
  const [selected, setSelected] = useState(initialPath.toLowerCase().endsWith('.csv') ? initialPath : ''), [approving, setApproving] = useState(false), [confirm, setConfirm] = useState(false), [manage, setManage] = useState(false), [notice, setNotice] = useState('')
  const locations = useQuery({ queryKey: ['host-locations'], queryFn: hostLocations })
  const listing = useQuery({ queryKey: ['host-browse', folder, query], enabled: !!folder, retry: false, queryFn: () => browseHost(folder, query) })
  const folders = useQuery({ queryKey: ['host-approved-folders'], enabled: manage, queryFn: approvedFolders })
  useEffect(() => { setTyped(folder); setConfirm(false) }, [folder])
  const open = (path: string) => { setFolder(path); setQuery(''); setNotice('') }
  const entries = useMemo(() => {
    const list = [...(listing.data?.entries ?? [])]
    const factor = descending ? -1 : 1
    return list.sort((a, b) => a.kind !== b.kind ? (a.kind === 'directory' ? -1 : 1)
      : sort === 'size' ? factor * ((a.size ?? 0) - (b.size ?? 0)) : sort === 'modified' ? factor * (Date.parse(a.modified ?? '') - Date.parse(b.modified ?? '')) : factor * a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }))
  }, [listing.data, sort, descending])
  const go = (event: FormEvent) => {
    event.preventDefault()
    const value = typed.trim()
    if (!value) return
    if (value.toLowerCase().endsWith('.csv')) { setSelected(value); open(parentFolder(value)) } else open(value)
  }
  const approve = async () => {
    setApproving(true); setNotice('')
    try { const result = await approveFolder(folder); setNotice(`Approved ${result.path} for browsing and source selection.`); await Promise.all([client.invalidateQueries({ queryKey: ['host-locations'] }), client.invalidateQueries({ queryKey: ['host-approved-folders'] })]); await listing.refetch() }
    catch (cause) { setNotice(cause instanceof Error ? cause.message : 'The folder could not be approved.') }
    finally { setApproving(false); setConfirm(false) }
  }
  const revoke = async (path: string) => {
    try { await revokeFolder(path); await Promise.all([client.invalidateQueries({ queryKey: ['host-locations'] }), client.invalidateQueries({ queryKey: ['host-approved-folders'] })]); setNotice(`${path} is no longer approved. Sources below it need exact authorization; their data is unchanged.`) }
    catch (cause) { setNotice(cause instanceof Error ? cause.message : 'The folder could not be removed.') }
  }
  const host = locations.data?.host || listing.data?.host || 'the AuthLens server'
  const failure = listing.error ? category(listing.error) : undefined
  const header = (key: Sort, label: string) => <th scope="col" aria-sort={sort === key ? (descending ? 'descending' : 'ascending') : 'none'}><button type="button" className="host-file-sort" onClick={() => { if (sort === key) setDescending(!descending); else { setSort(key); setDescending(false) } }}>{label}</button></th>
  return (
    <Dialog title="Select a file on the AuthLens host" onClose={onCancel}
      description={`Browsing ${host} as the AuthLens service. Files on your own device are uploaded with "Upload from this device" instead.`}
      footer={<>
        <Button onClick={onCancel}>Cancel</Button>
        <Button variant="primary" disabled={!selected} onClick={() => onSelect(selected)}>Select</Button>
      </>}>
      <div className="host-file-picker">
        <nav aria-label="Host locations" className="host-file-locations">
          <p className="host-file-host"><Server size={16} aria-hidden="true" /><strong>{host}</strong></p>
          {locations.isLoading ? <LoadingState /> : locations.isError ? <p role="alert">Host locations could not be loaded.</p> :
            !locations.data?.locations.length ? <p className="ui-description">No folder is approved for browsing yet. Enter a folder path below; an administrator can approve it.</p> :
            <ul>{locations.data.locations.map(location => <li key={location.path}>
              <button type="button" className="host-file-location" aria-current={folder === location.path ? 'location' : undefined} title={location.path} onClick={() => open(location.path)}>
                {location.network ? <Network size={16} aria-hidden="true" /> : <HardDrive size={16} aria-hidden="true" />}<span>{location.name}</span>
                <small>{location.kind === 'operator' ? 'Operator folder' : location.kind === 'approved' ? 'Approved folder' : 'Configured source'}</small>
              </button></li>)}</ul>}
          <Button size="compact" variant="ghost" aria-expanded={manage} onClick={() => setManage(!manage)}><FolderCheck size={14} aria-hidden="true" />Approved folders</Button>
          {manage && <div className="grid gap-2" aria-label="Approved folders">
            {folders.data?.approved.length ? <ul className="grid gap-1">{folders.data.approved.map(path => <li key={path} className="flex min-w-0 items-center gap-2"><span className="host-file-path" title={path}>{path}</span><IconButton label={`Remove approval of ${path}`} onClick={() => void revoke(path)}><Trash2 size={14} /></IconButton></li>)}</ul> : <p className="ui-description">No administrator-approved folders.</p>}
            {!!folders.data?.operator_roots.length && <p className="ui-description">Operator folders (server configuration): {folders.data.operator_roots.join(', ')}</p>}
            <p className="ui-description">Approval lets AuthLens list and read CSV files below a folder. Windows NTFS and share permissions for the service identity are still required and are never changed by AuthLens.</p>
          </div>}
        </nav>
        <section className="host-file-main" aria-label="Folder contents">
          <form className="host-file-address" onSubmit={go}>
            <IconButton label="Parent folder" disabled={!listing.data?.parent} onClick={() => listing.data?.parent && open(listing.data.parent)}><ArrowUp size={16} /></IconButton>
            <FormField label="Folder or file path"><Input value={typed} maxLength={4096} spellCheck={false} autoCapitalize="off" autoCorrect="off" placeholder="D:\Exports or \\fileserver\share\exports" onChange={event => setTyped(event.target.value)} /></FormField>
            <Button type="submit" size="compact" disabled={!typed.trim()}>Open</Button>
            {folder && <IconButton label="Reload folder" onClick={() => void listing.refetch()}><RefreshCw size={16} /></IconButton>}
          </form>
          {listing.data && <nav aria-label="Folder path" className="host-file-breadcrumbs"><ol>{listing.data.breadcrumbs.map((crumb, index) => <li key={crumb.path}>
            {index > 0 && <ChevronRight size={14} aria-hidden="true" />}
            <button type="button" aria-current={crumb.path === listing.data.path ? 'page' : undefined} onClick={() => open(crumb.path)}>{crumb.name}</button></li>)}</ol>
            {listing.data.network && <StatusBadge tone="info">Network folder</StatusBadge>}</nav>}
          {folder && <SearchInput aria-label="Search this folder" placeholder="Search file names in this folder" value={query} onChange={event => setQuery(event.target.value)} onClear={() => setQuery('')} />}
          {notice && <p role="status" className="ui-description">{notice}</p>}
          {!folder ? <EmptyState>Choose a location or enter a folder path on {host}.</EmptyState>
            : listing.isLoading ? <LoadingState>Reading the folder on the AuthLens host…</LoadingState>
            : listing.isError ? <Problem error={listing.error} category={failure} folder={folder} confirm={confirm} setConfirm={setConfirm} approving={approving} onApprove={() => void approve()} />
            : listing.data && <FileList listing={listing.data} entries={entries} selected={selected} header={header} onOpen={open} onSelect={setSelected} onChoose={path => onSelect(path)} />}
          {selected && <p className="host-file-selected" role="status"><FileSpreadsheet size={16} aria-hidden="true" />Selected: <span className="host-file-path" title={selected}>{selected}</span>{isNetworkPath(selected) && <StatusBadge tone="info">Network file</StatusBadge>}</p>}
        </section>
      </div>
    </Dialog>
  )
}

function FileList({ listing, entries, selected, header, onOpen, onSelect, onChoose }: { listing: HostListing; entries: HostEntry[]; selected: string; header: (key: Sort, label: string) => JSX.Element; onOpen: (path: string) => void; onSelect: (path: string) => void; onChoose: (path: string) => void }) {
  if (!entries.length) return <EmptyState>No folders or CSV files here.</EmptyState>
  return <div className="host-file-list" role="region" aria-label={`Contents of ${listing.path}`} tabIndex={0}>
    <table>
      <thead><tr>{header('name', 'Name')}{header('size', 'Size')}{header('modified', 'Modified')}</tr></thead>
      <tbody>{entries.map(entry => {
        const picked = entry.path === selected
        return <tr key={entry.path} data-selected={picked || undefined} aria-selected={entry.kind === 'file' ? picked : undefined}>
          <td>
            <button type="button" className="host-file-entry" disabled={entry.kind === 'file' && !entry.supported}
              aria-label={entry.kind === 'directory' ? `Open folder ${entry.name}` : `Select file ${entry.name}`}
              onClick={() => entry.kind === 'directory' ? onOpen(entry.path) : onSelect(entry.path)}
              onDoubleClick={() => entry.kind === 'file' && entry.supported && onChoose(entry.path)}>
              {entry.kind === 'directory' ? <Folder size={16} aria-hidden="true" /> : entry.supported ? <FileSpreadsheet size={16} aria-hidden="true" /> : <FileX size={16} aria-hidden="true" />}
              <span className="host-file-name">{entry.name}</span>
            </button>
          </td>
          <td className="host-file-size">{size(entry.size)}</td>
          <td className="host-file-modified">{entry.modified ? formatTimestamp(entry.modified) : ''}</td>
        </tr>
      })}</tbody>
    </table>
    {listing.truncated && <p className="ui-description">Only the first 2,000 entries are shown; search to narrow the list.</p>}
  </div>
}

function Problem({ error, category, folder, confirm, setConfirm, approving, onApprove }: { error: unknown; category?: string; folder: string; confirm: boolean; setConfirm: (value: boolean) => void; approving: boolean; onApprove: () => void }) {
  const message = error instanceof Error ? error.message.split(' Reference:')[0] : 'The folder could not be read.'
  if (category !== 'not_approved') return <div role="alert" className="host-file-problem"><p>{message}</p>{category === 'access_denied' && <p className="ui-description">Application approval and Windows permissions are separate: the folder must also grant the AuthLens service identity read access.</p>}</div>
  return <div role="alert" className="host-file-problem">
    <p>{message}</p>
    <Checkbox checked={confirm} onChange={event => setConfirm(event.target.checked)}>I approve AuthLens to list and read CSV files below <strong>{folder}</strong>{isNetworkPath(folder) ? ' and to connect to this network share with its service identity' : ''}. I control this location and who can write to it.</Checkbox>
    <Button variant="primary" size="compact" loading={approving} disabled={!confirm} onClick={onApprove}>Approve folder</Button>
  </div>
}
