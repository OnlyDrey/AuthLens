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

## Implementation

The implementation is an ASP.NET Core (.NET 10) backend in [`backend/`](backend) serving the React/Vite frontend in [`frontend/`](frontend),
as a Windows service or console **Server** (browser access over HTTPS) and a WebView2 **Desktop** for one user.
Product version `2.0.0-alpha.1` (pre-release; [versioning](docs/architecture/VERSIONING.md)).

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
backend/scripts/build-release.sh <output>                     # Linux; Windows: backend\scripts\build-release.ps1 -Output <folder>
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
