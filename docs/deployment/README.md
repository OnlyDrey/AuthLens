# Installation and deployment (AuthLens)

| Guide | Content |
| --- | --- |
| [DESKTOP_SERVER_DEPLOYMENT.md](DESKTOP_SERVER_DEPLOYMENT.md) | The two products: Desktop (WebView2, one user, loopback) and Server (console or Windows service); release folder, run commands, acceptance checklist |
| [SERVER_NETWORK_ACCESS.md](SERVER_NETWORK_ACCESS.md) | Every Server option and environment variable, HTTPS and certificates, host allow-list, Origin/CSRF, reverse proxy and trusted proxies, authentication, firewall, Windows service and systemd |
| [WINDOWS_DEPLOYMENT.md](WINDOWS_DEPLOYMENT.md) | SSH-driven build, verified deployment, rollback, recovery and restore of the `AuthLens` Windows service; firewall behind a reverse proxy; Desktop and Server installers; acceptance checklist |
| [WINDOWS_TEST_VM.md](WINDOWS_TEST_VM.md) | Windows test machine runbook: native release build, test launcher, TLS checks, logs and acceptance levels |

## Commands

```powershell
# Canonical Windows workflow: build, package and verify both products; never installs
.\build.ps1
# Development packaging: skip backend tests, retain security and manifest checks
.\build.ps1 -SkipTests -OutputRoot C:\AuthLens-Development
# Managed Windows service deployment on the host (or over SSH with backend/scripts/deploy/deploy-windows.sh)
.\backend\scripts\deploy\Deploy-AuthLens.ps1 -Action Status
```

Installed services run from a verified release directory selected by the deployment junction.

Manual installer updates use the existing backup/deployment engine. Desktop retains the selected data profile and a private recovery journal;
Server uses a reviewed explicit or validated discovered configuration, resolves its program directory before staging and preserves existing settings.
Its interactive pages review configuration; they do not yet generate certificates, provision custom service credentials or manage firewall rules.
Both refuse updates with pending schema changes and preserve recovery artifacts. See
[installer transactions and acceptance limits](WINDOWS_DEPLOYMENT.md#manual-installer-transaction) before any installation.
