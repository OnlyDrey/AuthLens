# AuthLens architecture

AuthLens is a modular .NET application with one React frontend and two hosts: Windows Desktop and Server. This page describes the **current**
architecture of the 2.0.0 candidate (RC6). It is implemented; native Windows acceptance of the RC6 candidate is pending
([status](../validation/STATUS.md#rc6-candidate-status)).

**History.** The product was previously named SAP Lens. SAP Lens 1 (Python/FastAPI) is archived outside this repository (last commit with it in
place: `604f21e`); nothing active depends on it. Docker support was removed. The only Python left is the repository checks in `scripts/` and the
historical v1 reference generators in `backend/tools`, which regenerate committed comparison fixtures and are not part of builds or tests.
Their removal is deferred until migration completion is formally established. Compatibility identifiers that keep an earlier name are in the
[naming register](VERSIONING.md#compatibility-identifiers-naming-register).

## Project boundaries

| Project | Responsibility |
| --- | --- |
| `AuthLens.Domain` | CSV interpretation, normalization, catalogue/user analysis and SoD business rules |
| `AuthLens.Persistence` | SQLite schema, revisions, write coordination, storage and backup primitives |
| `AuthLens.Application` | Imports/jobs, accounts/sessions, review decisions, backup/restore and retention |
| `AuthLens.Api` | Shared host, HTTP routes (the v1-compatible API, `V1*.cs`), authentication/Origin boundary, source authority and embedded production frontend; runs as the Server |
| `AuthLens.Desktop` | WinForms/WebView2 lifecycle and private loopback launch |
| `AuthLens.Documents` | Frozen-model PDF/DOCX rendering and image validation |
| `AuthLens.Cli` | Local tools |

Keep business rules shared across hosts. Domain code does not own service installation or HTTP behavior. The frontend (React 18, TypeScript,
Vite, TanStack Query) uses typed API clients in `frontend/src/api`; permissions, revision conflicts, immutable evidence and data-integrity
enforcement remain on the server. See [UI integration](UI_INTEGRATION.md).

## Hosts and deployment modes

| Mode | Process and identity | Network | Storage |
| --- | --- | --- | --- |
| Desktop | `AuthLens.exe` per user, WebView2 | `127.0.0.1` on an OS-assigned port, private launch capability | `%LOCALAPPDATA%\AuthLens` |
| Server, Windows service | `AuthLens.Api.exe` as service `AuthLens`, identity `NT SERVICE\AuthLens` | HTTPS; loopback (Local), one private interface (Corporate) or behind an explicitly trusted reverse proxy (ReverseProxy) | `C:\ProgramData\AuthLens` (data, config, TLS, keys, releases) |
| Server, console | `AuthLens.Api.exe` started by an operator or the test launcher | Same rules as the service | Explicit `--data-dir` |

A loopback listener accepts loopback host names only. Network access needs HTTPS, an explicit host allow-list covered by the certificate SAN and,
behind a proxy, explicit trusted peers; host, Origin and CSRF validation stay enabled
([network access](../deployment/SERVER_NETWORK_ACCESS.md)).

## Authentication and authorization

Desktop trusts its single local user through the private launch capability. Server uses local accounts (`security/accounts.sqlite3`) with
sessions and role permissions; administration rights gate accounts, sources, backups and settings. Authorization is enforced in the backend for
every route; the UI only reflects it.

## Storage, imports and source authorization

Each installation uses dedicated mutable storage outside the program/release directory. SQLite (`authlens.sqlite3`) holds durable datasets,
settings, jobs and review history. Imports are staged and validated before activation; failed, missing or disabled sources never replace the
last valid dataset.

Each CSV source has a **file location** (browser upload, stored as a managed copy, or a file on the host, local or UNC) and an independent
**update mode** (static, or dynamic refresh from the file). Host files are read by the server process as its service identity, never with the
browser user's identity or stored credentials. They must lie inside an approved folder or be authorized exactly; the signed source authority
lives in a protected folder beside the data directory, outside restorable backups, and an unapproved UNC path causes no SMB contact. Validation
and import are hash-bound. See [imports and refresh](../data/IMPORT_AND_REFRESH.md).

## Reviews and evidence

Review decisions, SoD decisions, period snapshots and evidence fingerprints are immutable business records: later imports, filters or current
AD membership never reinterpret them, and reports render from one frozen model. Approval and hash verification do not become optional because
data was restored or sources changed. See [Account Review](../features/ACCOUNT_REVIEW.md), [Reviews](../features/REVIEWS.md), [SoD](../features/SOD.md)
and [reporting](REPORTING_ARCHITECTURE.md).

## Backup and recovery

Application backups are encrypted (`.slbak`) with the host recovery key and verified after writing. Every deployment and Server upgrade takes and
verifies a backup with the running release before it stops the service. Restore stages and verifies complete state before activation; a failed
restore never initializes an empty database. Operators can create and verify an independent recovery bundle and run an isolated restore
rehearsal. See [backup and recovery](../operations/BACKUP_AND_RECOVERY.md) and [database](DATABASE_DESIGN.md).

## Build, installer and update architecture

The root `build.ps1` produces one build id per build and writes the verified release (`Build\<version>\<build-id>`), both Inno Setup installers
and the packaged deployment, verification and recovery tooling (`Installer\<version>\<build-id>`) and, optionally, a portable ZIP package
(`Packages`) under `C:\AuthLens`. Installed Servers run from verified immutable release directories selected by a junction; updates use explicit
backup and rollback preparation, a deployment journal and a controlled program switch. Never copy live database files as a deployment shortcut.
See [canonical Windows build](../deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build), [installers](../deployment/WINDOWS_DEPLOYMENT.md#installers)
and [versioning](VERSIONING.md).
