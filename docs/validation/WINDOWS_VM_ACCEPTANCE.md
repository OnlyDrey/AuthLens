# AuthLens 2.0.0 release candidate: Windows VM acceptance runbook

**Status: procedure ready; not executed.** This is the ordered, operator-executed acceptance for a release candidate on a **disposable Windows
VM**. Nothing here has been run natively by the development agent. Results recorded here are the only acceptance evidence; static checks, Pester
with mocks, installer compilation and browser tests are not acceptance, even when they run on the VM. The candidate stays **NOT APPROVED** until
every mandatory scenario passes and the final regression ([§J](#j-final-regression-and-release-sequence)) is approved and green.

Detailed background for each step is in [Windows deployment](../deployment/WINDOWS_DEPLOYMENT.md) (§8 items 8.1 to 8.14), [backup and
recovery](../operations/BACKUP_AND_RECOVERY.md), [imports and refresh](../data/IMPORT_AND_REFRESH.md) and [Reviews](../features/REVIEWS.md).
Package status is in the [work-package tracker](WORK_PACKAGES.md).

## Rules for the operator

- Never run any step against DASH1 or another production host. Use VM snapshots; revert instead of hand-repairing.
- Run elevated PowerShell (Windows PowerShell 5.1 is supported) on the VM. Never record transcripts while activation/recovery codes or keys are shown.
- Use synthetic SAP exports only (reserved domains such as `example.org`). Never copy production role data, keys or certificates to the VM.
- Every `-ResultFile` path must be new. Keep every `operation-result.json`, `transaction-diagnostic.txt`, Setup log and journal as evidence.
- A failed mandatory scenario stops the run: record it, collect evidence, revert to the scenario's snapshot. Do not change the candidate.

## A. Prerequisites

| Item | Requirement |
| --- | --- |
| VM | Windows Server 2022 or 2025 (x64), current updates, **domain-joined** (needed for remote UNC under the virtual account), 4 vCPU, 8 GB RAM, 40 GB free on `C:` (NTFS) |
| Snapshots | `S0-clean` before anything is copied; later snapshots named in each phase |
| Network | One static private IPv4 address (example `192.0.2.10` below; substitute) and a DNS A record (example `lens.example.org`) |
| Second server | A Windows file server in the same domain with an SMB share (remote UNC); a reverse-proxy host for phase B4 (IIS ARR or another HTTPS reverse proxy you operate) |
| Clients | A domain workstation with Edge for browser steps |
| Certificates | Lab PFX `lab-server.pfx` with SANs `lens.example.org` and `192.0.2.10`, its password in a separate file; a second PFX `lab-renewed.pfx` with the same SANs; a third PFX `lab-wrong-name.pfx` **without** those SANs (negative test) |
| Software | None beyond Windows; the release is self-contained. WebView2 Runtime only for the Desktop check |
| Candidate | The build folder from the build host (see the current candidate in the [acceptance tracker](ACCEPTANCE_TRACKER.md#candidates)), in the canonical run directory `C:\AuthLens\<run directory>` (built there or copied with the same name); verify hashes first (A1) |
| Data | Synthetic CSV exports for every supported source (role catalogue, user–role mapping, user accounts, SoD matrix, Employee Directory); one malformed and one empty variant |
| Accounts | Two AuthLens accounts created during the run: `admin.synthetic` (Administrator) and `reviewer.synthetic` (Reviewer) |

Operator variables (set once per session):

```powershell
$built   = 'C:\AuthLens\<run directory>'                 # canonical build.ps1 run directory (contains build\ and installer\)
$release = (Get-ChildItem "$built\build" -Directory | Where-Object Name -Like 'AuthLens-2.0.0-*-win-x64').FullName
$tools   = (Get-ChildItem "$built\installer" -Directory -Filter 'installer-tools-*').FullName
$server  = Join-Path "$built\installer" 'AuthLens-Server-2.0.0-Setup.exe'
$desktop = Join-Path "$built\installer" 'AuthLens-2.0.0-Setup.exe'
$data    = 'C:\ProgramData\AuthLens\data'
$config  = 'C:\ProgramData\AuthLens\config\deploy.json'
$exe     = 'C:\ProgramData\AuthLens\releases\current\server\AuthLens.Api.exe'
$evidence = "C:\AuthLens\acceptance\$(Split-Path $built -Leaf)"; New-Item -ItemType Directory -Force $evidence | Out-Null
# After installation (Setup stages the package under <Root>\app\setup\<package>):
$package = Split-Path $release -Leaf
$staged  = "C:\ProgramData\AuthLens\app\setup\$package"
$itools  = "$staged\tools"                                   # installed, hash-verified tools (Install-AuthLens.ps1, deploy\*)
$manager = "$staged\payload\$package\Service-Manager.ps1"  # the Start-menu "AuthLens Service Manager" target
$deploy  = "$itools\deploy\Deploy-AuthLens.ps1"             # installed entry point; accepts the Setup configuration
```

The runbook targets the **replacement candidate** recorded in the [acceptance tracker](ACCEPTANCE_TRACKER.md#candidates), which corrects D-001
(installed `Deploy-AuthLens.ps1` refused Setup configurations), D-002 (Service Manager ignored custom data directories) and G-001 (no supported
network change). Do not run this runbook against the superseded first candidate.

### A1. Candidate integrity (mandatory)

A candidate built by the canonical `build.ps1` has `build-summary.json` (identity, test filter, verification flags, relative artifact hashes).
A candidate produced by calling `build-release.ps1` and `build-installers.ps1` directly (RC3-VM130) has none; its integrity rests on the release
manifest, both `verify-release.ps1` copies, `SHA256SUMS`, `installers-SHA256SUMS`, `installer-manifest.json`, `installer-tools.json` and the
recorded hashes, and `Test-AuthLensUpgradeReadiness.ps1` cannot be used for it (use the packaged `-Operation Upgrade -PreflightOnly`). Operator
batches run as one unit; a `STOP-INTEGRITY` line ends the batch before any relocation or test.

| | |
| --- | --- |
| Commands | Packaged verifier: `powershell -NoProfile -File "$tools\verify-release.ps1" -ReleasePath $release`. Then `Get-FileHash "$built\installer\*.exe" -Algorithm SHA256` and compare with `installer\installers-SHA256SUMS` and the hashes in the tracker |
| Expected | Verifier exit 0; every installer hash equals the recorded value; `build-manifest.json` `version` = `2.0.0`, `source_sha` = the recorded candidate commit, `source_dirty` = `false` |
| Evidence | `A1-verify.txt`, `A1-hashes.txt` |
| Recovery | Any mismatch: stop; obtain a fresh copy from the build host. Never run an unverified package |

## B. Installation (snapshot `S1-installed-local` after B2)

| ID | Scenario | Commands | Expected | Evidence | Recovery |
| --- | --- | --- | --- | --- | --- |
| B1 | Read-only preflight | `& "$tools\Install-AuthLens.ps1" -Mode Server -NetworkSuggestions -ResultFile "$evidence\B1-suggest.json"` | Suggests the assigned private IP and host names; nothing created under `C:\ProgramData\AuthLens` | `B1-suggest.json`, `dir C:\ProgramData` | None needed |
| B2 | Fresh install, **Local** mode, review and progress (8.14) | `& $server /LOG="$evidence\B2-setup.log"`; choose *Configure a fresh Server*, root `C:\ProgramData\AuthLens`, *Local access only*, *Generate local HTTPS*; keep firewall *Preserve* | Each wizard step that validates shows the progress page naming the check; Ready page lists storage, access mode, listener `127.0.0.1:18795`, hosts, certificate (self-signed note), firewall preserved, service `AuthLens` / `NT SERVICE\AuthLens`, post-install steps; Installing page shows the transaction text; Finish shows the backend URL and operation report | Screenshots of every page; `B2-setup.log`; `app\setup\<package>\operation-result.json` | Revert `S0-clean` |
| B3 | Service registration, identity and readiness | `Get-CimInstance Win32_Service -Filter "Name='AuthLens'" \| Select Name,StartName,StartMode,State,PathName`; `& $deploy -Action Status -ConfigFile $config` (expect `execution_context: packaged`); `& $manager -Action NetworkStatus`; `curl.exe -sk https://127.0.0.1:18795/health/ready`; `curl.exe -sk https://127.0.0.1:18795/product-version.json` (`-k` only because the generated certificate is not trusted; the thumbprint is recorded separately) | `StartName` = `NT SERVICE\AuthLens`, `Auto`, `Running`; `PathName` under `releases\current\server`; readiness HTTP 200; product identity `version` `2.0.0` and `source_sha` = candidate commit; `netstat -ano \| findstr 18795` shows only `127.0.0.1` | `B3-service.txt`, `B3-status.json`, `B3-health.json`, `B3-netstat.txt` | Revert `S0-clean` |
| B4 | **Corporate** mode (from `S0-clean`) | Repeat B2 with *Corporate network*, listening IP `192.0.2.10`, allowed hosts `lens.example.org,192.0.2.10`, *Use an existing PFX* `lab-server.pfx`, approve exposure; firewall *authorize* with sources = client subnet, profile `Domain` | Ready page lists the approved firewall scope; one rule `AuthLens` scoped to `192.0.2.10:18795`, remote = client subnet, profile Domain; browser on the client opens `https://lens.example.org:18795`; `https://<other-name>:18795` is refused (Host check) | `Get-NetFirewallRule -DisplayName 'AuthLens*' \| Get-NetFirewallAddressFilter`, screenshots, B3 outputs | Revert `S0-clean` |
| B5 | **Reverse Proxy** mode (from `S0-clean`) | Repeat B2 with *Reverse proxy*, backend IP `192.0.2.10`, public host `lens.example.org`, trusted proxy = proxy host IP; configure the proxy to forward to `https://192.0.2.10:18795` with the original Host | Requests through the proxy work; direct requests with a forged `X-Forwarded-*` from a non-trusted host are not trusted; `/health/ready` through the proxy = 200 | Proxy config export, `curl.exe -v` outputs, screenshots | Revert `S0-clean` |
| B6 | Failed-install retry (from `S0-clean`) | Occupy the port first: `$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,18795);$l.Start()`; run B2; then `$l.Stop()` and run Setup again | First run refuses in preflight with a port diagnostic; no service created; retry succeeds; failed attempt evidence retained, never overwritten | Both Setup logs, `operation-result.json` of each, `Get-Service AuthLens` before/after | Revert `S0-clean` |
| B7 | Upgrade (from `S1`) | Requires a **second, newer** verified candidate (`$next`) from the build host: `& "$next\installer\AuthLens-Server-2.0.0-Setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CONFIGFILE="C:\ProgramData\AuthLens\config\deploy.json" /OPERATION=Upgrade /LOG="$evidence\B7.log"` | Verified pre-deployment backup in `backups\predeploy`; service restarts on the new release; data, accounts, key, TLS, sources preserved; identity changes to the new commit | B3 outputs, journal `deployment\deployment-journal.json`, backup listing | `& $deploy -Action Rollback -Yes` per [rollback](../deployment/WINDOWS_DEPLOYMENT.md); else revert `S1` |
| B8 | Repair (from `S1`) | `Stop-Service AuthLens`; `& "$tools\Install-AuthLens.ps1" -Mode Server -PreflightOnly -Operation Repair -Package $release -ConfigFile C:\ProgramData\AuthLens\config\deploy.json -ResultFile "$evidence\B8-plan.json"`; then the same without `-PreflightOnly` plus `-Yes` | Plan lists only missing/damaged components; repair restarts the service; database untouched | `B8-plan.json`, result JSON, B3 outputs | `& "$tools\Install-AuthLens.ps1" -Mode Server -Recover -Yes`; else revert `S1` |
| B9 | Interrupted deployment recovery (from `S1`) | During B7, end the Setup/PowerShell process after the journal reaches `stopping` (Task Manager); then `& $deploy -Action Status`; `& $deploy -Action Recover -RecoveryAction Auto -Yes` | Status `recovery_needed: true`; Recover returns to a verified release (previous or candidate) with readiness; no data loss | Journal before/after, Recover result | Revert `S1` |
| B10 | Controlled cleanup (last, from `S1`) | `& "$tools\Install-AuthLens.ps1" -Mode Server -Operation UninstallPlan -ConfigFile … -ResultFile "$evidence\B10-plan.json"`; then `-Operation Uninstall -Yes` | Verified encrypted backup first; only the owned service and installer-owned firewall rules removed; data, config, TLS, keys, releases and evidence remain | Plan and result JSON, `dir C:\ProgramData\AuthLens -Recurse -Depth 1` | Revert `S1` |

## C. Security and administration (from `S1`; snapshot `S2-admin` after C4)

| ID | Scenario | Commands | Expected | Evidence | Recovery |
| --- | --- | --- | --- | --- | --- |
| C1 | Administrator activation | `& $manager -Action ActivationCode -DataDirectory $data -Executable $exe -Yes`; sign in at the URL and create `admin.synthetic` | One-use code works once; second use refused | Screenshot (no code visible) | Revert `S1` |
| C2 | Reviewer account | In Settings → Accounts create `reviewer.synthetic` (Reviewer) | Reviewer can sign in | Screenshot | — |
| C3 | Recovery key not readable by the service (8.9) | `New-Item -ItemType Directory C:\ProgramData\AuthLens\keys\host -Force`; `& $exe --backup-key create C:\ProgramData\AuthLens\keys\host\host.key --data-dir $data` (CLI, grants nothing); `& $manager -Action Status -DataDirectory $data -Executable $exe`; `& $deploy -Action Status …` | Settings → Backup shows **Configured but inaccessible** (`state: inaccessible`), not "Not configured"; Service Manager prints `Service key access: not readable`; Status `backup_key_service_access: not_readable`; no key bytes or key path in API/logs | `C3-status.txt`, `/api/backups` key status JSON, `icacls` of the key | Revert `S1` |
| C4 | Repair inaccessible key, permissions and traversal (8.10) | `& $manager -Action GrantKeyAccess -DataDirectory $data -Executable $exe -Yes`; `icacls C:\ProgramData\AuthLens\keys\host\host.key`; `icacls C:\ProgramData\AuthLens\keys\host`; `Restart-Service AuthLens` | One explicit `NT SERVICE\AuthLens:(R)` on the file only, nothing new on folders; key `state: usable`; Status `backup_key_service_access: readable` (traversal works through the default *Bypass traverse checking* right) | `icacls` outputs before/after, key status JSON | Revert `S1` |
| C5 | Fresh key through Service Manager | From `S1` (no key): `& $manager -Action CreateKey -DataDirectory $data -Executable $exe -Path C:\ProgramData\AuthLens\keys\host\host.key -Yes` | Output `Service key access: granted (S-1-5-80-…)`; key usable without a further step | Output, `icacls` | Revert `S1` |
| C6 | Recovery-copy export and verification | `& $manager -Action ExportKey -DataDirectory $data -Executable $exe -Path D:\private-recovery\host-copy.key -Yes`; verify in Settings → Backup (reauthentication) or `-Action VerifyKey` | Export refuses an existing destination; after verification `escrow_verified: true`; automatic backups can be enabled only now. RC3 known defect D-005: `-Path` (and the menu prompt) must be a complete file name; a directory ends Service Manager with access denied. Record it if observed; do not count it as a pass | Key status JSON before/after | — |
| C7 | Administrator recovery | `& $manager -Action RecoveryCode -DataDirectory $data -Executable $exe -Username admin.synthetic -Yes` | Existing sessions of that administrator end; code resets the password once | Screenshot, audit entry | — |
| C8 | Certificate replacement and rollback (8.13; Corporate install from B4) | `& $deploy -Action ReplaceCertificate -ConfigFile $config -CertificateFile D:\lab\lab-wrong-name.pfx -CertificatePasswordFile D:\lab\wrong-password -DryRun` (refused); same with `lab-renewed.pfx` `-DryRun` then `-Yes`; forced failure: block the port with a listener after `Stop-Service` is observed, or replace with a certificate whose password file the service cannot read, and confirm restoration | Wrong name refused before any change; dry run changes nothing; replacement restarts on the new certificate (browser shows the new thumbprint), new files under `tls\renew-<id>` with service read; failure restores the previous certificate and command line; `certificate_replacement_pending: false` afterwards | Result JSON, thumbprints, `icacls` of the renew folder, `config\deploy.json` before/after | `& $deploy -Action Recover -ConfigFile $config -Yes` restores a pending record; else revert |
| C9 | Post-install network change (8.15; Corporate install from B4) | `& $manager -Action ChangeNetwork -AllowedHosts 'lens.example.org,192.0.2.10,lens2.example.org'` (summary only), then with `-Yes`; `& $manager -Action ChangeNetwork -Port 18796 -ApproveFirewall -FirewallSources <client subnet> -FirewallProfiles Domain -Yes`; negative: `-ListenAddress 192.0.2.99` (not on the VM), a host the certificate lacks; forced failure: after the summary, occupy the new port from another elevated session (`$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('192.0.2.10'),18797);$l.Start()`) and apply `-Port 18797 -RemoveFirewall -Yes` | Summary lists current and proposed values; valid changes answer on the new listener and the owned firewall rule follows; invalid proposals are refused before any change; the forced failure restores the previous configuration and command line; `& $deploy -Action Status` shows `configuration_change_pending: false` | Service Manager output, Status JSON before/after, `Get-NetFirewallRule -DisplayName 'AuthLens*' \| Get-NetFirewallPortFilter` | `& $deploy -Action Recover -ConfigFile $config -Yes` restores an interrupted change |
| C10 | Firewall, DNS, TLS and allowed hosts | From the client: `Test-NetConnection lens.example.org -Port 18795`; `curl.exe -vk https://lens.example.org:18795/health/ready`; with a non-allowed Host header: `curl.exe -vk -H "Host: evil.example.org" https://192.0.2.10:18795/health/ready`; from a non-approved subnet | DNS resolves; TLS chain/name as configured (self-signed needs explicit trust); disallowed Host refused (HTTP 421/400); non-approved subnet blocked by the firewall | Outputs, `Get-NetFirewallRule` | — |

### Acceptance harness (WP21)

Use the maintained runner `backend\scripts\acceptance\Invoke-AuthLensAcceptance.ps1` (module `AuthLens.Acceptance.psm1`, cases in
`backend\scripts\acceptance\cases`) instead of the ad-hoc `OP1`/`OP2`/`b13.ps1` scripts in the RC4 evidence folder (kept there as history; their
results stand as recorded, with the assertion limits noted in the tracker). Every case states its execution context, expected exit code,
expected refusal reason (and a forbidden one, so an unrelated refusal cannot pass), expected `simulation`/`changes_applied` fields and that the
protected state stays unchanged; a group stops at the first unexpected mutation. Results: `<evidence>\<RunName>\results.json`; exit 0 passed, 1
failed, 2 refused before running, 3 stopped on mutation.

```powershell
$runner = 'C:\Users\<operator>\Git\AuthLens\backend\scripts\acceptance\Invoke-AuthLensAcceptance.ps1'
$built  = 'C:\AuthLens\AuthLens-2.0.0-2026-11-25_0807-37eadd5'
# B13 (any context), B14 split into two guarded groups:
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Operation B13 -Candidate $built -RunName B13-<n>
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Operation B14Approval -Candidate $built -RunName B14-approval-<n>     # ELEVATED only
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Operation B14Elevation -Candidate $built -RunName B14-elevation-<n>   # NON-elevated only
# Lifecycle (B17 upgrade, C12, C14, B15 simulation check, B17 repair): elevated, state-changing, every prerequisite explicit.
powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Operation Lifecycle -Candidate $built -RunName Lifecycle-<n> -AuthorizeMutation `
  -RecoveryReport <backup-result-*.json> -ReadinessReport <readiness output with AUTHLENS-UPGRADE-READINESS> -SnapshotAttestation '<Proxmox snapshot name>' `
  -ExpectedInstalledSha <installed baseline commit> -VerifierExecutable <AuthLens.Api.exe with --fingerprint-data>
```

B14 elevation-refusal cases carry `-Yes`; the runner refuses them in an elevated session, and only cases whose inputs fail safely even if the
gate were missing are run natively. Lifecycle refuses without `-AuthorizeMutation`, an explicit passed recovery report, a readiness PASS for the
candidate younger than 24 hours that used an explicit report, verified escrow, the expected installed baseline, a terminal journal, the Setup
hash from `build-summary.json` and a snapshot attestation (recorded as `operator_attested_not_verified`). The repair is validated read-only
before the authorized stop; a refused plan starts the service again unchanged.

### RC4 priority order

Run on RC5 (`C:\AuthLens\AuthLens-2.0.0-2026-11-25_1442-b10dd50`, [build record](ACCEPTANCE_TRACKER.md#rc5-build-record); verify A1 against its hashes first; RC4 results do not transfer) in this order, using the [acceptance harness](#acceptance-harness-wp21) where it covers the scenario; stop and record a failure before continuing:

1. B13 – simulation leaves the persistent installation state unchanged (D-006).
2. B14 – approval enforcement for every mutating deployment action.
3. T-001 – recovery with the RC4 tools against an installed older release (for example RC3-VM130 or `8ec7f77`).
4. B11 – guided recovery (Service Manager group 6).
5. B12 – recovery with certificate replacement (G-007).
6. C11 to C13 – recovery-key export, certificate status and export, combined network and certificate change.
7. C14 – Service Manager restart.
8. B15 – recovery audit (G-004).
9. B16 – Setup registration reconciliation (G-005).
10. B17 – upgrade and repair preserve certificates and data.
11. D2 to D7 and D12 – CSV and server-source validation.
12. D3 – UNC and SMB access with the Windows Service identity, recorded separately for a **local server file**, a **same-host UNC** share and
    a **remote SMB** share. **D3 stays a release blocker** until it passes natively; administrator-session access and mocked tests do not count.

### Next-candidate scenarios (D-006, WP19, WP20; not applicable to RC3)

Implemented in the sources after RC3 (`c077eaf` D-006, `6fbfd48` WP20, `928b6bc` WP19); a candidate containing them needs build approval. Run
these only on a candidate whose build record lists them; on RC3 they are **Not applicable**, not failed. Never run B13's `-DryRun` commands with
RC3 tools (D-006).

| ID | Scenario | Commands | Expected | Evidence | Recovery |
| --- | --- | --- | --- | --- | --- |
| C11 | Guided recovery-key export (WP19, D-005) | Start-menu Service Manager → Backup and recovery keys → Export: enter a directory with spaces that does not exist, accept the default name; repeat with `name.key`, with an existing file, with a folder the operator cannot write to, and cancel at each prompt | Resolved path shown before confirmation; missing folder created only after confirmation; `.key` appended once; existing file and unwritable folder refused before export; cancellation writes nothing; successful export is verified automatically (`escrow_verified: true`); no key value on screen or in `logs\service-manager`; menu returns after each refusal | Screenshots, key status JSON, `logs\service-manager` file | Revert `S1` |
| C12 | Certificate status and public export (WP20) | Service Manager → TLS certificates → Status; Export public certificate to `D:\lab\public.cer`; `certutil -dump D:\lab\public.cer` | Subject, issuer, validity, SANs per required identity and thumbprint shown; exported file has no private key | Output, `certutil` dump | — |
| C13 | Network change that needs a new certificate identity (WP20, D-004) | Corporate install (B4): change the listener to a second VM address that is **not** an allowed host (accepted with the existing certificate); then add that address as an allowed host (refused, the missing identity named); then the combined change with a certificate covering it | First change succeeds; second refused before any change; combined change restarts on the new certificate with pinned readiness; a forced failure restores the previous certificate and configuration | Result JSON, thumbprints, `config\deploy.json` before/after | `& $deploy -Action Recover -ConfigFile $config -Yes` |
| B11 | Guided deployment recovery (WP19, G-003) | During B7 end Setup after `stopping` (as B9); open Service Manager → Deployment and recovery | Journal phase and history shown; only the actions valid for the state are offered; the chosen action completes as in B9 | Screenshots, journal before/after | Revert `S1` |
| B12 | Interrupted first install whose certificate blocks recovery (WP20, G-007) | Fresh install from `S0`; force readiness failure after the service starts (block the port), leaving `manual_recovery_required`; change the listener so the certificate no longer covers an allowed host; `Install-AuthLens.ps1 -Mode Server -Recover -RecoveryAction VerifyCandidate` with a replacement PFX | Without the PFX: refused, nothing changed; with it: certificate imported to `tls\renew-<id>`, readiness pinned to the new certificate, journal `complete` with history kept; forced failure restores the previous certificate and phase | Journal, result JSON, thumbprints | Revert `S0` |
| B14 | Approval enforcement | Without `-Yes`: `& $deploy -Action <A> -ConfigFile $config` for A in Deploy, InstallService, Restore, Rollback, Recover, ReplaceCertificate, ChangeNetwork, RestartService, ProtectAcl, RestoreAcl; with `-DryRun` for InstallService, Restore, Rollback, RestoreAcl, Build | Every call exits 2 before any change ("repeat with -Yes" or "-DryRun is not supported"); journal, configuration, service PID and `WorkRoot` file list unchanged | Outputs, hashes before/after | — |
| T-001 | Recovery against an installed older release | On a snapshot with an interrupted first install made by an older candidate (RC3-VM130 or `8ec7f77`), copy the RC4 run folder; run R1 to R4 from the [reconciliation procedure](../deployment/WINDOWS_DEPLOYMENT.md#reconciling-an-interrupted-first-installation-that-was-corrected-manually) with the RC4 packaged tools | R1 preconditions met; `Recover -DryRun` previews `would_succeed`; VerifyCandidate completes; older history entries preserved | Journal before/after, R1 to R4 transcripts | Revert the snapshot |
| C14 | Service Manager restart | Service Manager → 1 → Restart: review state and downtime, type YES; then repeat while a deployment is interrupted (B9 state) | Restart completes with a new PID, listener owned by the service, readiness and identity verified; refused with the recovery message while interrupted | Output, `Get-Service`, `netstat -ano` | — |
| B15 | Recovery audit (G-004) | After B11/B12/T-001: `Get-Content C:\ProgramData\AuthLens\deployment\recovery-audit.jsonl`; then a `Recover -DryRun` | One line per attempt with action, decision, outcome, operator (the account that ran it), runs, version, commit, manifest and configuration hashes; no secrets; the simulation adds no line | The file, journal history | — |
| B16 | Setup registration reconciliation (G-005) | Fresh install interrupted by Setup (B12 state): `reg query HKLM\Software\AuthLens\Server` and the uninstall entry; recover through Service Manager or `Install-AuthLens.ps1 -Recover`; query again; then **Apps** shows AuthLens Server and an upgrade from RC4 runs | Before `SetupState=pending-verification`; after `verified` with Root, ProgramDirectory, ConfigFile, FileVersion; display name `AuthLens Server`; uninstall string unchanged; no second entry; `Test-AuthLensUpgradeReadiness.ps1` accepts it | `reg query` outputs, result JSON `setup_registration` | Revert `S0` |
| B17 | Upgrade and repair preserve certificates and data | Upgrade from RC3-VM130 to RC4, then Repair RC4; compare certificate thumbprint, `config\deploy.json`, record counts and review decisions | Certificate and configuration unchanged (no TLS generation), data and decisions intact, verified backup taken before the service stopped | Thumbprints, hashes, counts | Revert `S1` |
| B13 | Simulation never changes state (D-006) | Leave an interrupted first install as in B12 (`manual_recovery_required`); copy `deployment-journal.json`, `config\deploy.json` and `Get-Service AuthLens` output; run `& $deploy -Action Recover -RecoveryAction VerifyCandidate -DryRun` and the same with `-Yes`; run `-Action Restore -DryRun`, `-Action Rollback -DryRun`, `-Action InstallService -DryRun`; then `& $deploy -Action Recover -RecoveryAction VerifyCandidate` (no `-Yes`) | Recover `-DryRun` prints `SIMULATION`, `simulation: true`, `changes_applied: false`, `would_succeed`; the journal, configuration, service PID and `WorkRoot` file list are byte-for-byte unchanged and no `runs\<id>` folder appears; the other `-DryRun` actions exit 2 ("-DryRun is not supported"); Recover without `-Yes` exits 2 | Hashes and file lists before/after, results | Revert `S0` |

## D. Data sources (from `S2-admin`; snapshot `S3-sources` after D3)

Shares: same-server `\\<VM>\authlens-src` (NTFS: `NT SERVICE\AuthLens` Read) and remote `\\<fileserver>\authlens-src` (share and NTFS: computer
account `<DOMAIN>\<VM>$` Read; the virtual account authenticates as the computer account on the network). No mapped drives; no interactive session.

Run D1 to D11 for **every** supported file-based source (role catalogue, user–role mapping, user accounts, SoD matrix, Employee Directory) unless
a row says otherwise. The source list and modes are in the [compatibility matrix](../data/IMPORT_AND_REFRESH.md#data-source-compatibility-matrix).

| ID | Scenario | Procedure | Expected | Evidence | Recovery |
| --- | --- | --- | --- | --- | --- |
| D0 | Authority folder (8.1) | `icacls (Get-ChildItem C:\ProgramData\AuthLens -Force -Filter '.authlens-source-policy-*').FullName` | Protected; SYSTEM, Administrators, `NT SERVICE\AuthLens` Modify only | `D0-acl.txt` | — |
| D1 | Browser upload | Settings → Data Sources → source → **Browser upload** → file | Import succeeds; snapshot counts shown | Screenshot, refresh history | — |
| D2 | Local server path, Static and Dynamic (8.2) | **Local server file** → `C:\AuthLens-Sources\<file>.csv` → authorize → **Test connection and validate source** → **Activate validated source**; repeat in Dynamic mode with **Validate and import** (next candidate: one step, imports exactly the validated content) | Validation reports records without activating; activation imports; status `Authorization: exact` | `/api/server/sources/<source>` JSON | — |
| D3 | Same-server and remote UNC (8.3) | As D2 with **Network file (UNC)** and each share; then try `\\<VM>\c$\…` and `\\<host>@SSL\…` | Reads succeed as the service identity; refused paths are rejected before SMB traffic | File-server audit/packet capture showing no request for refused targets | — |
| D4 | Individual refresh and Global Refresh (8.4) | Change a Dynamic CSV; refresh that source; then Global Refresh | Changes appear only after validation; Static sources are skipped by Global Refresh | Refresh history export | — |
| D5 | Missing and invalid files (8.5) | Rename the file; then replace with the empty and malformed variants; refresh each | `missing`; header-only file `empty` (next candidate; RC3 reports `validation`); malformed `malformed_csv` or `headers`; previous snapshot counts unchanged | Counts before/after | Restore the file |
| D6 | Denied access (8.5) | Remove the service identity's NTFS read (and on the remote share the computer account's); refresh | `access_denied`; snapshot unchanged | Refresh history | Restore permissions |
| D7 | Unavailable share (8.5) | Disable the remote share or block SMB; refresh | `network_unavailable`; snapshot unchanged | Refresh history | Re-enable |
| D8 | Authorization revocation (8.6) | **Revoke authorization**; refresh | `policy_prohibited`; path, mode and snapshot retained; status `required` | Source JSON | Re-authorize |
| D9 | Restart and reboot persistence (8.7) | `Restart-Service AuthLens`; then reboot the VM | Dynamic configuration and authority persist; refresh succeeds without the browser | Source JSON after each | — |
| D10 | Last valid dataset preserved | After D5 to D7, compare record counts with the last successful import | Identical | Counts | — |
| D12 | Validation outcomes from the service (next candidate) | With **Test connection and validate source** enter in turn: the source folder itself, a `.txt` file, a relative path, an unauthorized CSV, a header-only CSV, a deleted CSV, then a valid one; repeat the folder case with a UNC folder path | `not_a_file` (folder named), `invalid_path`, `invalid_path`, `policy_prohibited` (authorization required), `empty`, `missing`, `validated` with record count; the UNC folder path is refused without any SMB connection (no outbound authentication in the remote share's security log) | Messages, share security log | — |
| D11 | Employee Directory and Functional Groups | Activate the Employee Directory source; define two Functional Groups | Manager and Functional Group options populate User Access, SoD and Reviews filters | Screenshots | — |

## E. Backup and restore (from `S3-sources`)

| ID | Scenario | Procedure | Expected | Evidence | Recovery |
| --- | --- | --- | --- | --- | --- |
| E1 | Encrypted backup under the service identity | After C6 (escrow verified): Settings → Backup → create backup; and an automatic backup | `.slbak` created by the service; verification (hash + SQLite) passes | Backup history JSON | — |
| E2 | Recovery-copy requirement | On a fresh key without verification try to enable automatic backups | Refused until the recovery copy is verified | Screenshot | — |
| E3 | Cross-instance restore (8.8) | Second VM from `S0-clean`, fresh Local install (B2); copy the `.slbak` and the recovery copy; `& $deploy -Action Restore -Backup D:\transfer\<file>.slbak -KeyFile D:\transfer\host-copy.key -ConfigFile … -Yes` | Key copied into `keys` and selected, service read granted; protected destination recovery backup created first; restore applied at restart; accounts, decisions, periods, frozen snapshots, source configuration restored; server sources show `required` until re-authorized; nothing read before that | Restore result JSON, period checksums before/after, source JSON | Destination recovery backup; else revert |
| E4 | Historical SoD evidence integrity | Before E3 record `/api/sod/periods/<id>` checksums and a report hash; compare after restore and after upgrade B7 | Identical checksums; reports render from the same frozen model | Checksum table | Stop (blocker) |
| E5 | SAP Lens backup migration | Restore a synthetic SAP Lens 1 backup into a fresh instance as documented in [backup and recovery](../operations/BACKUP_AND_RECOVERY.md) | Preview identifies the source product/version; restore validates; no SAP Lens service, directory or database is adopted or changed | Restore preview and result | Revert |

## F. Application smoke tests (from `S3-sources` or after E3)

| ID | Scenario | Expected | Evidence |
| --- | --- | --- | --- |
| F1 | Administrator and Reviewer sign-in | Both sign in; Reviewer sees no administrative Settings, no Open Features, no period administration; Bulk Review card hidden without `review` only (Reviewer has `review`) | Screenshots both roles, light and dark |
| F2 | Permission-aware navigation (8.11) | Main navigation entries match effective permissions; legacy `#/sod/reviews`, `#/sod/periods`, `#/sod/reports` land on Reviews | Screenshots |
| F3 | Personal theme preferences | Each account keeps its own theme across sign-out and another browser | Screenshots |
| F4 | Reviews with SoD enabled | Overview counters global with the scope line; Work Queue keeps filtered counters; Open Work Queue from SoD Overview, Access Explorer, conflict panel | Screenshots |
| F5 | Reviews with SoD disabled | Settings → Features → SoD off: Reviews keeps Overview with Account reviews; SoD review pages show the turned-off notice; re-enable restores everything | Screenshots |
| F6 | Account Review | Filters and counters on the page; decisions recorded with `review`; not mixed with SoD decisions | Screenshots, decision history |
| F7 | Functional Groups, Manager, Exact Usernames (8.12) | Same scope at every destination; frozen period checksum unchanged | Checksums |
| F8 | Review periods, Remediation, Reports and evidence | Create a period, freeze, decide, approve; remediation actions; report PDF/DOCX with checksum | Report files and checksums |
| F9 | Service restart and VM reboot | After `Restart-Service AuthLens` and a reboot: readiness, sessions require sign-in, data and sources intact | B3 outputs |
| F10 | Desktop (separate snapshot) | `& $desktop /LOG="$evidence\F10.log"` per user; starts with WebView2, loopback only | Screenshot, `netstat` |

## G. Mandatory scenarios (release blockers on failure)

A1, B2, B3, B4, B6, B7, B9, C3, C4, C5, C6, C8, C9, C10, D2, D3, D5 to D9, E1, E3, E4, F1, F2, F5, F7, F9. B5 is mandatory when Reverse Proxy is
offered to customers for 2.0.0; otherwise record it as not accepted and keep the mode out of the release notes.

## H. Evidence package

Zip `C:\AuthLens\acceptance\<run directory>` plus each scenario's JSON results and screenshots, named `<ID>-<description>`. Record in the tracker: VM image and
build, candidate commit, installer hashes, date, operator, and pass/fail per ID. Never include keys, passwords, certificates with private keys or
activation codes.

## J. Final regression and release sequence

1. Mandatory scenarios in §G passed on the VM; evidence recorded in the tracker.
2. Separate authorization for FULL: whole .NET suite (`dotnet test backend/tests/AuthLens.Tests -c Release`), complete browser suite, Pester and
   script tests on the build host, from the candidate commit (or a fix commit followed by a rebuilt candidate and the affected acceptance rerun).
3. Authorization to merge `experiment/dotnet-backend` into `main` (CI runs on that push only).
4. Rebuild the final candidate from the merge commit, verify, code-sign (separate authorized step), tag and publish only with explicit authorization.
