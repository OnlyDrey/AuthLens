# Current validation status

AuthLens development targets `2.0.0`. **Release status: NOT APPROVED / NO-GO** until all mandatory acceptance gates pass. Existing alpha installation evidence below does not approve the new target. This page records current verification boundaries, not a release history.

| Area | Current result |
| --- | --- |
| Windows Server | Installed service passed local HTTPS, readiness, identity, automatic startup, restart and persistent-state checks |
| Reverse proxy | Explicit trusted-peer/public-host support is implemented and deployed; authenticated external acceptance remains outstanding |
| Accounts | Administrator guards, session revocation and permanent deletion passed focused backend/frontend validation |
| Backup and recovery | Encrypted creation, verification and isolated restore have been exercised; recovery and upgrade acceptance must remain part of future updates |
| Evidence | Database integrity, foreign keys, immutable review history and evidence fingerprints passed preservation checks |
| Branding | Brand Assets v2 uses stable canonical paths and byte-identical supplied images; manifest metadata does not override application theme colors. Focused build/visual verification is recorded in the design-system guide; native Explorer/taskbar/installed-shortcut appearance remains separate acceptance |
| Windows build workflow | Root build entry point produced both Windows packages and Setup executables with matching manifests; focused orchestration/installer tests passed |
| Server Setup lifecycle | Fresh configuration editing, local TLS generation/PFX import, bound publication, owned firewall lifecycle, receipt-bound missing virtual-account service repair, interrupted-repair recovery and preservation-only CLI/Inno uninstall implemented. Published Server releases use their explicit verification scope; full installer payload checks remain strict. Restricted SYSTEM task bootstrap has focused security and native synthetic timeout coverage; actual read-only SYSTEM Health/Preflight now pass with structured reports; mutating lifecycle acceptance remains pending. These checks and Inno compilation do not establish installer acceptance. Installed-certificate renewal, custom accounts, optional test-data deletion and native SCM lifecycle acceptance remain incomplete |
| Mobile UX | Header tools, independent navigation drawers, Filters, configurable tables, Functional Group pills and SoD scrolling passed focused isolated browser acceptance; not deployed |

Scheduled refresh stays disabled until configured external sources and credentials have been reviewed. Production data, accounts, keys,
certificates and retained rollback copies must be preserved during every update. Successful smoke checks do not establish production readiness.

Windows continuation: an independent encrypted archive was actually restored through the supported workflow into a new private loopback HTTPS
process using build `89901d7`. SQLite integrity/foreign keys passed. DatasetRecords (332,348), ReviewDecisions (3), SodDocuments (11),
SodDecisionEvents (1,086) and SodEvidenceSnapshots (1,023) retained identical table fingerprints from validated staging through activation and
process restart; empty SavedFilters/ReviewInvalidations also matched. Account/credential fingerprints and active-administrator state remained
unchanged, the removed temporary account stayed absent, and scheduled refresh stayed disabled. HTTPS used an explicit public certificate anchor
without verification bypass or trusted-store changes. Frontend HTML loaded; password login was not exercised. The isolated process was forcibly
terminated for the persistence check; this proves neither graceful SCM restart nor installer/VM rollback. The original service PID and source
archive hash remained unchanged. Private raw evidence and failed harness runs are retained outside Git. The on-VM recovery directory is separate
from installer targets; move a verified copy off-VM before any Proxmox disk-snapshot rollback, which would discard files created after that snapshot.

## 2.0.0 release gates

**NOT APPROVED.** The version target does not change the approval status. Fresh Server extraction ownership and
missing-journal diagnostics have focused PowerShell tests, native Inno compilation and an actual disposable Inno
metadata-timing probe. These are component evidence, not a successful full Server installation.

The diagnostic build attempt from `e971147` compiled the frontend and .NET solution, then reported a
`LanHttpsTests` failure: the startup certificate handshake self-check returned `TaskCanceledException` before host startup.
The run was stopped when validation execution transferred to the user; no final passing test or packaging result is available
for that attempt. The user subsequently reported a successful focused build/retest (65.3 seconds combined):
`LanHttpsTests.Lan_https_serves_ui_enforces_token_hosts_cookies_csrf_and_persists_across_restart` passed,
with 1 passed, 0 failed and 0 skipped. The retained local TRX at
`build/test-artifacts/lan-https-20261123T1756177818287Z/results.trx` was inspected and confirms those counters
(test duration 7.577 seconds). This focused pass does not complete the interrupted full regression or packaging run.
Synchronization-context capture remains an unconfirmed hypothesis, not an established root cause or implemented fix;
no TLS validation or timeout was weakened.
Further builds/tests require explicit authorization or user execution under the repository's Build and Test Execution Policy.

Installer journal diagnostics now distinguish present, unresolved and not-created/unavailable journals in both the structured
result and human-readable failure message. The Setup retry message requires review of retained evidence instead of suggesting
that another payload makes a partial installation clean. User-run Pester 5.9.1 validation passed all 48 tests in
`Installer-Preflight.Tests.ps1`, `Server-Setup.Tests.ps1` and `InnoIsolation.Tests.ps1` (28.55 seconds, no failures or skips).
This includes native compilation of Desktop/Server scripts for alpha and stable versions using synthetic payloads,
journal-state diagnostics, hash-bound fresh metadata and preservation/refusal checks. The user-run documentation check
covered 44 Markdown files with zero failures. Real fresh installation, upgrade, SCM and recovery acceptance remain pending;
synthetic installer compilation is not production-package or installation acceptance.

| Mandatory gate | Evidence boundary |
| --- | --- |
| Source/build identity | Clean SHA, version `2.0.0`, channel `stable`, file version `2.0.0.0`, manifests/checksums and secret scan must agree |
| Backend/frontend regression | Matching-source full relevant regression and retained reports required; focused results alone do not approve release |
| Desktop | Real clean installation, alpha upgrade, launch/shutdown, loopback isolation, dropdown/icons and saved filters required |
| Server | Real clean GUI/silent install and independent alpha upgrade, canonical SCM identity/Automatic startup, restart and preservation required |
| Direct HTTPS | IP and FQDN SAN/name/trust validation without bypass, with no proxy dependency, required |
| Recovery | Independent current backup including security/TLS/keys/configuration; actual restore and rollback with record/evidence/account fingerprints required |
| Uninstall | Owned service/firewall cleanup with data preserved and tested recovery required |
| Distribution | Unsigned unless independently signed; approved signing/transport policy and matching payload verification required |

Do not run destructive tests against production. VM 130 is the designated development VM; initial administrator
bootstrap, current independent recovery verification and confirmation of the retained Proxmox snapshot are prerequisites
before replacing its existing service. A disk snapshot without QEMU Guest Agent is not proof of application consistency.
Protect off-VM recovery material before a snapshot rollback. See the [production checklist](../deployment/DESKTOP_SERVER_DEPLOYMENT.md#production-installation-checklist).

### Responsive acceptance scope

Release browser audits navigate through the responsive drawer on narrow viewports, rather than targeting the hidden
desktop navigation. Active-route, decoration and keyboard-focus assertions still apply to the visible navigation links.
Narrow filter audits dismiss the shared dialog through its scoped close action and verify removal before interacting
with results; Settings audits use the section drawer below its breakpoint.
Search-layout assertions follow the implemented shared filter sidebar/drawer and verify visual and DOM reading order.
Release regression reproduced an assignment-date popover behind the mobile drawer backdrop. Popover and calendar
portals now stay within their owning modal; the original 375 px interaction and Account Review light/dark checks at
375/800/1280 px pass. This correction does not complete the full release browser or native installer gates.
The remaining Playwright campaign was stopped at the user's request; completed results and failure traces are retained.
Unexecuted or interrupted tests are not passes, and full browser acceptance remains outstanding before release approval.

Focused Edge/Chromium checks cover light/dark layouts from 360 to 1600 px, keyboard/focus behavior, touch emulation, Settings sections, column preferences and displayed-row CSV exports. Screenshots and failed-run diagnostics remain in ignored local test artifacts. Real iOS/Android browsers, Safari and acceptance against the deployed application remain outstanding. Complex tables intentionally scroll horizontally; column configuration does not imply manual width resizing.

## Validation policy

Run the smallest relevant tests while developing, then the complete affected specifications and direct dependents. The full backend/browser suites
are explicit release/merge checkpoints, not automatic development checks. Record infrastructure failures separately from application failures.
Use synthetic data and disposable test storage. Native Windows, WebView2, SCM, reboot/recovery, UNC and outside-network acceptance require the actual environment.

Backup lifecycle fixtures use a nonparallel collection because the production backup/scheduler gates are process-wide.
Their explicit simultaneous-tick checks remain concurrent within the fixture; unrelated fixtures must not consume those gates.
Installer contracts read the canonical product version and prohibit Desktop-only callbacks/defaults in Server code, while
allowing the implemented advanced Server `DataDirectory` setting. These test-isolation/contract corrections do not relax runtime guards.
Accessibility audits use the shared responsive navigation/Settings helpers, preserving their original viewport,
focus-order, accessible-name and clipping assertions instead of waiting for hidden desktop controls on mobile.

See [development](../development/README.md), [acceptance guide](README.md), [Windows deployment](../deployment/WINDOWS_DEPLOYMENT.md) and
[backup/recovery](../operations/BACKUP_AND_RECOVERY.md). Current runtime/install state is operational evidence and is not a repository deployment configuration.
