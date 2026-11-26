<!-- LOGO -->
<h1>
<p align="center">
  <img src="assets/branding/app.png" alt="Logo" width="200">
  <br>AuthLens
</h1>
  <p align="center">
    <b>SAP S/4HANA</b> · Role analysis and comparison tool for Company's internal SAP authorisation landscape.
    <br />
    <br />
    <a href="docs/README.md">Documentation</a>
    ·
    <a href="docs/README.md#quick-start">Quick Start</a>
    ·
    <a href="docs/deployment/README.md">Build &amp; Deployment</a>
    ·
    <a href="docs/features/README.md">Features</a>
    ·
    <a href="docs/development/README.md">Development</a>
    ·
    <a href="https://github.com/OnlyDrey/AuthLens/releases">GitHub Releases</a>
  </p>
</p>

---

## Overview

AuthLens is a local-first SAP investigation and access-review application. It works on CSV exports you provide (role catalogue, user-role
mapping, optional Employee Directory and SoD matrix); no direct SAP connection or third-party upload service is required. Role-derived
transaction coverage is investigation evidence, not proof of effective authorization or license consumption.

**Release status:** `2.0.0` is a release candidate (RC6, built from `839123c`) awaiting native Windows acceptance. It is **NOT APPROVED for
production** and has not been published as a stable release; see [current status](docs/validation/STATUS.md).

## Key features

- **Dashboard** with a global overview and a filtered analytical view (organization, SAP and governance dimensions, saved filters, drill-down).
- **Role Lookup**, Role Comparison and proposed access packages; **User Access** and **Compare Users** investigations.
- **Account Review** and the **Reviews** workspace with persistent, immutable decisions and evidence.
- **Segregation of Duties**: risk and activity matrices, Access Explorer, review rules, frozen periods and DOCX/PDF reports.
- **Unified file sources**: upload from the browser or select a file on the host (local or UNC, within approved roots), static or dynamic update
  mode, validation before import and a retained last valid dataset.
- **Server** (Windows service, HTTPS, local accounts and roles) and **Desktop** (single user, WebView2, loopback only) from one code base.

Feature guides: [features](docs/features/README.md). No screenshots are kept in the repository; the UI is described in the feature guides.

## Architecture and technology

| Layer | Technology |
| --- | --- |
| Backend | .NET 10, ASP.NET Core, EF Core SQLite (`authlens.sqlite3`), xUnit; solution [`backend/AuthLens.slnx`](backend) |
| Frontend | React 18, TypeScript, Vite, TanStack Query, Tailwind 3; Playwright browser tests ([`frontend/`](frontend)) |
| Server host | `AuthLens.Api.exe` as the Windows service `AuthLens` (installation root `C:\ProgramData\AuthLens`) or a console process |
| Desktop host | `AuthLens.exe` (WinForms + WebView2), per user, OS-assigned loopback port, data in `%LOCALAPPDATA%\AuthLens` |
| Installers | Inno Setup 6: `AuthLens-<version>-Server-Setup.exe`, `AuthLens-<version>-Desktop-Setup.exe` |

Details: [architecture](docs/architecture/TARGET_ARCHITECTURE.md), [versioning and identities](docs/architecture/VERSIONING.md). The product
was previously named SAP Lens; SAP Lens 1 (Python/FastAPI) is archived outside this repository.

| Path | Content |
| --- | --- |
| [`backend/`](backend) | .NET solution (`src/`, `tests/`), build, release, installer, deployment and recovery scripts (`scripts/`, `installer/`), historical v1 reference generators (`tools/`) |
| [`frontend/`](frontend) | React/Vite application UI |
| [`docs/`](docs/README.md) | Documentation (canonical) |
| [`scripts/`](scripts/README.md) | Repository-wide checks (documentation links, secrets, structure, workflow contracts) |
| [`examples/`](examples/README.md), [`assets/`](assets) | Synthetic example data; product icon and logo |

## Installation

Install from a verified build (or a verified portable package, below). Both Setup programs are currently **unsigned**.

- **Server:** run `AuthLens-<version>-Server-Setup.exe` in an elevated session. A fresh installation creates the `AuthLens` service under
  `C:\ProgramData\AuthLens`; upgrades take and verify a backup first and keep configuration, data, keys and certificates.
- **Desktop:** run `AuthLens-<version>-Desktop-Setup.exe` as the user; no service and no Server configuration.

Uninstall removes the program and owned service resources but preserves data, keys, certificates and backups. Procedures, upgrade, repair
and recovery: [Windows deployment](docs/deployment/WINDOWS_DEPLOYMENT.md#installers), [Desktop and Server](docs/deployment/DESKTOP_SERVER_DEPLOYMENT.md).

## Build from source

**Prerequisites (Windows build host):** Windows PowerShell 5.1 (or PowerShell 7), Git, .NET SDK 10, Node.js 24 or 25 with npm, Python 3
(as `python`) and Inno Setup 6 (`ISCC.exe`), all on `PATH` except Inno Setup, which is found in its standard locations (or `-Iscc`). Restore
needs NuGet/npm access or populated caches. Run from the repository root; the working tree must be clean (`git status --short` prints
nothing), because the build refuses dirty sources.

```powershell
# Standard release build
.\build.ps1 -OutputRoot C:\AuthLens

# Release build with portable deployment package
.\build.ps1 -OutputRoot C:\AuthLens -ZipPackage
```

Without `-TestFilter` the build runs the whole .NET test suite. Development candidates use the focused deployment filter instead:

```powershell
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)
```

| Parameter | Effect |
| --- | --- |
| `-OutputRoot` | Artifact root; default and mandatory standard `C:\AuthLens` (other roots only with explicit approval) |
| `-TestFilter <filter>` | Runs only the matching .NET tests (`dotnet test --filter`) |
| `-SkipTests` | Skips .NET test execution; everything else still runs. Skipped tests never satisfy release acceptance |
| `-Iscc <path>` | Absolute path to `ISCC.exe` when Inno Setup is not in a standard location |
| `-ZipPackage` | After build, installers and verification passed, also writes the portable deployment package |

The build compiles the frontend and .NET solution, publishes both products, scans the release for secrets, verifies build identity and
checksums, compiles both installers and verifies installer hashes and branding. It never installs AuthLens or changes services, and it does
not run the browser or Pester suites. To package an **existing** verified build without rebuilding:

```powershell
.\backend\scripts\New-AuthLensPackage.ps1 -Candidate C:\AuthLens\Build\<version>\<build-id>
```

Only builds in the category layout (RC6 and later) can be packaged; RC5 and older run directories lack the extraction tooling and are refused.
Details, failure handling and storage needs: [canonical Windows build](docs/deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build).
Development commands and validation levels: [development](docs/development/README.md).

## Build artifacts

```text
C:\AuthLens\
    Build\
        <version>\
            <build-id>\
    Installer\
        <version>\
            <build-id>\
    Acceptance\
        <version>\
            <build-id>\
    Packages\
        AuthLens-<version>-<build-id>.zip          (a later package of the same build: -pkg<N>.zip)
        AuthLens-<version>-<build-id>.zip.sha256   (build metadata; optional on the target)
```

The build id is `<UTC yyyy-MM-dd_HHmm>-<sha7>`: the UTC build time and the first seven characters of the source commit. It is generated once
per build and shared by every category, so the release, its installers, its acceptance evidence and its package always carry the same
immutable identity; manifests keep the full commit SHA and the exact timestamp. If any category already holds that id, the build appends
`-02`, `-03` and so on up to `-99`; nothing is reused, overwritten, moved or renamed.

| Location | Contents |
| --- | --- |
| `Build\<version>\<build-id>\` | Verified release (`server\AuthLens.Api.exe`, `desktop\AuthLens.exe`, symbols, `build-manifest.json`, `SHA256SUMS`) and the build record (`build-summary.json`, `build.log`, `branding-verification.json`) |
| `Installer\<version>\<build-id>\` | Both Setup programs, `installer-manifest.json`, `installers-SHA256SUMS`, packaged installation, verification and recovery tooling, `DEPLOY.txt`, `Expand-AuthLensPackage.ps1` |
| `Acceptance\<version>\<build-id>\<run>\` | Evidence of each acceptance run, written later by the acceptance tooling |
| `Packages\` | Optional portable package and its SHA-256 file (`-ZipPackage` or `New-AuthLensPackage.ps1`) |

RC5 and older candidates keep their legacy run directories `C:\AuthLens\AuthLens-<version>-<UTC>-<sha7>\` and stay valid where they are.

## Portable deployment packages

A package is flat: both Setup programs, `Expand-AuthLensPackage.ps1`, `README.txt`, `installer-manifest.json`, `package-manifest.json`,
`SHA256SUMS.txt` and `Tools\` sit at the root of the ZIP; there are no sources, tests, Build outputs, evidence, credentials, keys,
certificates or databases. On the target machine, copy the ZIP to `C:\AuthLens` and extract it with its own `Expand-AuthLensPackage.ps1`
(passing the ZIP's SHA-256 from the build report; the `.zip.sha256` file is optional) into `C:\AuthLens\AuthLens-<version>-<build-id>`. The
script refuses modified packages, unexpected entries and existing destinations; Explorer's *Extract All* followed by `-VerifyOnly` is the
alternative. Neither the repository nor the Build directory is needed. The copy-paste procedure is in
[production package transfer](docs/deployment/WINDOWS_DEPLOYMENT.md#production-package-transfer).

A SHA-256 checksum proves that the files match the recorded digest (integrity), not who published them (authenticity). The current
installers are not Authenticode-signed.

## Security and recovery

- The Server listens on loopback unless network mode is configured; network mode requires HTTPS, an explicit host allow-list and, behind a
  reverse proxy, an explicit trusted-proxy list ([network access and security](docs/deployment/SERVER_NETWORK_ACCESS.md)). The Desktop listens
  on loopback only.
- Installation ACLs are assessed as SAFE, REVIEW_REQUIRED or UNSAFE; named principals are never removed automatically and the optional strict
  readiness gate (`-StrictAcl`) refuses unreviewed findings ([NTFS permissions](docs/deployment/WINDOWS_DEPLOYMENT.md#ntfs-permissions)).
- Host file sources are read with the service identity, only inside approved roots; AuthLens never stores SMB credentials or changes share or
  NTFS permissions ([imports and refresh](docs/data/IMPORT_AND_REFRESH.md)).
- Backups are encrypted and verified; every deployment takes and verifies a backup before it stops the service. An independent recovery
  bundle (backup plus recovery key copy) can be created and verified from the Service Manager
  ([backup and recovery](docs/operations/BACKUP_AND_RECOVERY.md)).
- Private CSVs, exports, logs, configuration, certificates and deployment settings never belong in Git or in build artifacts; the repository
  ships synthetic [examples](examples/README.md) only.

## Documentation

| Topic | Guide |
| --- | --- |
| Index | [Documentation index](docs/README.md) |
| Features and data | [Features](docs/features/README.md), [data and CSV formats](docs/data/README.md) |
| Build and deployment | [Deployment index](docs/deployment/README.md), [Windows deployment](docs/deployment/WINDOWS_DEPLOYMENT.md) |
| Operations | [Backup and recovery](docs/operations/BACKUP_AND_RECOVERY.md), [troubleshooting](docs/deployment/WINDOWS_DEPLOYMENT.md#troubleshooting) |
| Development | [Commands and validation](docs/development/README.md), [CI policy](docs/development/CI.md) |
| Release | [2.0.0 release overview](docs/RELEASE_NOTES.md), [current status](docs/validation/STATUS.md), [acceptance tracker](docs/validation/ACCEPTANCE_TRACKER.md) |

## Current release status

| Item | State |
| --- | --- |
| Version | `2.0.0` (candidate RC6, build id `2026-11-26_0330-839123c`, source commit `839123c`) |
| Automated validation | Focused .NET, Pester, browser and static checks passed for RC6; FULL regression not yet executed |
| Native Windows acceptance | Pending (installation, upgrade, UNC sources, strict ACL gate, recovery bundle, storage and retention, real iPhone) |
| Signing | Installers unsigned (`NotSigned`) |
| Production | **NOT APPROVED** |

Release history is published through [GitHub Releases](https://github.com/OnlyDrey/AuthLens/releases); no stable 2.0.0 release exists yet.

## Licensing

AuthLens is proprietary software. All rights reserved; no open-source license is
granted. Use or distribution requires authorization from the applicable rights
holder. See [LICENSE.md](LICENSE.md). Third-party components retain their own licenses.
