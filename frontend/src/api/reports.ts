import { useQuery } from '@tanstack/react-query'
import { apiRequest } from './client'
import type { ReportsView } from '@/hooks/useViewHistory'

/** A column of a configurable CSV report, as the backend report catalogue defines it. */
export interface ReportColumn { key: string; label: string; required: boolean; default: boolean }
/** One report of the backend catalogue (`GET /api/reports/availability`), with its availability for the signed-in account. */
export interface ReportDefinition {
  id: string; page: ReportsView; title: string; description: string; formats: string[]; contexts: string[]
  available: boolean; reason: string | null; columns: ReportColumn[] | null
}
export interface ReportAvailability { pages: ReportsView[]; reports: ReportDefinition[]; sod_enabled: boolean }

export const fetchReportAvailability = () => apiRequest<ReportAvailability>('/api/reports/availability')

/** NAV-4: report pages and reports the account may use, from the backend (existing permissions, the SoD switch and loaded data). Reports never depend
 *  on the SoD switch as a module: only SoD reports do. The navigation hides Reports when no page is available. */
export function useReportAvailability(): { pages: ReportsView[]; reports: ReportDefinition[]; loading: boolean } {
  const query = useQuery({ queryKey: ['report-availability'], queryFn: fetchReportAvailability, staleTime: 30_000 })
  return { pages: query.data?.pages ?? [], reports: query.data?.reports ?? [], loading: query.isLoading }
}
