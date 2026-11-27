import {useSodSubject,useSodContext} from '@/components/Sod/SodShared'
import { MainNavigation, MainNavigationGroup, MainNavigationItem } from '@/components/Shared/Navigation'
import { availableReviewsViews, REPORTS_NAVIGATION, SOD_VIEWS, USERS_VIEWS } from '@/lib/navigationItems'
import { pageHref, reportsHref, reviewsHref, sodHref, usersHref, useHistoryValue, useViewHistory } from '@/hooks/useViewHistory'
import { useReportAvailability } from '@/api/reports'
import { DISCARD_PROMPT, settingsDirty } from '@/lib/settingsGuard'
import { lazy, Suspense, useState, useCallback, useRef, useLayoutEffect } from 'react'
import { LoadingState } from '@/components/Shared/Presentation'
import { AppLayout } from '@/components/Layout/AppLayout'
import { RoleList } from '@/components/RoleList/RoleList'
import { RoleDetailPanel } from '@/components/RoleDetail/RoleDetailPanel'
import { ComparisonView } from '@/components/RoleComparison/ComparisonView'
import { MappingAvailability } from '@/components/Access/MappingAvailability'
import { UserAccess } from '@/components/Access/UserAccess'
import { ReleaseRoles } from '@/components/Access/ReleaseRoles'
import { Search, Users, FileText, LayoutDashboard, ShieldCheck, ClipboardList } from 'lucide-react'
import { Dashboard } from '@/components/Dashboard'
import { useTheme } from '@/hooks/useTheme'
import { useQuery } from '@tanstack/react-query'
import { fetchConfiguration } from '@/api/configuration'

// SoD is a large, occasionally visited area: it loads on first use instead of with the application shell.
const SodWorkspace = lazy(() => import('@/components/Sod/SodWorkspace').then((module) => ({ default: module.SodWorkspace })))
const ReviewsWorkspace = lazy(() => import('@/components/Reviews/ReviewsWorkspace').then((module) => ({ default: module.ReviewsWorkspace })))
const ReportsWorkspace = lazy(() => import('@/components/Reports/ReportsWorkspace').then((module) => ({ default: module.ReportsWorkspace })))
const SodInvestigation = lazy(() => import('@/components/Sod/SodInvestigation').then((module) => ({ default: module.SodInvestigation })))

export function App() {
  const { isDark, toggle } = useTheme()
  const [subject,setSubject]=useSodSubject(), [sodContext]=useSodContext()
  const [page] = useHistoryValue('page')
  const [settingsOpen] = useHistoryValue('settings')
  const [kpiNavigation] = useHistoryValue('kpiNavigation')
  const [catalogueArea] = useHistoryValue('catalogueArea')
  const { change } = useViewHistory()
  const configuration = useQuery({ queryKey: ['configuration'], queryFn: fetchConfiguration })
  // Unknown (still loading or unreadable) keeps the entry; only an explicit saved "off" hides it.
  const sodEnabled = configuration.data?.settings.features?.sod !== false
  // NAV-4: report pages this account may use (availability per report, independent of the SoD switch); Reports is hidden when there is none.
  const reportPages = useReportAvailability().pages
  const [visited, setVisited] = useState(() => new Set([page]))
  const scrollPositions = useRef<Record<string, number>>({})
  // BUG-08: main navigation is a page boundary. Each visit through it opens the page fresh: pages kept mounted are remounted (their search and
  // temporary filters reset) and the page's temporary filter state in the view history is cleared. Saved Filters stay stored and can be applied
  // again. Contextual navigation (Dashboard tiles, Open in Reviews, user or role links) carries its explicit destination context through
  // change() and is unaffected; Back and Forward restore the history entry they return to. Panels, modals, paging, sorting, refreshes, review
  // decisions and theme changes never pass this boundary.
  const [visits, setVisits] = useState<Record<string, number>>({})
  const freshPage = (next: string, force = false): Record<string, unknown> => {
    // Views of one module (Users pages including Release Access; SoD and Reviews as one review workspace) share their filters by design: only a module change resets.
    const workspace = (value: string) => value === 'sod' || value === 'reviews' ? 'review' : value === 'releases' ? 'users' : value
    // A main-navigation link is a boundary (`force`): it opens the landing page fresh, also from another page of the same module. The review workspace
    // (SoD and Reviews) is the exception by design: its filters, subject and review context are shared, so moving between them never changes scope.
    if ((!force || workspace(next) === 'review') && workspace(page) === workspace(next) && !settingsOpen) return {}
    setVisits(previous => ({ ...previous, [next]: (previous[next] || 0) + 1 }))
    return next === 'roles' ? { catalogueArea: undefined }
      : next === 'users' ? { accessSubjectFilters: undefined, accountReviewFilters: undefined, userComparison: undefined, reviewFindings: undefined, assignmentBand: undefined, user: '', userContext: {}, userTrail: [] }
      : next === 'releases' ? { release: null, releaseContext: '', accessSubjectFilters: undefined }
      : next === 'sod' || next === 'reviews' ? { sodFilters: undefined, sodExplorer: undefined, bulkSelectMatching: undefined, accountReviewFilters: undefined, reviewFindings: undefined }
      : {}
  }
  const navigate = (next: 'dashboard'|'roles'|'users'|'releases'|'sod'|'reviews'|'reports') => { scrollPositions.current[page] = window.scrollY; scrollPositions.current[next] = 0; setVisited(previous => new Set([...previous, next])); change({page:next, detailRole:null, settings:false, ...freshPage(next)} as never) }
  const [accessMode] = useHistoryValue('accessMode'), [sodView] = useHistoryValue('sodView'), [reviewsView] = useHistoryValue('reviewsView'), [reportsView] = useHistoryValue('reportsView')
  /** A submenu entry opens one page of a module; unsaved Settings edits are confirmed first, like every other destination. */
  const openPage = (next: 'users' | 'releases' | 'sod' | 'reviews' | 'reports', patch: Record<string, unknown>, fresh = false) => { if (settingsDirty() && !window.confirm(DISCARD_PROMPT)) return; scrollPositions.current[page] = window.scrollY; setVisited(previous => new Set([...previous, next])); change({ page: next, detailRole: null, settings: false, ...freshPage(next, fresh), ...patch } as never) }
  const submenus = {
    users: USERS_VIEWS.map(({ value, label, icon }) => ({ value, label, icon, href: usersHref(value),
      active: !settingsOpen && (value === 'release-access' ? page === 'releases' : page === 'users' && (accessMode === 'compare' ? 'compare' : 'directory') === value),
      onSelect: () => value === 'release-access' ? openPage('releases', { release: null, releaseContext: '' }) : openPage('users', { accessMode: value, user: '', userContext: {} }) })),
    sod: SOD_VIEWS.map(({ value, label, icon }) => ({ value, label, icon, href: sodHref(value), active: page === 'sod' && !settingsOpen && (sodView || 'overview') === value, onSelect: () => openPage('sod', { sodView: value }) })),
    reviews: availableReviewsViews(sodEnabled).map(({ value, label, icon }) => ({ value, label, icon, href: reviewsHref(value), active: page === 'reviews' && !settingsOpen && (reviewsView || 'overview') === value, onSelect: () => openPage('reviews', { reviewsView: value, user: '' }) })),
    reports: REPORTS_NAVIGATION.filter(item => reportPages.includes(item.value)).map(({ value, label, icon }) => ({ value, label, icon, href: reportsHref(value), active: page === 'reports' && !settingsOpen && reportsView === value, onSelect: () => openPage('reports', { reportsView: value }) })),
  } as const
  /** Settings stay open until the destination is confirmed when they hold unsaved edits. */
  /** NAV-1: a main-navigation link always opens its module's default landing page, never the last visited subpage: Users the User Directory, SoD and
   *  Reviews their Overview, Reports its first authorized report page (Review Reports when available). BUG-08 still applies: crossing into another
   *  module opens it fresh. Contextual links and Back/Forward keep their own destination. */
  const go = (next: 'dashboard'|'roles'|'users'|'sod'|'reviews'|'reports') => {
    if (next === 'dashboard' || next === 'roles') { if (settingsDirty() && !window.confirm(DISCARD_PROMPT)) return; navigate(next); return }
    openPage(next, next === 'users' ? { accessMode: 'directory', user: '', userContext: {} } : next === 'sod' ? { sodView: 'overview' } : next === 'reviews' ? { reviewsView: 'overview', user: '' } : { reportsView: reportPages[0] }, true)
  }
  useLayoutEffect(() => { setVisited(previous => new Set([...previous, page])); window.scrollTo(0, scrollPositions.current[page] || 0) }, [page])
  const [userContext] = useHistoryValue('userContext')
  const [selectedUser] = useHistoryValue('user')
  const [releaseDrill] = useHistoryValue('release')
  const [releaseContext] = useHistoryValue('releaseContext')
  const investigateUsers = (filter:{user?:string;role?:string;tcode?:string}) => { setVisited(previous => new Set([...previous, 'users'])); change({accessMode:'directory',page:'users', user:filter.user || '', userContext:{role:filter.role,tcode:filter.tcode},detailRole:null,settings:false}) }
  const investigateRelease = (release:string) => { setVisited(previous => new Set([...previous, 'releases'])); change({page:'releases', release:{role:release,status:'all'},releaseContext:release,detailRole:null,settings:false}) }
  const [catalogueOrder, setCatalogueOrder] = useState<string[]>([])
  const [selectedRoles, setSelectedRoles] = useState<string[]>([])
  const [detailRole, setDetailRole] = useHistoryValue('detailRole')
  const [showComparison, setShowComparison] = useHistoryValue('comparison')
  const [dataGeneration,setDataGeneration] = useState(0)

  const handleSelectRole = useCallback((name: string) => {
    setSelectedRoles(prev =>
      prev.includes(name) ? prev.filter(r => r !== name) : prev.length >= 5 ? prev : [...prev, name]
    )
  }, [])

  const cataloguePosition = detailRole ? catalogueOrder.indexOf(detailRole) : -1
  const catalogueNavigation = {
    index: cataloguePosition,
    total: catalogueOrder.length,
    onPrevious: cataloguePosition > 0 ? () => setDetailRole(catalogueOrder[cataloguePosition - 1]) : undefined,
    onNext: cataloguePosition >= 0 && cataloguePosition + 1 < catalogueOrder.length ? () => setDetailRole(catalogueOrder[cataloguePosition + 1]) : undefined,
    missing: cataloguePosition < 0,
  }

  return (
    <AppLayout
      navigation={<>
      <MainNavigation>
        {([['dashboard','Dashboard',LayoutDashboard],['roles','Role Lookup',Search],['users','Users',Users],['sod','SoD',ShieldCheck],['reviews','Reviews',ClipboardList],['reports','Reports',FileText]] as const)
          // Reviews stays without SoD (Account Review and Position Changes do not depend on it); Reports appears when the account may use any report.
          .filter(([key])=>(key!=='sod'||sodEnabled)&&(key!=='reports'||reportPages.length>0))
          .map(([key,label,Icon])=>{const props={label,icon:<Icon size={17} aria-hidden="true"/>,active:(page===key||(key==='users'&&page==='releases'))&&!settingsOpen,href:pageHref(key),onNavigate:()=>go(key)};return key==='users'||key==='sod'||key==='reviews'||key==='reports'?<MainNavigationGroup key={key} {...props} items={[...submenus[key]]}/>:<MainNavigationItem key={key} {...props}/>})}
      </MainNavigation>
      </>}
      onDataChanged={() => {
        setDataGeneration(value=>value+1)
        setSelectedRoles([])
        setDetailRole(null)
        setShowComparison(false)
      }}
      isDark={isDark}
      onToggleTheme={toggle}>
      {page === 'dashboard' && <Dashboard/>}
      {page === 'sod' && <Suspense fallback={<LoadingState/>}><SodWorkspace key={visits.sod || 0}/></Suspense>}
      {page === 'reviews' && <Suspense fallback={<LoadingState/>}><ReviewsWorkspace key={visits.reviews || 0}/></Suspense>}
      {page === 'reports' && <Suspense fallback={<LoadingState/>}><ReportsWorkspace key={visits.reports || 0}/></Suspense>}
      {visited.has('roles') && <div className={page==='roles'?'':'hidden'}>
      {showComparison
        ? <ComparisonView roleNames={selectedRoles} onBack={() => setShowComparison(false)} onRemove={name => setSelectedRoles(previous => previous.length > 2 ? previous.filter(role => role !== name) : previous)} />
        : <RoleList key={`${dataGeneration}:${kpiNavigation?.roles || 0}:${visits.roles || 0}`}
            initialArea={catalogueArea}
            onFilteredRoles={setCatalogueOrder}
            selectedRoles={selectedRoles}
            onSelectRole={handleSelectRole}
            onViewDetail={n => setDetailRole(n)}
            onCompare={() => { if (selectedRoles.length >= 2) { setShowComparison(true); setDetailRole(null) } }}
          />
      }
      </div>}
      {visited.has('users') && <div hidden={page!=='users'}><MappingAvailability><UserAccess key={`${JSON.stringify(userContext)}:${kpiNavigation?.users || 0}:${visits.users || 0}`} initialUser={selectedUser} initialRole={userContext.role} initialTcode={userContext.tcode} onRole={setDetailRole} onRelease={investigateRelease}/></MappingAvailability></div>}
      {visited.has('releases') && <div hidden={page!=='releases'}><MappingAvailability><ReleaseRoles key={`${releaseContext}:${kpiNavigation?.releases || 0}:${visits.releases || 0}`} initialRole={releaseDrill?.role || ''} onUser={user=>investigateUsers({user})}/></MappingAvailability></div>}
      {sodEnabled&&subject&&!detailRole&&!settingsOpen&&<Suspense fallback={null}><SodInvestigation context={sodContext} user={subject.user} risk={subject.risk} activity={subject.activity} role={subject.role} onClose={()=>setSubject(null)} onScope={setSubject}/></Suspense>}
      <RoleDetailPanel navigation={page === 'roles' && detailRole ? catalogueNavigation : undefined} parent={page === 'sod' ? 'SoD' : page === 'reviews' ? 'Reviews' : page === 'reports' ? 'Reports' : page === 'users' ? 'Users' : page === 'releases' ? 'Release Access' : 'Role Lookup'} roleName={detailRole} onClose={() => setDetailRole(null)} onUsers={role=>investigateUsers({role})} onTcodeUsers={tcode=>investigateUsers({tcode})}/>
    </AppLayout>
  )
}