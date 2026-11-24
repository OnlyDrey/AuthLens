# AuthLens architecture

AuthLens is a modular .NET application with one React frontend and two hosts: Windows Desktop and Server.

## Project boundaries

| Project | Responsibility |
| --- | --- |
| `AuthLens.Domain` | CSV interpretation, normalization, catalogue/user analysis and SoD business rules |
| `AuthLens.Persistence` | SQLite schema, revisions, write coordination, storage and backup primitives |
| `AuthLens.Application` | Imports/jobs, accounts/sessions, review decisions, backup/restore and retention |
| `AuthLens.Api` | Shared host, HTTP routes, authentication/Origin boundary and embedded production frontend |
| `AuthLens.Desktop` | WinForms/WebView2 lifecycle and private loopback launch |
| `AuthLens.Documents` | Frozen-model PDF/DOCX rendering and image validation |
| `AuthLens.Cli` | Local tools |

Keep business rules shared across hosts. Domain code does not own service installation or HTTP behavior. The frontend uses typed API clients;
permissions, revision conflicts, immutable evidence and data-integrity enforcement remain on the server.

## Storage and imports

Each installation uses dedicated mutable storage outside the program/release directory. SQLite holds durable datasets, settings, jobs and review
history. Managed source copies are part of protected application state. Imports are staged and validated before activation; missing or disabled
optional sources never authorize erasing valid observations. Writes use the existing coordination and transaction boundaries.

Review decisions and evidence snapshots are immutable business records. Approval/hash verification does not become optional because data was
restored or sources changed. See [database](DATABASE_DESIGN.md), [imports](../data/IMPORT_AND_REFRESH.md) and [Account Review](../features/ACCOUNT_REVIEW.md).

## Hosting and security

Desktop is per user, uses an OS-assigned loopback port and a private launch capability. Server owns separate storage, explicit configuration,
local-account authentication, role permissions and HTTPS. Host/origin/CSRF validation stays enabled behind a proxy; forwarded headers require
explicit narrow trust. Background jobs and scheduled refresh obey configured source modes and permissions.

Updates use verified immutable release directories, explicit backup/rollback preparation and a controlled program switch. Restore stages and verifies
complete state before activation. Never copy live database files as a deployment shortcut or silently initialize an empty database on recovery failure.

See [UI integration](UI_INTEGRATION.md), [security/network](../deployment/SERVER_NETWORK_ACCESS.md),
[deployment](../deployment/WINDOWS_DEPLOYMENT.md), [backup/recovery](../operations/BACKUP_AND_RECOVERY.md) and [acceptance](../validation/STATUS.md).
