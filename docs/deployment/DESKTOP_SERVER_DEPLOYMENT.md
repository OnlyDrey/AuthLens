# Desktop and Server distributions

AuthLens has one shared .NET backend and React frontend, packaged for Windows Desktop and Server.

## Desktop

Desktop is a per-user WinForms/WebView2 application. It launches the shared API on `127.0.0.1` with an OS-assigned port and private launch capability.
Its default installation is `%LOCALAPPDATA%\Programs\AuthLens Desktop`; mutable data is isolated under `%LOCALAPPDATA%\AuthLens\data`.
Network binding, extra hostnames, TLS/proxy options and server-account sign-in are refused in Desktop mode. Never expose its API to the LAN.

## Server

Server runs as a console process or the `AuthLens` Windows service. The canonical machine root is `C:\ProgramData\AuthLens`; the virtual service
identity is `NT SERVICE\AuthLens`. Network access needs explicit HTTPS, listen IP, hosts, credentials and dedicated storage. The frontend is served
by the same process. See [network/security](SERVER_NETWORK_ACCESS.md) and [Windows deployment](WINDOWS_DEPLOYMENT.md).

## Build and release folder

From a checkout of the intended source commit, use .NET SDK 10 and Node.js 24 or 25:

```powershell
.\build.ps1
```

The release script rebuilds the production frontend once, builds the solution and publishes self-contained Windows x64 executables. Use its
`-TestFilter` for an explicitly scoped validation run; `-SkipTests` is appropriate only when matching validation has already passed and source has
not changed. Never substitute a local dirty build for a verified release identity.

A versioned release contains `server/AuthLens.Api.exe`, `desktop/AuthLens.exe`, required native dependencies, symbols, helper tools, instructions,
`build-manifest.json` and `SHA256SUMS`. Existing release directories are never overwritten. Verify package scope and checksums after transfer.
Private data, configuration, certificates, keys, logs and credentials do not belong in packages.

## Frontend and branding

Production frontend assets are embedded in the shared API assembly and therefore ship with both hosts. Missing required files fail startup.
Branding sources are [assets/branding](../../assets/branding/); Vite emits the logo/favicon and both executable projects and Inno scripts consume
`app.ico`. Replacing the canonical source files preserves stable references; see [branding](../architecture/DESIGN_SYSTEM.md#branding-source-assets).

## Installers

The canonical command also builds installers from the same clean verified release and committed helper sources. Advanced installer-only invocation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\scripts\build-installers.ps1 -ReleasePath <release-directory> -Output C:\AuthLens-Build\installers
```

Inno Setup 6 is required. Desktop setup is per user and never requires Server configuration. Server Setup derives its program directory from reviewed
configuration (explicit absolute `/CONFIGFILE`, validated registered/managed discovery or the known default); ordinary upgrades need no `/DIR`.
Fresh configuration can be authored in the Server wizard; existing protected TLS/password files and keys remain explicitly provisioned.
Source-restricted firewall creation requires explicit approval; rule updates/removal remain incomplete. Each installer owns its validation callbacks; shared transaction code does not
select a different installer's configuration path. Existing data, installation identities and recovery artifacts remain protected.
See [installer transactions](WINDOWS_DEPLOYMENT.md#installers). Compilation does not replace native installation, upgrade, interruption and rollback checks.

## Backups, keys and update recovery

Use a verified encrypted backup and a complete rollback plan before changes. Restore into a separate clean environment when rehearsing recovery.
Keys, TLS and host/service configuration are provisioned explicitly and remain protected. Do not copy a live SQLite database or restore an older
archive over newer validated data to switch a program version. Upgrade confirmation does not itself delete protected backups.
See [backup/recovery](../operations/BACKUP_AND_RECOVERY.md).

## Acceptance

Check package identity and embedded frontend/icons, first-run state, filesystem permissions, Desktop lifecycle or Server service/HTTPS/account
behavior, database/evidence integrity, restart persistence, backup/restore and rollback. Use a dedicated acceptance root and synthetic data first.
No build, push or installer compilation automatically approves production deployment. [Current status](../validation/STATUS.md) distinguishes checks
that ran from platform-specific or external checks still outstanding.
