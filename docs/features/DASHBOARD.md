# Dashboard and shared notifications

Dashboard is the default landing page, available from the main navigation and at
`#/dashboard`. Explicit `#/role-lookup`, `#/users` and `#/users/release-access` routes
still work, and an existing detail history entry remains meaningful. No historical trends are inferred
from a single import. Data stays on the configured AuthLens instance; desktop defaults to loopback.

## Layout and cards (v4)

Three balanced columns on desktop (two at tablet width, one on mobile), with no separate key figure row and no metric repeated:

| Row | Column 1 | Column 2 | Column 3 |
| --- | --- | --- | --- |
| 1 | Access & Risk | Review Progress | Directory & Data Health |
| 2 | Segregation of Duties (only when SoD is enabled) | Role Distribution | Assignment Distribution |
| 3 | Data Sources & Configuration, spanning the grid | | |

Future assignment records are detected but not shown here.

- **Access & Risk.** SAP users as the headline row (larger number), then AD disabled / SAP active, Role assignment records, Role/T-code mappings, Catalogue roles and Release roles as compact rows. Each row opens the matching view; AD disabled / SAP active opens Account Review with that finding.
- **Review Progress.** The single Dashboard presentation of review completion: the percentage, reviewed of all imported accounts, one stacked bar (completed green, not yet reviewed neutral gray, outdated amber) and three rows that open Account Review with the Completed, Pending or Outdated filter. With no completed reviews no success color is shown. There is no separate Accounts requiring review or Review completion tile.
- **Directory & Data Health** (administrators only, NAV-5: the whole card is hidden for other roles, and `GET /api/dashboard` leaves its figures out for them). The match percentage (matched SAP identities of all applicable SAP identities) with a progress bar colored by the central thresholds in `frontend/src/lib/health.ts` (green from 95%, amber from 85%, red below; 251 of 264 is green). The color describes directory matching quality only, never other sources or SAP authorization. Rows: Matched identities, Missing matches (SAP user without an email, or an email not in the directory), Ambiguous matches (duplicate directory email, or an SAP email shared by several users) and Position changes. Matched, missing and ambiguous partition the SAP users (the backend counts the existing match statuses, nothing is guessed); Position changes is an independent signal and never changes the percentage. Each row opens Account Review with the matching filter (`matched`, `directory_missing`, `directory_ambiguous`, `position_change`), shown as a removable chip.
- **Segregation of Duties.** Users with potential conflicts, user-risk findings, SoD reviews pending, open and overdue remediation actions, from the Dashboard's own request (no SoD page visit is needed). Hidden when SoD is disabled. The card distinguishes four states: *loading* ("Preparing SoD analysis…" while the application is still restoring data or the request has not answered; never a missing-data verdict), *failed* (the request failed; message and **Try again**), *unavailable* (a real cause: the backend names the missing inputs, for example "The SoD matrix is not loaded", or says that User-Role Mapping is disabled, with an **Open SoD source** button, a shared secondary button with an icon, that opens the matching source in Settings) and *ready*. Counts are never zero-filled.
- **Role Distribution.** The five largest SAP areas with count and share; **Show all N areas** opens a dialog with every area (Escape closes it and returns focus). Each area keeps its drill-down; the card height never changes.
- **Assignment Distribution.** Five non-overlapping ranges of distinct currently valid roles per SAP user: 0-5, 6-10, 11-20, 21-30 and 31+. The population is every applicable SAP user, users without a valid role included in the first range, each user counted once, so the five counts sum to the SAP user total. Duplicate assignment records of one role count once. All bars share one scale; tooltips carry the exact percentage. Each bar opens User Access with the range applied (the `assignment_band` filter, also available as **Currently valid roles** in the User Access filters and in saved filters; earlier ranges in saved filters stay valid).
- **Data Sources & Configuration.** One compact card per relevant source (Role Catalogue, User-Role Mapping, Employee Directory, SoD Matrix; a source is shown when it is enabled or configured). Each card has an honest state computed from what the backend holds (Ready, Loading, Refreshing, Failed, Not loaded, Not configured, Disabled; never Ready just because it is enabled), the mode, source-specific records (composite roles, users and assignment records, directory records, matrix records) and the last import. Selecting a card opens that source in Settings.
- **Explanations.** Technical notes sit in an info popover beside the card title.
- No horizontal scroll from 375 px upward.

## Global and filtered modes (WP30)

One dashboard serves both modes. Without filters it is the **global overview** of the validated SAP data. The **Filters** button opens the
shared filter sidebar used by User Access (BUG-014): integrated on the left of the cards from 1024 px wide (the cards reflow beside it; no
overlay), the shared drawer on narrow screens. It is closed by default, remembers its own open state, and edits a draft: nothing changes until
**Apply filters**; **Clear** in the sidebar header and **Reset filters** in the toolbar clear the draft and the applied filters. Showing or
hiding the sidebar keeps the applied filters. The button shows the number of selected values, removable chips under
the toolbar show every applied value, and a status line states whether the overview is global or filtered. Clearing the filters restores the
global overview. Saved filters use the view `dashboard`; a loaded definition is validated value by value. Dashboard filters are temporary page
filters: like every page (BUG-08), the dashboard opens in the global mode from the main navigation; a saved filter brings a population back.

| Area | Dimension (query parameter) | Values and source |
| --- | --- | --- |
| Organization | Functional Group (`functional_groups`), Manager (`managers`), exact usernames (`usernames`) | Existing shared population filters |
| Organization | Department (`departments`), Site (`sites`), Title (`titles`), Directory account status (`ad_states`) | Employee Directory, matched identities only; hidden when the directory is not available |
| SAP account | User group (`user_groups`), User type (`user_types`) | User-Role Mapping account and assignment evidence |
| SAP account | Account validity (`account_states`: `valid`, `future`, `expired`, `unknown`), Account status (`lock_states`: `locked`, `unlocked`, `unknown`) | Account intervals evaluated today; lock status as in Account Review |
| Access | Assigned role (`roles`), Assigned transaction (`tcodes`), Role type (`role_types`: `business` ZC, `release` ZO, `other`), Organizational suffix (`org_suffixes`) | Currently valid assignments only; a suffix is a final business-role segment used under at least two role stems (the Access Package rule) |
| Governance | SoD risk (`sod_risks`) | Current SoD findings (enabled SoD with a loaded matrix; otherwise 409 and no values) |
| Governance | Review status (`review_states`: `completed`, `pending`, `outdated`) | Current Account Review state; outdated reviews are also pending |

Values combine with **OR within a dimension and AND between dimensions** (at most 200 values per dimension; more is refused with 422).
`GET /api/dashboard/filter-options` lists only values present in the current data, with user counts; nothing is invented. The filters are
resolved by the shared server-side population resolver (`SubjectSelection`), which Account Review, User Access, Release Roles, Employee
Directory and SoD governance use as well, so the same query parameters scope the SoD summary.

**Access matching** (`access_scope`). *User population* (default): a user matches an access dimension when any current assignment matches it,
so a role and a transaction may come from different assignments of the same user, and access metrics show the users' complete current access.
*Matching access* (`access_scope=matching`): one current assignment must match every active access filter at once, and access metrics count only
those assignments. In both modes SoD is evaluated over the selected users' complete access: a genuine conflict is never hidden because one
conflicting role does not match an access filter. Reviews, SoD decisions, period snapshots and historical evidence are never reinterpreted
through current directory or assignment data; governance dimensions read the current evaluation only.

**Drill-down.** Opening a metric carries the population: organization filters travel as they are; when another dimension is active the
response includes `population_usernames` (up to 500), and the target view opens with those exact usernames. Larger populations open with the
organization filters only, which the status line states.

### Metric scope matrix

| Metric (id) | Without filters | With filters | Matching access |
| --- | --- | --- | --- |
| Catalogue roles (`roles`), Enabled SAP areas (`areas`), Role/T-code mappings (`mappings`) | Catalogue | **Global**, marked "Global" | Global |
| SAP users (`users`) | All users | Users in the population | Same population (one assignment matches all access filters) |
| Distinct assigned roles (`assigned_roles`), Transaction codes in use (`assigned_tcodes`), Role/T-code mappings in use (`assigned_mappings`) | All current business and release access | Complete current access of the population (shown on the card when filtered) | Only matching current assignments |
| Role assignment records (`assignments`), Users with assignments (`assigned_users`), Release roles (`releases`), Expired/Future assignment records | All records | Records of the population | Records of the population that match the access filters |
| Review progress (`reviewed`, `pending`, `outdated`, `account_review`), Position changes, AD disabled / SAP active | All accounts | Accounts in the population | Same population |
| Directory matching (`email_matches`, `directory_missing`, `directory_ambiguous`, `unresolved`) | All SAP identities | Identities in the population | Same population |
| Employee Directory records (`employees`) | Directory total | **Global**, marked "Global" | Global |
| Segregation of Duties card (`/api/sod/overview`) | All users | Users in the population, complete access | Users in the population, complete access |
| Role Distribution | Catalogue roles by area (`scope.role_distribution` `catalogue`) | Catalogue roles currently assigned to the population (`population`) | Only matching assignments |
| Assignment Distribution | Every SAP user | Users in the population | Users in the population |
| Data Sources & Configuration, freshness, lifecycle | Global | Global (system metadata) | Global |

`scope.global_metrics` lists the metrics that stay global; `scope.access_semantics` is `user_population` or `matching_access`.

Verification: .NET `DashboardAndSavedFiltersTests` (dimensions, both access modes, governance, SoD risk with a real matrix, options) and
browser `dashboard-filters.spec.ts`, `filter-consistency.spec.ts`. Performance with large production datasets is not measured yet; the
resolver evaluates the current snapshot in memory, and SoD and review dimensions load their current evaluations once per request.

## Segregation of Duties summary

When the SoD feature is enabled, a **Segregation of Duties** section shows users with potential conflicts, user-risk findings, pending reviews and open or overdue remediation actions, each opening the matching [SoD](SOD.md) view. If analysis is unavailable the section says why. The counts are potential transaction-derived conflicts, not effective authorization.

## Position changes metric

**Users requiring review — Position changes** counts Account Review accounts with an unreviewed Department or Job title change between Employee Directory imports. It opens Account Review filtered to those accounts and is separate from SoD conflicts and the other account findings.

## Startup, refresh and navigation

Configured SAP sources initialize in the backend lifespan, independently of which
page opens. The [CSV lifecycle](../data/IMPORT_AND_REFRESH.md) validates independent source
candidates and publishes one coherent generation after committing references. Failed
sources retain validated observations; retained users are remapped if the catalogue changes.

`ApplicationDataProvider` observes configuration above the page routes. It polls
at 500 ms during a load and 3 seconds otherwise. Configuration's `data_revision`
is the published snapshot's timestamp (or `empty`), not CSV contents or a path.
On initial readiness or a changed publication, the provider cancels obsolete
query results and invalidates dataset queries across all routes, including inactive
cached pages. Active queries refetch; inactive pages refetch when used. Backend
publication remains atomic; requests can finish at different times, so a shared
updating indicator remains visible while active views synchronize. Previously
accepted data is retained while loading and after a rejected replacement. Initial
empty/not-found states wait for startup completion. Service loss offers retry
without restarting navigation or discarding the last accepted view.

**Restart behavior.** Persisted datasets are restored by the backend at startup (static sources from their private snapshots, dynamic sources re-read from their files, a failed check keeping the validated snapshot with its error visible). The backend marks itself as loading before it serves its first request, so a client never reads an idle, empty backend. `GET /api/configuration` returns `instance_id` (new for every server process) next to `data_revision`. The provider treats the end of every observed load as a reason to re-read active dataset views, and an instance change as a new publication, because a restored snapshot keeps its old revision timestamp and views read while the backend was still restoring would otherwise stay in their loading-time state (a five minute default cache) until a manual refresh. While configuration has not yet answered, the application reports loading instead of a missing-data verdict. Native Windows/WebView2 startup is not covered by the Linux tests; its manual acceptance is listed in the implementation handoff.

Previously, refresh state and role/module invalidation lived in page components.
Dashboard, user and release results could remain cached after startup completion;
a delayed response could repopulate an obsolete route cache. Browser regressions
cover that failure, navigation during refresh, stale responses, recovery and restored
detail history. Backend regressions verify atomic two-source publication.

## Overview layout

The Dashboard opens with a compact **Key figures** KPI section: SAP users, Catalogue roles, Release roles, Accounts requiring review, Users with potential conflicts (when SoD is enabled), Pending reviews and Missing or ambiguous directory matches. Each KPI is a button that opens the relevant view with its filter applied (for example Accounts requiring review opens Account Review filtered to those accounts). The sections beneath add detail instead of repeating the key figures: **Access & Risk**,
**Directory & Data Health** (matched identities with coverage), **Review Progress** (completed, not yet reviewed and outdated reviews with the share reviewed; no trend is invented), **Segregation of Duties** (findings, pending reviews, remediation), **Role Distribution**,
**Assignment Distribution**, then **Data Sources & Configuration**. Source setup
buttons open the correct Data Sources tab. Smaller icon/value tiles replace the twelve equal, descriptive cards; metrics
have explanatory accessible text/tooltips and no fabricated historical trends.
The default Dashboard does not mount Role Lookup or download its catalogue until
that investigation is visited. Profile/filter layouts use four/two/one-column
breakpoints at 1100 and 640 pixels; the profile itself uses three/two/one groups.

## Metrics and data boundaries

`GET /api/dashboard` returns aggregate metrics from the same validated cache used by
investigation APIs. It requires the existing application session/origin protections.
Each metric contains `id`, `label`, numeric `value` or null, `destination`, `context`
and an `unavailable_reason`. Null means disabled or unavailable; zero is used only
when a loaded, enabled source genuinely has no matching records. No identity rows, paths, source filenames or snapshot IDs are returned. Compact
source availability and the email-coverage denominator accompany the metrics.

| Metric | Definition | Destination |
| --- | --- | --- |
| Catalogue roles | Distinct catalogue composite-role records | Role Lookup |
| Enabled SAP areas | Enabled areas represented in the loaded catalogue | Role Lookup |
| Role/T-code mappings | Sum of distinct T-codes per catalogue role; a code in two roles counts twice | Role Lookup |
| SAP users | Distinct normalized SAP usernames, including users without roles | User Access |
| Role assignment records | Imported distinct assignment intervals, including technical roles | User Access |
| Users with assignments | Distinct usernames with any retained assignment | User Access |
| Release roles | Distinct normalized ZO role names across all assignment validity states | Release Roles |
| Expired/future assignment records | Existing assignment validity calculation, evaluated today; not account validity | User Access |
| Employee Directory records | Confirmed directory records, when enabled and available | Employee Directory data source |
| Directory email matches | SAP identities with unique exact directory-email matches; context supplies the denominator | Filtered Account Review |
| Missing or ambiguous directory matches | SAP identities in all non-matched coverage categories, including missing email and unmatched values | Filtered Account Review |

Access metrics require enabled User–Role Mapping and a loaded User Access CSV.
Directory record counts require enabled Employee Directory and imported records.
Email coverage additionally requires enabled User–Role Mapping with SAP identities.
A disabled dependency does not disable Employee Directory or erase its import.

KPI actions open the relevant investigation with fresh list filters, leaving other
views alone. Release Roles opens its ordinary currently-valid assignment view, even
though its KPI includes all validity states; the card explicitly explains this.
Expired/future counts open User Access and explain how to select assignment status
inside User Details. They do not pretend to apply an unsupported directory-wide
status filter. Data-quality cards open filtered Account Review evidence, not a second Diagnostics implementation. Ordinary navbar navigation retains existing list
filters. Browser Back/Forward uses the existing view-history provider.

The dashboard summarizes data quality. Detailed technical health remains under
Health & Diagnostics; import counts/history live under Data Sources, and
Features contains preferences plus compact availability only.

## Shared notifications

`Shared/Notification.tsx` provides persistent success, error, warning and information
variants. Content uses the same 1536-pixel maximum width and responsive horizontal
padding as the main application. Dismissal uses a keyboard-focusable Lucide X button
with the accessible label **Dismiss notification**. Text can wrap without overlapping
it. Success uses a status region; errors use an alert. There is no automatic timeout
for important feedback. Existing data-source recovery and service-connection banners
retain their actionable recovery buttons and established status semantics.

## Related workflows

- [Employee Directory, feature dependencies and persistence](../data/EMPLOYEE_DIRECTORY.md)
- [Transaction evidence and assignment date filters](FILTERS.md)
- [Development, builds and native Windows validation](../development/README.md)

Automated Chromium screenshots cover both themes at 375, 800 and 1280 pixels.
They do not replace Windows/WebView2, native file-dialog or UNC-share validation.

## Operational overview and review links

Overview prioritizes SAP users, Catalogue roles, Release roles and Role/T-code
mappings. User Access groups users-with-assignments, assignment records and supported
account-review findings. Access Lifecycle owns expired/future **assignment** totals:
these are not inherently data-quality failures. Data Quality presents matched SAP
identities, missing/ambiguous matches and an accessible progress indicator/count/
one-decimal percentage (243 of 259 = 93.8%). Unavailable coverage is not zero.
Configuration stays secondary with source state, enabled areas and last successful
refresh. No historical trends or licensing savings are inferred.

Matching/review KPI actions open filtered **User Access → Account Review**. Missing
matches selects the directory-match finding; matched identities selects reliably
matched rows; review findings selects accounts requiring investigation. Source
configuration actions still open Data Sources directly. Release role KPI includes
all imported validity states and opens the ordinary currently-valid view, explained
by its context; lifecycle totals do not silently apply account-validity filters to
assignment evidence. See [Account Review](ACCOUNT_REVIEW.md).

## Overview and investigation workspace

The icon-led shared header introduces SAP Overview's four primary metrics. Access
& Risk uses compact investigation rows rather than another equal-sized card grid;
Directory & Data Health keeps identity counts and the coverage progress together.
Data Sources & Configuration includes all four independent sources (including the SoD Matrix) with their
feature/availability state and actual last successful refresh. Counts and KPI
navigation retain their existing backend definitions. Lifecycle totals are
informational evidence, not automatically a security-risk finding.

## Investigation distributions and freshness

The middle workspace is three columns on wide desktop, two on tablet and stacked
on mobile: Access & Risk, Directory & Data Health, and Review Progress. Section
headings share the icon-led SectionHeader. One coverage indicator displays matched
count/eligible count, percentage and progress; it is not repeated in adjacent cards.

Review progress uses all currently imported SAP accounts, not just accounts with
findings. Pending includes outdated reviews; decisions never suppress underlying
findings. Reviewed, pending, outdated and AD-disabled/open-account links open the
corresponding Account Review filters. Unavailable annotations are not zero-filled.

Role Distribution counts each catalogue role once using its canonical SAP area;
click a bar to investigate that area in Role Lookup. It does not combine single-role
relationships or release assignments into those counts. Assignment distribution
counts users by distinct **currently valid** business/release roles (1–5, 6–20,
21+; zero-role users remain available through User Directory); it is descriptive, not a security score. The separate Users with assignments
metric still includes imported intervals of every validity state.

Source cards distinguish last import/activation, last validated source check and the
last successful global refresh. Missing timestamps remain unavailable. File modification
times are not inferred. All calculations use validated local snapshots; no history,
license consumption or effective authorization is inferred.

Role Distribution and Data Sources & Configuration share a two-column lower row on wide screens and stack at 800px or below. Source summaries reuse canonical diagnostic state (mode, loaded status, records and actual import freshness). Row navigation highlights the whole target for hover/focus; each source row remains one configuration action.

## Compact analytical row

Role Distribution, Data Sources & Configuration and Assignment Distribution are
separate responsive panels. Assignment bands count distinct currently valid
business/release roles, excluding expired, future and unknown intervals. Selecting
a band opens its filtered User Directory population; the removable chip, Saved
Filters and assignment CSV export retain that scope. High role counts are
informational, not security findings. Review completion uses the existing imported
SAP account population; outdated decisions remain pending.

Role Distribution initially shows the five largest SAP areas, with Show all/Show
less controls. Data Sources & Configuration is the final full-width section.
