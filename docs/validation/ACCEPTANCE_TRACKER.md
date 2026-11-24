# AuthLens 2.0.0 Windows acceptance tracker

**Candidate status: accepted for controlled testing, NOT APPROVED for production.** This file records only results the operator actually
produced on the disposable Windows VM. A scenario is **Passed** only with operator evidence; otherwise it is Not run, Blocked (environment) or
Failed (product). Procedures: [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md). Implementation status: [work packages](WORK_PACKAGES.md).

## Candidates

Internal identifiers only; the product version is 2.0.0 for both and nothing is branded RC.

### RC2 (current, under test)

Built from the correction commit for D-001, D-002 and G-001; identity, hashes and test filter are recorded in
[RC2 build record](#rc2-build-record) once the build has passed. Until then RC2 does not exist and no acceptance runs.

### RC1 (superseded before acceptance)

Not used for acceptance: D-001 affected too many installed administration and recovery operations. Artifacts are preserved unchanged.

| Item | Value |
| --- | --- |
| Source commit | `c780ff6d3f525d8589e3b64f29ffe99cdf4fa9fa` |
| Release folder | `AuthLens-2.0.0-20261124-181522-c780ff6-win-x64` |
| Server installer | `AuthLens-Server-2.0.0-Setup.exe`, 93,405,080 bytes, SHA-256 `f7fde8da9cb66351d36bdc0978787b20b6e15b5a268c58138a6f357ef0f9f983` |
| Desktop installer | `AuthLens-2.0.0-Setup.exe`, 93,397,477 bytes, SHA-256 `4df6a6c2b4fc25255fb1d8e880b559c25d5612f3a2632a1a6da41c62e25dde50` |
| `server\AuthLens.Api.exe` | SHA-256 `6114e76c7db3a73af65d66511d64a50c5589d6f46c7f0a1a098280fbe7634b49` |
| `build-manifest.json` | SHA-256 `5837d41be8a7b7b2621a55c873ced9166da8b2935a563e66fedfa0877bf5d282` |

### RC2 build record

Pending: written after the canonical build of the correction commit passes.

## Test environment

| Item | Value |
| --- | --- |
| VM | _to be recorded from Stage 1 batch 1 output (OS, build, domain membership, IP)_ |
| Snapshot names | _to be recorded_ |
| Operator | _to be recorded_ |

## Stage prerequisites

| Stage | Needs | Does not need |
| --- | --- | --- |
| 1 Core installation | VM snapshot, local administrator, the copied build directory, ~2 GB free on `C:` | Domain, DNS, certificates, SMB, proxy, second VM |
| 2 Core application and data | Stage 1 passed; synthetic CSV set for every source; a second browser profile; a folder `D:\` or `C:\AuthLens-Private` for recovery copies; Desktop Edge on the VM | Domain, remote SMB, proxy (backup/restore within the same VM) |
| 3 Enterprise networking | Static private IP and DNS record; domain membership; lab PFX set (valid, renewed, wrong-name) whose SANs include every host used in C9; a client in the domain; a remote SMB share; a reverse-proxy host | — |
| 4 Lifecycle and recovery | A **second newer** candidate for upgrade (built later from a newer commit; RC1 is older than RC2 but has D-001 and must not be used); a second VM (or snapshot clone) for cross-instance restore; a synthetic SAP Lens 1 backup | — |

## Scenario results

Status values: Not run · Passed · Failed · Blocked (environment). Evidence names refer to files in the operator's evidence package.

| Stage | ID | Scenario | Status | Actual result | Evidence | Defects |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | A1 | Candidate integrity | Not run | | | |
| 1 | B1 | Read-only network suggestions | Not run | | | |
| 1 | B2 | Fresh install, Local mode, review and progress | Not run | | | |
| 1 | B3 | Service registration, identity, startup, readiness, product identity | Not run | | | |
| 1 | C1 | Administrator activation and basic access | Not run | | | |
| 2 | C3 | Key not readable by the service | Not run | | | |
| 2 | C4 | GrantKeyAccess, permissions, traversal | Not run | | | |
| 2 | C5 | CreateKey through Service Manager | Not run | | | |
| 2 | C6 | Recovery-copy export and verification | Not run | | | |
| 2 | C2/F1 | Reviewer account and permissions | Not run | | | |
| 2 | D0 to D2, D4 to D6, D8 to D10 | Local sources for every type, browser upload, Static/Dynamic, refresh, failures, revocation, persistence | Not run | | | |
| 2 | E1, E2 | Encrypted backup, recovery-copy requirement | Not run | | | |
| 2 | F2 to F7 | Navigation, themes, Reviews SoD on/off, Account Review, organizational filters | Not run | | | |
| 3 | B4 | Corporate mode | Not run | | | |
| 3 | B5 | Reverse Proxy mode | Not run | | | |
| 3 | C8 | Certificate replacement and rollback | Not run | | | |
| 3 | C9 | Post-installation network change (Service Manager) | Not run | | | |
| 3 | C10 | Firewall, DNS, TLS, allowed hosts | Not run | | | |
| 3 | D3, D7 | Same-server and remote UNC, unavailable share | Not run | | | |
| 4 | B6 to B10 | Failed-install retry, upgrade, repair, interrupted deployment, cleanup | Not run | | | |
| 4 | E3 to E5 | Cross-instance restore, evidence integrity, SAP Lens backup migration | Not run | | | |
| 4 | F9 | Service restart and VM reboot | Not run | | | |

## Defects and gaps

"Corrected in implementation" means fixed in source with focused automated evidence on the development workstation; native acceptance on the
VM is still required and is tracked by the scenario rows above.

| ID | Class | Found | Description | Root cause | Correction | Status |
| --- | --- | --- | --- | --- | --- | --- |
| D-001 | Product defect (P0) | 2026-11-24, reproduced on the workstation with a Setup-shaped configuration | Installed `Deploy-AuthLens.ps1` refused Setup-published configurations ("Deployment setting 'RepositoryPath' is required"): Status, Health, InstallService, ReplaceCertificate (and its rollback), Restore, Rollback and Recover all failed on Setup-created servers | `Read-AuthLensSettings` required `RepositoryPath` unless the caller passed `-Packaged`; only the installer adapter did, `Deploy-AuthLens.ps1` and the certificate restoration did not. The `-Packaged` path also substituted the module folder as a fake repository path | Execution context derived from the configuration (`repository` with `RepositoryPath`, else `packaged`); no invented path; only source builds (`Resolve-ALCommit`, `New-ALWorktree`) refuse in packaged context; Status reports `execution_context` | Corrected in implementation: `Packaged-Runtime.Tests.ps1` (Setup-shaped configuration; installed tool layout copied from the `build-installers.ps1` inventory and run outside the repository from another working directory), `Server-CertificateReplacement.Tests.ps1` and `Server-NetworkChange.Tests.ps1` on Setup-shaped configurations; native pending (B3, C8, C9, E3) |
| D-002 | Product defect (P1) | 2026-11-24, packaged-runtime audit (source inspection) | The Start-menu Service Manager shortcut passes no `-DataDirectory`, and Service Manager defaulted to `C:\ProgramData\AuthLens\data`, so on a custom root or data directory key and code operations targeted the wrong (possibly new) directory | Hard-coded default instead of the installation's configuration | Without `-DataDirectory`, Service Manager resolves the configuration Setup registered (`HKLM\Software\AuthLens\Server` `ConfigFile`) and uses its `DataDirectory` (or `Root\data`) and `ServiceName` | Corrected in implementation (`Packaged-Runtime.Tests.ps1`); native pending (C3 to C7 on a custom root) |
| G-001 | Implementation gap (P1, original remediation scope) | Product owner, 2026-11-24 | No supported post-installation network configuration: manual JSON edit plus `InstallService -Reconfigure` without validation or rollback | Not implemented in the first remediation | Service Manager options 8/9 (`NetworkStatus`, `ChangeNetwork`) over `Deploy-AuthLens.ps1 -Action ChangeNetwork`: validation (access-mode rules, assigned address, port ownership, packaged-host preflight with the existing certificate), consolidated summary, explicit confirmation, recorded transaction shared with certificate replacement, readiness/listener/identity verification, automatic restoration, interrupted-run recovery (`Recover`), explicit owned-firewall decision | Implemented: `Server-NetworkChange.Tests.ps1` (7 tests); native pending (C9, 8.15) |

## Required corrections for the next candidate

None open. New findings from RC2 acceptance are added above and consolidated before any further candidate.
