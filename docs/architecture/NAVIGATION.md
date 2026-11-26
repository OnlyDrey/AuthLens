# Navigation patterns

## Four distinct interactions

| Pattern | Purpose | AuthLens implementation |
| --- | --- | --- |
| Main navigation | Major application destinations | Dashboard, Role Lookup, User Access, Release Roles, SoD, Reviews; Settings is a compact utility opening the existing workspace |
| Secondary navigation | Related pages within a major area | User directory, Account Review, Position Changes, Compare users; real anchor destinations and bottom-border current-page indicator |
| Content tabs | Associated content in one investigation | User Details role sections and Settings import sources; roving focus and an associated tabpanel |
| Actions / filter controls | Perform an operation or constrain results | Canonical buttons, neutral Clear filters, pressed button groups for Table/Matrix and AND/OR |

Do not make secondary routes look like primary operation buttons. Do not label a form-containing popover as an ARIA menu. Do not force tabs onto a page without associated content.

## Routing contract

The existing `useViewHistory` hash/history architecture is extended, not replaced:

- `#/dashboard`
- `#/role-lookup`
- `#/user-access` (directory)
- `#/user-access/account-review`
- `#/user-access/position-changes`
- `#/user-access/compare`
- `#/release-roles`
- `#/sod`, `#/sod/risk-matrix`, `#/sod/activity-matrix`, `#/sod/explorer`
- `#/reviews`, `#/reviews/queue`, `#/reviews/bulk`, `#/reviews/remediation`, `#/reviews/periods`, `#/reviews/reports`

Legacy `#/sod/reviews[/bulk|/remediation]`, `#/sod/periods` and `#/sod/reports` redirect to the matching Reviews route ([Reviews](../features/REVIEWS.md#routes-and-compatibility)).

Legacy primary paths continue to work. Secondary links preserve hash query parameters. Normal primary clicks use application history; modified secondary clicks keep native anchor behavior. Direct secondary URLs and page reload restore the correct view. Back/Forward use the same state reader and bootstrap boundary; startup screens do not reappear as investigation history.

Existing identities, record navigation, role comparison, selected transaction codes, source settings and release drilldowns retain their current state contracts. Comparison controls and Account Review search/sort/review controls are bounded history metadata; result datasets and credentials are never stored there. Saved-filter definitions remain in their existing private store rather than URL query strings.

## Filter lifecycle at page boundaries (BUG-08, after RC4)

Main navigation to another module is a page boundary: every such visit opens the page fresh. Views of one module (the User Access pages) and the review workspace (SoD and Reviews, which share filters, subject and review context by design, see [Reviews](../features/REVIEWS.md#context-preservation)) keep their shared filters while you move between them. Pages that stay mounted
(Role Lookup, User Access, Release Roles) remount, so search fields, temporary filters, selections and open records reset, and the page's
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

A restructured information architecture (Users, Reviews, Reports) is assessed and awaiting approval; it is not implemented
([assessment](../validation/WORK_PACKAGES.md#planned-navigation-and-information-architecture-phase-1-assessment-2026-11-26-awaiting-approval)).

On desktop, modules with pages (User Access: User directory, Account Review, Position Changes, Compare users; SoD: Overview, Risk Matrix, Activity Matrix, Access Explorer; Reviews: Overview, Work Queue, Bulk Review, Remediation, Review Periods, Reports and Evidence) are `MainNavigationGroup`s: the module link and a separate chevron button (`<Module> pages`). The link opens the module (returning to where it was left when coming from another module, and its main page when the module is already open); the chevron opens a submenu of direct page links with the module's icons (`lib/navigationItems.tsx`, shared with the secondary navigation). The group stays highlighted while a child page is open, the active entry is marked `aria-current="page"`, modified clicks open a new tab, Escape closes the menu and returns focus to the chevron. Modules without pages (Dashboard, Role Lookup, Release Roles) show no chevron. After following a manager link the way back is **Return to previous user** inside the Organization section next to the manager relationship (the trail keeps every previous SAP username), not in the top navigation. The submenu is the shared `Popover` with the `ui-popover-menu` variant: it overlays the page, sizes to its items, never scrolls and never changes the navbar size. The current page uses the shared primary tint (no left border on hover, focus or the current entry); Escape, outside click and keyboard behavior come from `Popover`. The main navigation strip is not a scroll container (it wraps when its items exceed the header): a scroll container shows classic scrollbars as soon as the SoD chevron group makes the strip wider than the header, which is what produced the scrollbar when opening a submenu at narrow widths; secondary strips and tabs remain horizontal scroll strips.

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
