import { createContext, useContext, useEffect, useState, type ReactNode, type SetStateAction } from 'react'
import type { AssignmentPick } from '@/api/sod'

export type ReleaseDrill = {functional_groups?:string[];managers?:string[];usernames?:string[]; status?: string; username?: string; role_search?: string; ungrouped?: boolean; role?: string; group?: string; user_groups?: string[]; document_type?: string; release_group?: string; strategy?: string; /** NAV-6 matrix totals: parsed release roles with the matrix filters */ parsed?: boolean; strategies?: string[]; release_groups?: string[]; release_areas?: string[] }
export type SodFilterState = Record<string,string|boolean|number|string[]>
/** SoD analysis pages. 'reviews', 'periods' and 'reports' are legacy values kept for old bookmarks and callers; they are normalized to the Reviews workspace. */
export type SodView = 'overview'|'risk-matrix'|'activity-matrix'|'explorer'|'reviews'|'periods'|'reports'
/** Pages of the first-class Reviews workspace (same review engine, decisions and periods as before). Account Review and Position Changes moved here
 *  from User Access (NAV-3); 'reports' is a legacy value kept for old bookmarks and callers and is normalized to the Reports module (NAV-1). */
export type ReviewsView = 'overview'|'queue'|'position-changes'|'account-review'|'bulk'|'remediation'|'periods'|'reports'
const REVIEWS_VIEWS: ReviewsView[] = ['overview','queue','position-changes','account-review','bulk','remediation','periods','reports']
/** Pages of the Reports module (NAV-4). Without a page, the module opens its first report page the account may use. */
export type ReportsView = 'review'|'access'|'sod'|'evidence'
export const REPORTS_VIEWS: ReportsView[] = ['review','access','sod','evidence']
/** Users pages (NAV-2). The view-history values 'review' and 'positions' are legacy (those pages moved to Reviews) and are normalized. */
export type UsersMode = 'directory'|'compare'
type Page = 'dashboard' | 'roles' | 'users' | 'releases' | 'sod' | 'reviews' | 'reports'
export type SodExplorerTable = 'user_risk'|'user_activity'|'access_list'|'lookup'|'roles'
type View = { accessSubjectFilters?:{functional_groups:string[];managers:string[];usernames:string[]};bulkSelectMatching?:boolean; /** NAV-8: the exact assignments selected in Access Explorer, handed to Bulk Review once */ bulkPicks?:AssignmentPick[];userTrail?:string[]; sodView?:SodView; reviewsView?:ReviewsView; reportsView?:ReportsView; sodFilters?:Record<string,SodFilterState>; sodContext?:string; sodSubject?:{user:string;risk?:string;activity?:string;role?:string}|null; sodExplorer?:SodExplorerTable; sodReviews?:'queue'|'bulk'|'remediation'; /** Work Queue user-progress filter (WP37 drill-down from the Reviews Overview). */ queueProgress?:''|'outstanding'|'complete'|'removal'; assignmentBand?:string; catalogueArea?:string; accountReviewFilters?:{search:string;licenses:string[];states:string[];sort:string;descending:boolean;groups?:string[];managers?:string[];usernames?:string[]}; userComparison?:{sort?:string;descending?:boolean;a:string;b:string;validity:string;kind:string;difference:string;search:string;areas:string[]}; accessMode?: 'directory'|'review'|'positions'|'compare'; reviewFindings?: string[]; kpiNavigation?: Partial<Record<'roles'|'users'|'releases',number>>; settingsTarget?: 'roles' | 'users' | 'employees' | 'sod' | 'diagnostics' | 'features'; page: Page; user: string; release: ReleaseDrill | null; detailRole: string | null; comparison: boolean; settings: boolean; releaseContext: string; userContext: { role?: string; tcode?: string } }
/** Canonical first path segments per page (NAV-1). Release Access is a Users page: `#/users/release-access`. */
const paths = { dashboard: 'dashboard', roles: 'role-lookup', users: 'users', releases: 'users/release-access', sod:'sod', reviews:'reviews', reports:'reports' }
/** Legacy first segments that still open their page (bookmarks and deep links from before NAV-1). */
const legacyPaths: Record<string, Page> = { 'user-access': 'users', 'release-roles': 'releases' }
const defaults: View = { page: 'dashboard', user: '', release: null, detailRole: null, comparison: false, settings: false, releaseContext: '', userContext: {} }
/** Canonical Users routes (NAV-2). */
export function usersHref(mode:UsersMode|'release-access'='directory') {return '#/users'+(mode==='directory'?'':`/${mode}`)}
/** Earlier User Access destinations, resolved to their canonical routes (Account Review and Position Changes are Reviews pages). */
export function userAccessHref(mode:'directory'|'review'|'positions'|'compare') {return mode==='review'?reviewsHref('account-review'):mode==='positions'?reviewsHref('position-changes'):usersHref(mode)}
/** Direct link to one SAP user in Users; the same route is produced when a user is opened in the app. */
export function userHref(username:string){return '#/users/user/'+encodeURIComponent(username)}
export function pageHref(page:Page){return page==='users'?usersHref('directory'):page==='sod'?sodHref('overview'):page==='reviews'?reviewsHref('overview'):page==='reports'?'#/reports':`#/${paths[page]}`}
/** Legacy SoD review pages resolve to their Reviews or Reports route, so existing links keep working. */
export function sodHref(view:SodView){return view==='reviews'?reviewsHref('queue'):view==='periods'?reviewsHref(view):view==='reports'?reportsHref('review'):'#/sod'+(view==='overview'?'':`/${view}`)}
export function reviewsHref(view:ReviewsView){return view==='reports'?reportsHref('review'):'#/reviews'+(view==='overview'?'':`/${view}`)}
export function reportsHref(view:ReportsView){return `#/reports/${view}`}
/**
 * Moves legacy SoD review destinations into the Reviews workspace and keeps the work-queue tab (`sodReviews`) and `reviewsView` in step.
 * Review context, filters and the selected subject are shared state and are never changed here, so the scope is preserved exactly.
 */
function normalize(view:View, patch:Partial<View>={}):View {
 const next={...view}
 // A SoD or Reviews page named without a page (for example "Review in Risk Matrix" from a period) opens that workspace.
 if(patch.page===undefined&&patch.sodView)next.page='sod'
 if(patch.page===undefined&&patch.reviewsView)next.page='reviews'
 if(patch.page===undefined&&patch.reportsView)next.page='reports'
 // NAV-3: Account Review and Position Changes are Reviews pages; earlier User Access destinations (links, history entries, callers) move there.
 if(next.page==='users'&&(next.accessMode==='review'||next.accessMode==='positions')){next.page='reviews';next.reviewsView=next.accessMode==='review'?'account-review':'position-changes';next.accessMode='directory'}
 // NAV-1: SoD reports and the former Reviews "Reports and Evidence" page open Review Reports.
 if(next.page==='sod'&&next.sodView==='reports'){next.page='reports';next.reportsView='review';next.sodView='overview'}
 if(next.page==='sod'&&(next.sodView==='reviews'||next.sodView==='periods')){
  // An explicit "reviews" destination without a tab is the Work Queue; a URL such as #/sod/reviews/bulk carries its tab in sodReviews.
  const tab=patch.sodView==='reviews'?(patch.sodReviews||'queue'):(next.sodReviews||'queue')
  next.page='reviews';next.reviewsView=next.sodView==='reviews'?tab:next.sodView;next.sodView='overview'
 }
 if(next.page==='reviews'&&next.reviewsView==='reports'){next.page='reports';next.reportsView='review';next.reviewsView='overview'}
 if(next.page==='reports'&&next.reportsView&&!REPORTS_VIEWS.includes(next.reportsView))next.reportsView=undefined
 if(next.page==='reviews'){
  if(patch.sodReviews&&!patch.reviewsView&&!patch.sodView)next.reviewsView=patch.sodReviews
  if(!next.reviewsView||!REVIEWS_VIEWS.includes(next.reviewsView))next.reviewsView='overview'
  if(next.reviewsView==='queue'||next.reviewsView==='bulk'||next.reviewsView==='remediation')next.sodReviews=next.reviewsView
 }
 return next
}
function viewUrl(view:View) {
 const mode=view.accessMode==='compare'?'compare':'directory'
 const base=view.page==='reviews'?reviewsHref(view.reviewsView||'overview'):view.page==='sod'?sodHref(view.sodView||'overview'):view.page==='reports'?(view.reportsView?reportsHref(view.reportsView):'#/reports')
  :view.page==='users'?(mode==='directory'&&view.user?userHref(view.user):usersHref(mode)):`#/${paths[view.page]}`
 const query=location.hash.startsWith('#/')?location.hash.split('?').slice(1).join('?'):''
 return base+(query?'?'+query:'')
}
function readView(): View {
 const stored=history.state?.authLensView as View|undefined
 const segments=location.hash.slice(2).split('?')[0].split('/')
 // `#/users/release-access` is the Release Access page; `#/user-access` and `#/release-roles` are the legacy forms of Users and Release Access.
 const releaseAccess=segments[0]==='users'&&segments[1]==='release-access'
 const page=(releaseAccess?'releases':Object.entries(paths).find(([,value])=>value===segments[0])?.[0]??legacyPaths[segments[0]]) as View['page']|undefined
 const base=stored&&['dashboard','roles','users','releases','sod','reviews','reports'].includes(stored.page)?{...defaults,...stored}:{...defaults,page:page||'dashboard'}
 if(page)base.page=page
 if(page==='sod'){
  const part=segments[1],views:SodView[]=['risk-matrix','activity-matrix','explorer','reviews','periods','reports']
  base.sodView=views.find(item=>item===part)||(part==='users'||part==='roles'?'explorer':'overview')
  if(part==='reviews')base.sodReviews=segments[2]==='bulk'?'bulk':segments[2]==='remediation'?'remediation':'queue'
  if(part==='users')base.sodExplorer='user_risk'
  if(part==='roles')base.sodExplorer='roles'
 }
 if(page==='reviews'){const part=segments[1] as ReviewsView;base.reviewsView=REVIEWS_VIEWS.includes(part)?part:'overview'}
 if(page==='reports'){const part=segments[1] as ReportsView;base.reportsView=REPORTS_VIEWS.includes(part)?part:undefined}
 if(page==='users'&&segments[1]){
  base.accessMode=segments[1]==='account-review'?'review':segments[1]==='position-changes'?'positions':segments[1]==='compare'?'compare':'directory'
  if(segments[1]==='user'&&segments[2]){try{base.user=decodeURIComponent(segments[2])}catch{base.user=segments[2]}}
 }
 if(page==='users'&&(base.accessMode||'directory')==='directory'&&segments[1]!=='user')base.user=''
 return normalize(base)
}
export function initializeViewHistory() {
    const current = readView()
    const url = viewUrl(current)
    if (!history.state?.authLensView) {
      // Boundary is the same meaningful view, never a bootstrap document. Back at
      // the app's first record stays here; normal Back/Forward is untouched.
      history.replaceState({ authLensView: current, authLensBoundary:true }, '', url)
      history.pushState({ authLensView: current }, '', url)
    } else history.replaceState({ ...history.state, authLensView: current }, '', url)
}
const Context = createContext<{ view: View; change: (patch: Partial<View>, replace?: boolean) => void } | null>(null)
/** Navigation identities and bounded comparison controls live in session history; result datasets and credentials never do. */
export function ViewHistory({ children }: { children: ReactNode }) {
  const [view, setView] = useState(readView)
  useEffect(() => {
    const pop = (event: PopStateEvent) => {
      if (event.state?.authLensBoundary) { history.forward(); return }
      setView(readView())
    }
    // A typed or bookmarked legacy hash (NAV-1) is shown under its canonical route; the hash query is kept and no history entry is added.
    const hash=()=>{if(history.state?.authLensBoundary)return;const next=readView(),url=viewUrl(next);if(url!==location.hash)history.replaceState({...history.state,authLensView:next},'',url);setView(next)}
    window.addEventListener('popstate', pop)
    window.addEventListener('hashchange',hash)
    hash() // a hash that changed before this listener existed (an early typed or scripted navigation) is resolved too
    return () => {window.removeEventListener('popstate',pop);window.removeEventListener('hashchange',hash)}
  }, [])
  const change = (patch: Partial<View>, replace = false) => {
    const next = normalize({ ...readView(), ...patch }, patch)
    if (JSON.stringify(next) === JSON.stringify(readView())) return
    history[replace ? 'replaceState' : 'pushState']({ authLensView: next }, '', viewUrl(next))
    setView(next)
  }
  return <Context.Provider value={{ view, change }}>{children}</Context.Provider>
}
export function useViewHistory() {
  const context = useContext(Context)
  if (!context) throw new Error('View history provider is missing')
  return context
}
export function useHistoryValue<K extends keyof View>(key: K): [View[K], (value: SetStateAction<View[K]>) => void] {
  const { view, change } = useViewHistory()
  return [view[key], value => change({ [key]: typeof value === 'function' ? (value as (old: View[K]) => View[K])(view[key]) : value })]
}
