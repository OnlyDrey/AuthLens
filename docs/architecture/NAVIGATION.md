# Navigation patterns

## Four distinct interactions

| Pattern | Purpose | AuthLens implementation |
| --- | --- | --- |
| Main navigation | Major application destinations | Dashboard, Role Lookup, Users, SoD, Reviews, Reports (NAV-1); Settings is a compact utility opening the existing workspace |
| Secondary navigation | Related pages within a major area | Module tabs (`Users view`, `SoD views`, `Review views`, `Report views`) with the same items, labels, icons and order as the main-navigation dropdown (`lib/navigationItems.tsx`); real anchor destinations and bottom-border current-page indicator |
| Content tabs | Associated content in one investigation | User Details role sections and Settings import sources; roving focus and an associated tabpanel |
| Actions / filter controls | Perform an operation or constrain results | Canonical buttons, neutral Clear filters, pressed button groups for Table/Matrix and AND/OR |

Do not make secondary routes look like primary operation buttons. Do not label a form-containing popover as an ARIA menu. Do not force tabs onto a page without associated content.

## Routing contract

The existing `useViewHistory` hash/history architecture is extended, not replaced. Canonical routes (NAV-1):

| Module | Pages and canonical routes |
| --- | --- |
| Dashboard | `#/dashboard` |
| Role Lookup | `#/role-lookup` (Role Lookup, role details, comparison, Role Cart and Access Packages stay one page) |
| Users | User Directory `#/users`, a user `#/users/user/<name>`, Compare Users `#/users/compare`, Release Access `#/users/release-access` |
| SoD | Overview `#/sod`, Risk Matrix `#/sod/risk-matrix`, Activity Matrix `#/sod/activity-matrix`, Access Explorer `#/sod/explorer` (`#/sod/users`, `#/sod/roles` select its tabs) |
| Reviews | Overview `#/reviews`, Work Queue `/queue`, Position Changes `/position-changes`, Account Review `/account-review`, Bulk Review `/bulk`, Remediation `/remediation`, Review Periods `/periods` |
| Reports | `#/reports` (the first report page the account may use), Review Reports `#/reports/review`, Access Reports `/access`, SoD Reports `/sod`, Evidence `/evidence` |

Legacy routes resolve to their canonical destination on load, reload, typed or bookmarked hashes, Back/Forward and in-app callers
(`normalize`, `readView`, `legacyPaths`); the hash query is kept and the address shows the canonical route (`replaceState`, no extra history entry):

| Legacy route | Canonical route |
| --- | --- |
| `#/user-access` | `#/users` |
| `#/user-access/user/<name>` | `#/users/user/<name>` |
| `#/user-access/compare` | `#/users/compare` |
| `#/release-roles` | `#/users/release-access` |
| `#/user-access/account-review`, `#/user-access/position-changes` | `#/reviews/account-review`, `#/reviews/position-changes` |
| `#/reviews/reports`, `#/sod/reports` | `#/reports/review` |
| `#/sod/reviews[/bulk\|/remediation]`, `#/sod/periods` | `#/reviews/queue` (`/bulk`, `/remediation`), `#/reviews/periods` |

Internal page keys, saved-filter view keys (`users`, `release`, `review`, `sod_*`, ...) and local preference keys are unchanged, so stored
filters and preferences stay valid. Browser spec `navigation-routes.spec.ts` covers the redirects with their query, Back, default landing
pages and the Users and Reviews structure.

Legacy primary paths continue to work. Secondary links preserve hash query parameters. Normal primary clicks use application history; modified secondary clicks keep native anchor behavior. Direct secondary URLs and page reload restore the correct view. Back/Forward use the same state reader and bootstrap boundary; startup screens do not reappear as investigation history.

Existing identities, record navigation, role comparison, selected transaction codes, source settings and release drilldowns retain their current state contracts. Comparison controls and Account Review search/sort/review controls are bounded history metadata; result datasets and credentials are never stored there. Saved-filter definitions remain in their existing private store rather than URL query strings.

## Filter lifecycle at page boundaries (BUG-08, after RC4)

Main navigation is a page boundary: every visit through a main-navigation link opens the module's default landing page (User Directory, SoD Overview, Reviews Overview, the first available report page) fresh, also from another page of the same module (NAV-1); the review workspace (SoD and Reviews) keeps its shared filters, subject and review context, as below. Views of one module reached through its dropdown or tabs (the Users pages including Release Access) and the review workspace (SoD and Reviews, which share filters, subject and review context by design, see [Reviews](../features/REVIEWS.md#context-preservation)) keep their shared filters while you move between them. Pages that stay mounted
(Role Lookup, Users, Release Access) remount, so search fields, temporary filters, selections and open records reset, and the page's
temporary filter state in the view history (`catalogueArea`, `accessSubjectFilters`, `accountReviewFilters`, `userComparison`,
`reviewFindings`, `assignmentBand`, `release`, `sodFilters`, `sodExplorer`, `bulkSelectMatching`) is cleared. Exceptions, by design:

- **Contextual navigation** (Dashboard tiles, Open in Reviews, user, role and release links, KPI drill-downs) carries its explicit destination
  context through `change()` and is not reset: an intentional destination is not a stale filter.
- **Back and Forward** restore the history entry they return to, including its filters (an explicit return, not a silent restore).
- **Saved Filters** stay stored and are applied again explicitly.
- Opening or closing panels and dialogs, paging, sorting, refreshes, review decisions and theme changes never cross the boundary.
- Review periods, frozen evidence and selected review contexts are data, not temporary filters, and are not touched.

Browser spec `user-feedback-2026-11.spec.ts` (BUG-08) covers reset on a new visit and Back restoring the earlier entry.

## Content tabs

`ContentTabs` owns a tablist and selected panel. `ContentTabList` is the same keyboard implementation for existing independently rendered panels, such as the three Data Source forms. Arrow Left/Right, Home and End select/focus a tab; Tab proceeds into the content. Import-source tab/panel IDs remain stable for recovery and direct source actions.

Role sections retain the actual existing ZC/ZO investigation scopes; these naming conventions are not presented as universal SAP standards. Changing tabs does not change parsing, transaction resolution or date filters' scope.

## Links, deep links and keyboard order

- Main navigation items are real `<a href>` links (`#/dashboard`, `#/role-lookup`, `#/user-access`, `#/release-roles`, `#/sod`, `#/reviews`). A plain click is handled in-app and closes Settings; Ctrl/Cmd/Shift/middle click and "Open in new tab" use the browser. Leaving Settings with unsaved changes asks `Discard unsaved settings changes?` (`lib/settingsGuard.ts`); opening a link in a new tab never discards the draft.
- SAP usernames are links to `#/user-access/user/<username>` (directory, Account Review, SoD, manager links). A missing user shows the normal not-found state. Manager links append to a route-based trail, so User Details shows **Back to previous user: NAME** and browser Back/Forward follow it.
- DOM order is interaction order; there are no positive `tabindex` values or CSS visual reordering. Filter controls follow their visible reading
  sequence inside the desktop sidebar or mobile drawer. Column changes reorder the rendered cells and export fields together. Identifier text adds
  no tab stop; its existing open/copy/investigation actions remain keyboard accessible.
- Secondary navigation (`SecondaryNavigation`) accepts an optional Lucide icon and has no count badges; counts belong in the result summary.
- Stacked list rows use `.ui-list-row`: bottom separator, no rounded or double borders, with hover, active and focus-visible states.

## Main navigation submenus

On desktop, modules with pages (Users: User Directory, Compare Users, Release Access; SoD: Overview, Risk Matrix, Activity Matrix, Access Explorer; Reviews: Overview, Work Queue, Position Changes, Account Review, Bulk Review, Remediation, Review Periods; Reports: Review Reports, Access Reports, SoD Reports, Evidence, as far as the account may use them) are `MainNavigationGroup`s: the module link and a separate chevron button (`<Module> pages`). The link always opens the module's default landing page (NAV-1; if it is not available, the first authorized page); the chevron opens a submenu of direct page links with the module's icons (`lib/navigationItems.tsx`, shared with the secondary navigation). The group stays highlighted while a child page is open, the active entry is marked `aria-current="page"`, modified clicks open a new tab, Escape closes the menu and returns focus to the chevron. Modules without pages (Dashboard, Role Lookup) show no chevron. Reports is shown only when the account may use at least one report (report availability endpoint). After following a manager link the way back is **Return to previous user** inside the Organization section next to the manager relationship (the trail keeps every previous SAP username), not in the top navigation. The submenu is the shared `Popover` with the `ui-popover-menu` variant: it overlays the page, sizes to its items, never scrolls and never changes the navbar size. The current page uses the shared primary tint (no left border on hover, focus or the current entry); Escape, outside click and keyboard behavior come from `Popover`. The main navigation strip is not a scroll container (it wraps when its items exceed the header): a scroll container shows classic scrollbars as soon as the SoD chevron group makes the strip wider than the header, which is what produced the scrollbar when opening a submenu at narrow widths; secondary strips and tabs remain horizontal scroll strips.

## Compact navbar and metadata

Theme, Settings and Refresh are visible icon actions beside the profile menu at every width, with accessible names/tooltips and touch-sized targets.
The header wraps on narrow screens instead of hiding utilities or squeezing brand/context text. Below 1024 px a hamburger opens the main modal drawer.
Modules with child pages use compact expandable groups with one chevron, full icon/text labels and the active route; there is no duplicate overview link.
Escape, backdrop interaction and route selection close the drawer. Shared Dialog owns scroll lock, focus isolation and restoration; a desktop resize closes it.
Refresh retains application-scoped loading, request suppression, permissions and explicit feedback.

The bounded profile icon menu opens the existing profile/session dialog, with icon-leading, left-aligned actions and sign-out. It does not navigate
to a separate profile page. Sign-in/reset actions have their own icons and the reset action is centered in the sign-in card.

Below 768 px Settings has its own **Settings sections** drawer containing the same grouped sections, labels, icons and permissions as the desktop
sidebar. It closes on selection, Escape or backdrop; selection focuses the section heading. The main drawer is disabled while Settings is open,
so the two navigations cannot overlap. Back returns to the application and restores focus to Settings. Desktop Settings retains tab/arrow-key behavior.

The navbar no longer displays the full updated timestamp. Dashboard and Data Sources already show the backend's actual successful publication/import metadata. A redundant frontend `new Date()` refresh clock was removed rather than relabeled as source time.

## Investigation actions

Keep exact identifier copy, manager-to-SAP-user navigation, record Previous/Next and browser Back behavior. Popovers close on outside click, Escape and history traversal, restoring trigger focus for keyboard dismissal. Tables may scroll within their named focusable region; controls and page-level navigation must remain within the viewport.

See [Component Library](COMPONENTS.md) for APIs and [validation tracker](../validation/README.md) for actual checks and platform limits.

The shared SAP username codeblock can open the application-level SoD Review panel
without changing the parent page. Exact user selection is stored in existing view
history; switching preserves the panel tab and isolates user-bound evidence state.
Closing clears the active indicator. Existing open-user links, modified clicks
and copy actions remain independent. Unsupported modal and preview contexts omit
the additional review action. See [SoD usage](../features/SOD.md#shared-username-review-action).
