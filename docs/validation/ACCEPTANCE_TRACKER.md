# AuthLens 2.0.0 Windows acceptance tracker

**Candidate status: accepted for controlled testing, NOT APPROVED for production.** This file records only results the operator actually
produced on the disposable Windows VM. A scenario is **Passed** only with operator evidence; otherwise it is Not run, Blocked (environment) or
Failed (product). Procedures: [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md). Implementation status: [work packages](WORK_PACKAGES.md).

## Candidates

Internal identifiers only; the product version is 2.0.0 for every candidate and nothing is branded RC. Acceptance results belong to one exact
artifact identity and are never transferred between candidates.

### RC3-VM130 (current, under test on VM130)

Built on VM130 itself from `19a1113`; see the [RC3-VM130 build record](#rc3-vm130-build-record). Accepted for controlled testing only; NOT APPROVED.
Known defects present in this candidate (found 2026-11-25, corrections planned in WP19/WP20, not implemented): D-004 (the preflight requires the
bind address in the certificate; affects C8, C9 and any listener change) and D-005 (recovery-key export needs a complete file path; affects C6).
Acceptance on RC3 continues; record these defects against the affected scenarios instead of working around them.

### RC2 (superseded for VM130 acceptance; artifacts preserved)

Built on VM130 by the agent session from the correction commit for D-001, D-002 and G-001 (`af744c9`); see the
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
| Build directory | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_1926-af744c9` on VM130 (relocated 2026-11-24 from a user-profile root; 32 build-summary artifacts and `verify-release.ps1` verified before and after; not committed) |
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

Reported by the operator from the VM130 build. The release and installers were produced by `build-release.ps1` and `build-installers.ps1`
invoked directly, not by `build.ps1`, so the run directory has **no `build-summary.json`** (not fabricated). Lower-case hashes below equal the
operator-reported upper-case values. Integrity evidence for this candidate: release manifest identity, the packaged and repository
`verify-release.ps1`, `SHA256SUMS`, `installers-SHA256SUMS`, `installer-manifest.json`, the `installer-tools.json` helper hashes and the five
recorded hashes.

| Item | Value |
| --- | --- |
| Source commit | `19a1113adffe780630b52edba8f1ee8dc70bc110` on `experiment/dotnet-backend` |
| Build | On VM130 with `build-release.ps1 -TestFilter (Get-ALTestFilter focused)` and `build-installers.ps1` (lower-level scripts; deviation from the `build.ps1` standard); UTC `2026-11-24T20:21:17.2986796Z`; win-x64; .NET SDK 10.0.404; Node.js 24.22.3 |
| Original output path | `C:\AuthLens-Acceptance\RC2-20261124-212116-19a1113` (non-canonical root and name; local time UTC+1) |
| Canonical path | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_2021-19a1113` (the name `build.ps1` derives from the manifest identity), with `build\AuthLens-2.0.0-20261124-202117-19a1113-win-x64` and `installer\`. Already relocated by the operator; the original path no longer exists |
| Pre-check (agent, read-only, 2026-11-24T20:45Z, on VM130) | Batch 1 section A in self-check mode: all five recorded artifacts, `installers-SHA256SUMS`, `installer-manifest.json`, the seven packaged helpers, packaged and repository `verify-release.ps1` (17 artifacts) and the helpers' equality with the repository at an unchanged commit verified. This validates the batch; A1 itself is recorded from the operator run |
| Upgrade-readiness limitation | `Test-AuthLensUpgradeReadiness.ps1` requires `build-summary.json` (and a recovery report), which this manually orchestrated candidate lacks. Supported read-only substitute: the packaged `Install-AuthLens.ps1 -Mode Server -Operation Upgrade -PreflightOnly -Package <release>` plus the integrity checks above; the wrapper is not bypassed or fed fabricated metadata |
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
  packaged helpers are identical. Artifact hashes differ because every artifact embeds the commit and build time.
- Test selection: RC1/RC2 used the standard focused classes **plus** `ServerSourcePolicyTests`, `DataSourcesTests` and `BackupCryptoTests`
  (194 = 151 + 43). RC3-VM130 used the standard `Get-ALTestFilter focused` (151). The 43 tests of those three classes passed on identical source
  (RC2 build on the workstation) but were not run for this artifact; batch 2 runs them natively on VM130 against the RC3 build outputs, together
  with the focused Pester suites for the packaged runtime, network change and certificate replacement. These are test runs, not acceptance.
- Operator note: the source-commit guard in an earlier manual PowerShell sequence reported a mismatch while later commands continued.
  Operator batches now run as one unit whose guards throw (AGENTS.md).

### Build-root deviations (corrected)

| Candidate | Original location | Canonical location | Verification |
| --- | --- | --- | --- |
| RC1 `c780ff6` | `<user profile>\AuthLens-RC\…` | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_1815-c780ff6` | 32 build-summary artifacts and `verify-release.ps1` exit 0, before and after the move (agent, 2026-11-24) |
| RC2 `af744c9` | `<user profile>\AuthLens-RC2\…` | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_1926-af744c9` | Same, before and after |
| RC3-VM130 `19a1113` | `C:\AuthLens-Acceptance\RC2-20261124-212116-19a1113` | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_2021-19a1113` | Moved by the operator; integrity re-verified by batch 1 |

An earlier run `C:\AuthLens\AuthLens-2.0.0-2026-11-24_0948-8ec7f77` (another session) is preserved untouched. From now on only `C:\AuthLens` is
used ([canonical Windows build](../deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build)).

**Environment correction.** The machine described in earlier reports as the "development workstation" is VM130 itself (`WINDOWS-VM`,
10.0.7.50, WORKGROUP) with the existing AuthLens 2.0.0-alpha.1 service running as `NT SERVICE\AuthLens` on port 18795. Earlier statements that
no AuthLens service existed on that host were wrong. The agent sessions did not install, stop, reconfigure or change that service, its
configuration, data, keys or firewall rules: their test runs used temporary Pester drives, the isolated browser test host on 127.0.0.1:18745,
and read-only service queries.

## Test environment

| Item | Value |
| --- | --- |
| VM | VM130 (`WINDOWS-VM`): Windows 11 Pro build 26300, WORKGROUP (not domain-joined), IPv4 10.0.7.50 (confirmed read-only by the agent; recorded again by batch 1). Repository `C:\Users\<operator>\Git\AuthLens` |
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
| D-004 | Product defect (P1) | 2026-11-25, DASH1 (operator, native) | The installer-generated certificate does not cover a listener IP configured later (`10.26.1.55`), and the installed release's `--server-preflight` refuses it, so every operation gated by that preflight (Setup, VerifyCandidate, ReplaceCertificate, ChangeNetwork) refuses the installation | Three inconsistent SAN requirement sets (source inspection): runtime startup (`HostSettings.Validate`) requires the allowed hosts in network mode only; `--server-preflight` (`MaintenanceCommands.ServerPreflight`, since `503b0f9`, also in `8ec7f77`) requires allowed hosts **plus the bind address** in every mode; generation (`New-ALServerTlsMaterial`) issues listen address + allowed hosts (+ `localhost` on loopback) once, at fresh install. A bind address that no client uses as Host is required anyway, and a later listener change invalidates an otherwise valid certificate | WP20: one shared endpoint-identity rule for generation, runtime, preflight, network change, replacement and recovery (allowed hosts in network mode, the readiness probe authority, the loopback address in Local mode; the bind address only when it is an intended HTTPS identity, that is, listed as an allowed host); hostname verification, pinning, trust and the Host filter unchanged | Recorded; not implemented. Operator evidence: a replacement certificate with all original DNS/IP names plus `10.26.1.55` passed DASH1's read-only preflight (schema compatible, 6 migrations applied, no certificate warnings); **not activated** |
| D-005 | Product defect (P2, usability) | 2026-11-25, DASH1 (operator, native) | Service Manager recovery-key export with a directory instead of a file name ended Service Manager with an access-denied exception | One "absolute key file path" prompt validated only that the path is absolute; the packaged host opened the directory create-only (`UnauthorizedAccessException`, exit 3); the script rethrew at top level and ended (the Start-menu shortcut runs `powershell.exe -File` without `-NoExit`). `recovery.export_requested` is audited before the write; a failed export adds no failure audit entry | WP19: separate directory and file-name prompts, default `AuthLens-<ComputerName>-recovery.key`, extension normalization, destination validation before execution, automatic verification of the exported copy, menu loop with actionable errors | Recorded; not implemented. Workaround on RC3: give a complete file path, for example `E:\AuthLens-recovery\AuthLens-DASH1-recovery.key` |
| G-007 | Implementation gap (P1, blocks DASH1 reconciliation) | 2026-11-25, DASH1 analysis (source inspection) | No supported route when the active certificate itself blocks recovery: VerifyCandidate runs the **candidate's** `--server-preflight` with the configured certificate (on DASH1 the installed `8ec7f77` executable, which has the D-004 rule), and ReplaceCertificate/ChangeNetwork refuse while the journal is in a critical phase (`Assert-ALConfigurationChangeAllowed`: "An interrupted deployment requires -Action Recover before the configuration can be changed"). Setup upgrade and repair stop at the same journal barrier | Recovery and configuration transactions were designed separately; neither accepts a certificate change for an interrupted fresh install | WP20: a recorded certificate step inside candidate recovery (`Recover -RecoveryAction VerifyCandidate` with an explicit replacement PFX): import create-only into `tls\renew-<id>`, candidate preflight against the final configuration, service read grant, configuration and command line replaced through `configuration-pending.json`, restart, readiness pinned to the new certificate, completion; any failure restores the previous certificate and command line and leaves `manual_recovery_required`. Because DASH1 runs `8ec7f77`, correcting D-004 alone does not unblock it | Recorded; not implemented. Requires a new candidate build (approval) |

### DASH1 interrupted first installation (2026-11-24)

Reported by the operator; DASH1 is not a candidate under test and is not modified by the agent.

| Item | Finding |
| --- | --- |
| State | Service `AuthLens` running as `NT SERVICE\AuthLens`, installed `2.0.0` `8ec7f77`, readiness `ready`; journal `20261124-101158-installer-840e61e7` phase `manual_recovery_required` (history backup > switched > starting > verifying > manual_recovery_required), no previous release, no backup. RC3 Setup refused the upgrade in read-only preflight (exit 4, journal barrier); nothing was changed |
| Journal `to_release` | Reported as `AuthLens-2.0.0-20261124-094806-8c6ea68-win-x64`; the `8ec7f77` build produced `AuthLens-2.0.0-20261124-094806-8ec7f77-win-x64` (8c6ea68 is the alpha.1 commit). R1 verifies the actual pointer, folder and manifest |
| Root cause (D-003) | `8ec7f77` probed readiness with the first allowed host even for a loopback listener and had no access-mode consistency rules, so a loopback listener with corporate hosts passed preflight and failed with HTTP 421 after the service was installed. Current sources probe loopback with its own address; Setup-authored configurations carry an access mode whose rules refuse the combination. Residual: configurations without `AccessMode` (Auto) are not checked for it |
| Existing capability | Current tools (RC3 `19a1113`) support this case: `Recover -RecoveryAction VerifyCandidate` revalidates a running owned fresh candidate without a previous release or backup (Pester `Deployment-Recovery`: "fixes forward a running owned fresh candidate..."). `8ec7f77` itself cannot: it treats `manual_recovery_required` as final and has no recovery choices |
| Procedure | [Reconciling an interrupted first installation](../deployment/WINDOWS_DEPLOYMENT.md#reconciling-an-interrupted-first-installation-that-was-corrected-manually): R1 read-only preconditions, R2 verified backup, R3 VerifyCandidate (no service restart), R4 confirmation. R1 was self-tested read-only on VM130 (all probes executed; identity checks correctly refused VM130's own completed journal) |
| Reconciliation attempt (operator, 2026-11-25) | Reconciliation failed on the TLS certificate: the installer-generated certificate lacks the later listener IP `10.26.1.55`, and the installed release's read-only preflight refuses it (D-004). A replacement certificate (all original DNS names and IPs plus `10.26.1.55`) passed the same read-only preflight: database compatible, all 6 migrations applied, no certificate warnings. It is **not activated**. Recovery-key export through Service Manager failed on a directory path (D-005) |
| Status | **Blocked by G-007.** VerifyCandidate (R3) refuses while the configured certificate fails the candidate's preflight, and no supported tool can activate the replacement under the journal barrier. Do not run R3, do not activate the replacement certificate manually (no PFX overwrite, configuration or ImagePath edit) and do not change the journal. The service stays operational as it is; keep the replacement PFX and its password file in protected storage. Next: the G-007 correction in an approved candidate, then R1 to R4 with the certificate step. Data-ownership marker (G-006) still to be confirmed by R1 |

### VM130 upgrade alpha.1 to RC3-VM130 (observation)

Operator functional test passed; formal evidence pending. Agent read-only observation during the R1 self-test (2026-11-24T21:29Z): journal
`20261124-211931-installer-ab89b53f` phase `complete` (backup > stopping > switched > starting > verifying > complete) from
`AuthLens-2.0.0-alpha.1-20261123-120358-8c6ea68-win-x64` with a pre-deployment backup; service running as `NT SERVICE\AuthLens`, command line
equals the configuration, listener owned by the service, ACL audit safe, `--server-preflight` validated (schema compatible, 6 applied, none
pending), pinned readiness 200 with runtime identity `2.0.0 19a1113`, Setup registration `verified`. Host key usable, recovery copy not yet
verified (backups blocked until it is). B7 stays **Not run** until the operator's evidence batch.

## Required corrections for the next candidate

Gaps from the DASH1 investigation (not implemented; proposals for the next candidate, subject to approval). They are delivered through two
work packages ([work-package tracker](WORK_PACKAGES.md#fourth-round-service-manager-usability-and-tls-lifecycle-wp19-wp20)); each ID is listed
once and keeps its own focused tests:

| Work package | Includes |
| --- | --- |
| WP19 Service Manager usability | D-005, G-003 (guided deployment recovery), the Service Manager parts of G-005 |
| WP20 Installer and TLS lifecycle | D-004, G-007, D-003 (probe authority accepted by the host policy), the certificate parts of G-001 network changes |
| Recovery records (with WP19) | G-004, G-005, G-006, T-001 |

| ID | Class | Gap | Proposed correction | Focused tests |
| --- | --- | --- | --- | --- |
| D-004 | Product defect (P1) | Preflight requires the bind address in the certificate SANs; SAN rules differ between generation, runtime and preflight | WP20 shared endpoint-identity rule (see [D-004](#defects-and-gaps)) | `CertificatePolicy`/`ServerPreflight` .NET tests per access mode; `Server-Tls`, `Server-NetworkChange`, `Installer-Preflight` |
| D-005 | Product defect (P2) | Recovery-key export accepts a directory and ends Service Manager on access denied | WP19 guided export | `Service-Manager.Tests.ps1` path, permission, cancellation and verification cases; `BackupCryptoTests` directory destination |
| G-007 | Implementation gap (P1) | No certificate step inside candidate recovery; configuration changes refuse under the journal barrier | WP20 recorded certificate step in VerifyCandidate | `Deployment-Recovery.Tests.ps1`: recovery with certificate completes; failure restores the previous certificate and phase; ordinary ReplaceCertificate still refuses under the barrier |
| D-003 | Product defect (fixed in current sources; residual) | Loopback listener with non-loopback allowed hosts passes preflight in Auto mode | Refuse in preflight when the probe authority the readiness check will use is not accepted by the configured host policy (all modes, including Auto); Setup shows the reason before installing | Access plan and `Wait-ALReady` probe authority for loopback + corporate hosts in Auto, Local and Corporate; Setup preflight refusal before any service change |
| G-003 | Implementation gap (P1) | Service Manager has no deployment-recovery workflow; Setup only says recovery is required | Service Manager option: show journal phase/history and offer only the actions valid for the state (VerifyCandidate when running, owned, no previous release; Resume when stopped; Rollback only with a verified previous release and backup; Cancel only at prepared/backup); run `Install-AuthLens.ps1 -Recover -RecoveryAction` after a summary and confirmation | State-matrix tests: each journal shape offers exactly its valid actions; refused actions never change the journal |
| G-004 | Implementation gap (P2) | The completion entry records only the phase, not which recovery action or operator reconciled it | Append action, actor, configuration and manifest hashes and the result operation ID to the history entry | Journal history contents after VerifyCandidate, Resume and Rollback |
| G-005 | Implementation gap (P2) | After CLI recovery the Setup registry key keeps `SetupState=pending-verification` and lacks `ConfigFile`/`Root`; readiness refuses until a Setup run rewrites it | Bind a supported registration update to a successful VerifyCandidate (same values Setup writes), never a manual edit | Registration before/after recovery; readiness wrapper accepts the reconciled registration |
| G-006 | Implementation gap (P1, conditional) | No supported reconciliation when the fresh-install data-ownership marker is gone (for example data copied back manually) | Explicit, audited "adopt verified restored data" path bound to a verified backup identity and the existing instance, never automatic | Missing/invalid marker refusal stays; adoption only with matching verified backup evidence |
| T-001 | Test gap | VerifyCandidate is not tested against a journal written by an older build (`manual_recovery_required` as terminal, no `-RecoveryAction` era) with a configuration without `AccessMode`/`RepositoryPath` and service arguments changed manually afterwards | Add the cases: consistent manual correction completes and preserves history; inconsistent command line, changed pointer, manifest/commit mismatch, pending markers and missing marker refuse | `Deployment-Recovery.Tests.ps1` |

New findings from RC3 acceptance are added above and consolidated before any further candidate.
