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
