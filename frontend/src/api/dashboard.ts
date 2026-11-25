import { apiRequest } from './client'

export interface FilterOption { value: string; count: number }
/** Values present in the current validated snapshot (GET /api/dashboard/filter-options). Directory dimensions list only matched identities. */
export interface DashboardFilterOptions {
  user_groups: FilterOption[]; user_types: FilterOption[]; account_states: FilterOption[]
  departments: FilterOption[]; sites: FilterOption[]; titles: FilterOption[]; ad_states: FilterOption[]
  lock_states: FilterOption[]; roles: FilterOption[]; tcodes: FilterOption[]; role_types: FilterOption[]; org_suffixes: FilterOption[]
  sod_risks: FilterOption[]; review_states: FilterOption[]
  directory_available: boolean; matched_identities: number; sod_available: boolean
}
export const dashboardFilterOptionsKey = ['dashboard-filter-options'] as const
export const fetchDashboardFilterOptions = () => apiRequest<DashboardFilterOptions>('/api/dashboard/filter-options')
