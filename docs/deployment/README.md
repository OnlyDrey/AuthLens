# Installation and deployment (AuthLens)

| Guide | Content |
| --- | --- |
| [DESKTOP_SERVER_DEPLOYMENT.md](DESKTOP_SERVER_DEPLOYMENT.md) | The two products: Desktop (WebView2, one user, loopback) and Server (console or Windows service); release folder, run commands, acceptance checklist |
| [SERVER_NETWORK_ACCESS.md](SERVER_NETWORK_ACCESS.md) | Every Server option and environment variable, HTTPS and certificates, host allow-list, Origin/CSRF, reverse proxy and trusted proxies, authentication, firewall, Windows service and systemd |
| [WINDOWS_DEPLOYMENT.md](WINDOWS_DEPLOYMENT.md) | SSH-driven build, verified deployment, rollback, recovery and restore of the `AuthLens` Windows service; firewall behind a reverse proxy; Desktop and Server installers; acceptance checklist |
| [WINDOWS_TEST_VM.md](WINDOWS_TEST_VM.md) | Windows test machine runbook: native release build, test launcher, TLS checks, logs and acceptance levels |

## Commands

```powershell
# Canonical Windows workflow (mandatory output root C:\AuthLens): build, focused tests, package and verify both products; never installs
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)              # add -ZipPackage for the portable package
# Package an existing verified build (RC6 and later) without rebuilding
.\backend\scripts\New-AuthLensPackage.ps1 -Candidate C:\AuthLens\Build\<version>\<build-id>
# Managed Windows service deployment on the host (or over SSH with backend/scripts/deploy/deploy-windows.sh)
.\backend\scripts\deploy\Deploy-AuthLens.ps1 -Action Status
```

Installed services run from a verified release directory selected by the deployment junction.

Manual installer updates use the existing backup/deployment engine. Desktop retains the selected data profile and a private recovery journal;
Server uses a reviewed explicit or validated discovered configuration, resolves its program directory before staging and preserves existing settings.
Interactive Setup can author fresh path/network/proxy configuration, generate local self-signed TLS or import an existing PFX, and explicitly
approve a restricted firewall rule. Certificate trust is never installed automatically. Upgrades preserve configuration. Installed-certificate
replacement and network configuration changes are supported transactions (Service Manager and `Deploy-AuthLens.ps1`); custom credential
provisioning and optional test-data removal remain incomplete. CLI offline repair can publish verified replacement components while retaining damaged payloads;
owned-rule updates/removal/recovery now verify the native definition and preserve administrator changes. Server uninstall verifies recovery and removes owned service/rules while preserving all persistent data. Native lifecycle/recovery acceptance is still pending.
Both refuse updates with pending schema changes and preserve recovery artifacts. See
[installer transactions and acceptance limits](WINDOWS_DEPLOYMENT.md#manual-installer-transaction) before any installation.
