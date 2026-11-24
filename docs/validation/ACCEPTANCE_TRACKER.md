# AuthLens 2.0.0 Windows acceptance tracker

**Candidate status: accepted for controlled testing, NOT APPROVED for production.** This file records only results the operator actually
produced on the disposable Windows VM. A scenario is **Passed** only with operator evidence; otherwise it is Not run, Blocked (environment) or
Failed (product). Procedures: [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md). Implementation status: [work packages](WORK_PACKAGES.md).

## Candidate under test

| Item | Value |
| --- | --- |
| Source commit | `c780ff6d3f525d8589e3b64f29ffe99cdf4fa9fa` (documentation-only commits after it do not change the candidate) |
| Release folder | `AuthLens-2.0.0-20261124-181522-c780ff6-win-x64` |
| Server installer | `AuthLens-Server-2.0.0-Setup.exe`, 93,405,080 bytes, SHA-256 `f7fde8da9cb66351d36bdc0978787b20b6e15b5a268c58138a6f357ef0f9f983` |
| Desktop installer | `AuthLens-2.0.0-Setup.exe`, 93,397,477 bytes, SHA-256 `4df6a6c2b4fc25255fb1d8e880b559c25d5612f3a2632a1a6da41c62e25dde50` |
| `server\AuthLens.Api.exe` | SHA-256 `6114e76c7db3a73af65d66511d64a50c5589d6f46c7f0a1a098280fbe7634b49` |
| `build-manifest.json` | SHA-256 `5837d41be8a7b7b2621a55c873ced9166da8b2935a563e66fedfa0877bf5d282` |

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
| 3 Enterprise networking | Static private IP and DNS record; domain membership; lab PFX set (valid, renewed, wrong-name); a client in the domain; a remote SMB share; a reverse-proxy host; fix for **D-001** before C8/C9 | — |
| 4 Lifecycle and recovery | A **second newer** candidate for upgrade; a second VM (or snapshot clone) for cross-instance restore; a synthetic SAP Lens 1 backup; fix for **D-001** for `Deploy-AuthLens` recovery/restore commands (the packaged `Install-AuthLens.ps1 -Recover` path is unaffected) | — |

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
| 3 | C8 | Certificate replacement and rollback | Not run | | | Blocked by D-001 until fixed |
| 3 | C9 | Post-installation network change | Not run | | | G-001, D-001 |
| 3 | C10 | Firewall, DNS, TLS, allowed hosts | Not run | | | |
| 3 | D3, D7 | Same-server and remote UNC, unavailable share | Not run | | | |
| 4 | B6 to B10 | Failed-install retry, upgrade, repair, interrupted deployment, cleanup | Not run | | | D-001 affects `Deploy-AuthLens` variants |
| 4 | E3 to E5 | Cross-instance restore, evidence integrity, SAP Lens backup migration | Not run | | | D-001 affects `Deploy-AuthLens -Action Restore` |
| 4 | F9 | Service restart and VM reboot | Not run | | | |

## Defects and gaps

| ID | Class | Found | Description | Impact | Correction (next candidate) |
| --- | --- | --- | --- | --- | --- |
| D-001 | Product defect, confirmed | 2026-11-24, reproduced on the development workstation with an installer-shaped synthetic configuration (not on the VM) | `Deploy-AuthLens.ps1` reads the configuration without `-Packaged`, so a configuration published by Server Setup (no `RepositoryPath`) is refused: "Deployment setting 'RepositoryPath' is required". `Restore-ALCertificateReplacement` reads the restored configuration the same way | On Setup-created servers every `Deploy-AuthLens.ps1` action fails before doing anything (Status, Health, InstallService, ReplaceCertificate, Restore, Rollback, Recover); a certificate-replacement rollback would fail at its configuration read | Read packaged settings when no repository is configured (packaged entry point), including in the certificate restoration; Pester case with a Setup-shaped configuration. Workaround for acceptance: use `Install-AuthLens.ps1` from `{app}\setup\<package>\tools` (packaged settings) and direct service/HTTPS checks; do not run C8/C9 until fixed |
| G-001 | Implementation gap, P1 (original remediation scope) | Product owner, 2026-11-24 | Post-installation network configuration through Service Manager: today only the manual configuration edit plus `InstallService -Reconfigure` without validation, readiness-based rollback or a Service Manager workflow | Ordinary administrators must edit deployment JSON; no safe rollback | Validated, Service Manager driven network change with server preflight, readiness verification and automatic restoration (same transaction pattern as certificate replacement); no manual JSON or ImagePath edits |

## Required corrections for the next candidate

1. D-001 (blocker for Stage 3 C8/C9 and the `Deploy-AuthLens` paths of Stage 4).
2. G-001 (P1).
3. Any defect found in Stages 1 and 2 (consolidated before rebuilding).
