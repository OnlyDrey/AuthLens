# Reviews workspace

**Status: implemented; focused browser tests passed (Windows host, Edge Chromium); not deployed or accepted.**

Reviews is a top-level, application-level destination (`#/reviews`) for access governance. SoD access reviews reuse the existing review
engine, decisions, periods, frozen evidence and report renderer unchanged; Account Review keeps its own engine in User Access and is reached from
the Reviews Overview. There is no second review engine, no new API and no database change.

## Information architecture

Implemented with NAV-1 to NAV-3 (source; Windows acceptance pending). Navigation and routes: [navigation](../architecture/NAVIGATION.md#routing-contract).

| Area | Purpose | Pages |
| --- | --- | --- |
| Users | Account and access analysis | User Directory, Compare Users, Release Access |
| SoD | Risk and activity analysis | Overview, Risk Matrix, Activity Matrix, Access Explorer (heatmap stays here) |
| Reviews | Access governance: SoD access reviews and the account reviews | Overview, Work Queue, Position Changes, Account Review, Bulk Review, Remediation, Review Periods |
| Reports | Report generation and frozen evidence | Review Reports, Access Reports, SoD Reports, Evidence ([Reports](REPORTS.md)) |

- **Position Changes and Account Review are Reviews pages** on their one shared implementation (`AccountReview`, `mode="positions"`): the same
  rows, detection, decisions, history, filters and authorization. They are separate pages and never depend on the SoD switch; their decisions
  are never merged with SoD access-review decisions. An account opened from either page shows its details inside Reviews; *Back to Account
  Review* (or *Position Changes*) returns to the list. The Reviews Overview keeps its separate **Account reviews** card.
- **Work Queue and Bulk Review stay separate pages.** Access Explorer hands an explicit selection to Bulk Review (NAV-8, [SoD](SOD.md)).
- **Reports moved to the Reports module (NAV-4).** The formal review report and the access removal report are Review Reports; `#/reviews/reports`
  and `#/sod/reports` open Review Reports.
- **Reviews is independent of the SoD feature switch; SoD access reviews are not.** With SoD turned off, Reviews offers Overview, Position
  Changes and Account Review; the SoD access-review part of the Overview shows a "turned off" notice (Open Features for administrators). A
  bookmarked Work Queue, Bulk Review, Remediation or Review Periods page shows the same notice instead of data; decisions, periods and snapshots
  are kept. The review context bar is hidden while SoD is off and on the account pages. Backend authorization and the SoD API gating are
  unchanged.
- **The SAP User Group heatmap remains in SoD.** Reviews shows no large visualization above the Work Queue.

## Routes and compatibility

| Route | Page |
| --- | --- |
| `#/reviews` | Overview |
| `#/reviews/queue`, `/position-changes`, `/account-review` | Work Queue, Position Changes, Account Review |
| `#/reviews/bulk`, `/remediation`, `/periods` | Bulk Review, Remediation, Review Periods |

Legacy routes and in-app callers keep working: `#/sod/reviews`, `#/sod/reviews/bulk`, `#/sod/reviews/remediation` and `#/sod/periods` are
normalized to the Reviews route, `#/user-access/account-review` and `#/user-access/position-changes` to the Reviews account pages, and
`#/reviews/reports` and `#/sod/reports` to Review Reports, on load, reload, Back/Forward and in-app navigation (`useViewHistory` `normalize`). Stored
history entries with the old SoD views are normalized the same way. The legacy `sodReviews` state still selects the work page, so existing
links such as "Bulk review" from Access Explorer, Dashboard review KPIs, SoD Overview remediation tiles and period "View work queue" open the
correct Reviews page.

## Overview

**WP37 (RC7 target): the Reviews Overview is an operational dashboard** for SoD access reviews in the selected review context, plus the
separate Account Review counters. It replaced the earlier navigation cards (Work Queue, Bulk Review, Remediation, Review Periods, Reports and
Evidence, Related analysis); those destinations stay in the **Review views** navigation, and **Open Work Queue** sits in the page toolbar.
Every figure comes from one request, `GET /api/sod/reviews/overview?context=…&group_by=…&<Work Queue filters>`, which reuses the authoritative
models instead of recalculating them: the Work Queue items (lifecycle, review coverage and its manual or derived provenance, frozen period
evidence), the Remediation rows and actions (the same removal follow-up as Reports and Evidence) and the period index.

**Filters.** The integrated left filter sidebar (shared `FilterLayout`, closed by default, its own remembered state, the drawer on narrow
screens) shows the **Work Queue's own filters and Saved Filters** (`sod_queue`): SAP User Group, Functional Group, Manager, exact usernames,
search, risk, activity, role, role suffix, transaction, category and assignment validity, OR within and AND between dimensions. The Overview
and the Work Queue therefore always count the same population, and a drill-down never broadens or replaces it. Risk, activity, role and
transaction filters narrow the review **items**, exactly as in the Work Queue, so user completion is measured within that item scope.

**Cards** (three columns on wide screens, two or one when narrower or beside the sidebar; light and dark):

- **Access Review Progress**: users in scope, users requiring review (with partly reviewed and not started), users with completed reviews,
  completion with a progress bar, users with removal recommendations and users with outdated decisions. Removal and outdated overlap the
  complete / requiring split and say so.
- **Review Coverage**: for role, activity and risk reviews separately, covered items of applicable items, the percentage and the split into
  recorded and derived coverage (each item once). Zero applicable items reads *No applicable items*, never 0% or 100%. No combined percentage;
  risk coverage is not formal acceptance and coverage is not verified remediation.
- **Review Workload**: pending role, activity and risk reviews (investigations included and named), outdated decisions, and the outstanding
  total (pending, investigate and outdated, each item once).
- **Review Decisions**: per review type, the recorded states of the existing model (Keep, Removal recommended, Investigate; Approved,
  Conditional, Removal recommended, Investigate; Risk accepted, Risk rejected), derived coverage without an own decision, and outdated items.
- **Remediation**: assignments recommended for removal (a recommendation, not proof), awaiting a remediation action, open actions, overdue
  actions, actions recorded as completed (manual, not proof) and removals confirmed by newer SAP evidence.
- **Review Periods**: open (Draft, In review), awaiting approval, approved, closed and rejected periods. **Global**: not limited by the review
  context or filters, and labelled so.

**Organizational review progress** (below the cards): group by SAP User Group, Functional Group, Manager, Department or Site, sortable by name,
completion, users requiring review and total users. Each row shows users, complete, requiring review and completion. A user in several groups
counts in each group; the distinct total is stated. Users without a value have their own row (No SAP User Group, Unassigned, No manager,
Unmatched or not recorded). Department and site need an enabled Employee Directory with matched identities. **Frozen periods** offer SAP User
Group only, from the period's own evidence; the other dimensions were not captured and are reported as unavailable, never filled from current
data. SAP User Group, Functional Group and Manager rows open the Work Queue with that filter added; Department and Site have no Work Queue
filter and do not navigate.

**Drill-down** (keeps the review context and every applied filter, adds the metric's constraint): users in scope → Work Queue; users requiring
review, pending and outdated work → Work Queue *Needs review*; completed users → Work Queue *Complete*; users with removal recommendations →
Work Queue *Removal recommended*; recommended for removal and open actions → Remediation; awaiting action → Remediation *Awaiting action*;
confirmed removals → Remediation *Verified removals*; periods → Review Periods. The Work Queue progress filter is kept in the view history
(`queueProgress`) so the destination shows the matching tile and count.

### Metric scope matrix (WP37)

| Metric | Source | Unit | Numerator / denominator | Filters | Review context | Deduplication | Drill-down | Scope |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Users in scope | Work Queue items | SAP user | users with at least one current review item | Work Queue filters | context's items (period: frozen) | distinct user | Work Queue | filtered |
| Users requiring review | Work Queue items | SAP user | users with an undecided item / users in scope | same | same | distinct user | Work Queue *Needs review* | filtered |
| Users with completed reviews, Completion | Work Queue items | SAP user | users whose items are all covered / users in scope | same | same | distinct user | Work Queue *Complete* | filtered |
| Users with removal recommendations | Work Queue items | SAP user | users with a *Removal required* item (overlaps) | same | same | distinct user | Work Queue *Removal recommended* | filtered |
| Users with outdated decisions | Work Queue items | SAP user | users with an *Outdated* item (also requiring review) | same | same | distinct user | — | filtered |
| Role, activity, risk coverage | Work Queue items, `review_coverage` | review item | covered / applicable items of that type | same | same | each item once (recorded or derived) | — | filtered |
| Pending, outdated, outstanding | Work Queue items | review item | pending + investigate, outdated, their sum | same | same | each item once | Work Queue *Needs review* | filtered |
| Decision states | Work Queue items, lifecycle | review item | items per recorded state and type | same | same | per type, not combined | — | filtered |
| Recommended for removal, awaiting action | Remediation rows | exact role assignment | rows with *Remove assignment*, without a tracked action | same | same | one per assignment | Remediation, *Awaiting action* | filtered |
| Open, completed actions | Remediation actions | action | actions Open or In progress, Completed | same | same | per action | Remediation | filtered |
| Overdue actions | Remediation rows | role assignment | tracked removal or investigation past its due date | same | same | one per assignment | — | filtered |
| Confirmed removals | removal verification | action | tracked removals absent from newer imported evidence | same | same | per action | Remediation *Verified removals* | filtered |
| Period lifecycle | period index | period | periods per lifecycle state | none | all periods | per period | Review Periods | **global** |
| Organizational progress | Work Queue items + group membership | SAP user per group | complete / users per group | same | current: all dimensions; period: SAP User Group only | distinct per group, overlap stated | Work Queue with the group filter | filtered |

**Account reviews** (always): counters from the existing Account Review endpoint (`/api/account-review?limit=1`, its `summary`) for the whole SAP
account population: SAP accounts, Requiring review and Completed. Account Review is a separate process (account and license findings); its
completion is never combined with access-review completion, and Account Review page filters do not apply to these counters. **Open Account
Review** opens the existing page; decisions are still recorded there with `review`.

Status: implemented; backend `SodPeriodsTests.Reviews_overview_reconciles_with_the_work_queue_remediation_and_periods` and browser
`reviews-overview.spec.ts`; native acceptance pending (R7-RV1).

## Work Queue export

**Export CSV** in the Work Queue opens a dialog (shared `Dialog`, checkboxes, selects, `DataTable` preview) instead of downloading at once.

| Preset | Rows | Default columns |
| --- | --- | --- |
| Full review export | the existing fixed export (`/api/sod/queue/export`, unchanged schema) | fixed |
| Role removal | one row per exact SAP user and role whose **every** visible assignment of that role is decided *Remove* in role review | SAP username, Role name |
| Pending review | review items in state Pending, Outdated or Investigate | SAP username, Review type, Review item, Review status |
| Custom | review items filtered by review type and decision state | chosen |

**Role removal eligibility.** Decided per exact role assignment, never per user: a user with Keep, Remove and pending roles exports only the
Remove role. A user and role with differing assignment decisions is ambiguous and excluded (the preview says how many). Activity and risk
decisions never become role removals; the remediation model treats them as investigations. **Scope**: current filtered results (the Work
Queue filters, all pages) or all results in the review context. **Columns**: SAP username, role or review item, role description, review type,
risks, employee name, SAP user group, Functional Group, department, manager, review status, comment, reviewer, review date; *Select all*,
*Clear*, and up/down ordering; only selected columns are written, and export is disabled without columns. Role description, employee,
Functional Group, department and manager need current data and are refused for a frozen review period (no current data is substituted).
**File**: UTF-8 with BOM, semicolon or comma, CRLF, quotes only where a value contains the delimiter, a quote or a line break, ordered by user
and role. Identifiers are written exactly; free text gets the formula guard, and the preview warns when an identifier could be read as a
formula. **Preview**: the same server request with `preview=true` (first 10 rows, row count, distinct users). The last configuration is
remembered in the browser (`authlens-queue-export`); presets stay available. API: `GET /api/sod/queue/export/configured`. Read only: no
decision, remediation, evidence or history is changed.

## Context preservation

Review context (current evidence or a frozen period), SoD filters and the selected subject are shared view-history state. Moving between SoD
and Reviews never changes them, so a frozen period stays frozen and filters are neither broadened nor dropped.

Contextual entry points into the Work Queue (shown only while SoD is enabled, because they open SoD access reviews):

| Source | Entry point | Scope carried |
| --- | --- | --- |
| Dashboard | **SoD reviews pending** row; remediation rows | Functional Groups, Managers, exact SAP usernames of the Dashboard (existing contract) |
| User Access directory | **Open in Reviews** | Functional Groups, Managers, exact SAP usernames |
| Account Review | **Open access reviews** | Functional Groups, Managers, exact SAP usernames |
| Employee Directory (Settings) | **Open in Reviews** | Functional Groups, Managers, exact SAP usernames |
| Role Lookup → role details | **Review assigned users** | Exact role (`role_exact`) |
| SoD Overview | **Open Work Queue** (filter toolbar); remediation tiles open Remediation | Shared SoD filters (Functional Group, Manager, exact usernames) |
| SoD Access Explorer | **Open Work Queue**; **Review matching assignments** (Bulk Review, existing) | Shared SoD filters (users, SAP User Group, risk, activity, role, transaction, business area) |
| SoD conflict analysis (investigation panel from Risk/Activity Matrix or Explorer) | **Open in Work Queue** (hidden inside Reviews) | Exactly the investigated SAP username |
| Review period actions | **View work queue** | The period as review context (existing) |

The destination receives exactly the source scope: an empty source dimension clears that dimension, as the Dashboard already did. Page-only
filters that the Work Queue does not apply (search, role suffix, assignment validity, risks per user, decision filters) are never silently dropped:
SoD Overview and Access Explorer name them next to the button ("Not applied in the Work Queue: …"). The review context (current evidence or the
selected period) and its evidence revision are never changed by these links; SoD Overview figures are always current evidence, so opening the Work
Queue while a frozen period is selected keeps that period.

Intentional exclusions: the Role Lookup list (a role catalogue without a user population; role details carry the exact role), SoD Role
Conflicts (catalogue roles, not assignments) and Data Health (global source integrity). Release Roles has no Work Queue entry; its role details
open the shared review panel per user instead (below).

### Shared review panel entry points (BUG-01, BUG-02, BUG-07; after RC4)

- **Toggle (BUG-01).** The row control that opens a user in the shared review panel (User Access, SoD tables, member lists) also closes it; it
  keeps a stable name and reports its state with `aria-pressed`. Closing changes only the review subject: search, filters and the selected user
  stay. Another user's control switches the open panel; the panel's own Close and Escape still work, and unsaved review input asks before it is
  discarded.
- **Release role details (BUG-02).** Each assignment row of a reviewable user has **Review** next to the username. It opens the same panel for that
  user with the Roles tab selected and the release role's assignment highlighted (all of the user's items stay reviewable); users the review
  does not cover show no action. Decisions use the existing review services, permissions and scope, enforced by the API.
- **Profile progress (BUG-07).** User details show **Role review** with `reviewed/total roles reviewed` and the outcome breakdown (kept, removal
  recommended — not yet removed in SAP —, under investigation, pending), from the same subject query and counting rule (`lib/reviewProgress.ts`)
  as the panel's "Roles n/m" tab, in the selected review context. A row counts as reviewed when the server's review coverage says so, so
  invalidated or outdated decisions are pending. The model records one current decision per assignment (not per reviewer), so progress is
  assignment-level. It updates after a decision because the panel invalidates the shared query.

## Permissions

Navigation uses effective backend permissions (`useAuthentication().can`), not role names. Reviews is visible to every signed-in account that
can read SoD data; review actions keep their existing `review`/`approve`/`admin` gates in the UI and on the backend (`V1Auth.Permission`). Period
creation and administrative period operations remain hidden without permission (unchanged components). Backend authorization is unchanged.

## Historical organizational evidence (recommendation, not implemented)

**Implemented today: nothing in this section.** Product decision: deferred to a future release (provisionally 2.1.0). The 2.0.0 evidence
contract, snapshot schema and checksums are unchanged and existing frozen snapshots are never rewritten.

Frozen period snapshots do not record Functional Group membership or manager relationships. Organizational filters in a frozen context use
**current** membership; the UI states this. Changing the evidence contract requires product-owner approval. Recommended design:

- **Schema:** a new optional `organization` section in snapshot schema version N+1, captured at freeze time: per SAP username the Functional
  Group IDs and names, and the direct manager SAP username (or unresolved marker). No recursive hierarchy, no Employee Directory personal fields.
- **Integrity:** include the section in the snapshot checksum for new snapshots only; record the Functional Group definition revision and
  Employee Directory dataset hash it was captured from.
- **Existing snapshots:** never rewritten. They report `organization: unavailable`; filters keep the current-membership notice.
- **Reports:** may group by captured organization when present and must state which basis (captured vs. current) was used.
- **Storage:** roughly one group-ID list and one manager username per reviewed user; negligible relative to review items.
- **Backup/restore and migration:** the section travels inside the snapshot; old readers ignore unknown optional sections; restoring an older
  backup yields snapshots without the section.
- **Privacy:** capture only identifiers needed for scoping (group IDs/names, manager SAP username), no names, emails or HR attributes.

## Validation

`frontend/tests/reviews-workspace.spec.ts` (top-level navigation, overview, legacy redirects, context preservation, Reviews with SoD turned off
and the Account Review entry, Access Explorer **Open Work Queue** with the page-only note) plus updated review, navigation and responsive specs. See the [work-package tracker](../validation/WORK_PACKAGES.md) for exact runs and gaps.
