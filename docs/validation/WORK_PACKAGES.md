# AuthLens 2.0.0 remediation: work-package tracker

**Release status: NOT APPROVED.** This tracker lets the next agent resume without reconstructing earlier sessions. It records implemented
work and actual test evidence; native Windows acceptance is listed separately and is never implied by focused tests.

Status vocabulary: **Remaining implementation** · **Implemented and verified** (focused automated tests on this host passed) · **Awaiting native
acceptance** (implemented; needs an installed service, SCM, SMB, elevation or an isolated machine) · **External blocker** · **Product-owner decision**.

Environment of the 2026-11-24 Claude rounds: Windows 11 Pro developer workstation (not a server; no AuthLens service installed, no SMB shares, not
elevated), .NET SDK 10.0.404, Node 24, Windows PowerShell 5.1 with Pester 5.9.1 (no PowerShell 7), Inno Setup 6 (compile probes only), Microsoft
Edge and the repository-pinned Playwright Chromium (installed this round into the user cache with `npx playwright install chromium`). Python
checks run in an isolated virtual environment outside the repository with `scripts/requirements-checks.txt` (PyYAML 6.0.3). Earlier rounds:
Codex (installer, deployment, filters, accounts, checkpoint `dcbb38a`), Claude `68ee12b`, `e457ab6`.

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
| 7 | Service Manager | Implemented; this round `GrantKeyAccess`, service-identity resolution, key-access status | `Service-Manager` (6 tests, real DACL on synthetic files) | Run elevated against an installed service |
| 8 | Recovery keys and service permissions | Implemented: key states (`68ee12b`); least-privilege provisioning (this round) | `BackupCryptoTests` (earlier round), `Service-Manager`, `Server-Diagnostics` | Service-identity read under SCM (8.9, 8.10) |
| 9 | Backup and restore | Implemented; restore copies and selects the key and re-grants service read (`Grant-ALAccess`); source authority excluded from backups by design | Earlier round `ApplicationBackupTests` | Encrypted backup and cross-instance restore (8.8) |
| 10 | All server-side sources | Implemented | Earlier round: `ServerSourcePolicyTests`, `DataSourcesTests`, `server-source-configuration.spec.ts` | Service-identity reads (8.2) |
| 11 | Local and UNC paths | Implemented (lexical + DNS policy, exact authority, revocation) | Earlier round (focused .NET) | **Blocker until run**: real SMB as the service (8.3, 8.5) |
| 12 | Static/Dynamic and Global Refresh | Implemented | Earlier round (focused .NET) | Under SCM, restart, reboot (8.4, 8.7) |
| 13 | Personal themes | Implemented (Codex `0817d57`) | Earlier round `personal-preferences.spec.ts` | Cross-browser on a server |
| 14 | Permission-aware UI | Implemented; Reviews now follows effective permissions and feature availability independently | `reviews-workspace.spec.ts` | Administrator/Reviewer smoke (8.11) |
| 15 | Functional Groups across screens | Implemented (Codex `2a78dfc`); coverage audit below | `filter-consistency.spec.ts` | 8.12 |
| 16 | SoD Manager and Exact Usernames | Implemented (Codex `2a78dfc`) | `filter-consistency.spec.ts` | 8.12 |
| 17 | Regression and acceptance preparation | Focused validation below; acceptance procedure in [Windows checklist §8](../deployment/WINDOWS_DEPLOYMENT.md#8-server-sources-recovery-key-service-access-and-reviews-200-remediation) (8.1 to 8.14) | FULL not run (not authorized) | Entire §8 |
| 18 | Dedicated Reviews workspace | Implemented; SoD independence, Account Review entry, complete contextual entry points, global Overview counters (`c780ff6`) | `reviews-workspace.spec.ts` (5 tests) and affected specs | Administrator/Reviewer smoke (8.11) |

**Remaining implementation (cross-platform and Windows-independent): none identified.** Every package above has its implementation in the
repository; what remains is native acceptance, the external blockers and the product-owner decisions below.

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
| Post-installation network configuration | `Deploy-AuthLens.ps1 -Action InstallService -Reconfigure` after a reviewed configuration edit, then restart and Health; Service Manager does not offer it and there is **no automatic rollback** | Supported manual procedure (limitation, not deferred silently); native check C9 |
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

**AuthLens 2.0.0 release candidate, NOT APPROVED** (native acceptance and FULL regression outstanding). Built on the development workstation with
the canonical `build.ps1` (authorized release-candidate and installer build); nothing was installed, signed, tagged, uploaded or merged.

| Item | Value |
| --- | --- |
| Source commit | `c780ff6d3f525d8589e3b64f29ffe99cdf4fa9fa` on `experiment/dotnet-backend` (clean; manifest `source_dirty: false`) |
| Build directory | `<build root>\AuthLens-2.0.0-2026-11-24_1815-c780ff6` on the development workstation (outside the repository; binaries are not committed) |
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
| External blockers | SMB infrastructure, a domain and an isolated Windows Server VM are not available on the development workstation; native acceptance runs on the operator's VM ([runbook](WINDOWS_VM_ACCEPTANCE.md)) |
| Known limitation | Post-installation network reconfiguration is a manual reviewed procedure (`InstallService -Reconfigure`, restart, Health) without automatic rollback (runbook C9) |
| P1 issues | Reviewer smoke on a server; restored-source reauthorization end to end; Linux host run of source tests |
| P2 improvements | Persist an audit trail of source authorization beyond service logs; browser coverage of every filter screen; optional Windows DACL check of the key file inside the server's own key status (today the deployment ACL audit and `backup_key_service_access` cover it) |
| Product-owner decisions | None open for 2.0.0 (snapshot enrichment deferred, virtual-account scope, global Overview counters: decided in the third round) |
| Unverified native behavior | SCM lifecycle, firewall/GPO, DNS/TLS trust, reboot recovery, WebView2 Desktop |
