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

Focused Edge/Chromium checks cover light/dark layouts from 360 to 1600 px, keyboard/focus behavior, touch emulation, Settings sections, column preferences and displayed-row CSV exports. Screenshots and failed-run diagnostics remain in ignored local test artifacts. Real iOS/Android browsers, Safari and acceptance against the deployed application remain outstanding. Complex tables intentionally scroll horizontally; column configuration does not imply manual width resizing.

## Validation policy

Run the smallest relevant tests while developing, then the complete affected specifications and direct dependents. The full backend/browser suites
are explicit release/merge checkpoints, not automatic development checks. Record infrastructure failures separately from application failures.
Use synthetic data and disposable test storage. Native Windows, WebView2, SCM, reboot/recovery, UNC and outside-network acceptance require the actual environment.

See [development](../development/README.md), [acceptance guide](README.md), [Windows deployment](../deployment/WINDOWS_DEPLOYMENT.md) and
[backup/recovery](../operations/BACKUP_AND_RECOVERY.md). Current runtime/install state is operational evidence and is not a repository deployment configuration.
