# CSV data lifecycle and refresh evidence

## Sources and compatibility

AuthLens has four independent local CSV sources: Role Catalogue, User–Role Mapping, Employee Directory and the [SoD Matrix](SOD_MATRIX.md). Role catalogue and user assignments default to **Dynamic**, preserving the existing refresh behavior. Employee Directory and the SoD Matrix default to **Static**, retaining snapshots until explicit replacement. Older schema-3 settings receive these additive defaults without losing feature preferences, profiles or paths.

Settings → Data Sources offers a source mode selector. Use the existing **Apply settings** action to persist mode changes; no second Save action is needed. Changing a mode does not delete imported records. Existing CSV mappings, delimiter/encoding controls and validation remain authoritative.

- **Static:** selecting a replacement automatically validates and imports it. Global Refresh skips the CSV and continues using the private snapshot, even if the original file is unavailable.
- **Dynamic:** Global Refresh rereads the entire configured file. A daily export can overwrite that file; AuthLens does not schedule or monitor exports. A complete valid replacement removes records absent from the incoming file.

Never point two sources at different interpretations of the same file without configuring their respective import formats.

## Preparation, publication and persistence

Parsing happens in a persistent background job, off the request thread. Each candidate is validated separately and staged as a dataset revision in the AuthLens database (`authlens.sqlite3`: `Datasets` with its canonical rows in `DatasetRecords`, identified by the SHA-256 of its content); Employee Directory uses the same store (source `employees`). Canonical observations are rebuilt from the stored rows through the catalogue/user processing, not deserialized executable objects../operations/BACKUP_AND_RECOVERY.md).

Activation is one database transaction: the staged revision becomes `Active`, the previous one `Retired` (a unique index allows one active revision per source), and the settings document records the source path and report reference with a revision check that rejects a competing settings/import operation. Only after that commit are the prepared cache generation and directory indexes activated. Readers keep the previous generation during preparation. Cancellation prevents the commit; no timed-out worker may later overwrite a newer generation.

A source read/validation/staging failure retains that source. Other independent sources can succeed. If catalogue data changes while user CSV reading fails, retained **raw validated user observations** are remapped against the new catalogue. This rebuilds wildcard/transaction indexes; old derived transaction claims are never mixed with a new catalogue. A transaction or storage failure before the activation commit activates none of the staged candidates.

Successful imports store full replacements, not email-based upserts. For example, replacing 1,310 directory rows with 1,295 leaves exactly 1,295 active records, with removed employees absent from email/manager indexes. Missing email remains a quality warning. Empty email keys are excluded from duplicate-email indexing.

Startup restores durable observations and initializes enabled dynamic sources. Failed live reads can retain restored data. Static sources restore without reopening the original CSV. A legacy, enabled directory that only has a readable path is validated and durably captured once at startup. An invalid/missing snapshot is reported; it is never silently accepted as valid data. Original source availability and durable snapshot availability are separate facts.

Staged and retired revisions are private application data inside the database, never build inputs. Clearing a source retires its active revision; retired revisions are removed only by approved [data retention](#data-retention), and every application backup contains the database as a whole.

## Change identity and evidence

Logical records are compared independently of row order. Exact duplicate representations follow the existing importer's deduplication rules; distinct assignment intervals remain distinct evidence.

| Source | Stable grouping key | Important limitation |
|---|---|---|
| Catalogue | AGR_NAME, CHILD_AGR, PARENT_AGR, Effective_Role, TCODE | Multiple relationship observations are retained. |
| User assignments | Normalized USERNAME, exact-role identity, USER_GROUP | Exact intervals cancel first; multiple remaining observations are not arbitrarily paired. |
| Employees | DistinguishedName, otherwise SamAccountName | Email and display name are never universal record identifiers. |

Exact observations cancel as multisets. Only one remaining old/new record for a stable key is reported as modified. Ambiguous groups and records without usable identifiers remain additions/removals with an explicit identity limitation. Modified records retain field-level before/after values. Original display values remain available; normalization does not rewrite imported identity attributes.

Snapshots/reports have version-1 contracts and bounded input/storage sizes. A source changing during its read is rejected; retry after the external export finishes.

## Refresh results and history

The global refresh control is application-scoped and prevents concurrent repeated requests. Results appear at the top of the main content, not inside the navbar:

- Green: successful changes, with **View Changes**.
- Neutral: no changes, with no change-view action.
- Red: partial or complete failure, with **View Errors**, never View Changes.

Skipped static, disabled and unconfigured sources are counted separately. A partial failure does not turn successful independent updates into failures. Dismissing the banner does not remove its report.

Data Sources and Health & Diagnostics expose five recent private operation reports. Changes support source/type filters, search, bounded pages, copyable identifiers, expandable field evidence and CSV export. Export uses the selected change filters and escapes spreadsheet formula prefixes. Error views use safe categories and recovery advice without exposing exception text, private paths or CSV contents.

Reports contain personal data and stay local. Diagnostic exports contain only allowlisted aggregate status; they exclude report identities, record details, source paths and employee data. Normal logs never include imported record values. Older reports are removed by retention; corrupt/unavailable reports produce an explicit recovery state.

## Scheduled refresh

### Server source policy remediation (awaiting Windows acceptance)

All four CSV sources (Role Catalogue, User Access, SoD Matrix, Employee Directory) share one workflow and one policy for selection,
validation, preview, individual refresh and Global Refresh.

**Unified selection (WP33, after RC5).** In **Settings → Data Sources** every source asks two independent questions:

1. **File location.** *Upload from this device* (a copy of a file from the device running the browser) or *File on the AuthLens host* (a
   file the server reads directly). On the host, a local path (`D:\Exports\users.csv`) and a network path (`\\fileserver\share\users.csv`) use
   the same field; the type is detected from the path and shown, never chosen up front. **Browse host…** opens the host file picker. Desktop
   installations offer the upload (system file dialog) and a path field for a file on that computer.
2. **Update mode.** *Static: replace manually* or *Dynamic: refresh from the file*. It can change before or after validation and import:
   the configured file and the active dataset are kept, so switching back needs no new selection; saving the change reads nothing (the next
   Global or scheduled refresh reads a Dynamic file, or use **Refresh source**). An uploaded copy cannot follow changes on the device it came
   from: the panel says so and points to a host file instead.

**Host file picker.** An Open-dialog style browser of the AuthLens **server** (not the browser device; usable from a phone): host name, approved
locations (operator folders, administrator-approved folders, folders of configured sources), breadcrumbs, parent folder, direct path entry,
search within the folder, sorting by name, size and modification time, CSV filter, folder and file icons, Select and Cancel, and explicit
loading, empty, not approved, access denied, missing and unavailable states. It never creates, renames, moves, deletes or opens files; selecting
returns the host path only.

**Approved folders.** Administrators approve specific folders in the picker (an explicit confirmation; **Approved folders** lists and removes
them). Files below an approved folder validate without a per-file grant (`authorization: approved_folder`); any other host file is approved
for its exact source when it is first validated. Folder approval is stored in the protected, signed source authority (next to exact grants,
outside restorable data) and refuses volume and share roots, the AuthLens installation and data, and Windows, program and user-profile
locations. Operator folders (`AUTHLENS_SOURCE_ROOTS`) keep working. **Application approval is not a Windows permission:** the AuthLens service
identity still needs NTFS read access (and share access for network files); AuthLens never changes NTFS or share permissions, never asks for
or stores SMB credentials, and never uses the browser user's sign-in.

**Browsing security.** Browsing and approval require administration. A folder outside every approved location is refused before the
filesystem or network is touched, so an unapproved UNC path causes no SMB request; network targets must resolve to private addresses; every
directory from the volume root down must be a plain directory (junctions and symbolic links are refused, and skipped inside listings); hidden,
system and device entries are not listed; AuthLens private state (data, keys, TLS, backups, deployment state) is never listed even below a broad
operator folder; listings are capped at 2,000 entries. API: `GET /api/server/sources/browse[?path=&q=&all=]`, `GET|POST|DELETE
/api/server/sources/roots`.

**Validate and import** (the normal flow) reads the complete dataset as the running backend identity and imports exactly that validated
content (hash-bound; a suspicious reduction is still held for confirmation). **Validate only** checks without changing data; **Import
validated file** imports it later only if its SHA-256 still matches, and disappears as soon as the path changes. A changed file requires
validation again. Normal source configuration does not require editing JSON, registry or environment variables.

Validation runs in the AuthLens server process, so it proves access for the actual service identity, not for an administrator's PowerShell
session. Outcomes (`category`; the last valid dataset is always kept, `previous_preserved: true`):

| Category | Meaning |
| --- | --- |
| `validated` (status) | The source is accessible and complete; record count reported, nothing activated by a test |
| `invalid_path` | Not an absolute `.csv` path, or an unsupported form (device path, alternate data stream, traversal, junction or symbolic link) |
| `not_a_file` | The path names a folder; a local folder is detected, a UNC path is never touched before authorization |
| `policy_prohibited` | Authorization required: not authorized exactly on this host or by an approved directory (also after restore or revocation) |
| `missing` | The file does not exist (or the share path does not) |
| `access_denied` | The service identity cannot read it (NTFS, or for UNC also the SMB share permission) |
| `network_unavailable` | The share or server is unreachable, or its name does not resolve |
| `malformed_csv`, `encoding`, `headers`, `dates`, `validation` | Invalid CSV format, encoding, missing required columns or mappings, invalid dates, other validation |
| `empty` | No usable records (empty or header only) |
| `source_changed` | The file changed while it was read or after validation |

An unconfigured source shows its setup state (`authorization: none`, `configured: false`) and is counted separately by Global Refresh.

Exact-file authorization is source-specific and held in a protected sibling folder of the data directory,
`.authlens-source-policy-<data-path-hash>`. Deployment provisions only this folder for the service identity;
it grants no source/share access. The authority is authenticated to the protected host token and canonical
data path, excluded from application backups and never inferred from restored settings. Changing the host
token or data location requires reauthorization. Interrupted/invalid authority files fail closed; preserve
them for operator review. The administrator can replace one source's exact authorization, not browse files
or grant a whole directory. Application installation internals cannot be authorized through this interface.

For compatibility, administrator requests may still select CSVs beneath `<data-dir>/sources` or an additional
operator-approved directory. Configure the latter
with deployment JSON `SourceDirectory` (passed as `--source-dir`), or `AUTHLENS_SOURCE_DIR`. Advanced hosts may
provide `AUTHLENS_SOURCE_ROOTS` as a JSON array of absolute directories. Local directories and Windows UNC
directories are supported; roots are host configuration, excluded from application backups and never changed
by a browser. A restored external path requires approval on the destination host before a live read; its
saved path, mode and durable snapshot remain intact while approval is pending.

Use a dedicated export directory, not a drive containing unrelated confidential files. The actual service
identity requires directory traversal and CSV read access; for UNC sources both share and NTFS permissions
must allow that identity. Virtual accounts normally authenticate remotely as the computer account; confirm
the effective identity with the domain administrator. No credentials are stored by this workflow, and the
application does not change service accounts or grant filesystem access. Restart after host-policy changes.

Paths must be absolute CSV paths, authorized exactly or inside an approved directory at a directory boundary. Device paths,
alternate streams, traversal spellings, symbolic links and reparse points in any ancestor are refused.
UNC targets must resolve only to private or loopback addresses; administrative `$` shares and WebDAV-style
targets are refused. No SMB read is attempted until source authorization succeeds. Enterprise DNS, SMB
signing, DFS referral policy and share administrators remain trusted host infrastructure; DNS validation
does not pin the SMB session or replace host outbound-authentication policy. Protect source ancestors
against untrusted replacement during reads. Network
availability and ACL checks execute as the running service. Missing files, denied access, unavailable shares,
policy refusal and parser/schema errors retain the last validated snapshot. Source status shows the last
attempt separately from the durable snapshot; it does not claim current reachability without a read.
Refresh can use the saved source without disclosing its path back to the browser.

**Authorization status and revocation.** `GET /api/server/sources/{source}` (administrator only, `no-store`) reports the configured path,
mode and `authorization` without reading the source or contacting a share: `none`, `managed` (upload copy), `approved_root`, `exact`,
`required` (configured but needs authorization on this host, for example after restore or revocation) or `invalid` (path refused, or the
protected authority file is tampered/unreadable; fails closed). The Data Sources panel shows this status. **Revoke authorization**
(`DELETE /api/server/sources/{source}/authorize`) removes only that source's exact authority: the configured path, mode and last valid
snapshot are retained, and later validation or refresh is refused (`policy_prohibited`) until an administrator authorizes the file again.
Lexical UNC rules (named server and share, no administrative `$` share, no `@` WebDAV host) are enforced when authorizing, before anything
is stored; DNS private-address checks run before any SMB read. Authorization and revocation are logged under `AuthLens.Sources` with the actor.
Opening the panel selects **Local server file** or **Network file (UNC)** when such a path is configured, otherwise **Browser upload**.

#### Data-source compatibility matrix

Comparison basis: historical Python implementation at `604f21e` (`deployment.source_path`,
`validate_server_sources`, source selection and CSV lifecycle), current .NET routes and focused tests.
Historical code was inspected only; no Python service or fixtures were added to the active application.

| Contract | Python reference | Current .NET implementation | Remaining acceptance |
| --- | --- | --- | --- |
| Role Catalogue / SAP role extract | Upload and confined server path; Static/Dynamic | Shared import pipeline, approved local/UNC source roots, individual/Global Refresh | Actual Windows Service local/UNC reads |
| User–Role Mapping / SAP user extract | Independent upload/path and modes | Same shared policy and pipeline | Actual Windows Service local/UNC reads |
| Employee Directory | Fixed schema, upload/path, Static/Dynamic, durable snapshot | Shared policy includes directory preview/import and refresh; fixed schema retained | Restored alpha backup with real service identity |
| SoD Matrix | Upload/path, modes, matrix validation and retained review evidence | Shared policy; existing fingerprint, held-import and revision/approval paths retained | Review periods, frozen evidence and decisions across live matrix replacement |
| Browser uploads | Static managed uploads | Static multipart upload and durable managed copy | Native deployed UI smoke test |
| Restore / restart | Saved source and durable snapshot; host source-root policy | Saved settings persist; host approval is independent; failed reads retain snapshots | AuthLens alpha and supported SAP Lens backup acceptance on Windows |
| Unavailable/invalid source | Retain last valid data | Categorized refresh failures and durable snapshot retained | Denied ACL, disconnected share and recovery under SCM |

#### Data-source coverage matrix

Sources: the **SAP extract** is the Role Catalogue (SAP role/transaction extract) and the User–Role Mapping (SAP user/assignment extract);
with the Employee Directory and the SoD Matrix these are all file-based sources (`Sources.All`); there are no others. Every source uses the
same source policy (`ServerSourcePolicy`, `ServerSourceAuthorization`), validation endpoint, activation (`/api/data-sources/{source}/select`,
multipart upload) and import pipeline (`ImportService`, staged and atomically activated dataset revisions); individual refresh and Global
Refresh use the same resolution. Evidence: focused .NET tests on VM130 (Windows, not as a service) unless stated.

| Capability | Role Catalogue | User–Role Mapping | Employee Directory | SoD Matrix | Evidence | Native acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| Browser upload, Static | Yes | Yes | Yes | Yes | `DataSourcesTests` upload cases; `server-source-configuration.spec.ts` (panel) | D1 |
| Local server file, Static and Dynamic | Yes | Yes | Yes | Yes | `DataSourcesTests.Administrator_authorizes_validates_and_activates_exact_server_file` (4 sources × 2 modes, restart, missing file) | D2 |
| Network file (UNC), Static and Dynamic | Yes (same code path) | Yes | Yes | Yes | UNC lexical rules in `ServerSourcePolicyTests`; no SMB read is possible on VM130 | **D3, release blocker** |
| Validate and import in one step (hash-bound) | Yes | Yes | Yes | Yes | `server-source-configuration.spec.ts` (all four panels) | D2 |
| Validation outcomes (not configured, authorization required, missing, folder, invalid path, unsafe path, share unavailable, access denied, malformed, headers, empty, valid) | Yes | Yes | Yes | Yes | `DataSourcesTests.Source_validation_distinguishes_folder_invalid_path_authorization_missing_empty_and_valid`, `ServerSourcePolicyTests.Refusals_name_the_reason_and_never_touch_a_UNC_path_before_authorization`, category mapping | D5 to D7, D12 |
| Static not reread by Global Refresh; Dynamic reread | Yes | Yes | Yes | Yes | `DataSourcesTests`, `RefreshTests` | D4 |
| Failed or empty refresh keeps the last valid dataset | Yes | Yes | Yes | Yes | `RefreshTests.A_dynamic_source_whose_export_became_empty_keeps_its_data_on_refresh` (`empty`), `DataSourcesTests` | D5, D10 |
| Partial success, per-source errors, View Changes only with changes | Yes | Yes | Yes | Yes | `RefreshTests`, `RefreshReportTests` | D4 |
| Suspicious reduction held for confirmation | Yes | Yes | Yes | Yes | `SettingsReimportTests`, `DataSourcesTests` | D5 |
| Exact authorization, revocation, `required` after restore | Yes | Yes | Yes | Yes | `DataSourcesTests.Revoked_server_authority_fails_closed_and_preserves_configuration_and_snapshot`, `ServerSourcePolicyTests` | D8, E3 |
| Restart persistence (configuration, mode, snapshot) | Yes | Yes | Yes | Yes | `DataSourcesTests` restart cases | D9 |
| Backup and restore, legacy migration | Yes | Yes | Yes | Yes | `ApplicationBackupTests`, `LegacyRestoreTests` (snapshots restored); the source authority is excluded from backups by design | E3, E5 |
| Review and SoD evidence preserved across imports | n/a | Yes (review history) | n/a | Yes (fingerprints, revisions, stale reviews, approvals) | `SodSourceMetadataTests` (run in this round); the review and SoD suites were not rerun because their code is unchanged | E4 |
| Administrator-only configuration | Yes | Yes | Yes | Yes | `ServerSourcePolicyTests` permission assertions | C2 smoke |

Implemented in this round: precise validation categories (`not_a_file`, `invalid_path`, `empty`; `policy_prohibited` now means
authorization required) and **Validate and import**. Remaining gaps: native Windows Service reads of local and UNC files (same-host and remote
SMB), restored-source reauthorization end to end, and a persisted audit trail of source authorization beyond the service log (today
authorization, revocation and validation are logged under `AuthLens.Sources` with the actor). Mocked or local tests never count as SMB or
service-identity acceptance.

Source-type compatibility (all four sources share one policy and pipeline; status per combination):

| Combination | Implemented | Verified (focused tests, Windows host, not as a service) | Native Windows Service acceptance |
| --- | --- | --- | --- |
| Browser upload, Static | Yes | `DataSourcesTests` upload cases | Pending |
| Local absolute path, Static and Dynamic, exact authorization | Yes | `DataSourcesTests.Administrator_authorizes_validates_and_activates_exact_server_file` (8 cases: 4 sources × 2 modes; restart, missing file, snapshot retained) | Pending (service identity NTFS read) |
| Local path in operator-approved root | Yes | `DataSourcesTests`, `ServerSourcePolicyTests` | Pending |
| Revocation, `required`/`invalid` status | Yes | `DataSourcesTests.Revoked_server_authority_fails_closed_and_preserves_configuration_and_snapshot`, `ServerSourcePolicyTests` | Pending |
| UNC lexical policy (`$` share, `@` host, missing share) | Yes | `ServerSourcePolicyTests` (Windows only) | Pending |
| UNC same-server and remote SMB read, Static and Dynamic | Yes (shared code path) | Not verifiable without SMB shares | **Pending, release blocker** |
| Validate before activation, hash-bound activation | Yes | `DataSourcesTests` (changed file refused) | Pending |
| Individual and Global Refresh, failure retains snapshot | Yes | `DataSourcesTests` | Pending under SCM |
| Unauthorized (non-administrator) API access | Yes | `V1Auth.Permission` assertions in `ServerSourcePolicyTests` | Pending reviewer smoke test |
| Restore requires reauthorization, path/mode/snapshot kept | Yes (authority excluded from backups) | Status `required` covered by unit test; end-to-end restore not run | **Pending** |
| Native Linux absolute paths | Yes (same code path) | Not run in this round (Windows host) | n/a |

No supported source type is intentionally dropped. Native UNC/service identity, restored-source and SoD
evidence acceptance are release blockers until executed; focused local tests do not establish those results.

Acceptance in a disposable Windows Service installation must cover every source with local and UNC files,
Static and Dynamic modes, individual and Global Refresh, restart and restore, administrator versus reviewer
requests, denied ACLs, unavailable shares, malformed/empty files and recovery. Record dataset fingerprints,
SoD period/evidence fingerprints and decisions before failures/replacements and verify their preservation.
Never perform this test against the retained DASH1 installation.

**Settings → Runtime & Scheduling** can run the same refresh automatically. The backend schedules it, so no browser tab has to be open, and every run is the normal refresh: Dynamic sources are re-read, Static sources are not, a changed source is validated before it replaces the previous one, and any failure keeps the previously validated data.

- **Schedule.** Enable it, then choose a daily time (HH:MM, 24-hour) or an advanced five-field cron expression (`minute hour day-of-month month day-of-week`; lists, ranges, steps and `JAN`/`MON` names; Sunday is 0 or 7; day-of-month and weekday are OR-ed like standard cron). Runs must be at least 5 minutes apart. The page explains the schedule in words and lists the next runs before you apply it.
- **Time zone.** Local time (the computer or server), UTC, or an IANA name such as Europe/Oslo. The pinned `tzdata` database ships with the runtime, including Windows packages, so named zones work without an operating-system IANA database. Daily time uses explicit 24-hour `HH:mm` entry regardless of browser/Windows AM/PM preferences. A local time skipped by a spring-forward change is skipped; a repeated hour runs once.
- **Safety.** One process owns the data store, so a schedule cannot run twice, and a scheduled run is skipped when another load or refresh is already running. A slot missed while the application was not running is skipped, never replayed; editing the schedule starts it fresh from that moment.
- **Status.** Next run, last attempted run, last successful run, last failure (and failures in a row) and the last outcome (succeeded, partly failed, failed, skipped) are shown in Settings and summarized, without paths, in the diagnostics export. Failure messages are generic; details stay in the refresh history.

| Deployment | When scheduled refresh runs |
| --- | --- |
| Windows Desktop | Only while the AuthLens window is open |
| Windows Service | Continuously while the service runs; no sign-in or browser needed |
| Linux server / systemd | Continuously while the unit runs |

## Feature dependencies

1. User–Role Mapping enables SAP assignment investigations.
2. Employee Directory independently enables local employee records.
3. SAP Identity Enrichment is derived from both enabled features with available data; it is not an extra preference to keep in sync.

Disabling either source feature preserves its preference-independent data and configuration. Employee Directory does not automatically switch off when mapping is disabled. Its local records remain usable, while SAP email enrichment/manager-to-SAP navigation is unavailable. Backend endpoints enforce dependencies; hiding UI controls is not the boundary. Re-enabling valid retained sources resumes operation without reimport.

The older `operational_status` directory API field remains a compatibility description of enrichment readiness. The explicit `directory_operational` and `enrichment` fields distinguish local directory availability from matching prerequisites.

## Employee import and preview

For all four sources, selecting a file automatically reads, validates, stages and
activates a complete non-empty dataset. There is no separate normal-flow Validate,
Confirm or Import action. **Browse / Upload file** (one label for every source) is always available,
also when a file is already configured; only an import in progress for that source
blocks it. It opens the browser's file chooser (also in the Desktop window); a path the server can read
can instead be entered in the file location field and committed with Enter. A replacement that does not validate (invalid, empty or
unreadable) never replaces the configured file or its data: the attempted path stays in the field
for correction or column mapping, and the message says the active file is unchanged and names
it, while a valid replacement is confirmed by file name and counts.
Native Browse activates the selected server-visible file;
browser uploads activate a private Static source. Entering a path activates on Enter
or leaving the field. Selecting the same file again explicitly revalidates it.

Settings shows progress, committed record/change counts, source status and links to
View changes, Preview data and technical details. Preview inspects the current
validated snapshot without rereading the original CSV. For the **SoD Matrix** it is a read-only inspection: record, risk, activity and transaction counts, validation results (documented columns, required values, both activity sides, evaluated types, duplicates, missing descriptions, overlapping transactions), a column-interpretation table (the schema is fixed, so the meanings are explained; a mapping only chooses the source header), quality warnings, import metadata (file, mode, imported, checked, snapshot, feature state) and the imported records. Employee preview retains
search, sorting, paging and quality filters. Missing emails are warnings, not a
reason to discard otherwise valid records. Feature preferences are independent:
importing does not enable a disabled optional feature.

The previous dataset remains active while validation runs. Empty, unreadable,
malformed or changing files cannot replace it. Settings revision checks, source
signature checks and a single active load prevent conflicting publication. Source
files must remain stable until validation completes; select again after an export
finishes. Explicit Clear source data requires confirmation and never deletes the
original CSV. Opening Data Sources does not reimport configured files.

Mode/profile-only edits use Apply settings. Completed automatic imports persist
immediately and are not undone by Cancel settings; unrelated unsaved edits survive
source activation. Advanced mapping and optional parsing inspection remain available
for custom formats. The legacy preview/digest/import API contract remains supported
for existing callers; it is no longer the normal Settings workflow.

## Platform validation

Automated browser and backend tests use synthetic identities. Fresh-process snapshot restoration on Linux verifies persistence logic but does not prove Windows/WebView2, native file dialogs or UNC-share access. Run those checks on Windows before treating a new desktop distribution as validated. No new executable is built by these changes.

## SoD Matrix import format, mapping and validation

Settings → Data Sources → SoD Matrix has the same **Advanced import format and column mapping** section as the other CSV sources, in three steps: *CSV Import Format* (delimiter and encoding, both automatic by default; the documented columns RISK through TTEXT are a fixed schema), *Column mapping* (columns are matched by name; choose a source column only where a header differs, for example `Risk_ID` for RISK) and *Validation & preview* (counts, parser errors, SoD-specific checks and sample rows, in a table that scrolls inside its own container). The section inspects the selected file through `POST /api/data-sources/sod/inspect`, which parses it exactly as an import would but stores nothing: active data, risk definitions, decisions and review snapshots are never touched, and an invalid file never replaces the last valid dataset. The format and mapping are saved with the next import or **Apply settings** (`sod_import` in the configuration) and are used for static and dynamic refreshes. Browse / Upload file, Refresh source, Preview data, View changes, Technical source details and Clear source data are unchanged.


### Browser file uploads

In Settings → Data Sources, **Browse / Upload file** opens the browser's file picker
for Role Catalogue, User Access, Employee Directory and SoD Matrix CSVs. No server
filesystem path is required. Desktop WebView2 uses the same browser file picker; a path the server can read can
also be entered under *Advanced server source path* and committed with Enter. A browser connected to the desktop backend can also upload using its authenticated session.

The authenticated multipart request (`POST /api/server/uploads/{source}/activate`)
carries one CSV, the current settings revision and optional existing import profile.
It reuses the same source-selection, complete validation, atomic activation and snapshot
persistence service as desktop browsing. Only after activation succeeds does the shared
application-data owner refresh dependent views and show record/change counts. Active
filename, import timestamps and snapshot metadata remain available beside the source controls.

Limits are 50 MiB for Employee Directory and 128 MiB for other CSV sources, with bounded
multipart overhead and form fields. Empty files, invalid names/types/schemas, interrupted
uploads, stale revisions and concurrent replacements are rejected without replacing valid
data. Failed staged files and multipart temporary files are cleaned up. Files use generated
private names and Static mode; Global Refresh never rereads a client device. Optional
administrator-managed Dynamic paths remain under Advanced server source path and follow
server source-root permissions. Existing raw staging endpoints remain compatible with
packaging tools, but the UI uses multipart activation, not the legacy staging/confirmation flow.


There is one primary **Browse / Upload file** action per Data Sources tab. It uses the
authenticated multipart uploader in the browser and in the Desktop window alike. The optional
**Advanced server source path** contains only the path input, with no second Browse action.
Uploaded replacements explicitly use Static mode (shown beside the action and in completion
feedback/source mode); administrator-selected paths retain the chosen Static/Dynamic mode.
Global/manual/scheduled refresh behavior, inspection and failure recovery are unchanged.

## Source-specific refresh and the unchanged fast path

Start-up (Dynamic sources) and every refresh evaluate each source on its own:

1. **Read and hash.** The configured file is read and parsed with the active import profile (or SoD format), and the SHA-256 of its canonical
   records is computed.
2. **Unchanged:** a hash equal to the active revision's `ContentHash` means the file reproduces the active data exactly. The source is reported
   `unchanged` (marked `fast_path`); nothing is staged, compared again, anomaly-checked or activated, and its `checked_at` is updated. The
   content is never trusted by timestamp or size.
3. **Changed:** only that source is staged as a new revision, compared with the previous active revision of the same source, anomaly-checked
   and activated (or held for confirmation). Users are mapped against the catalogue that is active after the refresh.

Activation is atomic. The candidate rows are streamed into a `Staged` revision in bounded batches (invisible to readers); a suspicious import
stays `Held` until an administrator confirms it; activation is one transaction that marks the revision `Active`, retires the previous one and
records the settings reference. A failed or cancelled job leaves its revision `Failed` or `Discarded`, never active. Readers switch to the new
revision as one object after the commit. SQLite's integrity check runs at every start and gates readiness (`/health/ready`).

## Data retention

Old superseded source snapshots, completed review periods and expired automatic backups are cleaned up by three separate, approval-gated retention categories.
The rules, previews, approvals, recovery and undo are described in [Data retention](../operations/BACKUP_AND_RECOVERY.md#retention-retention-tab).

## Import checks: suspicious versus invalid

Every replacement source is compared with the **active revision of the same source** (roles, users, employees or SoD) and with nothing else: not another source, not an
unactivated or held file. A first import has nothing to compare and is never held.

| Outcome | Meaning | What happens |
| --- | --- | --- |
| Invalid | Structurally unusable: no records, wrong headers, bad dates, unreadable | Rejected. Cannot be confirmed. `severity: invalid`, `confirmable: false`. |
| Suspicious | Valid, but a sharp reduction against the active revision | Parsed and reported, **not activated**. Needs explicit confirmation. `category: needs_confirmation`, `severity: suspicious`. |
| Normal | Anything else | Activated atomically as before. |

Rules (Settings > Data Sources > Import checks; defaults 30 % and 20 records, changes apply with Apply settings):

- **Reduction:** records or a distinct-entity count falls by more than the limit. Entities per source: roles - catalogue entries and transactions; users - SAP users and assigned roles;
  employees - directory accounts; SoD - risks.
- **Missing group:** every record of an organizational group (user group, module area or department) disappears and that group held at least 5 records and 1 % of the previous source.
- Active sources smaller than the minimum are never held, and the checks can be switched off. The limit is between 1 % and 95 %.

A held import keeps the active data, settings revision and snapshots untouched. The API answers `409` with `code: import_needs_confirmation`, the triggered checks and the old and new counts; the
Settings dialog shows the same report. Importing again with confirmation (`confirm_anomalies`, upload form field of the same name) activates it through the normal atomic path and appends an entry
(source, time, actor, triggered checks, old and new record counts; last 100) to `data_lifecycle.confirmations`. A scheduled or startup refresh that finds a suspicious file reports the source as
failed with `previous_preserved: true` and never activates it.


## Managed source copies and import policy

Each durable import job captures the chosen import-check policy, rather than reading mutable process-wide policy at execution time. Header-only or otherwise unusable sources cannot replace valid data, including by confirming a historical empty held revision. The default holds a drop over 30 percent when the previous source has at least 20 records; the saved policy can be changed explicitly without allowing malformed input.

Successful and held imports retain a private immutable CSV addressed by its byte SHA-256 and linked from the dataset report. Files and canonical records have distinct hashes: raw formatting changes need not alter the business observations. Failed imports retain the last valid copy. Copies are included in the existing encrypted backup and rebound to the restored data root on another machine; see [managed imports and portability](../operations/BACKUP_AND_RECOVERY.md#managed-imports-and-portability). Old archives without copies still restore their durable observations.

SAP `data_revision` depends on catalogue/user revisions and the independent Employee Directory component. An SoD-only change updates its own generation, not the SAP revision. Functional Group and Account Review confirmations use the authenticated account or stable Desktop reviewer profile; request aliases never change attribution or rewrite prior history.
