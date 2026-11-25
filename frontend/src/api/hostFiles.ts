import { apiRequest } from './client'

/** WP33 host file picker: folders and CSV files on the AuthLens server, listed by the service identity inside approved folders only. */
export interface HostEntry { name: string; path: string; kind: 'directory' | 'file'; size: number | null; modified: string | null; supported: boolean }
export interface HostListing { host: string; path: string; root: string; parent: string | null; breadcrumbs: { name: string; path: string }[]; entries: HostEntry[]; truncated: boolean; network: boolean }
export interface HostLocation { name: string; path: string; kind: 'operator' | 'approved' | 'configured'; network: boolean }
export interface HostLocations { host: string; locations: HostLocation[] }
export interface ApprovedFolders { approved: string[]; operator_roots: string[]; max: number }

export const hostLocations = () => apiRequest<HostLocations>('/api/server/sources/browse')
export const browseHost = (path: string, query = '', all = false) =>
  apiRequest<HostListing>(`/api/server/sources/browse?${new URLSearchParams({ path, ...(query ? { q: query } : {}), ...(all ? { all: 'true' } : {}) })}`)
export const approvedFolders = () => apiRequest<ApprovedFolders>('/api/server/sources/roots')
export const approveFolder = (path: string) => apiRequest<{ approved: boolean; path: string }>('/api/server/sources/roots', 'POST', { path, approve_folder_access: true })
export const revokeFolder = (path: string) => apiRequest<{ revoked: boolean }>(`/api/server/sources/roots?${new URLSearchParams({ path })}`, 'DELETE')

/** Local or network, detected from the path itself; the workflow is the same for both. */
export const isNetworkPath = (path: string) => /^(\\\\|\/\/)/.test(path.trim())
export const parentFolder = (path: string) => { const trimmed = path.trim().replace(/[\\/]+$/, ''); const at = Math.max(trimmed.lastIndexOf('\\'), trimmed.lastIndexOf('/')); return at > 0 ? trimmed.slice(0, at) : '' }
