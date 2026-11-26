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

AuthLens is a local-first SAP investigation and access-review application. Browse roles and transaction mappings, propose access packages,
investigate user/release assignments, compare users, enrich identities with optional Employee Directory data, record Account Review decisions,
and investigate and review potential Segregation of Duties conflicts with frozen periods and DOCX/PDF reports. Role-derived transaction coverage
is investigation evidence, not proof of effective authorization or license consumption. No direct SAP connection or third-party data-upload
service is required.

## Getting Started

Build on Windows with **Windows PowerShell 5.1**, **Git**, **.NET SDK 10**, **Node.js 24 or 25 with npm**,
**Python 3** (available as `python`) and **Inno Setup 6** (`ISCC.exe`). Git, .NET, Node, npm and Python must
be available on `PATH`. Dependency restore needs access to NuGet/npm feeds or populated local caches.
Inno Setup is detected in its standard installation locations; use `-Iscc 'C:\Tools\Inno Setup 6\ISCC.exe'`
if installed elsewhere.

Run all commands **from the repository root**, containing [build.ps1](build.ps1). The working tree must
be clean, including untracked files: `git status --short` must print nothing. Commit reviewed changes
before building; the build refuses dirty sources. `-ExecutionPolicy Bypass` applies to the launched
PowerShell process and does not change the saved user or machine execution policy.

**Standard Windows build:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

**Build without regression tests:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SkipTests
```

`-SkipTests` skips the release builder's .NET test execution, including publish tests. It still builds the
frontend and .NET solution, publishes both products, scans the release for secrets, verifies build identity
and release checksums, compiles both installers, and verifies installer hashes and branding. Neither command
launches the separate browser or Pester suites. Skipped tests do not satisfy release acceptance.

Both commands produce **Server and Desktop release artifacts and installers**. The default output root
is `C:\AuthLens`; choose another with `-OutputRoot`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -OutputRoot 'C:\AuthLens-Builds'
```

Each build generates one build id `{yyyy-MM-dd_HHmm}-{shortSha}` (UTC time and the first seven commit characters, for example
`2026-11-25_2145-b10dd50`) and reuses it in every artifact category below. Collisions append `-02`, `-03`, etc.; existing directories,
packages and earlier run directories are never reused, overwritten, moved or renamed. Manifests and build metadata retain the full timestamp
precision and complete commit SHA.

| Location under the output root | Contents |
| --- | --- |
| `Build\<version>\<build-id>\` | The verified release itself: `server\AuthLens.Api.exe`, `desktop\AuthLens.exe`, symbols, `build-manifest.json`, `SHA256SUMS`, plus `build-summary.json`, `build.log` and `branding-verification.json` |
| `Installer\<version>\<build-id>\` | `AuthLens-<version>-Server-Setup.exe`, `AuthLens-<version>-Desktop-Setup.exe`, `installer-manifest.json`, `installers-SHA256SUMS`, packaged installation, verification and recovery tooling, `DEPLOY.txt` and `Expand-AuthLensPackage.ps1` |
| `Acceptance\<version>\<build-id>\<run>\` | Acceptance evidence, written later by the acceptance tooling |
| `Packages\AuthLens-<version>-<build-id>.zip` and `.zip.sha256` | Optional portable deployment package (`-ZipPackage`, off by default) |

Run directories of RC5 and earlier (`AuthLens-<version>-<yyyy-MM-dd_HHmm>-<shortSha>\build`, `\installer`) stay valid and are never moved.

**Build with the portable deployment package** (after the build, installers and verification passed):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -ZipPackage
```

Building does **not install AuthLens or modify Windows services**. For detailed switches, output layout
and failure handling, see the [canonical Windows build guide](docs/deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build).
Production approval remains subject to the [release gates](docs/validation/STATUS.md).

## Implementation

The implementation is an ASP.NET Core (.NET 10) backend in [`backend/`](backend) serving the React/Vite frontend in [`frontend/`](frontend),
as a Windows service or console **Server** (browser access over HTTPS) and a WebView2 **Desktop** for one user.
Development target `2.0.0` - **NOT APPROVED for production**; see [versioning and release gates](docs/architecture/VERSIONING.md).

| Area | Status |
| --- | --- |
| UI and API | Shared React frontend and authenticated .NET API ([UI integration](docs/architecture/UI_INTEGRATION.md)) |
| Data | SQLite system of record, immutable evidence and review history, encrypted backups ([database design](docs/architecture/DATABASE_DESIGN.md)) |
| Windows Server | The `AuthLens` Windows service, HTTPS and verified package updates with backup and rollback ([Windows deployment](docs/deployment/WINDOWS_DEPLOYMENT.md)) |
| Desktop | Per-user installation and loopback-only API with isolated application data |
| Acceptance | Current verification and remaining checks are recorded in [validation status](docs/validation/STATUS.md) |


## Repository layout

| Path | Content |
| --- | --- |
| [`backend/`](backend) | AuthLens .NET solution (`src/`, `tests/`), build, release, installer and deployment scripts (`scripts/`, `installer/`), offline fixture/reference utilities (`tools/`) |
| [`frontend/`](frontend) | React/Vite application UI |
| [`docs/`](docs/README.md) | Documentation (canonical for AuthLens) |
| [`scripts/`](scripts/README.md) | Repository-wide checks (documentation links, secrets, workflow contracts, frontend version and icon catalogue) |
| [`examples/`](examples/README.md), [`assets/`](assets) | Synthetic example data; product icon and logo |

## Quick commands

```bash
npm --prefix frontend ci && npm --prefix frontend run build
dotnet build backend/AuthLens.slnx -c Release
dotnet test backend/tests/AuthLens.Tests -c Release --no-build --filter "Category!=Publish"
backend/scripts/build-release.sh <output>                     # Linux; Windows: .\build.ps1
```

Details: [development](docs/development/README.md), [deployment](docs/deployment/README.md).

## Security and operations

* The Server listens on loopback unless `--network` is given; network mode requires HTTPS, an explicit host allow-list and, behind a reverse
  proxy, an explicit trusted-proxy list ([network access and security](docs/deployment/SERVER_NETWORK_ACCESS.md)). The Desktop listens on loopback only.
* Private CSVs, exports, logs, configuration, certificates and deployment settings never belong in Git or in build artifacts; the repository ships
  synthetic [examples](examples/README.md) only.
* Backups are encrypted and verified; every deployment takes and verifies a backup before it stops the service.


## Licensing

AuthLens is proprietary software. All rights reserved; no open-source license is
granted. Use or distribution requires authorization from the applicable rights
holder. See [LICENSE.md](LICENSE.md). Third-party components retain their own licenses.
