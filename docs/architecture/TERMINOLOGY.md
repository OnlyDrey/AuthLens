# Field terminology (TBL-04)

AuthLens uses one display label for each field that means the same thing in every module. The labels live in
`frontend/src/lib/fieldLabels.ts` (`FIELD`) and are used by table headers, column selectors, filters, detail views and report
configuration. They are display text only.

## Canonical labels

| Field | Label | Earlier labels replaced |
| --- | --- | --- |
| SAP account identifier | **SAP username** | SAP user, Username (SAP), username in profile and evidence summaries |
| Person behind the account (SAP or directory name of the same record) | **Employee** | Name, Full name |
| Name of an assigned or catalogue role | **Role name** | Role, Assigned role, Exact assigned role |
| Description of a role | **Role description** | Description (role columns only) |
| SAP user group | **SAP user group** | SAP User Group, User group, Group (SAP user group columns) |
| Employee Directory department | **Department** | Directory Department |
| Employee Directory job title | **Job title** | Job Title, Title (Dashboard filter) |
| Review decision state of a row | **Review status** | Review (SoD explorer and remediation columns), Review state (report configuration) |
| Release classification | **Release area**, **Release group**, **Release strategy** | Area, Group, Strategy, Release Area, Release Group, Release Strategy |

## Kept distinctions

Fields that only look alike keep their own names:

- **Username** for AuthLens application accounts (sign-in, User Management): not an SAP account.
- **Description** of a transaction (role detail, SoD source details): not a role description.
- **Role assignment** (a role with its validity interval) and **Single role** (SoD conflict evidence).
- **Exact usernames** (the exact list filter) and **Search users** (free-text search) stay separate concepts.
- Names of groups, risks, activities and review periods.

## What does not change

- API properties, database fields, saved-filter fields, URL parameters and view-history keys.
- Stable column keys: a renamed header declares its earlier text as `data-column-key`; `ConfigurableTable` uses it for the persisted
  column-preference key (`authlens.table-columns.*`), so saved column order and visibility survive the rename.
- CSV headers. Server exports keep their headers (`CsvColumn.Label` in `V1Reports.cs` is the CSV header; Reports shows the canonical label by
  the column's stable key instead, with the CSV header in the preview header's tooltip). The client table export (Columns, *Export visible
  columns*) writes the stable column key, and the SoD matrix CSV keeps `SAP user` and `SAP User Group`.

**Export headers awaiting a decision:** none were changed. Aligning CSV headers with the display labels (for example `Username` to
`SAP username`, `User group` to `SAP user group`, `Full name` to `Employee`) would change import and comparison contracts of consumers and needs
explicit approval.

## Filter discovery aliases

`FIELD_ALIASES` lists informal or earlier words for a canonical label (for example *sap user*, *user group*, *dept*, *title*); the filter
discovery search ([filter panels](COMPONENTS.md#tables-and-filter-panels-tbl-and-flt)) matches them.
