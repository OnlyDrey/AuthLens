# AuthLens 2.0.0 remediation: work-package tracker

**Release status: NOT APPROVED.** This tracker lets the next agent resume without reconstructing earlier sessions. It records implemented
work and actual test evidence; native Windows acceptance is listed separately and is never implied by focused tests.

Status vocabulary: Not started · In progress · Implemented · Statically validated · Focused unit tests passed · Browser tests passed ·
Native Windows validation pending · Blocked.

Environment of the 2026-11-24 Claude round: Windows 11 developer workstation (not a server, no SCM install, no SMB shares), .NET SDK 10.0.404,
Node 24.22.3, Windows PowerShell 5.1 (no PowerShell 7/Pester run), Playwright with `PLAYWRIGHT_EXECUTABLE_PATH` set to installed Microsoft
Edge (Chromium) because the bundled Chromium was not installed. Earlier rounds: Codex (installer, deployment, filters, accounts, checkpoint `dcbb38a`).

## Summary

| # | Package | Status | Windows acceptance |
| --- | --- | --- | --- |
| 1 | Installer network configuration and readiness | Implemented (Codex `e1299db`, `3b146d6`, `dcbb38a`); not changed this round | Pending: Inno compile, Local/Corporate/Reverse Proxy, readiness |
| 2 | Installation state and controlled cleanup | Implemented (Codex `f6a3765`) | Pending: failed fresh install, quarantine |
| 3 | Transactions, recovery and retry | Implemented (Codex `a4569ae`) | Pending: interrupted deployment, retry |
| 4 | Installer UX and progress | In progress (access-mode pages in `AuthLens-Server-Code.iss`, `dcbb38a`) | Pending: native wizard run |
| 5 | Diagnostics and error handling | Implemented (Codex); source/key diagnostics extended this round | Pending |
| 6 | Firewall, DNS and TLS | Implemented (Codex); Domain profile default in wizard | Pending: firewall/GPO, DNS, TLS identity |
| 7 | Service Manager | Implemented (Codex) | Pending: post-install network/certificate config |
| 8 | Recovery keys and service permissions | Status states implemented and focused-tested this round; provisioning not changed | Pending: service-identity ACL provisioning (8.9, 8.10) |
| 9 | Backup and restore | Existing implementation retained; source authority excluded from backups by design | Pending: encrypted backup, cross-instance restore |
| 10 | All server-side sources | Implemented; focused unit tests passed; browser UI test passed | Pending: service-identity reads |
| 11 | Local and UNC paths | Implemented (lexical + DNS policy, exact authority, revocation) | **Pending, blocker**: real SMB as service |
| 12 | Static/Dynamic and Global Refresh | Implemented; focused unit tests passed | Pending under SCM, restart, reboot |
| 13 | Personal themes | Implemented (Codex `0817d57`); `personal-preferences.spec.ts` rerun this round | Pending: cross-browser on server |
| 14 | Permission-aware UI | Implemented for existing areas (Codex); Reviews uses effective permissions | Pending: Reviewer smoke |
| 15 | Functional Groups across screens | Implemented (Codex `2a78dfc`); coverage matrix documented | Pending |
| 16 | SoD Manager and Exact Usernames | Implemented (Codex `2a78dfc`) | Pending |
| 17 | Regression and acceptance preparation | In progress: focused runs below; FULL not run (not authorized) | Procedure in [Windows checklist §8](../deployment/WINDOWS_DEPLOYMENT.md#8-server-sources-recovery-key-service-access-and-reviews-200-remediation) |
| 18 | Dedicated Reviews workspace | Implemented; browser tests passed | Pending: Administrator/Reviewer smoke |

## Package details (changed this round)

### 10–12. Server sources, local/UNC paths, Static/Dynamic refresh

- **Confirmed findings:** the inherited checkpoint compiled and its 27 focused tests passed unchanged on Windows. Gaps: no revocation, no
  authorization status (a restored path needing reauthorization was indistinguishable), UNC lexical rules only checked at read time, and the
  Data Sources panel always opened on Browser upload even for a configured server path.
- **Changes:** `ServerSourceAuthorization` (`Approved`, `Revoke`, `CheckNetworkSyntax` at authorization time, shared `Write`),
  `ServerSourcePolicy` (`InApprovedRoot`, `Authorization` status without touching the source), `V1ServerSources` (`authorization` in the
  descriptor, `DELETE …/authorize`), `ServerFileSource.tsx` (status line, Revoke authorization), `SourceManager.tsx` (initial source type).
- **Inherited test defect fixed:** `server-source-configuration.spec.ts` mocked validation with a settings revision captured before its own
  configuration POST, so activation stayed disabled; the mock now echoes the request revision.
- **Evidence:** `dotnet test … --filter "FullyQualifiedName~ServerSourcePolicyTests|FullyQualifiedName~DataSourcesTests"` 28 passed, 0 failed;
  `server-source-configuration.spec.ts` passed.
- **Remaining:** native SMB/NTFS reads as the service identity, restore-to-fresh-host reauthorization end to end, Linux host run.
- **Compatibility matrix:** [imports and refresh](../data/IMPORT_AND_REFRESH.md#data-source-compatibility-matrix).

### 8. Recovery-key status

- **Confirmed finding:** `BackupKeys.Status` mapped every read error to `configured: false`, so an inaccessible ACL-protected key was shown as
  "Not configured".
- **Changes:** `BackupKeys.Status` returns `state` (`not_configured`, `usable`, `inaccessible`, `missing`, `invalid`, `unsafe_permissions`,
  `location_unreadable`), `usable`, `escrow_pending`, `action`; `configured` now means a location is configured. Backup gates still use
  `escrow_verified` (false unless usable and verified). UI labels in `BackupEncryption.tsx`/`BackupRestore.tsx`. No key material or path in output.
- **Evidence:** `BackupCryptoTests|ApplicationBackupTests|AccountsTests` 80 passed (includes a native Windows ACL deny for `inaccessible`).
- **Remaining (Windows):** resolve the actual service identity and grant read only on the key file during provisioning; verify under SCM
  (checklist 8.9–8.10). Not implemented this round: changing provisioning without native verification was judged unsafe.

### 18. Reviews workspace

- **Changes:** `ReviewsWorkspace.tsx` (overview, routing to existing pages), `useViewHistory` (`reviews` page, `reviewsView`, legacy
  normalization), `navigationItems` (`REVIEWS_VIEWS`; SoD keeps analysis pages), `App.tsx` (main navigation group), `SodReviews` (`tab` prop),
  `SodWorkspace` (analysis only), contextual `OpenInReviewsButton` / `useOpenReviews` in User Access, Account Review, Employee Directory and
  Role details. Overview shows a Filtered note when Work Queue filters apply.
- **Decisions:** see [Reviews](../features/REVIEWS.md#information-architecture). Snapshot enrichment is a recommendation only
  ([design](../features/REVIEWS.md#historical-organizational-evidence-recommendation-not-implemented)); the evidence contract is unchanged.
- **Evidence:** `reviews-workspace.spec.ts` (3 tests) passed; updated specs listed below.

### 17. Focused validation run this round (Windows host, Edge)

| Command | Result |
| --- | --- |
| `dotnet build AuthLens.slnx -c Release` | Succeeded, 0 warnings, 0 errors |
| `dotnet test tests/AuthLens.Tests -c Release --no-build --filter "FullyQualifiedName~ServerSourcePolicyTests\|FullyQualifiedName~DataSourcesTests\|FullyQualifiedName~BackupCryptoTests"` | 43 passed, 0 failed |
| `dotnet test … --filter "…BackupCryptoTests\|…ApplicationBackupTests\|…AccountsTests"` | 80 passed, 0 failed |
| `Invoke-Pester backend/scripts/tests/Server-SourceAuthority.Tests.ps1` (Pester 5.9.1, Windows PowerShell 5.1, not elevated) | 3 passed (includes the .NET/PowerShell folder-name cross-check) |
| `npm run check:types`; `npx eslint` on changed files; `npm run build` | Passed; only pre-existing warnings |
| `python scripts/check-docs.py`, `check-secrets.py`, `check-structure.py`, `git diff --check` | Passed (46 Markdown files, 0 findings) |
| Browser, sources/navigation: `server-source-configuration`, `reviews-workspace`, `sod-reviews-r6`, `sod-periods`, `navigation-r3`, `responsive-navigation`, `secondary-navigation-icons` | All passed after fixes (34 + 13 + 7 runs) |
| Browser, review areas: `decision-controls`, `filter-consistency`, `multiselect-dropdown`, `remediation-export`, `sod-complete-bulk`, `sod-evidence-modals`, `sod-exact-groups`, `sod-governance`, `sod-review-coverage`, `sod-stability`, `sod-user-group-column`, `sod-work-queue-visual`, `sod-reviews-r6`, `mobile-acceptance`, `personal-preferences` | 92 passed, 5 failed; the 5 were fixed (3 spec updates for the move, 2 a real regression: Reviews lacked the `sod-workspace` layout scope, so the queue overflowed at 1280 px) and rerun: 36 passed, 1 failed (pre-existing, below) |

Pre-existing failures, reproduced on untouched `dcbb38a`:

- `navigation-r3` mobile-drawer tests: the drawer keeps inactive module groups collapsed (documented); the specs now expand the group first. Fixed.
- `sod-overview-actionable` "rows share one height": two distinct row heights on SoD Overview with Edge Chromium. Not changed (SoD Overview
  untouched); recheck with the bundled Playwright Chromium before treating it as a product defect.

Infrastructure: bundled Playwright Chromium missing (Edge override used); `python -m unittest discover -s scripts/tests` 6 errors from missing
PyYAML (`scripts/requirements-checks.txt` not installed). Not run: whole .NET suite and whole browser suite (FULL, not authorized), release
and installer builds (not authorized), Linux host.

## Windows implementation backlog (recommended order)

1. Build and focused tests on the Windows build host; Pester `Server-SourceAuthority.Tests.ps1` and deployment focused filter.
2. Inno Setup compilation and wizard run (packages 1, 4, 6): Local, Corporate, Reverse Proxy; readiness and host headers.
3. Fresh install, failed-install retry, upgrade, repair, interrupted deployment and cleanup (packages 2, 3) on a disposable VM.
4. Recovery-key provisioning for the resolved service identity, read-only key ACL, preserved across upgrade/repair (package 8; checklist 8.9–8.10).
5. Source acceptance under the service: local, same-server and remote UNC, custom/domain/managed accounts, denied/unavailable, restart,
   reboot, restore reauthorization (packages 10–12; checklist 8.1–8.8).
6. Encrypted backup and cross-instance restore, protected destination recovery backup (package 9).
7. Service Manager maintenance, firewall/GPO, DNS and TLS identity (packages 6, 7).
8. Administrator and Reviewer smoke, Reviews navigation, filtering and evidence integrity (packages 13–16, 18; checklist 8.11–8.12).
9. FULL regression only with explicit authorization before merge to `main`.

## Open items

| Class | Item |
| --- | --- |
| P0 release blockers | Native UNC/NTFS reads as the service identity; recovery-key service-identity provisioning; fresh install/upgrade/repair acceptance; encrypted cross-instance restore |
| P1 issues | Reviewer smoke on a server; restored-source reauthorization end to end; Linux host run of source tests |
| P2 improvements | Persist an audit trail of source authorization beyond service logs; browser coverage of every filter screen |
| Product-owner decisions | Historical organizational snapshot enrichment (evidence contract); whether Reviews should be independent of the SoD feature switch |
| Unverified native behavior | SCM lifecycle, firewall/GPO, DNS/TLS trust, reboot recovery, WebView2 Desktop |
