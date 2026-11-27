# AuthLens 2.0.0 remediation: work-package tracker

Acceptance results are recorded in the [acceptance tracker](ACCEPTANCE_TRACKER.md). Current candidate: **RC6** from `839123c` (build id `2026-11-26_0330-839123c`, `C:\AuthLens\Build\2.0.0\2026-11-26_0330-839123c`; NOT APPROVED, native acceptance not started; [open items](STATUS.md#rc6-candidate-status)). Previous: **RC5** from `b10dd50` (`C:\AuthLens\AuthLens-2.0.0-2026-11-25_1442-b10dd50`; native results in the tracker), **RC4** from `37eadd5` (`C:\AuthLens\AuthLens-2.0.0-2026-11-25_0807-37eadd5`), **RC3-VM130** from `19a1113` (same product source as RC2 `af744c9`, which corrects D-001, D-002, G-001); the RC1 record below (`c780ff6`) is kept for traceability and is superseded. Open 2.0.0 implementation work: the FILE-008 pre-import change indication; everything else awaits native acceptance ([RC6 open items](STATUS.md#rc6-candidate-status)).

**Release status: NOT APPROVED.** This tracker lets the next agent resume without reconstructing earlier sessions. It records implemented
work and actual test evidence; native Windows acceptance is listed separately and is never implied by focused tests.

Status vocabulary: **Remaining implementation** · **Implemented and verified** (focused automated tests on this host passed) · **Awaiting native
acceptance** (implemented; needs an installed service, SCM, SMB, elevation or an isolated machine) · **External blocker** · **Product-owner decision**.

Environment of the 2026-11-24 Claude rounds: VM130 (`WINDOWS-VM`, Windows 11 Pro build 26300, WORKGROUP, 10.0.7.50), which also hosts the
existing AuthLens 2.0.0-alpha.1 service (`NT SERVICE\AuthLens`, port 18795). Earlier wording called it a developer workstation without an
AuthLens service; that was wrong. The sessions never installed, changed or stopped that service: they used temporary test drives, the
isolated browser test host and read-only queries. .NET SDK 10.0.404, Node 24, Windows PowerShell 5.1 with Pester 5.9.1 (no PowerShell 7), Inno
Setup 6, Microsoft Edge and the repository-pinned Playwright Chromium (user cache). Python checks ran in an isolated virtual environment outside
the repository with `scripts/requirements-checks.txt`. Earlier rounds: Codex (installer, deployment, filters, accounts, checkpoint `dcbb38a`).

Nothing was installed or changed machine-wide: no Windows Service, firewall rule, trusted root, registry key or system ACL. DASH1 was not touched.

## Summary

| # | Package | Implementation | Verified on this host | Awaiting native acceptance |
| --- | --- | --- | --- | --- |
| 1 | Installer network configuration and readiness | Implemented (Codex `e1299db`, `3b146d6`, `dcbb38a`) | `InnoIsolation` compile of all four installer variants | Local/Corporate/Reverse Proxy wizard runs, readiness (checklist §3, 8.14) |
| 2 | Installation state and controlled cleanup | Implemented (Codex `f6a3765`) | `Installer-FailureRecovery` | Failed fresh install, quarantine |
| 3 | Transactions, recovery and retry | Implemented (Codex `a4569ae`); certificate replacement adds its own recorded transaction | `AuthLens.Deploy`, `Deployment-Recovery`, `Server-CertificateReplacement` | Interrupted deployment and retry under SCM |
| 4 | Installer UX and progress | Implemented: consolidated Ready-page review (fresh vs upgrade), Installing-page progress text, progress page during helper checks (`c780ff6`) | ISCC probe compile of the production Pascal code; `InnoIsolation` | Native wizard run (8.14) |
| 5 | Diagnostics and error handling | Implemented; this round: `backup_key_service_access` and `certificate_replacement_pending` in `-Action Status`, Service Manager key-access line | `Server-Diagnostics`, `Service-Manager` | Diagnostics on an installed service |
| 6 | Firewall, DNS and TLS | Implemented (Codex); installed-certificate replacement implemented this round | `Server-Tls`, `Server-CertificateReplacement` | Firewall/GPO, DNS, TLS identity, replacement under SCM (8.13) |
| 7 | Service Manager | Implemented; `GrantKeyAccess`, service-identity resolution, key-access status; RC2: network status/change (G-001), installation resolution from Setup registration (D-002) | `Service-Manager` (6 tests, real DACL on synthetic files) | Run elevated against an installed service |
| 8 | Recovery keys and service permissions | Implemented: key states (`68ee12b`); least-privilege provisioning (this round) | `BackupCryptoTests` (earlier round), `Service-Manager`, `Server-Diagnostics` | Service-identity read under SCM (8.9, 8.10) |
| 9 | Backup and restore | Implemented; restore copies and selects the key and re-grants service read (`Grant-ALAccess`); source authority excluded from backups by design | Earlier round `ApplicationBackupTests` | Encrypted backup and cross-instance restore (8.8) |
| 10 | All server-side sources | Implemented; sixth round: precise validation outcomes (`not_a_file`, `invalid_path`, `empty`) and one-step **Validate and import** | Earlier round: `ServerSourcePolicyTests`, `DataSourcesTests`, `server-source-configuration.spec.ts`; sixth round: `DataSourcesTests`, `ServerSourcePolicyTests`, refresh, preview, reimport, directory, SoD metadata, backup and legacy restore classes (84), `server-source-configuration.spec.ts` | Service-identity reads (8.2) |
| 11 | Local and UNC paths | Implemented (lexical + DNS policy, exact authority, revocation) | Earlier round (focused .NET) | **Blocker until run**: real SMB as the service (8.3, 8.5) |
| 12 | Static/Dynamic and Global Refresh | Implemented | Earlier round (focused .NET) | Under SCM, restart, reboot (8.4, 8.7) |
| 13 | Personal themes | Implemented (Codex `0817d57`) | Earlier round `personal-preferences.spec.ts` | Cross-browser on a server |
| 14 | Permission-aware UI | Implemented; Reviews now follows effective permissions and feature availability independently | `reviews-workspace.spec.ts` | Administrator/Reviewer smoke (8.11) |
| 15 | Functional Groups across screens | Implemented (Codex `2a78dfc`); coverage audit below | `filter-consistency.spec.ts` | 8.12 |
| 16 | SoD Manager and Exact Usernames | Implemented (Codex `2a78dfc`) | `filter-consistency.spec.ts` | 8.12 |
| 17 | Regression and acceptance preparation | Focused validation below; acceptance procedure in [Windows checklist §8](../deployment/WINDOWS_DEPLOYMENT.md#8-server-sources-recovery-key-service-access-and-reviews-200-remediation) (8.1 to 8.14) | FULL not run (not authorized) | Entire §8 |
| 18 | Dedicated Reviews workspace | Implemented; SoD independence, Account Review entry, complete contextual entry points, global Overview counters (`c780ff6`) | `reviews-workspace.spec.ts` (5 tests) and affected specs | Administrator/Reviewer smoke (8.11) |
| 19 | Service Manager usability review | Implemented (fifth round): grouped menus, status overview, guided key export with automatic verification, TLS, backup, diagnostics and guided recovery (D-005, G-003) | `Service-Manager.Workflow` (19), `Service-Manager` (6), `Packaged-Runtime` | C6, C11, B11 |
| 20 | Installer and TLS lifecycle review | Implemented (`6fbfd48`): shared endpoint-identity rule, certificate description and public export, combined network and certificate change, certificate step in recovery, Setup review details (D-004, G-007, D-003) | .NET `ServerPreflightTests` with host-policy classes (95); Pester `Server-TlsLifecycle`, `Server-NetworkChange`, `Deployment-Recovery`, installer set (133) | B12, C12, C13 |

**Remaining implementation:** none for packages 1 to 20 (WP19, WP20 and the P0 defect D-006 were implemented in the fifth round, see the
[fourth round](#fourth-round-service-manager-usability-and-tls-lifecycle-wp19-wp20) for their scope); deferred: G-004, G-005, G-006 and the
older-journal fixture of T-001 ([acceptance tracker](ACCEPTANCE_TRACKER.md#required-corrections-for-the-next-candidate)). What remains is native
acceptance, the external blockers and the product-owner decisions below.

## Release qualification (third round)

### Product decisions approved for 2.0.0

| Decision | Effect in the repository |
| --- | --- |
| Historical snapshot enrichment deferred (provisionally 2.1.0) | Evidence contract unchanged; frozen snapshots never rewritten; design kept as a [recommendation](../features/REVIEWS.md#historical-organizational-evidence-recommendation-not-implemented) |
| `NT SERVICE\AuthLens` is the primary supported identity; dedicated domain account/gMSA provisioning deferred | [Supported service identities](../deployment/WINDOWS_DEPLOYMENT.md#supported-service-identities-200-product-decision) documented; no credential handling added; local and UNC access under the virtual account stays mandatory acceptance |
| Reviews Overview counters global within the authorized scope; detail views keep filtered counters | Implemented (`c780ff6`): the access-review counters no longer use Work Queue filters; both cards state their scope; a note links to the filtered Work Queue |

### Implementation reconciliation

"Native acceptance" means implemented and focused-tested, but not yet executed on an installed service ([VM runbook](WINDOWS_VM_ACCEPTANCE.md)).

| Requirement | Implementation | Status |
| --- | --- | --- |
| Recovery-key provisioning | Service Manager `CreateKey` grants the resolved service identity read on the key file; `GrantKeyAccess` repairs; deployment/restore re-grant (`Grant-ALAccess`) | Implemented; native acceptance (C3 to C5) |
| Directory traversal to the key | No folder grant by design; relies on the default *Bypass traverse checking* right; a hardened policy is diagnosed (`inaccessible`, `backup_key_service_access`) and needs a reviewed grant | Implemented and documented; native acceptance (C4) |
| Actual service identity resolution | Service Manager reads `Win32_Service.StartName` and resolves virtual, built-in, local, domain and gMSA accounts to a SID; unresolvable identities are refused | Implemented (Pester); native acceptance (C5) |
| Installer integration of key provisioning | Setup never creates keys (no key material in the installer transaction); the Ready and Finish pages direct to Service Manager `CreateKey`, which grants service read; upgrade preserves the key file ACL | Implemented as designed; native acceptance (B2, C5) |
| Post-installation network configuration | `Deploy-AuthLens.ps1 -Action InstallService -Reconfigure` after a reviewed configuration edit, then restart and Health; Service Manager does not offer it and there is **no automatic rollback** | Implemented for RC2 (G-001): Service Manager network workflow over the shared configuration transaction; Pester-tested; native acceptance C9 |
| Certificate replacement and rollback | `-Action ReplaceCertificate`: validation first, create-only import, recorded switch, pinned readiness, automatic restoration and interrupted-run restoration | Implemented (Pester 7 tests); native acceptance (C8) |
| Installer responsiveness during certificate generation and preflight | Marquee progress page naming the running helper check (`c780ff6`) | Implemented (ISCC compile, `InnoIsolation`); native acceptance (B2) |
| Meaningful progress reporting | Progress page for wizard checks, Installing-page transaction text, consolidated Ready page | Implemented; native acceptance (B2) |
| Fresh-install recovery | Failed fresh install evidence, quarantine and retry (Codex `f6a3765`) | Implemented (Pester); native acceptance (B6) |
| Local, Corporate and Reverse Proxy modes | Wizard pages, draft configuration, server preflight and runtime host/proxy policy | Implemented; native acceptance (B2, B4, B5) |
| All server-side source types | Browser upload, local path, UNC for every file-based source ([matrix](../data/IMPORT_AND_REFRESH.md#data-source-compatibility-matrix)) | Implemented (focused .NET); native acceptance (D1 to D3) |
| Static and Dynamic refresh, Global Refresh | Implemented | Focused .NET; native acceptance (D4, D9) |
| Backup and restore compatibility | Encrypted archives, key-bound restore, source authority excluded and re-authorized | Implemented; native acceptance (E1 to E5) |
| Permission-aware Reviews navigation | Effective permissions and feature availability applied independently | Browser tests passed; native smoke (F1, F2, F5) |
| Historical evidence integrity | Unchanged evidence contract and checksums | No change this cycle; native check E4 |

No mandatory 2.0.0 implementation requirement was found deferred without documentation. The only functional limitation is the manual
post-installation network reconfiguration without automatic rollback (C9); a transactional network change would be a new feature and was not added.

### Release candidate

**AuthLens 2.0.0 release candidate, NOT APPROVED** (native acceptance and FULL regression outstanding). Built on VM130 with
the canonical `build.ps1` (authorized release-candidate and installer build); nothing was installed, signed, tagged, uploaded or merged.

| Item | Value |
| --- | --- |
| Source commit | `c780ff6d3f525d8589e3b64f29ffe99cdf4fa9fa` on `experiment/dotnet-backend` (clean; manifest `source_dirty: false`) |
| Build directory | `C:\AuthLens\AuthLens-2.0.0-2026-11-24_1815-c780ff6` on VM130 (relocated from a user-profile root with before/after verification; binaries are not committed) |
| Release folder | `build\AuthLens-2.0.0-20261124-181522-c780ff6-win-x64` (built `2026-11-24T18:15:22Z`, win-x64, .NET SDK 10.0.404, Node 24) |
| Command | `.\build.ps1 -OutputRoot <build root> -TestFilter <focused>` |
| Tests run by the build | Focused filter, recorded in `build-summary.json`: the deployment focused classes (`StartupTests`, `ApiTests`, `NetworkTests`, `ReverseProxyTests`, `SessionTests`, `AccountsTests`, `AccountCompatibilityTests`, `PersistenceTests`, `ApplicationBackupTests`, `LegacyRestoreTests`, `MaintenanceCommandsTests`, `V1CompatibilityTests`, `VersioningTests`, `V1DataMigrationTests`) plus `ServerSourcePolicyTests`, `DataSourcesTests`, `BackupCryptoTests`: **194 passed, 0 failed**. Not FULL |
| Verification | `build-summary.json` status `passed`; release, secrets, installers and branding verification `true`; `verify-release.ps1` (repository and packaged copy) exit 0: 17 artifacts |
| Unsigned | Code signing is a separate authorized step |

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `installer\AuthLens-Server-2.0.0-Setup.exe` | 93,405,080 | `f7fde8da9cb66351d36bdc0978787b20b6e15b5a268c58138a6f357ef0f9f983` |
| `installer\AuthLens-2.0.0-Setup.exe` (Desktop) | 93,397,477 | `4df6a6c2b4fc25255fb1d8e880b559c25d5612f3a2632a1a6da41c62e25dde50` |
| `server\AuthLens.Api.exe` | 123,305,575 | `6114e76c7db3a73af65d66511d64a50c5589d6f46c7f0a1a098280fbe7634b49` |
| `desktop\AuthLens.exe` | 178,506,366 | `5e31774798138177c26b4fca9326d56ff77e3f0146f397221d5b7062ed4c5c83` |
| `build-manifest.json` | — | `5837d41be8a7b7b2621a55c873ced9166da8b2935a563e66fedfa0877bf5d282` |
| `SHA256SUMS` | — | `7bb16c1f2405d7c0432a427194ab5b79367c0a955d288f29307094a5dc83c532` |

The installer hashes equal `installer\installers-SHA256SUMS` and `installer\installer-manifest.json`. Commits after `c780ff6` change
documentation only; they do not change the candidate.

## Fourth round: Service Manager usability and TLS lifecycle (WP19, WP20)

Recorded 2026-11-25 from native DASH1 findings (review of RC3 `19a1113` and the `8ec7f77` executable installed on DASH1). **Implemented in the
fifth round** (2026-11-25, approved): D-006 first (`c077eaf`), then WP20 (`6fbfd48`) and WP19; the corrections below describe what was built.
Focused tests only (Level 1 and 2); FULL, a candidate build and native acceptance are not run. DASH1 was not modified by the agent; it was
remediated manually by the operator (G-007 workaround) and its journal completed by D-006
([acceptance tracker](ACCEPTANCE_TRACKER.md#dash1-interrupted-first-installation-2026-11-24)).

### Fifth round: D-006 and implementation of WP19 and WP20

| Item | Implemented | Focused evidence (this host, VM130) |
| --- | --- | --- |
| D-006 (P0) | One action policy (`Get-ALActionPolicy`): read-only, simulated (Deploy, Recover, ReplaceCertificate, ChangeNetwork, ProtectAcl) or refusing `-DryRun` (Build, InstallService, Restore, Rollback, RestoreAcl, ExportCertificate); `-DryRun` never replaces `-Yes`; read-only `Recover -DryRun` preview sharing the real decision; simulations hold the mutex only, write nothing and are verified by a persistent-state snapshot; a finished journal is never reopened | `Deployment-DryRun` 11, affected Pester files 109 |
| WP20 | `CertificatePolicy.RequiredIdentities` everywhere; `--certificate-info`, `--certificate-export-public`; Status `certificate_status`; `ExportCertificate`; ReplaceCertificate and ChangeNetwork summaries with old and new thumbprints and the client-trust notice; combined network and certificate transaction; certificate step inside VerifyCandidate/Resume (also `Install-AuthLens.ps1 -RecoveryCertificateFile`); D-003 rule; Setup review page certificate details | .NET 16 + 79 (preflight, network policy, LAN HTTPS, origin, reverse proxy, configuration, maintenance, startup); Pester 42 (TLS lifecycle, network change, recovery, DryRun, replacement) and installer set 133 (1 skipped) |
| WP19 | Service Manager rewrite on the existing helpers: overview, seven groups with Back/Exit, menu loop and diagnostic log, guided key export (separate prompts, default name, extension, validation, confirmed protected folder, automatic verification, guidance), certificate status, export and replacement, encrypted backup with verification, diagnostics report, guided recovery (simulation first, explicit action, `YES`, installed Setup tools); all earlier `-Action` contracts kept | `Service-Manager.Workflow` 19, `Service-Manager` 6, `Packaged-Runtime` 6 |
| Not done | G-004 (actor and hashes in history), G-005 (registration update after CLI recovery), G-006 (audited adoption of restored data), T-001 older-build journal fixture; Desktop installer unchanged (no TLS); restart of the service from Service Manager is not offered (Services console) | — |

### WP19 Service Manager usability review

RC3 inventory (`backend/scripts/Service-Manager.ps1`, menu and `-Action`): 1 key status, 2 create host key, 3 export recovery copy, 4 verify
recovery copy, 7 grant the service key read, 5 activation code, 6 administrator recovery code, 8 network status, 9 network change. Deployment
status, certificate replacement, recovery and diagnostics exist only in `Deploy-AuthLens.ps1` and `Install-AuthLens.ps1`.

| Finding | Current behavior | Correction |
| --- | --- | --- |
| SM-01 (D-005) | One "absolute key file path" prompt; a directory passes validation; the packaged host refuses with access denied and the script ends | Separate directory and file-name prompts; default `AuthLens-<ComputerName>-recovery`; `.key` appended once (case-insensitive, never `.key.key`); quoted paths and spaces accepted; invalid file-name characters, relative paths, reparse points and the data directory refused before execution |
| SM-02 | Export does not verify the copy; escrow stays unverified until a separate VerifyKey | Successful export runs VerifyKey on the exported file and shows the fingerprint and `escrow_verified`; standalone VerifyKey stays |
| SM-03 | CreateKey creates a missing directory without asking; export never creates one; no write-access check | Missing directory: explicit confirmation, then the protected ACL CreateKey already uses; write access checked with a create-only probe file that is removed; an existing destination is refused and a new name requested (never overwritten) |
| SM-04 | One action per start; any error ends the script; raw stderr/JSON in messages | Menu loop; every action returns to its menu after a recoverable error with an actionable message; technical details (exit code, error type, message, operation) go to `<Root>\logs\service-manager\` without process output of key or code actions |
| SM-05 | Start shows data directory and executable only | Startup overview: service state and identity, running version and commit, readiness, access mode and listener, certificate expiry and missing identities, key state and escrow, journal phase, pending configuration change |
| SM-06 | Banner "never stops, starts or migrates services" although ChangeNetwork restarts the service | Each action labelled read-only, changes data or restarts the service; one confirmation style (summary, then `YES`) for every disruptive or sensitive action |
| SM-07 | Flat, out-of-order menu (7 between 4 and 5) | Grouped menus: 1 Service status and management, 2 Network, 3 TLS certificates, 4 Backup and recovery keys, 5 Administrator accounts, 6 Deployment and recovery, 7 Diagnostics and logs; `B` Back, `Q` Exit everywhere |
| SM-08 | No TLS operations | Group 3 over WP20: status, missing identities, replacement, public certificate export |
| SM-09 (G-003) | No deployment-recovery workflow, backup creation/verification or diagnostics export | Group 6: journal phase and history with only the actions valid for the state (VerifyCandidate, Resume, Rollback, Cancel) over `Install-AuthLens.ps1 -Recover -RecoveryAction`; group 4: verified local backup; group 7: Status/diagnostic bundle without secrets |
| SM-10 | Executable fallback `C:\ProgramData\AuthLens\releases\current` ignores a registered custom root (only when run outside the installed payload) | Resolve from the registered configuration's `Root` and `ReleasesRoot` |

Contracts kept: every existing `-Action` and parameter, `-Yes` for non-interactive use, exit codes, no key value or one-use code in logs,
existing host keys and fingerprints untouched, custom roots honored. In non-interactive mode a directory `-Path` is refused with a message naming
the default file name (no silent naming). Service Manager stays a client of the existing deployment tools and the packaged host; no duplicate
transaction or key logic.

### WP20 Installer and TLS certificate lifecycle review

| Finding | Current behavior | Correction |
| --- | --- | --- |
| TLS-01 (D-004) | Generation: listen address + allowed hosts (+ `localhost` on loopback). Runtime startup: allowed hosts in network mode, none on loopback. `--server-preflight`: allowed hosts **and the bind address** in every mode | One endpoint-identity rule shared by generation, runtime, preflight, ChangeNetwork, ReplaceCertificate and recovery: every allowed host in network mode, the readiness probe authority, the loopback address in Local mode. The bind address is required only when it is an intended identity (listed as an allowed host). Requests with any other Host value are already refused by the Host filter, so nothing is weakened |
| TLS-02 | ChangeNetwork keeps the certificate ("it must cover the new hosts"); a change to a new IP or host needs a separate replacement first | Network change shows the missing identities and offers a combined certificate replacement in the same recorded transaction |
| TLS-03 (G-007) | VerifyCandidate needs the configured certificate to pass the candidate's preflight; ReplaceCertificate and ChangeNetwork refuse under the journal barrier | Recorded certificate step inside VerifyCandidate (tracker G-007) |
| TLS-04 (D-003) | Probe authority: loopback listen address, else the first allowed host; Auto-mode configurations are not checked for a probe authority the Host filter rejects | Preflight refuses when the probe authority is not an accepted host or not covered by the certificate, in every access mode |
| TLS-05 | Status shows the certificate path only; `server.cer` exists only for generated certificates | Certificate status: subject, issuer, validity, SAN coverage per required identity, SHA-256 thumbprint, self-signed or CA-issued; public certificate export (DER/PEM, no private key) for generated and imported certificates |
| TLS-06 | No explanation of the client-trust effect of a new self-signed certificate | Replacement summary states which clients must trust the new certificate and that the old thumbprint stops working |
| TLS-07 | A generated certificate is checked by the packaged preflight right after generation (source-verified); the import path and certificate preservation on upgrade and repair were not re-verified in this review | Tests that Setup validates against the final network page values before committing, and that upgrade and repair never replace a certificate unless replacement is requested |
| TLS-08 | Generated certificates are valid 365 days; expiry under 30 days is only a startup log warning | Expiry in the status overview and Status JSON; renewal through the replacement workflow |

Constraints kept: no weaker hostname verification, pinning, chain trust or Host restrictions; no trust-store change; previous TLS files are
never deleted; every certificate change is a recorded transaction with rollback and interruption recovery.

### Focused tests required (Level 1 and 2; FULL not authorized)

| Package | Tests |
| --- | --- |
| WP19 | `Service-Manager.Tests.ps1`: directory-only destination gets the default name; missing extension; `.key` and `.KEY` not duplicated; spaces and quoted paths; relative path, invalid characters, reparse point and data directory refused; missing directory with confirmation yes and no; write-permission failure (Deny ACL on a TestDrive folder) refused before execution; existing file refused and unchanged; cancellation at each prompt writes nothing; export followed by automatic verification (mocked executable) and a verification failure reported; menu returns after an error; Back and Exit; output and diagnostic log contain no key value; CLI `-Action ExportKey -Path <file> -Yes` unchanged and a directory `-Path` refused. `BackupCryptoTests`: export to a directory gives a 422 refusal, not access denied. Recovery workflow: journal state matrix offers exactly the valid actions |
| WP20 | .NET `CertificatePolicy`/`ServerPreflight`: required identities per access mode, bind IP not required unless allowed, allowed IP required, wildcard DNS, runtime and preflight agree. Pester `Server-Tls` (generation from the final configuration), `Server-NetworkChange` (listener change accepted when the IP is not an identity; an added identity the certificate lacks refused before any change with that identity named; combined network and certificate change with rollback), `Server-CertificateReplacement` (status fields, public export has no private key, upgrade/repair preserve), `Deployment-Recovery` (VerifyCandidate with a certificate completes; failure restores the previous certificate and phase; ordinary ReplaceCertificate still refused under the barrier), `Installer-Preflight` (imported certificate missing an identity refused before commit) |

Native acceptance for the next candidate: runbook scenarios C11 to C13, B11 and B12 ([runbook](WINDOWS_VM_ACCEPTANCE.md#c-security-and-administration-from-s1-snapshot-s2-admin-after-c4)).

## Fourteenth round: shared table and filter standards from RC7 manual acceptance (TBL-01 to TBL-05, FLT-01 to FLT-03, 2026-11-27)

Status: implemented in source; targeted validation below; FULL regression, release build and Windows acceptance not run (not authorized).
Version 2.0.0 unchanged; RC7 artifacts and evidence untouched. Details and root causes: [acceptance tracker](ACCEPTANCE_TRACKER.md#rc7-table-and-filter-standardization-2026-11-27).

| Package | Status | Implemented | Tests |
| --- | --- | --- | --- |
| TBL-01 | Implemented | Long-text column contract; table regions contain absolutely positioned content | `position-changes.spec.ts` (TBL-01, 375-1600 px, both themes) |
| TBL-02 | Implemented | `TableRegion` sticky head with mirrored top scrollbar | `table-top-scrollbar.spec.ts`, `release-matrix-width.spec.ts`, `sod-evidence-modals.spec.ts` |
| TBL-03 | Implemented | Standard page sizes, per-table preference, 250-row server pages | `table-page-size.spec.ts`, `release-roles.spec.ts`, `AccessTests` |
| TBL-04 | Implemented | Canonical labels, stable column keys, unchanged CSV headers | `table-standards.spec.ts` and the specs whose labels changed |
| TBL-05 | Implemented | Frozen SAP username column | `table-standards.spec.ts` (375-1600 px, both themes) |
| FLT-01 | Implemented | Filter group order; Release Access exception | `filter-panels.spec.ts` |
| FLT-02 | Implemented | Collapsible, persisted, counted sections | `filter-panels.spec.ts` |
| FLT-03 | Implemented | Filter discovery | `filter-panels.spec.ts` |

Validation: Level 1 per package: TBL-01 `position-changes.spec.ts` 13/13; TBL-02 `table-top-scrollbar.spec.ts` 13/13; TBL-04/05 `table-standards.spec.ts` 13/13; TBL-03 `table-page-size.spec.ts` 2/2 and the Release Access pagination test; MW-1 `release-matrix-width.spec.ts` 20/20 after the table frame; FLT `filter-panels.spec.ts` 6/6. Backend (page cap): `AccessTests`, `AccountReviewTests`, `ReportsTests`, `SodPeriodsTests`, `SodAnalysisTests`, `FunctionalGroupTests`, `PositionChangeTests` and the other classes that page tables, 99/99. Level 2, 65 affected spec files in one process: 564 passed, 18 failed (1.6 h); the 18 were test contracts made obsolete by the new standards (collapsed secondary groups, the 25-row default where a test assumed 50, the rows-per-page selector now in the table toolbar, the canonical labels, *Expand all* names shared with page controls, the keyboard order with group headers), corrected without weakening assertions, plus one measurement race. Rerun of the 12 affected files: 110 passed, 2 failed, both then corrected (3/3); Level 3 `refinement-27.spec.ts` `--repeat-each 3`: 48/48. Static: type check, ESLint of `src` and `tests`, frontend unit tests, `check-docs`, `check-secrets`, `check-structure`, `git diff --check`: passed. FULL not run.

## Thirteenth round: FULL regression corrections (FULL-FIX-01) and Release Access matrix width (MW-1, 2026-11-27)

FULL regression of `de71c0b`: **failed** (20 of 21 stages; .NET 581/0, Pester 640/0/12 skipped, Playwright 938 passed and 23 failed of
961), evidence `C:\AuthLens\Validation\2.0.0\20261127-081117-de71c0b`. Status of the corrections: implemented in source; targeted
validation below; no new FULL run (not authorized). Version 2.0.0 unchanged.

| Package | Status | Implemented | Tests |
| --- | --- | --- | --- |
| FULL-FIX-01 | Implemented | The 23 failures: 20 obsolete test contracts (navigation and Settings drawers, NAV-3/NAV-4 module structure, renamed theme control), 2 locale-dependent number expectations, 1 test synchronization defect; no application defect ([disposition](ACCEPTANCE_TRACKER.md#full-regression-of-de71c0b-and-full-fix-01-2026-11-27)) | The 15 affected spec files (Level 2), locale Level 3 |
| MW-1 | Implemented | Release Access matrix spans the whole content width with the filter sidebar open or closed, one matrix per SAP User Group when comparing; internal horizontal scroll only when its columns exceed the width ([Release Access](../features/RELEASE_ROLES.md#matrix)) | `release-matrix-width.spec.ts` (20), the matrix specs (Level 2) |

Validation: Level 1, the 23 failed tests with every width and theme variant (15 spec files, one process): 35 passed, 0 failed. Level 3 locale, `refinement-r2.spec.ts:240` and `storage-upgrade.spec.ts:8` under nb-NO, en-US and de-CH: 2 of 2 each. MW-1: `release-matrix-width.spec.ts` failed on `de71c0b` (reproduction), 20 of 20 after the fix. Level 2, the 15 affected spec files plus the Release Access matrix specs (`access-investigation`, `investigation-filter-refinement`, `investigation-ux`, `refinement-completion`, `refinement-27`, `refinement-round2`, `stabilization`): 237 passed, 1 failed (`refinement-completion.spec.ts:79`, the compact-column contract broken by the first MW-1 variant); after the corrected MW-1, the nine matrix spec files (with `release-roles` and `release-matrix-width`): 137 passed, 0 failed, 0 skipped. No backend or script changed, so no .NET or Pester run. Static: ESLint of the changed specs, `check-docs`, `check-secrets`, `check-structure`, `git diff --check` passed. FULL not rerun.

## Twelfth round: pre-release test stabilization (TS-1) and User Directory export scope (#35, 2026-11-27)

Status: implemented in source on `experiment/dotnet-backend`; Level 1 and Level 2 validation of the affected specs and backend classes passed
(below); FULL regression, release build and Windows acceptance not run (not authorized). Version 2.0.0 unchanged.

| Package | Status | Implemented | Tests |
| --- | --- | --- | --- |
| TS-1 | Implemented | The 36 pre-existing browser failures and the two flaky tests resolved one by one ([TS-1 resolution](ACCEPTANCE_TRACKER.md#ts-1-resolution-2026-11-27)): obsolete expectations rewritten with the shared navigation and Settings helpers, order assertions re-measured, positional and stale locators replaced, the stale-session race and the saved-filter isolation fixed; no assertion weakened | The affected spec files (Level 2) |
| #35 | Implemented | User Directory CSV export scope `export_scope=matching\|all_assignments` (default matching; absent = unchanged v1 behaviour) on `/api/access/exports/users` and the `export_assignments` count of `/api/access/users`; *Assignment CSV rows* under Export scope and *Assignment rows* in Reports → Access Reports; the User Directory report now offers its columns and preview ([User Access](../features/USER_ACCESS.md#directory-assignment-csv-export)) | `UserRoleExportScopeTests`, `ReportsTests`, `user-directory-scope.spec.ts`, `reports.spec.ts`, `refinement-round2.spec.ts` (Task 31) |

Validation: Level 2 browser, the 14 affected spec files in one process (`navigation-a11y`, `stabilization`, `ui-consistency`, `user-role-export`, `design-system`, `investigation-tools`, `refinement-27`, `refinement-round2`, `bulk-group-assignment`, `loading-consolidation`, `status-consistency-r6`, `reports`, `user-directory-scope`, `data-aware-ux`): 166 passed, 0 failed (21.5 min); Level 3 `data-aware-ux.spec.ts:186` `--repeat-each 5`: 5 of 5. Backend: `UserRoleExportScopeTests`, `AccessExportTests`, `AccessTests`, `ReportsTests`, `AccountsTests`, `DataSourcesTests`, `FunctionalGroupTests`, `PositionChangeTests`, `UnicodeTests`, `V1DataMigrationTests`: all passed. Type check, ESLint of the changed files, `check-docs`, `check-secrets`, `check-structure`, `git diff --check`: passed. FULL regression not run.

## Eleventh round: navigation and information architecture (NAV-1 to NAV-8, COR-1, COR-2, COR-T, 2026-11-27)

Status: implemented in source on `experiment/dotnet-backend`; focused backend and browser validation passed (below); FULL regression and Windows
acceptance not run (not authorized). Version 2.0.0, packaging and release procedures are unchanged. Implementation approval of 2026-11-26
superseded the assessment where they differ: the SoD Overview keeps its Conflicts, Reviews and Remediation sections, period card and evidence
freshness card (the compact *Review status* row was rejected), Reports gets dedicated report generation, the Account Review and Compare Users
CSV exports moved to the backend, and NAV-8 was added. NAV-6 was amended on 2026-11-27: one column per strategy key with the key only as
header, PR/PO through the existing filter, no grouped headers.

| Package | Status | Implemented | Tests |
| --- | --- | --- | --- |
| COR-T | Implemented | Obsolete navigation, Settings and count expectations corrected with the shared drawer and Settings helpers; brittle counts made behavioural; the *Saved filters* failure was a stale locator (filters are a drawer dialog below 1024 px), not order dependence | The corrected specs |
| COR-1 | Implemented | Compare Users subject column has a fixed content width; long descriptions and identifiers truncate with the full value in the tooltip and copy (BUG-09 contract) | `refinement-completion` compact evidence, `role-codeblocks` Compare Users at 375 and 1280 px |
| COR-2 | Implemented | Root cause: the shared population resolver has a `review_states` dimension (pending/completed), and Account Review forwarded its own decision filter of the same name, emptying the population; the decision filter is no longer forwarded | `AccountReviewTests`, `account-review-completed`, `account-review-refinement` |
| NAV-1 | Implemented | Canonical routes and legacy redirects with query and history; main-navigation links always open the module's default landing page fresh (BUG-08 boundary, also within a module); dropdown items and tabs open their pages directly; the Release Roles contextual-return conflict is resolved in favour of the landing page, with Back for the earlier entry | `navigation-routes.spec.ts`, navigation and route specs |
| NAV-2 | Implemented | Users (User Directory, Compare Users, Release Access) with shared `UsersNavigation` tabs; Release Roles renamed Release Access under Users | Users, Release Access and navigation specs |
| NAV-3 | Implemented | Reviews: Overview, Work Queue, Position Changes, Account Review, Bulk Review, Remediation, Review Periods; the account pages on their shared implementation, independent of the SoD switch, with user details inside Reviews | `reviews-workspace`, `position-changes`, Account Review specs |
| NAV-4 | Implemented | Reports module with per-report availability (`/api/reports/availability`), report forms on existing endpoints, shared configurable CSV writer, server-side Account Review and Compare Users exports, new Position Changes CSV, Evidence page ([Reports](../features/REPORTS.md)) | `ReportsTests`, `reports.spec.ts` |
| NAV-5 | Implemented | `/api/data-health` administrator read; Dashboard card and its figures administrator-only | `AccountReviewTests.Data_health_and_the_dashboard_directory_figures_are_administrator_only`, `navigation-routes` (viewer) |
| NAV-6 | Implemented (amended) | One Release Access matrix with one column per strategy key; shared PR/PO strategies are one column with backend distinct users; `matrix_totals` per Release Group, strategy, type and in total; drill-downs reconcile (`parsed=true` with the matrix filters) | `ReleaseAccessMatrixTests`, `release-roles`, `refinement-completion` matrix tests |
| NAV-7 | Implemented | Shared navigation components for all multi-page modules, landing pages, active states, drawer; documentation and the tracker updated | Navigation specs at 375, 800, 1280 and 1600 px |
| NAV-8 | Implemented | Access Explorer *Review in Bulk Review* hands the exact selection, context and filters to the one bulk workflow (atomic); investigation action tracking is preserved and created in the decisions' transaction | `SodBulkReviewTests.An_atomic_investigation_tracks_its_actions_in_the_same_transaction`, `sod-bulk-review`, `consolidated-refinement` |

Decisions made without explicit guidance: Release Access keeps its internal page key and saved-filter view key; the account pages render
their title as a section heading under the Reviews page title; Bulk Review stays atomic and keeps investigation action tracking by creating the actions in the
decisions' own transaction (`atomic_actions`; the v1 refusal of `atomic` + `track_action` is unchanged); Account Review and Compare Users keep their earlier formula guard on every field,
identifiers included; SoD CSV exports keep their fixed columns; n/a marks a Release Group without a release role of a strategy (a valid
combination without users is not knowable from assignment data).

The assessment that preceded the implementation follows unchanged for traceability.

### Approved decisions

| Area | Approved requirement |
| --- | --- |
| Top level, in order | Dashboard, Role Lookup, Users, SoD, Reviews, Reports. Existing icons and the Settings utility are kept |
| Dashboard | Unchanged, except that the whole *Directory & Data Health* card is hidden from non-administrators (no reduced version) |
| Role Lookup | Unchanged: Role Lookup, Role Cart and Access Packages stay one integrated page |
| Users (renamed from User Access) | User Directory, Compare Users, Release Access (Release Roles renamed and moved here) |
| SoD | Stays a top-level module; the heatmap stays only in SoD; internal changes need separate approval (recommendation below) |
| Reviews, in order | Overview, Work Queue, Position Changes, Account Review, Bulk Review, Remediation, Review Periods. Position Changes and Account Review stay separate pages on their shared implementation; Work Queue and Bulk Review stay separate |
| Reports | Review Reports (default), Access Reports, SoD Reports, Evidence; no Reports Overview page; dedicated report generation that reuses existing services |
| Settings | Structure and the *Data & Integrations* group unchanged; no Data Management group; Data Health stays in Data & Integrations › Data Sources and is administrator-only |
| Routes | New canonical routes; every existing bookmark, deep link, supported query parameter and contextual link resolves to the new destination; one implementation per page |
| Reports availability | Independent of the SoD switch; authorization and module availability per report and evidence item, enforced in the backend as well; the default resolves to an authorized page; no empty destinations |
| Release Access | One matrix for PR and PO, the PR/PO filter reused, Matrix and Table kept with columns, sorting, filters, drill-down, comparison, Role Cart and exports; PR and PO stay distinct dimensions; an authoritative backend count of distinct users across PR and PO |
| Navigation pattern | Top-level modules, dropdowns for multi-page modules, module tabs, the existing shared navigation components and tokens; no per-module navigation system |

### Current navigation inventory (repository, `bbcfc0d`)

Main navigation (`App.tsx`, `lib/navigationItems.tsx`); routes from `hooks/useViewHistory.tsx`. `read` is held by every role.

| Main entry | Pages and routes | Gating |
| --- | --- | --- |
| Dashboard | `#/dashboard`; cards including *Directory & Data Health* (rendered for every role; its figures come from `GET /api/dashboard`) | `read` |
| Role Lookup | `#/role-lookup`; role details, comparison, Access Package panel | `read`; package export `export` |
| User Access | User directory `#/user-access`, user `#/user-access/user/<name>`, Account Review `/account-review`, Position Changes `/position-changes`, Compare users `/compare` | `read`; decisions `review` |
| Release Roles | `#/release-roles`; Table and Matrix (one PR and one PO matrix, per SAP User Group when comparing) | `read` |
| SoD | Overview `#/sod`, Risk Matrix `/risk-matrix`, Activity Matrix `/activity-matrix`, Access Explorer `/explorer` (`/users`, `/roles` select its tabs) | SoD switch |
| Reviews | Overview `#/reviews`, Work Queue `/queue`, Bulk Review `/bulk`, Remediation `/remediation`, Review Periods `/periods`, Reports and Evidence `/reports` | Overview always; the rest follow the SoD switch; actions `review`, period transitions `approve` |
| Settings (utility) | General, Data & Integrations (Data Sources with Data Health, SAP Modules, Runtime & Scheduling, Functional Groups), Security & Governance, System & Tools | `admin` (Desktop and access-token sessions are administrators) |

Legacy `#/sod/reviews[/bulk|/remediation]`, `#/sod/periods` and `#/sod/reports` already redirect through `normalize`. Saved Filters are keyed
by view (`users`, `roles`, `release`, `dashboard`, `sod_overview`, `sod_risk_matrix`, `sod_activity_matrix`, `sod_explorer`, `sod_queue`, ...;
`V1SavedFilters.Allowed`).

### Current-to-target route mapping

| Current route | Canonical target | Notes |
| --- | --- | --- |
| `#/dashboard`, `#/role-lookup` | Unchanged | — |
| `#/user-access` | `#/users` (User Directory) | Directory filters and `userContext` carried over |
| `#/user-access/user/<name>` | `#/users/user/<name>` | `userHref` callers (SoD, Reviews, Release drill-down) switch to the new builder |
| `#/user-access/compare` | `#/users/compare` | Compare selection kept |
| `#/release-roles` | `#/users/release-access` | `release` drill state and saved-filter view `release` unchanged |
| `#/user-access/account-review` | `#/reviews/account-review` | Must stay available with SoD turned off |
| `#/user-access/position-changes` | `#/reviews/position-changes` | Must stay available with SoD turned off |
| `#/sod`, `/risk-matrix`, `/activity-matrix`, `/explorer`, `/users`, `/roles` | Unchanged | — |
| `#/reviews`, `/queue`, `/bulk`, `/remediation`, `/periods` | Unchanged | — |
| `#/reviews/reports`, legacy `#/sod/reports` | `#/reports/review` | `#/reports` resolves to the first authorized report page |
| — | `#/reports/access`, `#/reports/sod`, `#/reports/evidence` | New |
| Legacy `#/sod/reviews*`, `#/sod/periods` | Unchanged redirect to Reviews | — |

The hash query (`?...`) is carried over on every redirect, stored `history.state` views are normalized by the same reader, and saved-filter
view keys and local preference keys keep their names, so stored filters and preferences remain valid.

### SoD: existing structure and recommendation

| Page or subview | Purpose (repository) |
| --- | --- |
| SoD header and *review context* bar (`ContextBar`) | Current evidence or a review period as the evaluation context for every SoD page |
| SAP User Group heatmap (`SodGroupHeatmap`) | Users per SAP User Group and risk or activity; rendered above Overview, Risk Matrix, Activity Matrix and Access Explorer; follows the page's filters (Overview population since BUG-015) |
| Overview (`SodOverview`) | Filters; *Open Work Queue*; key figures in three sections: **Conflicts** (users with conflicts, multi-risk users, user-risk findings, enabled risks), **Reviews** (activities pending/approved/removal, risks accepted/rejected/pending), **Remediation** (assignments marked for removal, open and overdue actions, awaiting action); *Review period and approval*; *Evidence freshness and coverage* |
| Risk Matrix, Activity Matrix (`SodMatrices`) | Users against risks or activities with paging, grouping by SAP User Group and CSV export |
| Access Explorer (`SodExplorer`) | Tabs **Users** (findings grouped by risk or activity, evidence modal), **Assignments** (role assignments with review progress and bulk selection), **Roles** (users behind a role), **Role conflicts** (`ConflictView`) |
| SoD Review panel (`SodInvestigation`, application-level side panel) | Subject summary, supporting evidence, remediation impact, what-if simulation and the decision form; opened from SoD, Reviews and User Access |

Functional overlaps: the Overview's *Reviews* and *Remediation* sections and its period card repeat figures that the Reviews Overview (WP37)
shows with the Work Queue population; Access Explorer **Users** grouped by risk or activity overlaps the Risk and Activity Matrix (list versus
grid of the same findings); the Explorer **Assignments** tab carries bulk selection that leads into Bulk Review.

Recommended SoD structure (needs approval; no change without it):

| Change | Rationale | Impact |
| --- | --- | --- |
| Keep Overview, Risk Matrix, Activity Matrix and Access Explorer, with their routes, names and the heatmap | Analysis views that the review workflows depend on; the heatmap requirement keeps it in SoD | None |
| Overview: replace the *Reviews* and *Remediation* tile sections and the period card with one compact *Review status* row (pending, removals, open actions) that opens the Reviews Overview, Work Queue or Remediation with the SoD filters | One place for review figures; avoids two pages with different populations for the same metric | Review workflows and decisions unchanged; drill-down targets move from SoD pages to Reviews pages; the SoD Overview browser specs change |
| Keep the Explorer **Assignments** bulk selection as an entry point that opens Bulk Review with the selection, not a second bulk workflow | Work Queue and Bulk Review stay the review pages | None for permissions (`review` gate unchanged) |
| No merge of the Explorer **Users** tab into the matrices | List and grid answer different questions; merging would remove evidence modals or paging | None |

Permissions and evidence: unchanged (SoD switch, `read`, `review` and `approve`); decisions, snapshots and frozen periods are not touched.

### Reports: existing reports and exports by category

| Category | Existing (reusable) | Generated by | Availability |
| --- | --- | --- | --- |
| Review Reports (default) | Formal review report DOCX/PDF (`/api/sod/reports/{kind}`, preview, period, status, comparison, comments); access remediation report DOCX/PDF/CSV (`/api/sod/reports/remediation/{kind}`, context, filters); configurable Work Queue CSV (`/api/sod/queue/export/configured`, presets, columns, delimiter, current or frozen context); remediation actions CSV (`/api/sod/reviews/actions/export`); Account Review CSV | Backend report builders; Account Review CSV in the browser (`lib/accessExport`) | SoD reports follow the SoD switch; Account Review CSV does not, so Review Reports stays available with SoD off |
| Access Reports | User directory CSV (`/api/access/exports/users`, scope and columns); Compare users CSV (browser); release role list (`/api/access/exports/release-roles`); release assignments (`/api/access/exports/releases`) | Backend, except Compare users | `read`/`export`; current snapshot only |
| SoD Reports | Risk and Activity Matrix CSV and the heatmap export (`/api/sod/matrix/{kind}/group-export`); Access Explorer exports (`/api/sod/explorer/{table}/export`, users-findings); SoD analysis export (`/api/sod/analysis/export`); remediation CSV (`/api/sod/remediation/export`); ruleset export (`/api/sod/catalogue/export`) | Backend | SoD switch |
| Evidence | Review periods with lifecycle state and frozen snapshots; report preview with `model_checksum`; formal and remediation reports regenerated from a frozen period | Backend | SoD switch |

Kept as contextual exports on their pages: Access Package CSV (Role Lookup; depends on the cart), refresh change CSV (Settings, data
administration), diagnostics and configuration exports (Settings), and the page exports above (Reports reuses them; nothing is removed).

Proposed dedicated report generation: one report page per category with a report picker, a description, the parameters the report supports
(population filters through the shared `FilterLayout`/`SodFilters`, scope, columns where the export supports them, output format, current
or frozen review context), a preview count and *Generate*. Every report calls the existing endpoint with the same filter semantics, so the
counts equal those of the source page.

Missing capabilities (new functionality, presented for approval; no placeholder pages):

1. **Server-side Account Review and Compare users reports.** Both are browser-built today; a Reports page outside their pages needs either the
   shared browser builder with the page's queries or a new backend export (recommended for consistent authorization and scope).
2. **Position Changes report.** No dedicated export exists (the Account Review CSV carries the rows); a position-change export is new.
3. **Column selection** exists only for the Work Queue and user directory exports; other exports have fixed columns, and adding selection is
   a backend parameter change per export.
4. **Historical context for access reports.** User Access data is the current snapshot only; historical access reports cannot be offered.
5. **Evidence index.** Generated documents are rendered on demand and not stored; Evidence can list frozen periods and regenerate their reports.
   Storing issued reports would be new functionality.
6. **Report availability.** A small backend endpoint (or configuration field) that states which reports the principal may use, built from the
   existing permissions and the SoD switch, so the default destination and the navigation never show inaccessible pages. Every report endpoint
   keeps its own authorization.

### Release Access: combined matrix

- **Layout.** One matrix per scope (one, or one per SAP User Group when comparing). Rows are Release Groups. Columns use a two-level header:
  the first level is the release type (PR, PO), the second its Release Strategies. A strategy column is identified by (type, strategy), so
  identically named strategies under PR and PO are separate columns and are never aggregated. Cells show distinct users as today and keep
  their click-through (`/api/access/release-assignments` with type, group and strategy). The PR/PO filter limits the matrix to one type.
- **Totals.** Per row and for the matrix: distinct users for PR, for PO and **combined**. The combined value comes from the backend.
- **Backend calculation.** In `GET /api/access/releases`, the existing loop over the filtered assignments already groups users by cell
  (`HashSet` of `UserKey`, the authoritative SAP identity). Add, in the same pass and the same filter scope, sets keyed by scope and type and by
  scope and Release Group (per type and combined), and return them as `matrix_totals` (counts only). A user with PR and PO assignments is one
  member of the combined set. Unparsed release names keep their existing treatment (Table only, *include unparsed* on request).
- **Drill-downs and exports.** A total opens the assignment list with the same parameters minus the strategy (and minus the type for the
  combined total); `release-assignments` already returns `distinct_users`, which must equal the total. The role list and assignment exports are
  unchanged and keep the page filters; KPI, matrix, drill-down and export counts are tested against each other.
- **Tests.** Backend: overlapping PR and PO assignments for one user, identical strategy names under both types, SAP User Group comparison,
  filtered populations. Browser: combined header, totals reconcile with the drill-down, Table and Matrix parity, Role Cart and export unchanged.

### Data Health and the Dashboard card (administrator-only)

- `GET /api/data-health` is a `read` route today (not in `V1Auth.AdminRead`); it becomes administrator-only by adding it to `AdminRead`.
- The Dashboard card is rendered from `GET /api/dashboard`, which returns the directory and data-health figures to every role. The card is
  hidden for non-administrators and the backend omits those figures for non-administrators; figures used by other authorized features
  (Account Review counters, Position Changes) keep their own endpoints and permissions.
- No new permission: the existing `admin` permission (`useAuthentication().can('admin')`, `V1Auth.Permission`).

### Open defects from the BUG-09 Level 2 run, classified

Each was reproduced at HEAD `bbcfc0d` without the BUG-09 change, and the cause was checked against the code and history.

| Test | Finding | Class | Package |
| --- | --- | --- | --- |
| `access-investigation.spec.ts:35` | Expects 4 main navigation links; Reviews (`e457ab6`) made it 5 | Obsolete navigation expectation | NAV-7 (counts change again with NAV-2 and NAV-4) |
| `access-investigation.spec.ts:152` | Expects the open release role detail after the main *Release Roles* link; BUG-08 made main navigation a page boundary, while a comment in `App.tsx` still describes returning to the open record | Contract conflict to settle | NAV-1 |
| `data-aware-ux.spec.ts:119`, `consolidated-role-ui.spec.ts:136` (800 px), `ui-polish-actions.spec.ts:146` (375 px) | Click main navigation links directly; below 1024 px they are in the drawer (`bb3bceb`, after the tests) | Obsolete navigation expectation (the shared `goTo` helper handles the drawer) | NAV-7 |
| `ui-polish-actions.spec.ts:107` | Looks for a *Reports* link; the page is *Reports and Evidence* (`e457ab6`) | Obsolete navigation expectation | NAV-4 |
| `refinement-search-layout.spec.ts:16` (375 px) | Clicks the *SAP Modules* tab; below 768 px Settings uses the sections drawer (`61c4830`, after the test; `selectSettingsSection` exists) | Settings navigation test defect | COR-T |
| `role-visuals.spec.ts:195` | Clicks *Appearance & Branding* without opening Settings | Settings navigation test defect, to confirm | COR-T |
| `refinement-completion.spec.ts:26` | In the full run *Saved filters* was missing in User Access; in isolation that step passes and the test stops at the source health summary, which has 5 rows since `555293c` added *Last source attempt* | Order-dependent state (isolation to investigate) and an obsolete count | COR-T (isolation first) |
| `refinement-completion.spec.ts:102` | 200 buttons instead of 199: the matrix region now holds *Columns for PR release matrix* | Obsolete count | NAV-6 (the matrix is replaced) |
| `refinement-completion.spec.ts:115` | Compare users: the *Role / transaction* column is 1439 px wide at 1280 px (table about 2150 px) | Application defect (responsive table layout) | COR-1, before NAV-2 |
| `account-review-completed.spec.ts:35`, `account-review-refinement.spec.ts:625` | *Review decision* filter returns no accounts | Application defect (filter) | COR-2, before NAV-3 |

No assertion is weakened: obsolete expectations are rewritten to the current, approved behavior, and defects are fixed in the application.

### Work packages

| Package | Scope | Depends on | Affected components and routes | Backend | Regression coverage | Related defects | Risks and open points |
| --- | --- | --- | --- | --- | --- | --- | --- |
| COR-1 | Compare users table column sizing | — | `UserComparison.tsx`, table CSS | — | `refinement-completion` :115, Compare specs at 375 to 1600 px | `:115` | Identifier and table contract (BUG-09) |
| COR-2 | Account Review decision filter | — | `AccountReview.tsx`, `V1AccountReview.cs` | Possibly the filter | Account Review classes, the two specs | `:35`, `:625` | Root cause unknown |
| COR-T | Test corrections and isolation | — | Specs only | — | The listed specs, `--repeat-each 3` for the order-dependent case | Settings and isolation rows | Must not weaken assertions |
| NAV-1 | Route model: canonical `#/users`, `#/reviews/account-review`, `#/reviews/position-changes`, `#/reports/*`; `normalize`, href builders, `readView`, legacy redirects with query and history state; settle the main-link return contract | COR-T | `useViewHistory`, `App.tsx`, every `userAccessHref`/`userHref`/`pageHref`/`sodHref` caller | — | Deep links, reload, Back/Forward, legacy URLs, saved filters | `access-investigation:152` | Broken bookmarks; done first, invisible |
| NAV-2 | Users: rename, User Directory, Compare Users, Release Access (moved, renamed) | NAV-1, COR-1 | `navigationItems`, `UserAccess`, `ReleaseRoles`, `App.tsx`, Role details parent labels | — | User Access, Release Roles, comparison and navigation specs | — | Labels in tests and documentation |
| NAV-3 | Reviews: Position Changes and Account Review pages in the approved order, available with SoD off | NAV-1, COR-2 | `navigationItems` (`REVIEWS_VIEWS`), `ReviewsWorkspace`, `AccountReview` (`mode`), Reviews Overview entry points | — | Account Review, Position Changes, Reviews workspace, SoD-off specs | — | Account Review must not follow the SoD switch; counters stay separate |
| NAV-4 | Reports module: Review Reports (default), Access Reports, SoD Reports, Evidence with dedicated generation on existing services; availability per report; authorized default | NAV-1; approval of the missing capabilities | New Reports workspace, `SodReports` (moved), export clients | Report availability; any approved new exports | Each report against its source page counts, viewer role, SoD off, frozen context | `ui-polish-actions:107` | Scope of new exports; no placeholder pages |
| NAV-5 | Administrator-only Data Health and Dashboard card | — | `Dashboard.tsx`, `V1Auth.AdminRead`, `V1Dashboard.cs` | `/api/data-health` admin; dashboard omits directory figures for non-admins | Viewer and administrator browser specs, `V1Auth` and dashboard tests | — | Other features must keep their data |
| NAV-6 | Release Access combined matrix and `matrix_totals` | NAV-2 | `ReleaseRoles` matrix, `V1ReleaseRoles.cs` | Distinct-user totals per type and combined | Backend overlap and filter tests; matrix, drill-down and export reconciliation | `refinement-completion:102` | Wide matrices at 375 px |
| NAV-7 | Navigation consistency, count-based assertions, Component Library and documentation (README, NAVIGATION, REVIEWS, feature guides) | NAV-2 to NAV-6 | Navigation specs, docs | — | `check-docs.py`, navigation specs at 375/800/1280/1600 px in both themes | `access-investigation:35`, drawer rows | Documentation drift |

Remaining decisions: the SoD recommendation above; which missing report capabilities (1 to 6) are in scope for NAV-4; whether COR-2 may
change backend filter logic if the root cause is there.

## Tenth round: RC7 consolidation (WP37 and RC6 acceptance defects, 2026-11-26)

Source-level work after RC6 (`839123c`); RC6 stays the immutable packaged baseline and remains installed on VM130 and DASH1 (operator
report). Defects found in RC6 acceptance (BUG-013 to BUG-015, the WP30 saved-filter defect, culture-dependent scheduled-refresh timestamps)
are recorded with root cause and tests in the [acceptance tracker](ACCEPTANCE_TRACKER.md); WP35 (frontend-only deployment) was assessed as not
feasible without a backend change ([assessment](../architecture/UI_INTEGRATION.md#frontend-only-deployment-assessment-wp35-2026-11-26)).
The brief's `REV-001` to `REV-013` are written `WP37/REV-n`; no `REV-` identifier exists elsewhere.

| Requirement | Status | Evidence and limits |
| --- | --- | --- |
| WP37/REV-1 replace navigation cards | Implemented | Cards removed; Review views navigation unchanged; **Open Work Queue** in the page toolbar |
| WP37/REV-2 shared dashboard design | Implemented | `dashboard-workspace`/`dashboard-cards` grid (container-query reflow from BUG-014), `SectionHeader`, `InfoList`/`InfoRow`, `DataTable`, shared states; light and dark |
| WP37/REV-3 review progress | Implemented | Users, requiring review (partly reviewed, not started), complete, completion, removal and outdated as overlapping indicators. *Users with no applicable items* is not shown: users without review items are not part of the review population |
| WP37/REV-4 review coverage | Implemented | Per type covered/applicable, recorded vs derived (each item once), explicit *No applicable items*, no combined percentage |
| WP37/REV-5 review workload | Implemented | Pending (investigations named), outdated, outstanding total without double counting; links to the Work Queue *Needs review* (user level) |
| WP37/REV-6 review decisions | Implemented | Existing states per type; derived coverage and outdated listed separately; no new states |
| WP37/REV-7 remediation | Implemented | Removal follow-up definitions of Reports and Evidence; recommendation, action, completed (manual) and evidence-confirmed removal kept apart |
| WP37/REV-8 review periods | Implemented | Existing lifecycle states, labelled global. No deadlines are shown: the period model has none beyond its start and end dates |
| WP37/REV-9 organizational progress | Implemented | SAP User Group, Functional Group, Manager, Department, Site; distinct totals; unassigned rows; frozen periods: SAP User Group only |
| WP37/REV-10 integrated filter panel | Implemented | Shared `FilterLayout` via `SodFilters` (new optional `storageKey`/`defaultOpen`), closed by default, Work Queue filters and Saved Filters (`sod_queue`). Department, site and review/decision/remediation status are not offered as filters: the Work Queue has no such population filter, and adding one would change its semantics |
| WP37/REV-11 consistent scope | Implemented | One endpoint, the Work Queue population; metric scope matrix in [Reviews](../features/REVIEWS.md#metric-scope-matrix-wp37) |
| WP37/REV-12 context-preserving drill-down | Implemented | Filters kept, metric constraint added (`queueProgress`, remediation `tracking`, group filters); destination counts reconcile (browser tests) |
| WP37/REV-13 review context and history | Implemented | All metrics follow the context; frozen evidence read only; unavailable dimensions stated |

Tests: backend `SodPeriodsTests.Reviews_overview_reconciles_with_the_work_queue_remediation_and_periods` (with the SoD route and saved-filter
classes 39/39); browser `reviews-overview.spec.ts` and `reviews-workspace.spec.ts`. Native acceptance: R7-RV1.

## Ninth round: RC6 implementation and consolidation (WP29 to WP34, 2026-11-25)

Source-level work after RC5 (`b10dd50`); RC5 stays the immutable packaged baseline. RC5 native results and the RC6 bug and baseline-failure
tables are in the [acceptance tracker](ACCEPTANCE_TRACKER.md#rc5-consolidated-candidate-after-wp21-to-wp28-native-acceptance-partly-run);
operator procedures in the [runbook](WINDOWS_VM_ACCEPTANCE.md#rc6-scenarios-wp29-to-wp31-wp33-run-only-on-a-candidate-whose-build-record-lists-them).

| Package | Implemented | Focused evidence |
| --- | --- | --- |
| WP33 file sources (FILE-001 to FILE-008, FILE-010) | One **File location** choice (upload or file on the host) for every CSV source, separate **Update mode**, Explorer-like host file picker through the service identity, approved browse folders with backend enforcement (no UNC contact outside approved roots; reparse points, system and private locations refused), unified validate/import (hash-bound) (`7e680a1`, `906f16e`) | .NET `ServerSourceBrowserTests`, `AccountsTests`; browser `server-source-configuration.spec.ts`; native R6-F1 to R6-F4 pending (FILE-011/012) |
| WP31 ACL status (SEC-001 to SEC-007) | SAFE / REVIEW_REQUIRED / UNSAFE with classified principals, exit codes 0/3/2, unauthorized named write on binaries is critical, scoped authorizations with reason and approver, controlled removal with preview; nothing removed automatically (`76a3412`) | Pester `Acl-NamedPrincipals`; read-only VM130 audit (UNSAFE, development source); native R6-S1 pending |
| WP29 mobile (BUG-011, BUG-012) | Shared Select leaves touch input to the native picker; one-row phone header with 44 px targets and safe-area insets | Browser `mobile-ui-wp29.spec.ts`, `mobile-acceptance.spec.ts`; iOS Safari (R6-M1) pending |
| WP30 dashboard (DASH-001 to DASH-015) | Global and filtered modes, closed-by-default Filters side panel with Apply/Reset, active count, chips and Saved Filters (`dashboard`); organization, SAP account (validity, lock status), access (role, transaction, role type, organizational suffix) and governance (SoD risk, review status) dimensions through the shared resolver (OR within, AND between); user-population and matching-access modes; metric scope matrix; drill-down with the population. Large-dataset performance not measured | .NET `DashboardAndSavedFiltersTests`; browser `dashboard-filters.spec.ts`, `filter-consistency.spec.ts` |
| Baseline browser failures | Four outdated test expectations corrected with root causes; no assertion weakened | Tracker table "Baseline browser failures investigated in RC6" |
| WP24 native acceptance | Tracker reconciled with RC5 evidence (readiness PASS, B14 approval 11/11, Lifecycle 17/17, D-007, D-008, DASH1 upgrade); RC6 scenarios added | Evidence under `C:\AuthLens\acceptance` |
| WP32 artifact organization (BUILD-001 to BUILD-010) | `C:\AuthLens\{Build,Installer,Acceptance}\<version>\<build-id>` with one build id `<UTC yyyy-MM-dd_HHmm>-<sha7>`, documented collision suffix, release directly in the Build directory, Setup names `AuthLens-<version>-Server-Setup.exe`/`-Desktop-Setup.exe`, optional `-ZipPackage`, `New-AuthLensPackage.ps1` for existing builds, safe `Expand-AuthLensPackage.ps1`; RC5 and older run directories resolved in place ([canonical build](../deployment/WINDOWS_DEPLOYMENT.md#canonical-windows-build)) | Pester `Artifact-Layout`, `Build-Workflow`, `Upgrade-Readiness`, `start-server-test`; node `branding.test.mjs`; first native build (RC6) and native extraction pending |
| WP34 storage and artifact lifecycle (INST-117 to INST-121) | Per-volume storage preflight with breakdown, deficit and guidance in Setup; staged payload no longer counted twice, in-app backups excluded, sequential backup phases counted once, data volume reserved, 256 MB margin per volume; `ArtifactInventory`/`PruneArtifacts` (installation) and `Invoke-AuthLensArtifactRetention.ps1` (build host) with preview, approval and preservation rules ([storage preflight](../deployment/WINDOWS_DEPLOYMENT.md#storage-preflight-and-installation-artifact-retention-wp34)) | Pester `Server-Setup`, `Artifact-Retention`, `Artifact-Layout`, `Deployment-DryRun`; native DASH1-like check and GUI text pending |
| QA-028 recovery tooling in Service Manager | Recovery scripts in the packaged helper inventory and the ZIP; Service Manager `CreateRecoveryBundle`/`VerifyRecoveryBundle` | Pester `Service-Manager`, `AuthLens.Installer`; native verification pending |

**Not complete in RC6.** FILE-008 is partially implemented (no pre-import "changed since validation" indication) and remains an open
2.0.0 requirement; all packages above still need native acceptance, and FULL regression has not run. Summary:
[RC6 candidate status](STATUS.md#rc6-candidate-status).

**Identifiers.** The RC6 brief numbers requirements per package (`FILE-001` to `FILE-012`, `SEC-001` to `SEC-007`, `DASH-001` to
`DASH-015`, `BUILD-001` to `BUILD-010`, `INST-117` to `INST-121`, `QA-028`). `SEC-00n` and `DASH-00n` already exist in
[validation-items.csv](validation-items.csv) with other meanings (API boundary, exports, dashboard cards); those validation items keep their
IDs. In this repository the brief's items are therefore written with their package prefix (`WP31/SEC-1`, `WP30/DASH-1`), never as new
validation-item IDs.

#### WP33 requirement reconciliation (FILE-001 to FILE-012)

| Item | Status | Evidence and limits |
| --- | --- | --- |
| FILE-001 unified configuration | Implemented | One `SourceManager` with **File location** and **Update mode** for every CSV source (Role Catalogue, User-Role Mapping, Employee Directory, SoD Matrix); shared `ServerFileSource`, `HostFilePicker`, validation and import contracts |
| FILE-002 location separate from update mode | Implemented | Upload from this device or file on the host; local and UNC paths share one field; the backend detects the path type (badge Local file on the host or Network file) |
| FILE-003 server-side browser | Implemented | `GET /api/server/sources/browse` as the service identity; approved, configured and recently used locations (recent ones are kept in the browser only), direct path entry, parent folder, refusal categories |
| FILE-003A Explorer-like picker | Implemented | Host name, locations, breadcrumbs, parent, path entry, icons, name/size/modified, sorting, search, CSV filter, Select/Cancel, loading/empty/unavailable/denied states; no file management actions. Desktop keeps the native system file dialog for local and network files |
| FILE-004 secure authorization | Implemented (source); native UNC pending | Approved roots enforced in the backend; no UNC contact outside them; reparse points, devices, ADS, volume/share roots, system and private AuthLens locations refused; bounded enumeration (2,000 entries) and network timeout; administration role required (`ServerSourceBrowserTests`, `AccountsTests`). Real UNC behaviour needs R6-F2 |
| FILE-005 unified validation and import | Implemented | Validate and import, Validate only, Import validated file; hash-bound (`validated_sha256`); validation independent of update mode; failures never replace the active dataset |
| FILE-006 static/dynamic transitions | Implemented | Mode changes keep the path and the active dataset; the notice states that saving reads nothing; uploads are explained as copies that cannot follow the original |
| FILE-007 editing and replacement | Implemented | Change path, browse again, replace an upload, switch location, change mode, revalidate, refresh; draft, saved configuration and active data are described separately |
| FILE-008 diagnostics | **Partially implemented (open 2.0.0 requirement)** | Location, type, mode, authorization, availability, last check and attempt, last import, records, snapshot, categorized errors are shown. Changed content is detected and refused at import (hash mismatch, `source_changed`), but the required **pre-import indication that the source changed since validation is not implemented**. Not deferred to a later version; it remains open for 2.0.0 |
| FILE-009 refresh consistency | Implemented (unchanged pipeline) | Global and scheduled refresh use the existing shared refresh service and authorization; static sources are skipped; last valid snapshot retained (existing refresh tests) |
| FILE-010 responsive and accessible | Implemented (source); iOS pending | Dialog, keyboard, labels, mobile layout; R6-M1 and R6-F1 on a real iPhone remain |
| FILE-011 compatibility | Implemented | Existing settings fields and authority files are read unchanged (no migration step, no reconfiguration); upgrade check in R6-F4 |
| FILE-012 acceptance | Automated part done; native pending | .NET and browser coverage above; native D2 to D12 and R6-F1 to R6-F4 (same-host and remote UNC with the service identity) are operator scenarios |

#### WP31 requirement reconciliation (WP31/SEC-1 to SEC-7)

| Item | Status | Evidence and limits |
| --- | --- | --- |
| SEC-1 status contract and exit codes | Implemented | `status` SAFE / REVIEW_REQUIRED / UNSAFE; AuditAcl exit 0 / 3 / 2; `safe` keeps its broad-only meaning for existing installer and upgrade gates |
| SEC-2 principal classification | Implemented | Expected (SYSTEM, Administrators, TrustedInstaller, CREATOR OWNER, service identity), `authorized` (scoped registry entry), `unreviewed`, `unauthorized_binary_write` |
| SEC-3 broad versus named findings, explicit and inherited | Implemented | Separate `findings` and `named_principals` per location, inheritance reported |
| SEC-4 binary write is critical | Implemented | Unauthorized named write on binaries makes the status UNSAFE |
| SEC-5 strict readiness gate | Implemented | `Test-AuthLensUpgradeReadiness.ps1` reports `acl_status`; `-StrictAcl` refuses REVIEW_REQUIRED, UNSAFE and an unverifiable audit (Pester `Upgrade-Readiness`); native run pending |
| SEC-6 Service Manager presentation | Implemented | Group 7, option 3: read-only status, classified principals and remediation commands |
| SEC-7 controlled remediation | Implemented | `AuthorizeAclPrincipal` / `RevokeAclPrincipal` with reason and approver; `ProtectAcl -RemovePrincipal` previews with `-DryRun`, needs `-Yes`, saves an ACL inventory first and rolls back with `RestoreAcl`; nothing is removed automatically; VM130 and DASH1 were only audited |

## Eighth round: release stabilization, acceptance harness and user feedback (WP21 to WP28, 2026-11-25)

Source-level work after RC4 (`37eadd5`); RC4 stays the immutable packaged baseline. Results per scenario and per user-reported item are in the
[acceptance tracker](ACCEPTANCE_TRACKER.md#rc4-native-results-on-vm130-2026-11-25).

| Package | Implemented | Focused evidence |
| --- | --- | --- |
| WP21 acceptance harness | `backend/scripts/acceptance` (QA-001 to QA-016, QA-018): reason, simulation and mutation assertions, guarded B14 groups, Lifecycle prerequisites | Pester `Acceptance-Harness` 16; native B13 26/26 and B14 elevation 5/5 (non-elevated) |
| WP22 recovery tooling | `backend/scripts/recovery` bundle and isolated restore rehearsal; `--fingerprint-data`; readiness diagnostics (QA-017, QA-019 to QA-032 except QA-028, deferred) | Pester `Recovery-Tooling` 3, `Upgrade-Readiness` 45; .NET `MaintenanceCommandsTests`; native restore rehearsal PASS |
| WP23 investigations | D-007 confirmed and corrected (update provisions the source authority); D-008 audit gap corrected (named-account findings), VM130 ACE environmental | Pester `AuthLens.Deploy` 48, `Acl-NamedPrincipals`; native read-only Status/AuditAcl with the source tools |
| WP24 native acceptance | A1, B1, B13, B14 (elevation), readiness, restore rehearsal, C12 (executable) passed; mutating scenarios need operator authorization; D-scenarios blocked (sign-in, D-007, remote SMB) | Acceptance tracker |
| WP26 review workflows | BUG-01 toggle, BUG-02 Release role review, BUG-03 group navigation, BUG-07 profile progress | `user-feedback-2026-11.spec.ts`, `sod-evidence-modals.spec.ts`, `release-roles.spec.ts` |
| WP27 sessions and preferences | BUG-04 inactivity warning, passive reads, explicit continue; BUG-05 verified with account-switching coverage | .NET `AccountsTests` 57; `session-timeout.spec.ts`, `personal-preferences.spec.ts`; unit `session-timing` |
| WP28 filters and layout | BUG-06 content-sized group cells, BUG-08 page-boundary filter reset, BUG-10 whole-word label wrapping; BUG-09 not reproduced | `user-feedback-2026-11.spec.ts`; affected navigation and filter specs |
| WP25 release assessment | RC5 built from `b10dd50` (`C:\AuthLens\AuthLens-2.0.0-2026-11-25_1442-b10dd50`, verified, unsigned); release NO-GO until native acceptance, D3, FULL and signing | Build focused tests 154 passed; agent verification in the acceptance tracker |
## Seventh round: final remediation before RC4 (2026-11-25)

| Item | Implemented | Focused evidence (VM130) |
| --- | --- | --- |
| G-004 recovery audit | `<WorkRoot>\recovery-audit.jsonl` (one line per acting recovery attempt: action, decision, outcome, operator from the process token or `null`, runs, phases, version, commit, manifest and configuration hashes, certificate replaced, redacted reason); recovery history entries carry action, run and operator; original entries kept; simulations and "nothing to recover" write nothing | `Recovery-AuditRegistration` (G-004 3 tests), `Deployment-DryRun` (no audit file) |
| G-005 Setup registration | After installer recovery: Setup's verified-success values written only with proven ownership (pending state, Inno uninstall entry, staged payload equals the recovered release); explicit outcome states; nothing invented | `Recovery-AuditRegistration` (G-005 3 tests on disposable HKCU keys; the machine registration is never touched) |
| G-006 | **Deferred** to a later release; fail-safe refusal kept | — |
| T-001 | Older-build journal fixture: consistent correction completes, five inconsistent states refused | `Recovery-AuditRegistration` (2 tests) |
| WP19 restart | `Deploy-AuthLens.ps1 -Action RestartService` (simulated, approval-gated, refused during pending recovery, verifies listener, readiness and identity) and Service Manager group 1 | `Recovery-AuditRegistration` (3), `Service-Manager.Workflow` (2), `Deployment-DryRun` (policy, entry point) |
| WP20 installer export | Server installer finish-page option runs the installed Service Manager `-Action ExportCertificate -Interactive` (destination prompt, no overwrite, public `.cer`, thumbprint and trust guidance) | Inno compile in the installer set; `Service-Manager.Workflow` destination tests |
| Validation | Affected Pester 84 and 77 (after a strict-mode fix in the audit writer), installer and deployment set 227 passed (2 failures fixed and rerun), 1 skipped; Python repository unit tests, workflow, structure and secret checks passed in the isolated venv; ruff not installed there (no Python changed); FULL not run | — |

## Sixth round: unified CSV import and server-side data sources (2026-11-25)

Review of the existing implementation against the brief (all file-based sources, upload, local and UNC paths, Static and Dynamic, validation,
security, integrity, Global Refresh, status, backup/restore/migration). Most of it was already implemented in earlier rounds and is
verified by the focused tests listed in the [data-source coverage matrix](../data/IMPORT_AND_REFRESH.md#data-source-coverage-matrix).

| Item | Result |
| --- | --- |
| Implemented | Validation outcomes distinguish a folder (`not_a_file`), an invalid or unsupported path (`invalid_path`), authorization required (`policy_prohibited`) and an empty dataset (`empty`, also in refresh results) instead of `access_denied`, a policy message or a generic `validation`; a UNC path is never touched before authorization. **Validate and import** in the server file panel validates as the service and imports exactly the validated content in one step; Test and Activate remain |
| Verified existing | Shared policy and pipeline for all four sources, browser upload (Static), exact authorization and revocation, hash-bound activation, Static/Dynamic refresh semantics, last valid dataset kept, held suspicious imports, restart persistence, restore and legacy migration of snapshots, refresh reports |
| Remaining gaps | Native Windows Service local/UNC reads (D2, D3, D6, D7, D12), restored-source reauthorization end to end (E3), persisted authorization audit trail (P2), source type shown in the compact source summary (the panel shows it in the source-type selector) |
| Focused tests | .NET 84 passed (data sources, source policy, refresh, refresh reports, import preview, reimport, employee directory, SoD metadata, application backup, legacy restore); TypeScript check, ESLint (changed files) and `server-source-configuration.spec.ts` (bundled Chromium) passed; Python repository unit tests not run (PyYAML missing outside the isolated venv; no workflow changed) |

## Changes in the 2026-11-24 second round

### Reviews information architecture (package 18, commit `146c463`)

- Reviews is independent of the SoD feature switch; only SoD access-review pages follow it. With SoD off, Reviews offers the Overview with a
  turned-off notice and the Account reviews card; bookmarked SoD review pages show the notice instead of data. Backend gating is unchanged.
- Account Review stays a separate governance concept in User Access and is discoverable from the Reviews Overview (own counters, **Open Account
  Review** on the unchanged route). Decisions and counters are never merged.
- Contextual entry points verified or added: Dashboard (existing), Role Lookup via role details (existing), SoD Overview (**Open Work Queue**, new),
  Access Explorer (**Open Work Queue**, new; Bulk Review existing), SoD conflict analysis panel (**Open in Work Queue**, new). Page-only filters that
  the Work Queue does not apply are named next to the button. Exclusions documented in [Reviews](../features/REVIEWS.md#context-preservation).
- SoD Overview row-height defect fixed: "Role assignments marked for removal" wrapped to two lines at 1280 px (47 px against 34 px for every other
  row) in both Edge and the bundled Chromium; the visible label is now "Assignments marked for removal" with the full meaning as its title. The
  frozen report wording is unchanged.

### Windows implementation (packages 4 to 8, commit `815420c` and the following commit)

- **Recovery-key provisioning:** confirmed defect: a key created with Service Manager after installation was readable only by the administrator,
  SYSTEM and Administrators, so the running service reported it `inaccessible` until a later deployment. `CreateKey` now resolves the installed
  service's logon identity and adds one explicit read rule on the key file only; `GrantKeyAccess` repairs existing installations; `Status` reports
  access. DACL-only reads/writes: `Get-Acl`/`Set-Acl` required SeSecurityPrivilege and failed even for an elevated token (found by Pester).
- **Installed certificate replacement:** `Deploy-AuthLens.ps1 -Action ReplaceCertificate` (see
  [Windows deployment](../deployment/WINDOWS_DEPLOYMENT.md#installed-certificate-replacement)). A `[IO.File]::Replace` call with `$null` as backup
  path (PowerShell passes an empty string) was found and fixed by Pester before commit.
- **Setup review and progress:** consolidated Ready page and Installing-page progress text. The ISCC probe found a forward reference
  (`ServerFreshInstall` used before declaration), fixed before commit.
- **Status diagnostics:** `backup_key_service_access`, `certificate_replacement_pending`.
- **Test isolation:** `AuthLens.Deploy.Tests.ps1` created the protected authority folder in TestDrive; on a non-elevated Windows host Pester could not
  clean it up and 17 later tests failed (reproduced on the untouched module). The unrelated test now mocks the provisioning.

### Functional coverage audit (packages 10 to 16)

| Requirement | Finding |
| --- | --- |
| Functional Group filtering | Shared `functional_group`/`functional_groups` dimension on every SoD and Reviews page with a username field; Dashboard, User Access, Account Review, Release Roles and Employee Directory as listed in the [coverage matrix](../features/FILTERS.md#organizational-and-exact-username-filter-coverage). No gap found. |
| Manager and Exact Usernames on SoD and Reviews | Same shared dimensions (`managers`, `usernames`) through `subjectFilterFields`; carried by every Reviews entry point. No gap found. |
| Saved filters | `V1SavedFilters` allows `functional_groups`, `managers`, `usernames` for `sod_overview`, `sod_risk_matrix`, `sod_activity_matrix`, `sod_explorer`, `sod_queue` (Work Queue, Bulk Review, Remediation) and the User Access/Release/Account Review views. No gap found. |
| Review counters and filtered exports | Reviews Overview counters use the Work Queue endpoint and filters; Remediation and Explorer exports use `scopeParams` with the same filters (server-side `SodScope`). Account Review counters are separate and unfiltered by design. |
| Permission-aware navigation | Reviews visible to every signed-in account (all roles hold `read`); Bulk Review card only with `review`; Open Features only with `admin`. |
| Server-source configuration per source type | Covered by the [source compatibility matrix](../data/IMPORT_AND_REFRESH.md#data-source-compatibility-matrix) (earlier round). |
| Static/Dynamic, Global Refresh, revocation, last valid snapshots | Implemented and focused-tested in the earlier round (`DataSourcesTests`, `ServerSourcePolicyTests`). |
| Backup and restore compatibility | Source authority excluded from backups and re-authorized on restore; restore re-grants service key read. |

No further independently testable functional defect was found in this audit.

## Focused validation (this round, this host)

| Command | Result |
| --- | --- |
| `npm run check:types`; `npx eslint` on changed files; `npm run build` | Passed |
| `npm run test:browser -- tests/reviews-workspace.spec.ts tests/sod-feature.spec.ts` (Edge) | 7 passed |
| Affected specs (Edge): `navigation-r3`, `responsive-navigation`, `secondary-navigation-icons`, `sod-overview-actionable`, `filter-consistency`, `sod-stability`, `mobile-acceptance`, `sod-evidence-modals`, `decision-controls` | 75 passed, 1 failed (row height, pre-existing; root cause found and fixed) |
| Bundled Playwright Chromium (no override): `sod-overview-actionable`, `kpi-semantic-tones`, `reviews-workspace` after the fix | 13 passed |
| Pester (Windows PowerShell 5.1): `AuthLens.Deploy`, `Deployment-Recovery`, `Server-Tls`, `Server-Setup`, `Server-CertificateReplacement`, `Service-Manager`, `Installer-FailureRecovery`, `InnoIsolation`, `Server-SourceAuthority` | 138 passed, 0 failed |
| Pester `Server-Diagnostics` (+ `AuthLens.Deploy`, `Server-CertificateReplacement` rerun after the status change) | 2 passed (56 rerun passed) |
| ISCC compile probe of `AuthLens-Server-Code.iss` + `AuthLens-Transaction.iss` (no payload, never run) | Compiled after fixing the forward reference |
| `backend/scripts/check-powershell.ps1` | 53 scripts, 0 errors |
| `python -m unittest discover -s scripts/tests -p "test_*.py"` (isolated venv with PyYAML) | 7 passed (the earlier 6 errors were only the missing PyYAML) |
| `check-docs.py`, `check-secrets.py`, `check-structure.py`, `check-workflows.py`, `git diff --check` | Passed |
| `node --test` over `scripts/tests/*.test.mjs` (explicit file list; PowerShell does not expand the glob) | 12 passed |

Not run: whole .NET suite and whole browser suite (FULL, not authorized); release and installer builds (not authorized); any elevated,
SCM, SMB or firewall operation; Linux host. No .NET code changed this round, so the earlier focused .NET results stand.

## Remaining native Windows acceptance (isolated machine)

The executable, ordered procedure is the [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md); the list below is its summary.

Prerequisites: a disposable Windows Server VM/snapshot without DASH1, local administrator rights, an installed AuthLens service from an
authorized release/installer build, a same-server and a remote SMB share with NTFS/share permissions for the service identity, a domain for
gMSA/domain-account cases, and a lab certificate (and a second one without the configured SAN) for 8.13.

1. Authorized release and installer build on the build host; Pester focused set and `Get-ALTestFilter focused`.
2. Inno wizard: Local, Corporate, Reverse Proxy; Ready-page review and progress (8.14); readiness and host headers.
3. Fresh install, failed-install retry, upgrade, repair, interrupted deployment and cleanup (packages 2, 3).
4. Recovery key: 8.9 (CLI key, `inaccessible`), 8.10 (`GrantKeyAccess`, `usable`, preserved across upgrade/repair).
5. Sources under the service: 8.1 to 8.8 (local, same-server and remote UNC, denied/unavailable, revocation, restart, reboot, restore).
6. Encrypted backup and cross-instance restore.
7. Certificate replacement (8.13), Service Manager maintenance, firewall/GPO, DNS and TLS identity.
8. Administrator and Reviewer smoke, Reviews with SoD on and off, filtering and evidence integrity (8.11, 8.12).
9. FULL regression only with explicit authorization before a merge to `main`.

## Open items

| Class | Item |
| --- | --- |
| P0 release blockers (acceptance) | Native UNC/NTFS reads as the service identity; recovery-key service read under SCM; fresh install/upgrade/repair acceptance; encrypted cross-instance restore; certificate replacement under SCM |
| Deferred by product decision | Dedicated domain account / gMSA provisioning (2.0.0 supports `NT SERVICE\AuthLens`; existing compatible identities preserved); historical organizational snapshot enrichment (provisionally 2.1.0) |
| External blockers | SMB infrastructure, a domain and a second Windows VM are not available on VM130; native acceptance runs on the operator's VM ([runbook](WINDOWS_VM_ACCEPTANCE.md)) |
| G-001 (P1) | Post-installation network configuration through Service Manager: implemented (Service Manager options 8/9, `-Action ChangeNetwork`), Pester-tested; native acceptance pending ([acceptance tracker](ACCEPTANCE_TRACKER.md#defects-and-gaps)) |
| D-006 (P0), WP19, WP20 (next candidate) | Implemented in the sources after RC3 with focused tests; native acceptance pending (B11 to B13, C11 to C13); not in any built candidate. Deferred: G-004, G-005, G-006, T-001 fixture |
| D-001 (P0), D-002 (P1) | Installed `Deploy-AuthLens.ps1` refused Setup configurations; Service Manager ignored custom data directories. Both corrected in implementation with Pester evidence on a Setup-shaped configuration and the installed tool layout; native acceptance pending |
| P1 issues | Reviewer smoke on a server; restored-source reauthorization end to end; Linux host run of source tests |
| P2 improvements | Persist an audit trail of source authorization beyond service logs; browser coverage of every filter screen; optional Windows DACL check of the key file inside the server's own key status (today the deployment ACL audit and `backup_key_service_access` cover it) |
| Product-owner decisions | None open for 2.0.0 (snapshot enrichment deferred, virtual-account scope, global Overview counters: decided in the third round) |
| Unverified native behavior | SCM lifecycle, firewall/GPO, DNS/TLS trust, reboot recovery, WebView2 Desktop |
