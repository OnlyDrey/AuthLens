import type { ReactNode } from 'react'
import { Activity, CalendarRange, ClipboardCheck, FileText, GitCompare, Grid3x3, LayoutDashboard, ListChecks, Search, Users, Wrench } from 'lucide-react'
import type { ReviewsView, SodView } from '@/hooks/useViewHistory'

/** One definition of the pages inside a module, shared by the main-navigation submenu and the secondary navigation, so labels, icons and order never diverge. */
export const USER_ACCESS_VIEWS: { value: 'directory' | 'review' | 'compare'; label: string; icon: ReactNode }[] = [
  { value: 'directory', label: 'User directory', icon: <Users size={16} aria-hidden="true" /> },
  { value: 'review', label: 'Account Review', icon: <ClipboardCheck size={16} aria-hidden="true" /> },
  { value: 'compare', label: 'Compare users', icon: <GitCompare size={16} aria-hidden="true" /> },
]
export const SOD_VIEWS: { value: SodView; label: string; icon: ReactNode }[] = [
  { value: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} aria-hidden="true" /> },
  { value: 'risk-matrix', label: 'Risk Matrix', icon: <Grid3x3 size={16} aria-hidden="true" /> },
  { value: 'activity-matrix', label: 'Activity Matrix', icon: <Activity size={16} aria-hidden="true" /> },
  { value: 'explorer', label: 'Access Explorer', icon: <Search size={16} aria-hidden="true" /> },
]
/** Access-review governance pages. Review decisions, periods and reports moved here from SoD; old SoD links redirect. */
export const REVIEWS_VIEWS: { value: ReviewsView; label: string; icon: ReactNode }[] = [
  { value: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} aria-hidden="true" /> },
  { value: 'queue', label: 'Work Queue', icon: <ListChecks size={16} aria-hidden="true" /> },
  { value: 'bulk', label: 'Bulk Review', icon: <ClipboardCheck size={16} aria-hidden="true" /> },
  { value: 'remediation', label: 'Remediation', icon: <Wrench size={16} aria-hidden="true" /> },
  { value: 'periods', label: 'Review Periods', icon: <CalendarRange size={16} aria-hidden="true" /> },
  { value: 'reports', label: 'Reports and Evidence', icon: <FileText size={16} aria-hidden="true" /> },
]
