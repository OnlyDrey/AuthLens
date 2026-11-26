# Frontend and API integration

## How it works

The React application in `frontend/` is built by Vite. Its production output is embedded in `AuthLens.Api` under logical resource names
`AuthLensUi/<relative path>`. Server and Desktop use that shared host and the same frontend assets. The host validates required resources at
startup; an incomplete UI fails with a clear error instead of silently serving an empty document.

The frontend uses typed clients from `frontend/src/api`, TanStack Query for server data and shared UI components. Business rules, durable
snapshots, jobs, accounts and review evidence stay in the .NET backend. A page must present unavailable/unknown evidence explicitly.

## Build and packaging

Build `frontend` with `npm ci` and `npm run build`, then build `backend/AuthLens.slnx -c Release`. The .NET build uses the existing `frontend/dist`
when present; `-p:BuildFrontend=true` explicitly rebuilds it. Release scripts clean and rebuild the UI once and embed that same output in both hosts.
They verify product identity, resource layout and package checksums. Avoid parallel builds that mutate the same output directory.

Branding sources live in [assets/branding](../../assets/branding/). The Vite branding plugin serves/emits the default logo and favicon; Windows
icons are compiled from the canonical ICO. See [design system](DESIGN_SYSTEM.md#branding-source-assets).

## API

The running host serves its current API description at `/openapi/v1.json`. Typed frontend clients use the implemented routes and preserve error,
permission, expected-revision and evidence-version checks. Unsupported operations fail explicitly. Do not replace missing data with invented defaults.

Server uses local accounts, role permissions and secure sessions. State changes retain same-origin and per-session CSRF checks. Desktop supplies
its private launch capability and binds only to an OS-assigned loopback port. It never exposes its API to the LAN or caches SAP data in a service worker.
See [network/security](../deployment/SERVER_NETWORK_ACCESS.md).

## Validation

Use the isolated BrowserHost with synthetic fixtures for focused Playwright checks. Test navigation, dialogs, imports and review workflows without
pointing tests at an installed Server. Check production resource embedding with the focused build-integration tests. Native WebView2, installer,
Windows-service and external-proxy acceptance are separate checks; see [current status](../validation/STATUS.md).

## Frontend-only deployment assessment (WP35, 2026-11-26)

**Decision: not feasible within a frontend-only boundary; nothing was implemented.** The assessment is based on the RC6 sources
(`839123c` and later, unchanged in this respect).

| Question | Finding (evidence) |
| --- | --- |
| How the frontend is built | Vite production build into `frontend/dist`; release builds rebuild it once (`-p:BuildFrontend=true`) |
| Where production assets live | Embedded as manifest resources `AuthLensUi/<path>` in the `AuthLens.Api` assembly (`AuthLens.Api.csproj`, `AuthLensEmbedFrontend` target) |
| Distributed separately? | No. Server (`AuthLens.Api.exe`) and Desktop (`AuthLens.exe`) are self-contained single-file executables (`PublishSingleFile`), so the assembly and its UI resources are inside the executable; there is no `wwwroot` or UI folder on disk |
| How the host serves them | `AuthLensHost` uses `UiAssets.Create()`, which always returns the `EmbeddedUiFileProvider` over the assembly's resources and validates the required files at startup; there is no configuration, option or environment variable for a disk-based UI root |
| Independent replacement | Impossible without replacing the executable: a UI change is a new `AuthLens.Api.exe`/`AuthLens.exe` |
| Activation | Replacing the executable needs a service stop and start (Server) or an application restart (Desktop) |
| Integrity effect | `build-manifest.json` and `SHA256SUMS` hash both executables; a changed executable is a different release and fails `verify-release.ps1` against the installed manifest by design |
| Cache behavior today | Every UI response is served with `Cache-Control: no-cache` (revalidation); Vite asset names are content-hashed |

Consequences:

- A frontend-only update would need either a new executable, which means rebuilding the backend and is the normal release path, or a
  backend change that adds a verified disk-based UI root. That change touches the host, its configuration and startup validation, and it would
  open a new writable code path that needs ACL and integrity design. Both are outside the WP35 scope ("no .NET backend source changes, no
  backend recompilation"), so no workaround was introduced. Operator approval of a design is required first.
- Desktop has the same embedding, so the same limitation applies.
- **BUG-013 (and any UI fix) reaches installations only through a full release:** the root `build.ps1` builds a new candidate, then the
  verified upgrade runs (Server Setup upgrade or `Deploy-AuthLens.ps1`, with backup and rollback). The BUG-013 change itself stays frontend-only
  in the sources; no backend functionality is needed for it, because the RC6 API already returns group ids and serves the member list.
- Possible future option (not approved, not implemented): an optional UI root that the backend only accepts with a signed or hash-pinned UI
  manifest, bound to the exact backend build identity. It would sit in a protected installation folder, switch through a junction like the
  release folder, keep the embedded UI as fallback, and record the change in the deployment history. It needs one backend release to
  introduce it; after that, UI-only updates would be possible.
