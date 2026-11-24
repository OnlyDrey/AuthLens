# Reviews workspace

**Status: implemented; focused browser tests passed (Windows host, Edge Chromium); not deployed or accepted.**

Reviews is a top-level destination (`#/reviews`) for access-review governance. It reuses the existing review engine, decisions, periods,
frozen evidence and report renderer unchanged. There is no second review engine, no new API and no database change.

## Information architecture

| Area | Purpose | Pages |
| --- | --- | --- |
| User Access | Account and access analysis | User directory, Account Review, Compare users |
| SoD | Risk and activity analysis | Overview, Risk Matrix, Activity Matrix, Access Explorer (heatmap stays here) |
| Reviews | Access-review decisions and governance | Overview, Work Queue, Bulk Review, Remediation, Review Periods, Reports and Evidence |

Decisions made without explicit product guidance (documented for product-owner review):

- **Account Review stays in User Access.** It records account/license review findings, a different governance concept from role, activity and
  risk access-review decisions. Reviews links to it but does not merge its decisions or counters.
- **SoD reports moved with Reviews.** The existing report generator produces the formal review report and the access remediation report from
  one frozen period model; both are review evidence. No SoD-only report exists separately today.
- **The SoD feature switch governs Reviews.** Every review workflow is backed by SoD evidence. When SoD is off, Reviews shows a "turned off"
  notice (with Open Features for administrators) and keeps all decisions, periods and reports.
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

The landing page shows the Work Queue counters from the same endpoint, definitions, review context and Work Queue filters
(`/api/sod/queue/users`): Total users, Needs review, Complete, Removal recommended and Completion (complete / total users). A user is complete
when every role, activity and risk access-review item in scope is decided. Counters are not combined across review contexts. Workflow cards
lead to each page; Bulk Review is shown only with the effective `review` permission.

## Context preservation

Review context (current evidence or a frozen period), SoD filters and the selected subject are shared view-history state. Moving between SoD
and Reviews never changes them, so a frozen period stays frozen and filters are neither broadened nor dropped.

Contextual **Open in Reviews** entry points (shown only while SoD is enabled) open the Work Queue with the source screen's exact subject scope:

| Source | Scope carried |
| --- | --- |
| User Access directory | Functional Groups, Managers, exact SAP usernames |
| Account Review (**Open access reviews**) | Functional Groups, Managers, exact SAP usernames |
| Employee Directory (Settings) | Functional Groups, Managers, exact SAP usernames |
| Role details (**Review assigned users**) | Exact role (`role_exact`) |
| Dashboard review KPIs, SoD Overview tiles, Access Explorer bulk review, period actions | Existing contracts (unchanged) |

The destination receives exactly the source scope: an empty source dimension clears that dimension, as the Dashboard already did. The review
context is never changed by these links.

## Permissions

Navigation uses effective backend permissions (`useAuthentication().can`), not role names. Reviews is visible to every signed-in account that
can read SoD data; review actions keep their existing `review`/`approve`/`admin` gates in the UI and on the backend (`V1Auth.Permission`). Period
creation and administrative period operations remain hidden without permission (unchanged components). Backend authorization is unchanged.

## Historical organizational evidence (recommendation, not implemented)

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

`frontend/tests/reviews-workspace.spec.ts` (top-level navigation, overview, legacy redirects, context preservation) plus updated review,
navigation and responsive specs. See the [work-package tracker](../validation/WORK_PACKAGES.md) for exact runs and gaps.
