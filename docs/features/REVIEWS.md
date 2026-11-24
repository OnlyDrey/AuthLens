# Reviews workspace

**Status: implemented; focused browser tests passed (Windows host, Edge Chromium); not deployed or accepted.**

Reviews is a top-level, application-level destination (`#/reviews`) for access governance. SoD access reviews reuse the existing review
engine, decisions, periods, frozen evidence and report renderer unchanged; Account Review keeps its own engine in User Access and is reached from
the Reviews Overview. There is no second review engine, no new API and no database change.

## Information architecture

| Area | Purpose | Pages |
| --- | --- | --- |
| User Access | Account and access analysis | User directory, Account Review, Compare users |
| SoD | Risk and activity analysis | Overview, Risk Matrix, Activity Matrix, Access Explorer (heatmap stays here) |
| Reviews | Access governance: SoD access reviews and the entry to Account Review | Overview, Work Queue, Bulk Review, Remediation, Review Periods, Reports and Evidence |

Decisions made without explicit product guidance (documented for product-owner review):

- **Account Review stays in User Access and is discoverable from Reviews.** It records account/license review findings, a different governance
  concept from role, activity and risk access-review decisions. The Reviews Overview has a separate **Account reviews** card (its own counters
  and **Open Account Review**, which opens the unchanged `#/user-access/account-review` route). Decisions and counters are never merged.
- **SoD reports moved with Reviews.** The existing report generator produces the formal review report and the access remediation report from
  one frozen period model; both are review evidence. No SoD-only report exists separately today.
- **Reviews is independent of the SoD feature switch; SoD access reviews are not.** Reviews stays in the main navigation for every signed-in
  account (all roles hold `read`, which Account Review requires). With SoD turned off, only the Overview is offered: the SoD access-review part
  shows a "turned off" notice (Open Features for administrators) and the Account reviews card stays. A bookmarked Work Queue, Bulk Review,
  Remediation, Review Periods or Reports page shows the same notice instead of data; decisions, periods, snapshots and reports are kept. The
  review context bar is hidden while SoD is off. Backend authorization and the SoD API gating are unchanged.
- **The SAP User Group heatmap remains in SoD.** Reviews shows no large visualization above the Work Queue.

## Routes and compatibility

| Route | Page |
| --- | --- |
| `#/reviews` | Overview |
| `#/reviews/queue`, `/bulk`, `/remediation` | Work Queue, Bulk Review, Remediation |
| `#/reviews/periods`, `#/reviews/reports` | Review Periods, Reports and Evidence |

Legacy routes and in-app callers keep working: `#/sod/reviews`, `#/sod/reviews/bulk`, `#/sod/reviews/remediation`, `#/sod/periods` and
`#/sod/reports` are normalized to the Reviews route on load, reload, Back/Forward and in-app navigation (`useViewHistory` `normalize`). Stored
history entries with the old SoD views are normalized the same way. The legacy `sodReviews` state still selects the work page, so existing
links such as "Bulk review" from Access Explorer, Dashboard review KPIs, SoD Overview remediation tiles and period "View work queue" open the
correct Reviews page.

## Overview

Product decision (2.0.0): Overview counters are **global** within the selected review context and the signed-in account's authorized data;
filtered detail views (Work Queue, Account Review) keep their own filtered counters. Each card states its scope.

**SoD access reviews** (while SoD is enabled): the landing page shows the Work Queue counters from the same endpoint and definitions
(`/api/sod/queue/users`) for the selected review context **without** the Work Queue filters: Total users, Needs review, Complete, Removal
recommended and Completion (complete / total users). When Work Queue filters are active, a note says so and opens the filtered Work Queue. A user
is complete when every role, activity and risk access-review item is decided. Counters are not combined across review contexts. Workflow cards
lead to each page; Bulk Review is shown only with the effective `review` permission.

**Account reviews** (always): counters from the existing Account Review endpoint (`/api/account-review?limit=1`, its `summary`) for the whole SAP
account population: SAP accounts, Requiring review and Completed. Account Review page filters do not apply to these counters, and they are never
added to the access-review counters. **Open Account Review** opens the existing page; decisions are still recorded there with `review`.

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
Conflicts (catalogue roles, not assignments), Release Roles (release governance, not access review) and Data Health (global source integrity).

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
