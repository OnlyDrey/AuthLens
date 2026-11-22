# Current validation status

AuthLens `2.0.0-alpha.1` is under private acceptance. This page records current verification boundaries, not a release history.

| Area | Current result |
| --- | --- |
| Windows Server | Installed service passed local HTTPS, readiness, identity, automatic startup, restart and persistent-state checks |
| Reverse proxy | Explicit trusted-peer/public-host support is implemented and deployed; authenticated external acceptance remains outstanding |
| Accounts | Administrator guards, session revocation and permanent deletion passed focused backend/frontend validation |
| Backup and recovery | Encrypted creation, verification and isolated restore have been exercised; recovery and upgrade acceptance must remain part of future updates |
| Evidence | Database integrity, foreign keys, immutable review history and evidence fingerprints passed preservation checks |
| Branding | Generic canonical assets, frontend production build, embedded Windows icons and isolated installer compilation passed |
| Windows build workflow | Root build entry point produced both Windows packages and Setup executables with matching manifests; focused orchestration/installer tests passed |
| Server Setup lifecycle | Fresh configuration editing/create-only publication, explicit restricted firewall creation and CLI offline component repair implemented alongside existing preflight/upgrade guards. Focused source tests and synthetic Inno compilation do not establish native acceptance. TLS issuance, custom-account provisioning, firewall update/removal, missing-service repair, safe uninstall and full native lifecycle/recovery acceptance remain incomplete |
| Mobile UX | Header tools, independent navigation drawers, Filters, configurable tables, Functional Group pills and SoD scrolling passed focused isolated browser acceptance; not deployed |

Scheduled refresh stays disabled until configured external sources and credentials have been reviewed. Production data, accounts, keys,
certificates and retained rollback copies must be preserved during every update. Successful smoke checks do not establish production readiness.

## Responsive acceptance scope

Focused Edge/Chromium checks cover light/dark layouts from 360 to 1600 px, keyboard/focus behavior, touch emulation, Settings sections, column preferences and displayed-row CSV exports. Screenshots and failed-run diagnostics remain in ignored local test artifacts. Real iOS/Android browsers, Safari and acceptance against the deployed application remain outstanding. Complex tables intentionally scroll horizontally; column configuration does not imply manual width resizing.

## Validation policy

Run the smallest relevant tests while developing, then the complete affected specifications and direct dependents. The full backend/browser suites
are explicit release/merge checkpoints, not automatic development checks. Record infrastructure failures separately from application failures.
Use synthetic data and disposable test storage. Native Windows, WebView2, SCM, reboot/recovery, UNC and outside-network acceptance require the actual environment.

See [development](../development/README.md), [acceptance guide](README.md), [Windows deployment](../deployment/WINDOWS_DEPLOYMENT.md) and
[backup/recovery](../operations/BACKUP_AND_RECOVERY.md). Current runtime/install state is operational evidence and is not a repository deployment configuration.
