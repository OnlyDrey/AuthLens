# Versioning and build identity

The product is **AuthLens**. The development target is `2.0.0` (**NOT APPROVED for production**); `backend/product-version.json` is its authoritative source.
Frontend package metadata mirrors that value. Builds do not increment the product version.

## Canonical identities

| Item | Identity |
| --- | --- |
| Windows service | `AuthLens`, account `NT SERVICE\AuthLens` |
| Server executable | `AuthLens.Api.exe` |
| Desktop executable | `AuthLens.exe` |
| Server installation root | `C:\ProgramData\AuthLens` |
| Application database | `authlens.sqlite3` |
| Desktop data root | `%LOCALAPPDATA%\AuthLens` |
| Configuration variables | `AUTHLENS_*` |
| Deployment module | `AuthLens.Deploy`, functions `*-AL*` |
| Desktop installer | `AuthLens-<version>-Desktop-Setup.exe` (WP32, RC6 and later; earlier candidates `AuthLens-<version>-Setup.exe`) |
| Server installer | `AuthLens-<version>-Server-Setup.exe` (WP32, RC6 and later; earlier candidates `AuthLens-Server-<version>-Setup.exe`) |
| Build artifacts | `C:\AuthLens\{Build,Installer,Acceptance}\<version>\<UTC yyyy-MM-dd_HHmm>-<sha7>`, `Packages\AuthLens-<version>-<build-id>.zip`; installed release folders keep `AuthLens-<version>-<yyyyMMdd-HHmmss>-<sha7>-win-x64` |
| Branding sources | [assets/branding](../../assets/branding/) |

## Version, channel and build

Product versions use `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH-alpha.N`, `-beta.N`, `-rc.N`. The pre-release number starts at 1.
The Windows file version is `MAJOR.MINOR.PATCH.N`, with 0 as its last component for a stable version.
The current assembly version is `2.0.0.0` and file version `2.0.0.0`.

Build identity is separate: source commit, UTC build timestamp, platform and SHA-256 checksums are recorded by the release scripts in
`build-manifest.json` and `SHA256SUMS`. A release build records whether the working tree was dirty. Versioned release directories are never overwritten.

The CLI `--version`, `/product-version.json`, application information, Desktop About and release manifest expose build/product identity.
The host serves its own runtime identity; frontend assets carry the product metadata embedded when they were built.

## Release policy

Build and verify packages using the [deployment guide](../deployment/DESKTOP_SERVER_DEPLOYMENT.md). A source push does not publish packages.
CI runs only on push to `main`; development validation is local. Tags, releases, merges and deployment require explicit authorization.
Native installer, Desktop, service, restart, TLS, backup/restore and rollback acceptance are tracked separately in [current status](../validation/STATUS.md).

## 2.0.0 target notes and approval gates

`2.0.0` is a development target, **not an approved stable release**. The runtime channel is technically `stable`
because the version has no prerelease suffix; this is not an operational readiness assertion. No tag or GitHub Release
has been approved. Release history remains GitHub Releases; these notes describe the current candidate only.

Changes carried into this target include the icon-preserving Role Lookup category dropdown, selected-role CSV export
scope, compact Functional Group cells, approved Brand Assets v2, configuration-bound Server Setup and permanent local
account deletion. The fresh Server extraction correction now binds legitimate Inno uninstall metadata to the exact
verified payload; early failures no longer imply that a deployment journal exists. Desktop alpha-to-stable ordering
uses semantic manifest versions rather than the lower Windows stable revision. See [installer/recovery details](../deployment/WINDOWS_DEPLOYMENT.md#fresh-server-extraction-ownership-and-early-failure-evidence).

Approval requires matching-SHA backend and frontend regression evidence, clean Windows fresh GUI/silent installation
and alpha-to-stable upgrade for both hosts, Desktop launch/shutdown, real SCM restart/persistence, direct HTTPS by IP
and FQDN without a proxy, verified backup restore, legacy backup conversion, rollback/recovery and preservation-only
uninstall. Record integrity/foreign keys, accounts and immutable evidence fingerprints before and after each applicable
operation. A missing environment, skipped mandatory test or failed gate means **NO-GO**. Prior alpha evidence does not
approve this candidate. `-SkipTests` cannot replace these gates.

Diagnostic builds may use the existing `build.ps1` with a dedicated `NOT-APPROVED` output root. The build summary's
`passed` status means packaging checks passed, not that release acceptance passed. Do not distribute these builds for
production or add unlisted approval files inside verified release folders. Preserve test reports and build logs separately.

Windows signing is a recommended production distribution gate: SHA-256 proves transfer integrity but does not establish
a trusted publisher. No signing certificate or approved distribution-policy exception is configured. Until signing and
timestamp verification or an explicitly approved controlled-distribution exception is documented, unsigned packages remain
unapproved for production distribution. No certificate, key or credential belongs in Git or a package.

Known lifecycle limits remain explicit: fresh Setup provisions only `NT SERVICE\AuthLens`; custom-account provisioning,
automatic certificate renewal and destructive data-purge uninstall are not implemented. Uninstall preserves persistent data
and recovery artifacts. Existing certificates can be imported through the wizard without silently changing trusted stores.
