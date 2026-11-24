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
