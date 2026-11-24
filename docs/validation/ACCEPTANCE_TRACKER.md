# AuthLens 2.0.0 Windows acceptance tracker

**Candidate status: accepted for controlled testing, NOT APPROVED for production.** This file records only results the operator actually
produced on the disposable Windows VM. A scenario is **Passed** only with operator evidence; otherwise it is Not run, Blocked (environment) or
Failed (product). Procedures: [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md). Implementation status: [work packages](WORK_PACKAGES.md).

## Candidates

Internal identifiers only; the product version is 2.0.0 for every candidate and nothing is branded RC. Acceptance results belong to one exact
artifact identity and are never transferred between candidates.

### RC3-VM130 (current, under test on VM130)

Built on VM130 itself from `19a1113`; see the [RC3-VM130 build record](#rc3-vm130-build-record). Accepted for controlled testing only; NOT APPROVED.

### RC2 (superseded for VM130 acceptance; artifacts preserved)

Built on the development workstation from the correction commit for D-001, D-002 and G-001 (`af744c9`); see the
[RC2 build record](#rc2-build-record). Same product source as RC3-VM130 (see reconciliation) but a different artifact identity; no acceptance
was run on it.

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

| Item | Value |
| --- | --- |
| Source commit | `af744c9f807a7191213b75cec86ba34c6eb1f3f5` on `experiment/dotnet-backend` (manifest `source_dirty: false`) |
| Build directory | `<build root>\AuthLens-2.0.0-2026-11-24_1926-af744c9` on the development workstation (separate from RC1; not committed) |
| Release folder | `build\AuthLens-2.0.0-20261124-192657-af744c9-win-x64`, built `2026-11-24T19:26:57Z`, win-x64 |
| Command | `.\build.ps1 -OutputRoot <RC2 build root> -TestFilter <focused>` (canonical build; installers built by it) |
| Tests run by the build | Same focused filter as RC1 (deployment focused classes plus `ServerSourcePolicyTests`, `DataSourcesTests`, `BackupCryptoTests`): **194 passed, 0 failed**. Not FULL |
| Verification | `build-summary.json` status `passed`; release, secrets, installers and branding `true`; `verify-release.ps1` (repository and packaged copy) exit 0, 17 artifacts; installer hashes equal `installers-SHA256SUMS` and `installer-manifest.json`; shipped `AuthLens.Deploy.psm1`, `Deploy-AuthLens.ps1` and `Service-Manager.ps1` equal the commit's sources |
| Focused Pester before the build (Windows PowerShell 5.1, Pester 5.9.1) | 20 deployment/installer suites: **255 passed, 0 failed** (includes `Packaged-Runtime`, `Server-NetworkChange`, `Server-CertificateReplacement`, `Service-Manager`, `InnoIsolation` compiling all installer variants) |
| Unsigned | Code signing is a separate authorized step |

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `installer\AuthLens-Server-2.0.0-Setup.exe` | 93,410,825 | `ed0dd3cf194d7f9e1d5d3b37e63a0276b7f035827057eec7e24166472624d99b` |
| `installer\AuthLens-2.0.0-Setup.exe` (Desktop) | 93,406,953 | `311fd6d8a730baf45ae7dcf15e10348cbd60ff90c94ca7f16cee74028b3a457d` |
| `server\AuthLens.Api.exe` | 123,305,575 | `ca5af577d9fbd84cce6bfb1a1f112450bd9b8141adaaddee534d3e1a7cd8bf03` |
| `desktop\AuthLens.exe` | 178,506,366 | `c38bc1039bbbc262f833ee0beba304b07d5299735a56105025cd2634d2360e23` |
| `build-manifest.json` | 5,933 | `16c481948516af064dc5076337d5aab11be9c3f3c1f21d168d3f4b4d8aabe33a` |
| `SHA256SUMS` | 1,769 | `7c5fe599e8fa08cb3f24b463e7125b22676c519096479b387e76dad821686305` |

### RC3-VM130 build record

Reported by the operator from the VM130 build; the canonical location and the hashes are re-verified by the operator in Stage 1 batch 1
(A1) before any test. Lower-case hashes below equal the operator-reported upper-case values.

| Item | Value |
| --- | --- |
| Source commit | `19a1113adffe780630b52edba8f1ee8dc70bc110` on `experiment/dotnet-backend` |
| Build | On VM130 with the canonical `build.ps1 -TestFilter (Get-ALTestFilter focused)`; UTC `2026-11-24T20:21:17.2986796Z`; win-x64; .NET SDK 10.0.404; Node.js 24.22.3 |
| Original output path | `C:\AuthLens-Acceptance\RC2-20261124-212116-19a1113` (non-canonical root and name; local time UTC+1) |
| Canonical path | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_2021-19a1113` (the name `build.ps1` derives from this identity). Relocation: **pending operator confirmation** (batch 1) |
| Tests run by the build | Standard focused filter: **151 passed, 0 failed, 0 skipped** |
| Verification (operator-reported) | Secret scan 0 findings; release verification 17 artifacts; Server and Desktop publish, Server and Desktop installers passed; unsigned |

| Artifact | SHA-256 |
| --- | --- |
| `AuthLens-Server-2.0.0-Setup.exe` | `9718614ff1186ce597985cba88ad7967f8bfba8cca8d5b94107ef4e17e4fc84c` |
| `AuthLens-2.0.0-Setup.exe` (Desktop) | `305589c614cfaccba869bd9d8366b76885524e1468983bb367ddee0d2e558c48` |
| `server\AuthLens.Api.exe` | `7309a99f32bffe340a773e14baed35cf34df999a09083562f888caadcb067b6a` |
| `desktop\AuthLens.exe` | `6181981854527d41c9dec1a67880195cec78422780ab24170ac02465ff42f622` |
| `build-manifest.json` | `92858ab9348edb716ddda820e8a540dc06e5d3ff0bbd05548d21061f6211fec3` |

**Reconciliation with RC2 (`af744c9`):**

- `git diff af744c9 19a1113` changes only `docs/validation/ACCEPTANCE_TRACKER.md` and `docs/validation/WORK_PACKAGES.md`. Documentation is not a
  build input (the release `README.txt` comes from `backend/scripts/release-README.txt`, unchanged), so code, scripts, installer sources and
  packaged helpers are identical. Artifact hashes differ because every artifact embeds the commit and build time and RC3 was built on another host.
- Test selection: RC1/RC2 used the standard focused classes **plus** `ServerSourcePolicyTests`, `DataSourcesTests` and `BackupCryptoTests`
  (194 = 151 + 43). RC3-VM130 used the standard `Get-ALTestFilter focused` (151). The 43 tests of those three classes passed on identical source
  (RC2 build on the workstation) but were not run for this artifact; batch 2 runs them natively on VM130 against the RC3 build outputs, together
  with the focused Pester suites for the packaged runtime, network change and certificate replacement. These are test runs, not acceptance.
- Operator note: the source-commit guard in an earlier manual PowerShell sequence reported a mismatch while later commands continued.
  Operator batches now run as one unit whose guards throw (AGENTS.md).

### Build-root deviations (recorded, preserved)

RC1 (`<user profile>\AuthLens-RC\AuthLens-2.0.0-2026-11-24_1815-c780ff6`) and RC2 (`<user profile>\AuthLens-RC2\AuthLens-2.0.0-2026-11-24_1926-af744c9`)
on the development workstation, and the original RC3 output under `C:\AuthLens-Acceptance`, used non-canonical roots. Their run-directory names
follow the `build.ps1` convention except the original RC3 folder. They are preserved unchanged; relocation of the workstation candidates into
`C:\AuthLens` needs approval. From now on only `C:\AuthLens` is used ([canonical Windows build](../deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build)).

## Test environment

| Item | Value |
| --- | --- |
| VM | VM130: Windows 11 Pro build 26300, WORKGROUP (not domain-joined), IPv4 10.0.7.50 (operator-reported; confirmed by batch 1) |
| Existing state | AuthLens 2.0.0-alpha.1 installed as a service with application data; port 18795 in use by it. Preserve its backups, keys and data |
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
