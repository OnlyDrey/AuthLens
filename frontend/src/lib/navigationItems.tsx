import type { ReactNode } from 'react'
import { Activity, Archive, ArrowRightLeft, CalendarRange, ClipboardCheck, FileCheck2, FileSpreadsheet, FileText, GitCompare, Grid3x3, LayoutDashboard, ListChecks, Search, ShieldCheck, Users, Wrench } from 'lucide-react'
import type { ReportsView, ReviewsView, SodView } from '@/hooks/useViewHistory'

/** One definition of the pages inside a module, shared by the main-navigation submenu and the secondary navigation, so labels, icons and order never diverge. */
/** Users pages (NAV-2): User Directory and Compare Users are views of the Users page; Release Access is its own page (`releases`) in this module. */
export type UsersNavigation = 'directory' | 'compare' | 'release-access'
export const USERS_VIEWS: { value: UsersNavigation; label: string; icon: ReactNode }[] = [
  { value: 'directory', label: 'User Directory', icon: <Users size={16} aria-hidden="true" /> },
  { value: 'compare', label: 'Compare Users', icon: <GitCompare size={16} aria-hidden="true" /> },
  { value: 'release-access', label: 'Release Access', icon: <FileCheck2 size={16} aria-hidden="true" /> },
]
export const SOD_VIEWS: { value: SodView; label: string; icon: ReactNode }[] = [
  { value: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} aria-hidden="true" /> },
  { value: 'risk-matrix', label: 'Risk Matrix', icon: <Grid3x3 size={16} aria-hidden="true" /> },
  { value: 'activity-matrix', label: 'Activity Matrix', icon: <Activity size={16} aria-hidden="true" /> },
  { value: 'explorer', label: 'Access Explorer', icon: <Search size={16} aria-hidden="true" /> },
]
/** Reviews workspace pages, in the approved order (NAV-3). `sod` marks pages backed by SoD evidence (access reviews); they follow the SoD feature
 *  switch. The Overview, Position Changes and Account Review do not: account reviews never depend on SoD. */
export const REVIEWS_VIEWS: { value: Exclude<ReviewsView, 'reports'>; label: string; icon: ReactNode; sod?: true }[] = [
  { value: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} aria-hidden="true" /> },
  { value: 'queue', sod: true, label: 'Work Queue', icon: <ListChecks size={16} aria-hidden="true" /> },
  { value: 'position-changes', label: 'Position Changes', icon: <ArrowRightLeft size={16} aria-hidden="true" /> },
  { value: 'account-review', label: 'Account Review', icon: <ClipboardCheck size={16} aria-hidden="true" /> },
  { value: 'bulk', sod: true, label: 'Bulk Review', icon: <ClipboardCheck size={16} aria-hidden="true" /> },
  { value: 'remediation', sod: true, label: 'Remediation', icon: <Wrench size={16} aria-hidden="true" /> },
  { value: 'periods', sod: true, label: 'Review Periods', icon: <CalendarRange size={16} aria-hidden="true" /> },
]
/** The Reviews pages available with the current feature switches: SoD access-review pages only while SoD is enabled. */
export const availableReviewsViews = (sodEnabled: boolean) => REVIEWS_VIEWS.filter(view => sodEnabled || !view.sod)
/** Reports pages (NAV-4), in the approved order. Which pages an account sees comes from the report availability endpoint. */
export const REPORTS_NAVIGATION: { value: ReportsView; label: string; icon: ReactNode }[] = [
  { value: 'review', label: 'Review Reports', icon: <FileText size={16} aria-hidden="true" /> },
  { value: 'access', label: 'Access Reports', icon: <FileSpreadsheet size={16} aria-hidden="true" /> },
  { value: 'sod', label: 'SoD Reports', icon: <ShieldCheck size={16} aria-hidden="true" /> },
  { value: 'evidence', label: 'Evidence', icon: <Archive size={16} aria-hidden="true" /> },
]
