# User Access

## Directory and profiles

Enable User–Role Mapping and import its [CSV](../data/CSV_SCHEMAS.md#userrole-mapping).
Search by SAP username, source name/email or group. Sort and paginate the directory;
open a user for SAP identity, Account Status and Organization. SAP CSV is authoritative
for SAP name/email. Optional [Employee Directory](../data/EMPLOYEE_DIRECTORY.md)
enriches title, department, AD status and an unambiguously resolved manager link.
Manager navigation uses exact normalized email, not AD username or name guesses.
A SAP user has a shareable route, `#/user-access/user/<username>`; manager links keep a trail and
User Details offers **Back to previous user**. The directory match status reads
"Directory match" followed by a status badge.

User validity, SAP lock and AD state are independent. Missing/conflicting evidence
is Unknown, never implicitly Valid/Unlocked/Enabled. The profile shows source
observations without claiming effective access. Previous/Next spans the filtered,
sorted result set across pages; browser Back preserves investigation context.

### Directory columns, group chips and column visibility

- **Job title** and **Department** come from the mapped Employee Directory employee, the same evidence User Details shows. They are filled
  only for a SAP user linked to exactly one Directory employee; otherwise the cell shows a dash whose tooltip states why (no Directory loaded,
  no unique match, or not recorded). Nothing is derived from SAP fields. Both columns can be sorted on the server (users without a value come
  last in both directions) and are covered by the free-text search.
- **Functional Group** shows memberships as compact chips keyed by the group id: the first two groups, then one `+N` control that names the
  remaining groups and opens the user. Archived groups are marked. The row stays on one line.
- **Columns** (above the table) hides or shows Full name, Job title, Department, Functional Group, SAP user group and Email. The choice is kept
  in this browser; Username, statuses and the role count always stay visible.
- **User Details > Functional Groups** lists memberships of active groups first and memberships of archived groups in their own labelled
  list. The last confirmation shows the stored date and time; when the store has no readable date it says so instead of "Unknown".
- Bulk assignment (below) is unchanged: it previews additions per user, never replaces existing memberships, and reports conflicts per user.

## Filters and assignments

Directory search, SAP User Group, catalogue-backed role-name/description selection,
transaction chips, sort/direction and expired-assignment control share one panel.
The role selector preserves the existing single-role association; it does not add
new multi-role AND/OR semantics. Remove individual chips or use Clear filters to
reset the panel. T-codes default to AND across the same user's relevant evidence;
OR is explicit. Unmapped/ambiguous roles cannot supply transaction evidence.

User Details uses All Roles, Business Roles and Release Roles content tabs. All
is the union of supported ZC and ZO assignments, not every technical role.
Exact assigned identifiers remain copyable; catalogue patterns are not assignments.
Distinct validity intervals and groups remain distinct. Expired evidence is hidden
by default; future and unknown intervals are labeled separately. Missing bounds
never automatically mean active. Account validity/lock does not alter assignment dates.

[Assignment date controls](FILTERS.md#assignment-dates-and-tables) belong above the
assignment table and do not filter the profile. Missing ends differ from the real
SAP maximum 31.12.9999. Display is DD.MM.YYYY; API/export comparisons use date-only ISO.

## Users lacking roles

**Roles the user must lack** selects up to 20 catalogue roles. The operator is always shown: **Missing ANY** lists users who lack at least one selected role, **Missing ALL** users who lack every selected role. With transactions, the **Exclude matching transactions** checkbox gives the same two readings (AND is Missing ANY, OR is Missing ALL). Only current, eligible assignments count (expired ones follow **Show expired assignments**), and only users whose assignments are all mapped to catalogue roles are listed; a user with no assignment evidence or an unmapped role is never reported as lacking access. The filter combines with the other directory filters, Saved Filters and the CSV export.

## Investigation and export

Open a matched catalogue role for relationships and transactions. Role or T-code
investigations can return distinct assigned users while retaining all explaining
roles. No catalogue match is shown as Unmapped, not invented transaction access.
Export includes all matching pages with frozen generation/date/filter guards,
spreadsheet protection and original assignment evidence. Desktop uses its native
save bridge; hosted mode downloads through the browser.

Use [Compare Users](COMPARE_USERS.md), [Account Review](ACCOUNT_REVIEW.md) and
[Saved Filters](SAVED_FILTERS.md) for related investigations. Disabling mapping
preserves imports/settings but blocks assignment-dependent results and exports;
Role Lookup remains independently usable.

## Compact assignment investigation

User Details defaults to **Match all (AND)** for selected transaction codes within
each assigned role's aggregate catalogue mappings. Choose **Match any (OR)**
explicitly to broaden that role filter. Zero selected codes leaves assignments
unchanged; one code has identical AND/OR results. Status, role view and date bounds
compose with this filter; export uses exactly the same matching mode and all pages.
The result summary reports matching assignment records. Unresolved mappings remain
a compact warning; explaining source roles belong to each row's Transaction
mapping evidence disclosure. Export scope is available on the export button.

Directory match status opens a modal with actual method, candidates and source
inspection. Ambiguous/missing/unavailable evidence never becomes a confirmed
identity. The SAP Identity, Account Status and Organization profile groups remain
independent of assignment filters.

## Directory assignment CSV export

The transaction filter has an **Exclude matching transactions** checkbox shared with Role Lookup (see
[Role Lookup](ROLE_LOOKUP.md#exclude-matching-transactions)); the export follows the same selection.

**Export CSV** beside the result count first selects users using every current directory filter, across all pages.
User search, exact usernames, SAP User Group, Functional Groups, manager, selected roles, missing roles, transaction AND/OR
and assignment-validity filters keep the same user-matching semantics. Multiple selected roles combine with OR; AND/OR
continues to control transaction matching across the user's eligible selected-role evidence.

When a role filter is active, only associations matching those roles are exported. Exact normalized names, resolved catalogue
role identities and the existing anchored literal-prefix `*` wildcard syntax share the same matcher used by the directory.
Concrete assigned role names remain in the CSV. Extra unrelated access is never included just because its user matched.
With no role filter, the original full-access behavior is retained, including other roles and future intervals.
Expired assignments are excluded while
**Show expired assignments** is off (the result count and the exported row count follow the same rule); turn it on, or
filter by expired status, to include them. `MATCHED_FILTER`
is Yes only for assignment evidence contributing to the active selection; No
does not imply invalid or unauthorized access. AND transaction matching retains
the directory's existing aggregate role-evidence semantics. `MATCHED_FILTER` is an evidence flag, never permission to broaden
the exported role scope. Other user-level criteria (for example SAP User Group) select users; they do not replace that role scope.

The existing **Export scope** disclosure now contains **Assignment CSV users**: **All matching users** (default, all pages)
or **Selected users**. Selected-user exports intersect the explicit selection with all current filters. Empty or nonmatching
selection never falls back to everyone. Clearing selection while selected scope is active disables Export until users are
selected again or All matching users is chosen. Selection/filter/source changes cancel an in-flight download.
The server accepts the existing GET for all matching users and a CSRF-protected read-only POST with `selected_usernames`
for up to 5,000 selected users, avoiding a large username query string; the existing request-body limit remains enforced.

The separate Columns CSV exports only displayed directory rows and chosen columns (or explicitly all columns), not role
associations or other pages; it follows the displayed user filters. A user's detail CSV follows that detail's own role-view,
date and transaction filters, not an implicit copy of the parent directory filter. These exports keep their existing formats.

Columns include SAP identity, exact assigned role, assignment dates/status and
release metadata where applicable. Distinct validity intervals are retained. The
file is UTF-8 with BOM, semicolon-separated, quote-escaped and protected against
spreadsheet formulas. Dates use DD.MM.YYYY. No source values are modified.
Catalogue wildcard patterns are never substituted for concrete assigned role
names; existing import validation of assignment names remains unchanged.

The button is disabled for zero assignments or unsettled filters. An in-flight
export is cancelled if filters change; source-generation/day mismatches require
a refresh. Exports remain local and user initiated, using the existing desktop
save dialog or browser download. Each export is bounded to 32 MiB; narrow filters
if this limit is reached.

## Exact usernames, selection and bulk assignment

- **Pasting a list:** paste several usernames into *Search users* (one per line, from Excel, or separated by commas, semicolons or tabs), or type them in *Exact usernames* and choose *Apply list*. A paste converts only when it has at least two entries and every entry is a single token without spaces or an at-sign; typed text and phrases such as "Jane Doe, John Smith" stay an ordinary text search. Matching is exact and case-insensitive, duplicates are removed (up to 500 names), and users keep their original SAP spelling. A line under the toolbar reports requested, matched, not found, invalid, duplicates removed and users hidden by other filters; *Show details* lists them. The list appears as an *Exact usernames* chip, is stored in Saved Filters and follows the same selection used by the CSV export.
- **Selection:** the header checkbox selects the current page; *Select all N matching* selects every user matching the filters (names are fetched from `users-selection`, capped at 5,000); *Clear selection* clears only the selection. The selection survives paging and sorting and is cleared when the result set changes (any filter or the username list), so no invisible user can be affected. The toolbar shows `N matching · M selected`.
- **Export CSV** defaults to all matching users; choose **Selected users** under **Export scope** to use the explicit row selection. Role-filtered exports never include unrelated roles in either scope.
- **Assign group** opens the bulk dialog for the explicit selected usernames (see [Functional Groups](FUNCTIONAL_GROUPS.md)); the dialog states the number of users, shows current assignments, requires confirmation before replacing and reports applied, unchanged and failed users, retrying only the failed ones.

## Table presentation and exports

**Columns** opens the shared editor for visibility, order and one-line cells. Sticky selection/identity columns remain fixed; other fields can be
reordered or hidden. Preferences are local to the browser profile and persist on reload. Functional Groups use bounded pills; **+N** or **View groups**
opens a read-only list of every group, including archived labels, without opening a record editor. Exported group values include the complete list.

The primary table export uses selected columns in their current order; **Export all columns** is an explicit alternative. These exports contain
only displayed rows, not other result pages. Existing full assignment/evidence exports retain their documented all-matching scope and revision checks.
CSV escaping protects spreadsheet fields and table projections enforce the 32 MiB limit. Source observations and historical decisions are not changed.
