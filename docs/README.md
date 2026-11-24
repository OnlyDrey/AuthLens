# AuthLens documentation

AuthLens is a local-first SAP investigation and access-review application, with a .NET 10 backend and React frontend.

| Topic | Guides |
| --- | --- |
| Features | [Feature guide](features/README.md), [Dashboard](features/DASHBOARD.md), [Role Lookup](features/ROLE_LOOKUP.md), [User Access](features/USER_ACCESS.md), [SoD](features/SOD.md), [Reviews](features/REVIEWS.md) |
| Data | [Data and CSV formats](data/README.md), [imports and refresh](data/IMPORT_AND_REFRESH.md), [Employee Directory](data/EMPLOYEE_DIRECTORY.md) |
| Architecture | [Architecture index](architecture/README.md), [database](architecture/DATABASE_DESIGN.md), [UI integration](architecture/UI_INTEGRATION.md) |
| UI design | [Design system](architecture/DESIGN_SYSTEM.md), [components](architecture/COMPONENTS.md), [navigation](architecture/NAVIGATION.md) |
| Build and deployment | [Deployment index](deployment/README.md), [Desktop and Server](deployment/DESKTOP_SERVER_DEPLOYMENT.md), [Windows service and installers](deployment/WINDOWS_DEPLOYMENT.md) |
| Security and network | [HTTPS, authentication, Origin, CSRF and proxies](deployment/SERVER_NETWORK_ACCESS.md) |
| Recovery | [Backup and recovery](operations/BACKUP_AND_RECOVERY.md) |
| Development | [Commands and validation](development/README.md), [CI policy](development/CI.md) |
| Acceptance | [Acceptance guide](validation/README.md), [current status](validation/STATUS.md), [2.0.0 work packages](validation/WORK_PACKAGES.md) |

## Quick start

1. Install .NET SDK 10 and Node.js 24 or 25.
2. Build the frontend: `cd frontend`, `npm ci`, `npm run build`.
3. Build the backend: `cd backend`, `dotnet build AuthLens.slnx -c Release`.
4. Run Desktop on Windows, or configure Server using the [deployment guides](deployment/README.md).
5. Configure the four independent CSV sources through Settings. Use [CSV schemas](data/CSV_SCHEMAS.md) to prepare source files.

The API contract is available at `/openapi/v1.json` on the running Server. Source data, local configuration, credentials, keys, backups and logs
must remain outside Git and release packages. Build success and focused automated tests do not replace native deployment and recovery acceptance.
