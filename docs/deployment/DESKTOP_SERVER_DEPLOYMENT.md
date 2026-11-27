# Desktop and Server distributions

AuthLens has one shared .NET backend and React frontend, packaged for Windows Desktop and Server.

The development target is `2.0.0`; it is **NOT APPROVED for production** until the [release gates](../architecture/VERSIONING.md#200-target-notes-and-approval-gates)
and [native acceptance](../validation/STATUS.md#200-release-gates) are complete. An unsigned diagnostic build is not a production candidate.

## Desktop

Desktop is a per-user WinForms/WebView2 application. It launches the shared API on `127.0.0.1` with an OS-assigned port and private launch capability.
Its default installation is `%LOCALAPPDATA%\Programs\AuthLens Desktop`; mutable data is isolated under `%LOCALAPPDATA%\AuthLens\data`.
Network binding, extra hostnames, TLS/proxy options and server-account sign-in are refused in Desktop mode. Never expose its API to the LAN.

The supported alpha-to-stable upgrade preserves the existing data directory, compares semantic versions from verified
manifests, creates a protective encrypted backup and validates rollback compatibility. Windows `2.0.0.0` is the stable
file version even though alpha used `2.0.0.1`; numeric revision ordering must not reject that product upgrade. Close Desktop
first and escrow its backup key. These safeguards are implemented; native GUI upgrade and WebView2 acceptance remain required.

## Server

Server runs as a console process or the `AuthLens` Windows service. The canonical machine root is `C:\ProgramData\AuthLens`; the virtual service
identity is `NT SERVICE\AuthLens`. Network access needs explicit HTTPS, listen IP, hosts, credentials and dedicated storage. The frontend is served
by the same process. See [network/security](SERVER_NETWORK_ACCESS.md) and [Windows deployment](WINDOWS_DEPLOYMENT.md).

## Production installation checklist

1. Require a release approval for the exact clean source SHA, not merely version `2.0.0`. Verify all mandatory
   [acceptance gates](../validation/STATUS.md#200-release-gates), package manifests/checksums, signing or an approved
   controlled-distribution exception, and the complete backend/frontend regression evidence.
2. Classify the destination as genuinely empty or a verified owned upgrade. Stop on an unregistered populated root,
   unexpected files, a foreign service/listener, unknown schema, stale transaction or missing rollback proof.
3. Preserve and independently verify current business and security databases, accounts, encryption/recovery keys,
   TLS private material/password files, configuration and immutable evidence. Rehearse restore in separate storage.
   Keep an off-machine copy; do not treat a hypervisor snapshot as application-consistent backup.
4. For direct HTTPS, select the specific private listen IP and port. Include the intended FQDN and IP in the backend
   certificate SAN and direct Allowed Hosts where used. Clients must trust the certificate issuer and validate the name.
   With no proxy, leave Trusted Proxies and Proxy Hosts empty. A reverse proxy is optional, not a prerequisite.
   See [network and certificate rules](SERVER_NETWORK_ACCESS.md#1-hosting-boundary). Never bypass TLS checks.
5. Use the supported wizard (or an explicit reviewed configuration for silent deployment), dedicated directories and
   default `NT SERVICE\AuthLens`. Approve only necessary restricted firewall sources/profiles; no inbound exception for loopback.
6. Verify the service name/display name `AuthLens`, virtual identity, Automatic startup, TLS readiness, effective
   version/SHA, `authlens.sqlite3` location and schema, SQLite integrity/foreign keys, administrator access, accounts,
   record/evidence fingerprints and disabled refresh. Verify graceful restart and persistence, and Desktop independently.
7. Keep the old release, deployment journals, immutable payload/tools and verified backups until recovery acceptance
   is complete. The installer completion screen is not sufficient release approval. Use the [failed-install procedure](WINDOWS_DEPLOYMENT.md#recovery-of-the-failed-production-installation-manual-not-automatic)
   for the known failed alpha fresh installation; do not run normal upgrade/rollback against an uninstalled service.

### Rollback and recovery boundaries

For an interrupted installed Server transaction, retain the original configuration and use the supported
`Install-AuthLens.ps1 -Mode Server -ConfigFile <same-configuration> -Recover -Yes` with verified retained helpers.
Recovery must bind the original journal, release and backup and prove schema compatibility before switching binaries.
A completed update uses the explicit, reviewed deployment `Rollback` operation; `Recover` is not a generic downgrade.
If binary rollback is refused, restore the verified pre-update backup into a separate clean environment with the
compatible previous release and verify it before a cutover. Do not copy live SQLite files or overwrite newer data.
Desktop uses its private `.setup-state` recovery journal and retained previous executable/manifest; close the app
and use its supported `-Mode Desktop ... -Recover -Yes` adapter with the same explicit program/data paths.

Preservation-only uninstall removes owned resources after verified backup; it is not a recovery strategy and does
not erase the data, keys, certificates or backup artifacts. Restore/rollback must actually be exercised; instructions
and unit tests alone do not prove success. See [backup/recovery](../operations/BACKUP_AND_RECOVERY.md).

## Build and release folder

Build from a clean checkout of the intended source commit with the root `build.ps1` and the output root `C:\AuthLens`; prerequisites,
parameters, the artifact layout and the optional portable package are in the [canonical Windows build](WINDOWS_DEPLOYMENT.md#canonical-windows-build):

```powershell
.\build.ps1 -OutputRoot C:\AuthLens              # add -ZipPackage for the portable deployment package
```

The build rebuilds the production frontend once, builds the solution and publishes self-contained Windows x64 executables into
`C:\AuthLens\Build\<version>\<build-id>`. Use `-TestFilter` for an explicitly scoped validation run; `-SkipTests` is appropriate only when
matching validation has already passed and source has not changed. Never substitute a local dirty build for a verified release identity.

A versioned release contains `server/AuthLens.Api.exe`, `desktop/AuthLens.exe`, required native dependencies, symbols, helper tools, instructions,
`build-manifest.json` and `SHA256SUMS`. Existing release directories are never overwritten. Verify package scope and checksums after transfer.
Private data, configuration, certificates, keys, logs and credentials do not belong in packages.

## Frontend and branding

Production frontend assets are embedded in the shared API assembly and therefore ship with both hosts. Missing required files fail startup.
Branding sources are [assets/branding](../../assets/branding/); Vite emits the logo/favicon and both executable projects and Inno scripts consume
`app.ico`. Replacing the canonical source files preserves stable references; see [branding](../architecture/DESIGN_SYSTEM.md#branding-source-assets).

## Installers

The canonical command also builds both installers from the same clean verified release and committed helper sources into
`C:\AuthLens\Installer\<version>\<build-id>` (`AuthLens-<version>-Server-Setup.exe`, `AuthLens-<version>-Desktop-Setup.exe`). There is no
supported installer-only build for candidates; transfer to another machine uses the
[portable package](WINDOWS_DEPLOYMENT.md#production-package-transfer).

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
