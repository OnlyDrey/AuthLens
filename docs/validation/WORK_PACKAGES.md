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
| 4 | Installer UX and progress | Implemented this round: consolidated Ready-page review (fresh vs upgrade), Installing-page progress text | ISCC probe compile of the production Pascal code; `InnoIsolation` | Native wizard run (8.14) |
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
| 18 | Dedicated Reviews workspace | Implemented; this round SoD independence, Account Review entry, complete contextual entry points | `reviews-workspace.spec.ts` (5 tests) and affected specs | Administrator/Reviewer smoke (8.11) |

**Remaining implementation (cross-platform and Windows-independent): none identified.** Every package above has its implementation in the
repository; what remains is native acceptance, the external blockers and the product-owner decisions below.

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
| External blockers | Dedicated domain account / gMSA provisioning: no secure credential transport and no logon-right/managed-password validation contract (Setup keeps the virtual account; existing identities are preserved); SMB infrastructure and an isolated Windows Server are not available on this workstation |
| P1 issues | Reviewer smoke on a server; restored-source reauthorization end to end; Linux host run of source tests |
| P2 improvements | Persist an audit trail of source authorization beyond service logs; browser coverage of every filter screen; optional Windows DACL check of the key file inside the server's own key status (today the deployment ACL audit and `backup_key_service_access` cover it) |
| Product-owner decisions | Historical organizational snapshot enrichment (evidence contract; [recommendation only](../features/REVIEWS.md#historical-organizational-evidence-recommendation-not-implemented)); gMSA/domain-account support scope; whether Account Review counters on the Reviews Overview should follow Account Review filters |
| Unverified native behavior | SCM lifecycle, firewall/GPO, DNS/TLS trust, reboot recovery, WebView2 Desktop |
