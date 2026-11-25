# Windows deployment: SSH-driven test server and installers

Server CSV sources are configured by an administrator in **Settings → Data Sources**: browser upload,
absolute local server file or UNC file, with explicit source authorization and full validation before
activation. See the [source policy and compatibility matrix](../data/IMPORT_AND_REFRESH.md#server-source-policy-remediation-awaiting-windows-acceptance).
Deployment creates a protected `.authlens-source-policy-<data-path-hash>` sibling of the data directory
for the configured service identity. This authority is excluded from application backups and does not
grant NTFS or SMB source access. For a domain-joined virtual service account, remote shares normally see
the computer account; custom domain/service accounts need their own share and NTFS rights. AuthLens
does not change identities, grant broad permissions or store share credentials. A fresh or restored host
may require source reauthorization while retaining configured paths, modes and durable snapshots.
Real local/UNC reads as a Windows Service, including managed service accounts supported by the host,
remain required acceptance tests; administrator-console success is insufficient.

Controlled installation, update, restore and rollback of AuthLens Server and Desktop. Use verified packages, dedicated storage, explicit
configuration and protected recovery material. Native and external acceptance boundaries are in [current status](../validation/STATUS.md).

## Components

| Path (under `backend/`) | Role |
| --- | --- |
| `scripts/deploy/deploy-windows.sh` | Linux entry point. Validates input, sends one PowerShell bootstrap over SSH (`-EncodedCommand`), keeps a local log, maps exit codes |
| `scripts/deploy/Deploy-AuthLens.ps1` | Windows entry point (Windows PowerShell 5.1 and PowerShell 7): actions, elevation and `-Yes` checks, result line `AUTHLENS-RESULT: <json>` |
| `scripts/deploy/AuthLens.Deploy.psm1` | Install, update and restore: installation layout, commit lock, isolated worktree build, release verification, backup, service control, rollback, recovery |
| `scripts/deploy/AuthLens.Acl.ps1`, `scripts/deploy/AuthLens.Paths.ps1` | NTFS audit and remediation; path safety (no reparse points, disjoint roots) |
| `scripts/deploy/deploy.example.json` | Configuration template (copy it outside the repository) |
| `installer/AuthLens-Desktop.iss`, `installer/AuthLens-Server.iss`, `scripts/build-installers.ps1` | Inno Setup installers and their build script |
| `installer/AuthLens-Transaction.iss`, `scripts/Install-AuthLens.ps1`, `scripts/deploy/AuthLens.Installer.ps1` | Manual installer transaction adapter; immutable payloads, Desktop recovery, Server delegation to the existing state machine |
| `scripts/Test-AuthLensUpgradeReadiness.ps1` | Read-only operator pre-upgrade checks against an existing verified canonical build; never installs, approves or performs an upgrade |
| `scripts/tests/AuthLens.Deploy.Tests.ps1`, `scripts/tests/deploy-windows.test.sh` | Pester (mocked operating system) and Bash (fake SSH, real PowerShell) tests |

The bootstrap resolves the branch or commit **on the Windows host**, locks the full SHA, extracts the deployment scripts of exactly that commit with
`git archive` and runs them. A developer checkout is never copied to the host. A commit that predates AuthLens (without
`backend/scripts/deploy/Deploy-AuthLens.ps1`) is refused.

Exit codes: `0` success, `1` failed (nothing changed, or rolled back and ready again), `2` refused before any change, `4` manual action required
(`RECOVERY-REQUIRED.txt` in the run folder), `64` invalid usage (Linux side, SSH never called), `255` SSH failure, `130` interrupted locally.

## Prerequisites on the Windows host

1. **OpenSSH Server** (Windows optional feature) with key authentication only:
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   Set-Service sshd -StartupType Automatic; Start-Service sshd
   # Administrators: the public key goes into C:\ProgramData\ssh\administrators_authorized_keys (owner SYSTEM/Administrators only)
   icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
   ```
   Set `PasswordAuthentication no` in `C:\ProgramData\ssh\sshd_config` and restart `sshd`. PowerShell remoting (WinRM) is not used and needs no change.
2. An **administrator account** for SSH (deploy, install, rollback and recover need elevation; status, health, build and dry-run do not change the service).
3. **Git**, **.NET SDK 10** and **Node.js 24 or 25** on `PATH` (the release builder builds the React UI and runs the tests).
4. A **clone of the repository** whose `origin` carries `experiment/dotnet-backend` (for example `C:\Users\example\Git\AuthLens`). The deployment
   never changes its checkout: builds use isolated worktrees under `WorkRoot`.
5. The **TLS certificate** (`.pfx`) and a **password file** readable by administrators, outside the repository and outside the data directory.

On Linux: `ssh`, `bash`, `iconv`, `base64` and an SSH key or agent for the host (`BatchMode=yes`: no password is ever asked for or passed).

## Configuration

Copy `backend\scripts\deploy\deploy.example.json` to `C:\ProgramData\AuthLens\config\deploy.json` (or elsewhere, outside the repository) and edit it.
Lookup when `-ConfigFile`/`--config` is not given: `$env:AUTHLENS_DEPLOY_CONFIG`, then `C:\ProgramData\AuthLens\config\deploy.json`. No other
location, and no configuration of an earlier product, is read.

| Setting | Default | Notes |
| --- | --- | --- |
| `Root` | `C:\ProgramData\AuthLens` | The installation root; every path below defaults to its [layout](#installation-layout) |
| `RepositoryPath` | required for repository deployment | The clone on the host; packaged installer mode needs neither Git nor an SDK and supplies its tools directory when omitted |
| `WorkRoot`, `ReleasesRoot`, `BackupRoot`, `DataDirectory` | `<Root>\deployment`, `\releases`, `\backups\predeploy`, `\data` | Set one explicitly only to move that path |
| `CertificatePath`, `CertificatePasswordFile` | `<Root>\tls\server.pfx`, `<Root>\tls\cert-password` | Provided by the operator before installing |
| `ServiceName`, `ServiceAccount` | `AuthLens`, `NT SERVICE\AuthLens` | Set only for an isolated test service |
| `ListenAddress`, `Port` | required | The server's HTTPS endpoint (`--listen`, `--port`) |
| `AllowedHosts`, `TrustedProxies` | `[]` | `--allowed-hosts` (every name the browser uses) and `--trusted-proxies` (only the reverse proxy's address) |
| `ReadyTimeoutSeconds`, `StopTimeoutSeconds` | 120, 90 | Readiness wait after start; graceful stop wait (the service is never killed) |

Unknown settings, relative paths and invalid ports are refused. The file holds paths, addresses and host names only: the certificate password stays in
its file, which only the server reads, and is never on a command line.

## Modes

```bash
D=backend/scripts/deploy/deploy-windows.sh
H=(--host 192.0.2.10 --user deployer --repo 'C:\Users\example\Git\AuthLens')
$D "${H[@]}" --mode status                       # service model, name, state, linked release, readiness, journal
$D "${H[@]}" --mode health                       # /health/ready and /product-version.json of the running server
$D "${H[@]}" --mode build --tests focused        # lock, build in a worktree, test, verify, publish to ReleasesRoot; no service change
$D "${H[@]}" --mode dry-run                      # lock the commit and print the plan; no build, backup or service change
$D "${H[@]}" --mode deploy --tests focused --yes # build, test, verify, back up, stop, switch, start, verify; roll back when safe
$D "${H[@]}" --mode deploy --commit 1a2b3c4d --tests full --yes
$D "${H[@]}" --mode rollback --yes               # previous release, only when it can open the current data
$D "${H[@]}" --mode recover --yes                # finish an interrupted deployment (Ctrl+C, dropped SSH)
$D "${H[@]}" --mode restore --backup 'D:\transfer\AuthLens-manual-<id>.slbak' --key-file 'D:\transfer\recovery.key' --yes
```

`--tests focused` runs the deployment-relevant test classes (startup, API, network, reverse proxy, sessions, accounts, persistence, backups,
maintenance commands, API contracts and versioning); `--tests full` runs the whole suite once. Tests run once per build, inside the
release builder, never again during the deployment. `main` and `work` are refused; a `--commit` must be on the pushed branch.

### Deployment sequence

The running service keeps serving while the release is built and tested. Then, each step journaled in `WorkRoot\deployment-journal.json` under an
exclusive lock:

1. Refuse when an earlier run was interrupted (run `recover` first), the service is not installed (unless `--first-install`), or the service runs
   another executable (unless `--adopt-service`, below).
2. `--schema-info` of the new release: refuse data written by a newer build.
3. Encrypted pre-deployment backup with the current release (`--backup-local`), then `--backup-verify`. No verified backup, no stop.
4. Stop through the Service Control Manager (graceful; imports are handed back). A service that does not stop in time is reported (exit 4), never killed.
5. Switch `ReleasesRoot\current` (a junction) to the new release, start, and wait for the service's own process to listen and `/health/ready` to answer 200.
6. Compare `/product-version.json` with the expected version and commit. Only then is the release kept (`complete`).
7. On any failure: roll back to the previous release when it can open the data (`--schema-info` of the previous build, or no migration applied
   during the run for older builds). Otherwise stop, keep the service stopped and write exact choices to `RECOVERY-REQUIRED.txt` (exit 4). An older
   database is never restored automatically.

### Release packages and integrity

Implemented and tested on Linux and Windows PowerShell 5.1 (Pester `verify-release.Tests.ps1` and a native clean Windows package).

| Kind | Where | Contents | Verify with |
| --- | --- | --- | --- |
| Full release | Builder output (`WorkRoot\builds\<sha12>\AuthLens-…-win-x64`, or `build-release.ps1 -Output`) | Every artifact in `build-manifest.json`: `server\`, `desktop\`, `symbols\`, `README.txt`, `Service-Manager.ps1` | `verify-release.ps1 -ReleasePath <folder>` |
| Server deployment package | `ReleasesRoot\AuthLens-…-win-x64` (what the service runs) | Every artifact except `desktop\**` and `symbols\**`, the unchanged `build-manifest.json` and `SHA256SUMS`, and `deployment-package.json` | `verify-release.ps1 -ReleasePath <folder> -Scope Server` |

- `build-manifest.json` and `SHA256SUMS` always describe the full build and are **never rewritten** in a package. `deployment-package.json`
  declares the package: kind `server`, the release name, the SHA-256 of `build-manifest.json`, and the exact omitted paths.
- `-Scope Server` allows only `desktop\**` and `symbols\**` to be absent and names every omitted file. Any other missing, changed or added file,
  a changed manifest, or a declaration that disagrees with the folder fails. The default full scope refuses a package outright.
- Publication (`Build` and `Deploy`) assembles the package in `ReleasesRoot\.staging\<name>`, verifies it there and only then moves it into
  place. A package that fails verification is never published; its staging copy is kept for inspection and blocks the next attempt until an
  operator removes it. An existing folder of the same commit is reused only if it verifies; it is never overwritten or repaired.
- `Deploy -Release <folder>` verifies with `-Scope Server` before anything else.


## Installation layout

One root, `C:\ProgramData\AuthLens` (setting `Root`). Nothing runs from the repository or a build folder; the service runs the verified release
under `releases\current`.

```text
C:\ProgramData\AuthLens\              protected DACL: SYSTEM and Administrators (not inherited from ProgramData)
  releases\<release>\, releases\current   verified server packages and the junction the service runs; service: read and execute
  data\                               authlens.sqlite3, accounts, uploads (sources\), application backups (backups\), logs\; service: modify
  config\deploy.json                  deployment configuration (no secrets)
  tls\server.pfx, tls\cert-password    TLS certificate and its password file; service: read
  keys\                               host backup key (selected with --backup-key use); service: read
  backups\predeploy\                   encrypted, verified pre-deployment backups
  deployment\                         journal, lock, runs (logs), worktrees and builds
```

Adjustments to the originally proposed layout, with the reason: application backups (automatic 90 days, manual until deleted, migration until
confirmed) stay in `data\backups\`, where the server manages and restores them; server logs stay in `data\logs\`; `app\` is used only by the
installer, scripted deployments use `releases\` (versioned, with rollback). A new root is created with its protected DACL by the first
install; an existing root must pass `-Action AuditAcl` (prepare it with `-Action ProtectAcl`, [NTFS permissions](#ntfs-permissions)).

## Install

```bash
$D "${H[@]}" --mode build --tests focused                   # verified release under releases\, no service change
$D "${H[@]}" --mode deploy --first-install --tests focused --yes
$D "${H[@]}" --mode status                                  # service AuthLens running, binary_path_matches true, ready
```

`--first-install` creates the root and its folders, installs the `AuthLens` service (automatic start, `NT SERVICE\AuthLens`, restart on failure,
per-folder grants) and starts it on a new, empty `authlens.sqlite3`. Then create the first administrator (Accounts mode) or restore a backup.
`--adopt-service` remains for a hand-installed `AuthLens` service with equivalent arguments (compared semantically; any difference is refused
before a change). Services of earlier products are never looked at, adopted, stopped or changed.

## Restore

`-Action Restore -Backup <file.slbak> [-KeyFile <recovery key>]` (`--mode restore --backup ... --key-file ...`) restores an AuthLens
backup into this installation: the key that sealed it is copied into `keys\` (never overwritten) and selected, `AuthLens.Api --restore` stages and
validates the archive (authenticated decryption, manifest checksums, SQLite integrity, known migrations, an enabled administrator), the service
restarts, and the server applies the restore before the database opens. The current data is first saved as an encrypted recovery backup (a fresh
installation has nothing to save). Any failure is rolled back by the server and reported with exit code 1; the previous data is unchanged.
A passphrase-protected backup takes `AUTHLENS_BACKUP_PASSPHRASE` instead of `-KeyFile`.


## NTFS permissions

Implemented and tested on Linux with synthetic ACLs (Pester `AuthLens.Acl.Tests.ps1`, including ProtectAcl/RestoreAcl with Windows-only
descriptor types replaced, and `AuthLens.Deploy.Tests.ps1`); **awaiting Windows acceptance** (no real ACL was read or changed from this
environment; `AuthLens.Acl.Native.Tests.ps1` and `AuthLens.Junction.Tests.ps1` run only on Windows).

**Broad principals** (matched by well-known SID, so localized account names do not matter): Everyone `S-1-1-0`, Authenticated Users
`S-1-5-11`, Users `S-1-5-32-545`, Interactive `S-1-5-4`, Network `S-1-5-2`, Anonymous Logon `S-1-5-7`, Guests `S-1-5-32-546`, Domain Users and
Domain Guests (`S-1-5-21-…-513`/`-514`). An allow rule counts when it applies to the object itself or, on a folder, to new children
(container/object inherit, also inherit-only): that is what a folder created later inherits. Deny rules and individual accounts are not findings.
*Read* is ReadData/ListDirectory, GENERIC_READ or GENERIC_ALL; *write* is any of WriteData/CreateFiles, AppendData/CreateDirectories, WriteEA,
WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership, GENERIC_WRITE or GENERIC_ALL.

| Class | Paths of the installation (role) | Broad read | Broad write | Required identities |
| --- | --- | --- | --- | --- |
| Private | `data` and every descendant (database, logs, application backups, accounts); `backups\predeploy`; `tls` (certificate, password file); the folder of the host backup key (`keys`); `deployment` | refused | refused | SYSTEM and Administrators full control; the service's virtual account modify on `data`, read on `tls` and `keys`, nothing on the others (an `NT SERVICE\…` account only: `LocalSystem` is SYSTEM) |
| Binaries | `releases`; the configuration file and its folder (`config`) | allowed on `releases` (read and execute), refused on configuration | refused | SYSTEM and Administrators full control; service read and execute on `releases` |

`C:\ProgramData` normally grants Users read and inherited create rights. It is **never changed**; `Initialize-ALInstallation` creates
`C:\ProgramData\AuthLens` with a protected DACL instead. A path that does not exist yet is reported (`exists: false`) without findings.
Secure provisioning refuses a parent with broad delete/replacement or DACL/owner rights. `AuditAcl` reports every finding with path, role,
principal, access, rights mask, inherited or explicit, and what it applies to.

This is a conservative allow-rule policy audit, not a Windows Authz effective-access calculation for every possible token. A broad allow remains
a finding even when a deny might cancel it for a particular user; individual account membership is not expanded. Native fixtures verify the SID
and inheritance representation Windows returns. Do not weaken these findings because an interactive administrator happens to have access.

### Audit and remediation

```powershell
$entry = '.\backend\scripts\deploy\Deploy-AuthLens.ps1'
$config = 'C:\ProgramData\AuthLens\config\deploy.json'
# Read-only: every finding for the installation (exit 0 safe, 2 unsafe). Changes nothing.
& $entry -Action AuditAcl -ConfigFile $config
# Only after approval and verified application/recovery backups. Review all roots first.
$approvedRoots = @('C:\ProgramData\AuthLens', 'C:\ProgramData\AuthLens-acl-recovery')
$aclBackupRoot = 'C:\ProgramData\AuthLens-acl-recovery'   # dedicated, outside affected trees; never ProgramData itself
# Explicit, approved remediation in an elevated session (does not stop or reconfigure the service):
& $entry -Action ProtectAcl -ConfigFile $config -ApprovedAclRoot $approvedRoots -AclBackupRoot $aclBackupRoot -Yes
# Undo exactly what ProtectAcl changed:
& $entry -Action RestoreAcl -ConfigFile $config -AclBackup <printed-backup-folder> -ApprovedAclRoot $approvedRoots -Yes
```

`ProtectAcl` changes only existing paths with broad grants or missing required access:

1. Requires explicit `-ApprovedAclRoot` application-owned roots and a disjoint `-AclBackupRoot` outside every affected tree. It rejects system
   roots, unapproved paths and reparse points before any change. Creates the backup storage with a protected DACL (SYSTEM, Administrators) and saves every affected ACL with its
   descendants into verified, icacls-compatible UTF-16 path/DACL inventories using in-process ACL reads, without recursive native traversal or per-object backup processes. Schema-2 `acl-backup.json` retains file checksums and original DACL inventories. All inventories and the manifest are flushed before application ACL changes.
2. For each path: `icacls /inheritance:r` with SYSTEM and Administrators full control (and the service's virtual account where the table says
   so), removes explicit grants to the broad SIDs (including the actual Domain Users/Guests SIDs found by the audit), grants authenticated users read and execute again on release folders only, and resets the
   inventoried physical descendants of private folders individually to inherit (their earlier explicit entries are in the backup). Ordinary files use a file-handle native reset; directories retain individual `icacls /reset /L /C /Q` calls. The native reset opens the final object with `OPEN_REPARSE_POINT`, rejects directory/reparse handles and supplies a real empty DACL with inheritance enabled, never a null DACL. Owner, group and SACL are outside this DACL-only operation.
3. New protected folders (the ACL backup storage, and the installation root through `Initialize-ALInstallation`) receive their DACL in the
   native exclusive [CreateDirectoryW operation](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createdirectoryw); ACE
   bytes/protection and required SYSTEM/Administrators access are verified before any file is written. Creation failure, a raced existing path,
   unsupported storage or verification failure refuses further writes.
4. Verifies required SYSTEM/Administrators full control and audits again; an unsafe result fails closed and retains the ACL backup.

It refuses drive roots, `%ProgramData%`, `%ProgramFiles%`, the Windows folder, `%SystemDrive%\Users` and user profiles. The running service
keeps its access (SYSTEM for `LocalSystem`, its own grant otherwise), so it is not stopped. Before running it on the production host: take a
verified application backup, run `AuditAcl` and review each listed path, run in a quiet window, and keep the printed backup folder.
`RestoreAcl` requires the independently approved roots again. Before its first restore command it validates all checksums and every UTF-16
path/DACL record against the saved inventory, rejecting path escapes. It replays saved ACLs newest first and verifies every original DACL afterward;
exit 4 indicates an unverified restore requiring manual recovery. Backup storage is retained; target-parent records of older backups are kept, never deleted. Schema-1 backups remain
untouched and require reviewed manual restoration; they lack the inventories required for an automated verified restore.
An elevated Windows token is required for native remediation/restore acceptance. An unprivileged `icacls /restore` can fail with exit 1300
(missing privilege); that is an infrastructure limitation, not evidence that restoration passed. Keep the original ACL backup and investigate.

### Release junction boundary

The source service may run through `<Source.ReleasesRoot>\current`. The former ACL backup path was
`Invoke-ALProtectAcl` -> `Get-ALAclSnapshot` -> `Get-ALTreeFiles`; the last helper intentionally rejects all reparse points, so snapshotting the
releases or installation folder rejected its legitimate release junction. Every other installation-tree traversal keeps that strict behavior.

ACL inventory alone accepts the exact `current` **directory junction** directly below the explicitly configured source releases root. Its target
must be an existing direct physical child of that root, contain a release manifest and Server directory, and have no linked ancestors or linked
descendants. Symbolic links, ordinary directories at `current`, missing/external/looping targets, additional aliases and nested reparse points
are refused. Approved roots must themselves remain physical; the exception never grants access through `current` or expands an approved root.
The exception compares configured paths and approved-root spelling exactly, including case, rather than accepting case-folded aliases. Use the
same physical path spelling in the source configuration, junction target and approved roots; a mismatch is refused without changing the junction.

The junction is validated and omitted from ACL inventory. Physical release files are inventoried through their real directory; overlapping plan roots can save the same physical object in separate inventories. ACL backup reads physical DACLs directly and writes UTF-16 restore records; it never invokes recursive native save or follows `current`.
Reset operations name individual physical descendants without wildcards or `/T`. Restore validates every recorded destination, rejects any path
through a link and uses `/restore /L`. See the [icacls command contract](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls).
Neither ACL remediation nor restoration deletes, recreates or redirects `current`. The physical target remains subject to its approved ACL policy.

New schema-2 backup entries for source release/installation roots record `releases_root` and the observed `junction` path/target. Binding and tree
checks run before commands and again before success. A changed binding, new unexpected link or unsafe target blocks further operations; a failed
post-operation check requires manual review (exit 4), retaining the backup. Do not run concurrent release switching during ACL operations. These
checks are fail-closed observations, not an atomic lock against a privileged administrator changing the filesystem concurrently.
Older backups receive no inferred junction exemption: link-free inventories remain supported, while an unrecorded junction requires manual review.
The release's historical build manifest is never regenerated for this procedure.

Read-only inspection from the updated checkout on the actual Windows host:

```powershell
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
$source = Read-AuthLensSettings 'C:\ProgramData\AuthLens\config\deploy.json'
Get-ALReleaseJunction $source.ReleasesRoot | ConvertTo-Json
# ACL metadata only: validates the whole installation tree and omits the validated current junction.
@(Get-ALAclSnapshot (Split-Path $source.ConfigFile) $source.ReleasesRoot).Count
```

Run `AuthLens.Junction.Tests.ps1` on isolated Windows fixtures. It covers allowed and rejected junctions, nonrecursive native ACL save, restore
binding/path boundaries and strict tree traversal. The native junction restore round trip additionally requires elevation; a skipped check is
pending acceptance, not a production-ready result. See the measured implementation and interruption procedure below; performance measurements do not establish production acceptance.

Windows junction checkpoint (2026-11-19, Windows PowerShell 5.1 / Pester 5.9.1): complete suite **208 passed, 0 failed, 11 skipped**,
0 failed containers (219 discovered). Nine skips are Linux-only fixtures and two require elevated native ACL restore. The final focused junction
spec passed 15 tests with its elevated restore case explicitly skipped. The 5.1 parser accepted all 24 active scripts; documentation links passed.
No production service, ACL, release pointer or private state was modified, and no full .NET/browser run was required for this PowerShell change.


### ACL performance and interrupted operations

The `8ee1cc6` backup invoked one `icacls /save` process **per snapshot object**, including duplicates in overlapping source roots. Private-state remediation then invoked another process per descendant, plus two or three commands per changed root. Restore already used one process per saved inventory, but validation searched the whole snapshot for each record (quadratic work). Repeated PowerShell ancestor/provider checks and tree/audit walks added time before the backup directory appeared. A changing `04.acl.part` in that implementation contained only the most recently saved object, not a cumulative or complete fourth backup. The startup-only deployment log contained no phase/count progress. An unsafe audit does not prove that no partial change occurred.

Backup now uses zero native processes per object, rechecks every ancestor through filesystem attribute APIs and compares the current DACL against the snapshot. It streams UTF-16 records to an exclusive `.part`, flushes to disk and renames without replacement. A failed write retains its partial output; it cannot be retried into the same filename. Completed records are validated with an indexed path lookup before the manifest is published. Root approval checks remain mandatory; descendant checks require containment within that approved root and physical, link-free ancestors. There is no cross-phase cache that would hide newly introduced links.

Recovery-path validation also covers a drive-root parent: the earlier `Parent.Length + 1` offset dropped the first character when the parent already ended in a separator (for example a source installation immediately under the drive). The writer now normalizes that offset, and validates the published inventory before permitting any ACL change. UTF-8 manifests are read explicitly as UTF-8 on Windows PowerShell 5.1 so Unicode filenames retain their exact paths. Old recovery artifacts are never rewritten to apply either correction; malformed historical inventories require reviewed manual recovery.

Ordinary file resets use a handle-based [SetSecurityInfo](https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo) operation, validated against `icacls /reset` with protected parents, inherited ACEs and repeated resets. Directory resets remain individual `/L` commands: directory `SetSecurityInfo` can propagate inheritable permissions to children, so it is not a safe replacement without further traversal analysis. For a changed private tree containing F files and D descendant directories, reset process launches drop from F+D to D. Root commands and one restore process per inventory remain. No wildcards or recursive native ACL switches were introduced.

Progress is printed to the terminal and the deployment log at stage boundaries and approximately every five seconds between objects: phase, stage, processed/total, elapsed seconds and ETA. Enumeration totals and ETA are `unknown` until measurable; ETA is a stage-local linear estimate only after 100 objects and five seconds. An individual native call or filesystem call can block longer than the reporting interval; no synthetic ETA or timeout hides that condition.

Each new operation writes a flushed append-only `acl-operation.jsonl` in its unique timestamp/GUID backup directory. The `backups_complete` checkpoint follows all inventories and the manifest; `mutation_started=true` is flushed **before** the first application ACL change. Normal failures append `failed`; abrupt termination leaves the last checkpoint, possibly an incomplete trailing JSON line. `Get-ALAclOperationStatus` reads this evidence without modifying it and treats truncated/absent journals conservatively. No automatic resume or rollback is implemented. Restore validates every inventory before changing any ACL, writes a separate new `acl-restore-<GUID>.jsonl`, and verifies original DACLs afterward. Recovery artifacts, created parents and prior journals are retained. The journal is a diagnostic checkpoint, not a replacement for inventory checksums, a verified application backup or explicit recovery approval.

Measured on the isolated Windows workstation checkout (Windows PowerShell 5.1, NTFS; **not the production VM**), using `Measure-AclPerformance.ps1`:

| Fixture/stage | Original | Optimized | icacls processes, original to optimized |
| --- | --- | --- | --- |
| 100 files + 11 directories, backup | 10.715 s | 0.961 s | 111 to 0 |
| 100 file resets | 9.097 s | 0.895 s | 100 to 0 |
| 2,000 files + 11 directories, inventory | not repeated | 13.850 s | 0 |
| Same large fixture, backup / indexed validation | not repeated | 14.804 s / 2.477 s | 0 |
| Same large fixture, file resets | not repeated | 8.048 s | 0 |

Small-fixture backup output was byte-identical to the original native-save output. Process counts cover deployment `icacls` calls; first-use `Add-Type` may invoke the framework compiler once on Windows PowerShell 5.1, independently of the object count. File reset timing includes first-use native helper compilation. Large-fixture native baselines were deliberately not repeated. At the small measured rate, 82,422 backup records alone would need roughly 2.2 hours with the original algorithm; an earlier 101-object measurement projected 2.6 hours. Duplicated inventories, disk/antivirus load and prevalidation increase the total. Large optimized measurements suggest minutes per pass at that scale, **not a promised VM completion time**. Overlapping snapshots, repeated physical/junction validation, in-memory snapshots/JSON manifests and directory process launches remain costs; an 82,422-object production-shaped elevated acceptance run remains pending.

Repeat only on fresh synthetic fixtures (the script accepts no installation path and retains its measurements under `build/test-artifacts/acl-benchmark-<GUID>`):

```powershell
& .\backend\scripts\tests\Measure-AclPerformance.ps1 -Objects 100
& .\backend\scripts\tests\Measure-AclPerformance.ps1 -Objects 2000 -SkipBaseline
```



#### Interrupted ACL operations

Keep incomplete recovery directories, `.part` files, backups and journals intact. Do not resume or reset permissions until the exact operation
and restoration prerequisites have been reviewed. The read-only status command is:

```powershell
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
Get-ALAclOperationStatus (Read-Host 'Exact existing ACL recovery directory (read only)') | ConvertTo-Json -Depth 5
```

Status inspection does not remediate findings or prove restoration. Do not weaken junction validation or global ACLs. Databases/WAL, keys,
TLS and unrelated installations remain protected.

### Windows script validation

Use Pester 5 in a fresh PowerShell process. Windows PowerShell 5.1 is supported for these deployment tests; PowerShell 7 is not required merely
to launch child scripts. `scripts/tests/TestHelpers.ps1` resolves the current edition's executable under `$PSHOME` by absolute path. To explicitly
test another installed edition, set `AUTHLENS_TEST_POWERSHELL` to its absolute executable path. An invalid override fails instead of falling back
or skipping. Run the suite from each installed edition to exercise that edition's parser and module behavior too.

```powershell
powershell.exe -NoProfile -File .\backend\scripts\check-powershell.ps1
# In a fresh Windows PowerShell 5.1 session with Pester 5 installed/importable:
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path .\backend\scripts\tests\TestHelpers.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\backend\scripts\tests\AuthLens.Acl.Tests.ps1,.\backend\scripts\tests\AuthLens.Acl.Native.Tests.ps1 -Output Detailed
# Phase checkpoint, after affected groups pass (not after every edit):
Invoke-Pester -Path .\backend\scripts\tests -Output Detailed
```

`Import-Module -Force` reloads one path but leaves same-name copies from other checkouts loaded. Pester's name-based mocks then fail with
"Multiple script or manifest modules named 'AuthLens.Deploy' are currently loaded." Repeated canonical imports alone do not imply that defect.
The shared test helper removes loaded copies and imports the resolved canonical module globally at each container's setup. Tests run serially;
do not share that process with operator actions. The regression creates a synthetic second module and proves the mock becomes unambiguous.
The test launcher protects `ProgramData\AuthLens` and every earlier product's production and Desktop data roots. The real NTFS fixtures touch only TestDrive. Their restore test explicitly reports a skip without elevation; mocked remediation is reported
separately. Linux shell-server fixtures remain Windows skips. Missing `pwsh` never skips deployment or release-contract tests.

Windows script checkpoint, 2026-11-19: Windows PowerShell 5.1 with Pester 5.9.1 discovered 203 tests: **193 passed, 0 failed, 10 skipped,
0 failed containers**. Nine skips were Linux shell-server fixtures; one was native ACL restoration without an elevated token. The 5.1 parser
accepted all 23 active scripts. Focused .NET StartupTests (5) and installer contracts (6) also passed. PowerShell 7 was unavailable. Real NTFS secure-at-creation, SID/inheritance and ACL-save tests passed; full native remediation/restore,
SCM, service continuity and production preflight remain unverified. The test workstation did not contain the active VM installation, so this run
did not prepare its target directories, verify its installed release, build a new production package or establish `safe: true`. Keep the existing
release manifest unchanged and obtain the actual VM connection before continuing the preparation checklist.

## Service model and permissions

- **Managed or not:** a service counts as managed (`binary_path_matches` in status) when its executable is the release link's
  `current\server\AuthLens.Api.exe` and its arguments are equivalent to the configuration. Both are compared normalized (quotes, separators and
  case of the path; option and list order of the arguments, as in [adoption](#install)), never as raw strings: Windows can store an
  equivalent command line differently (for example without the quotes around the executable when Windows PowerShell 5.1 passes `binPath=` to
  `sc.exe`). A real difference in any argument still reads as not managed.

- One service: `AuthLens`. Unrelated services are never adopted, stopped or changed.
- Account: the service's own virtual account (`NT SERVICE\<name>`), no password. Grants are added, never removed: modify on the data directory
  (inherited), read and execute on `ReleasesRoot`, read on the certificate, its password file and the backup key file. Path traversal to these
  files relies on the default *Bypass traverse checking* right (SeChangeNotifyPrivilege, held by Everyone and service accounts by default); no
  folder above a key or certificate is granted to the service. A hardened policy that removes that right makes the key `inaccessible`
  (diagnosed by `backup_key_service_access` and the key status) and requires a reviewed traverse grant; it is not added automatically.

#### Supported service identities (2.0.0 product decision)

| Identity | 2.0.0 support |
| --- | --- |
| `NT SERVICE\AuthLens` (virtual account) | **Primary supported identity.** Fresh Setup always uses it; deployment, key provisioning, source authority and ACL audit are built for it. Local and UNC source access under it is a mandatory acceptance requirement (UNC uses the computer account `DOMAIN\HOST$` on the remote share). |
| LocalSystem, LocalService, NetworkService | Not offered by Setup. An existing service with one of these identities is preserved and checked (never reconfigured); key access resolves them (LocalSystem needs no grant). Not part of 2.0.0 acceptance. |
| Existing local or domain account, existing gMSA | Compatible only when the service already exists with it: upgrades preserve and verify the identity and Service Manager grants key read to it. Not created, changed or validated by AuthLens; no password is ever handled. Not part of 2.0.0 acceptance. |
| New dedicated domain account or gMSA provisioning | **Deferred** (not in 2.0.0): no credential transport, logon-right or managed-password validation is introduced. |
- Command line (no secret): `AuthLens.Api.exe --data-dir … --network --listen … --port … --allowed-hosts … --cert … --cert-password-file … [--trusted-proxies …]`.
  TLS, the Host allow-list, Origin/CSRF checks and the trusted-proxy restriction are the server's own and unchanged by the deployment.
- Processes: only the service is stopped, through the SCM. A port held by another process (for example `start-server-test.ps1`) is reported and left alone.

### Installed and repository execution contexts

`Read-AuthLensSettings` derives the execution context from the configuration: with `RepositoryPath` it is a **repository** deployment (a source
checkout that may build from Git); without it, as Server Setup publishes it, an **installed (packaged)** Server. Every installed action works on
a Setup-published configuration (`Status`, `Health`, `InstallService`, `ReplaceCertificate`, `ChangeNetwork`, `Restore`, `Rollback`, `Recover`,
`Deploy -Release`); only actions that build from source (`Build`, `Deploy` without `-Release`) refuse with "builds from a source repository". No
repository path is invented and administrators never edit the Setup configuration. `-Action Status` reports `execution_context`. (Before this
correction, defect D-001, every `Deploy-AuthLens.ps1` action refused Setup configurations because `RepositoryPath` was mandatory.) Status:
Pester-tested on a Setup-shaped configuration and on a copy of the installed tool layout run outside the repository
(`Packaged-Runtime.Tests.ps1`); native acceptance pending.

### Simulation (-DryRun) and approval

`-DryRun` is a simulation and never replaces `-Yes` (defect D-006 corrected; Pester-tested, native acceptance pending). Deploy, Recover,
ReplaceCertificate, ChangeNetwork and ProtectAcl evaluate their read-only checks and report what would happen; every result carries
`simulation: true` and `changes_applied: false` and the output shows `SIMULATION (-DryRun): no change was made`. `Recover -DryRun` reports the
journal phase and history, the recovery actions the state allows (`options`), the decision for `-RecoveryAction`, and `would_succeed`,
`would_phase` or `blocking_reason`; exit 0 when the recovery would succeed, 2 when it would refuse. Build, InstallService, Restore, Rollback and
RestoreAcl refuse `-DryRun` with exit 2 before anything runs. `-DryRun -Yes` is still a simulation. A simulation writes no journal, recovery
note, configuration, installed-product record, run folder, log file or lock file (it holds the host mutex only), changes no service, registry,
ACL, firewall, certificate, key or data, and switches or removes no release. Its only output is the console and the `AUTHLENS-RESULT` line;
`Deploy -DryRun` from a repository configuration may fetch the source repository to resolve the commit (no installation change). A snapshot of
the persistent installation state is compared before and after; any difference, or a result claiming a completed operation, ends with exit 4.
RC3-VM130 and earlier tools do **not** have this protection: on them, never pass `-DryRun` to Recover, Restore, Rollback, InstallService or
RestoreAcl.

### Installed network configuration change

Status: implemented; Pester-tested with the platform layer mocked (`Server-NetworkChange.Tests.ps1`); native SCM, listener and firewall acceptance
pending (8.15).

Supported workflow for administrators: Start menu **AuthLens Service Manager** (the copy in `<Root>\app\setup\<package>\payload\<package>`, which
finds and hash-verifies the installed tools beside it), option **8** (network status) and **9** (change). The menu asks for each setting (empty keeps
it), validates, shows the consolidated current-to-proposed summary and applies only after typing `YES`. The same as commands:

```powershell
$manager = 'C:\ProgramData\AuthLens\app\setup\<package>\payload\<package>\Service-Manager.ps1'
& $manager -Action NetworkStatus
& $manager -Action ChangeNetwork -AccessMode Corporate -ListenAddress 10.20.30.40 -AllowedHosts 'lens.example.org,10.20.30.40'          # validates and prints the summary only
& $manager -Action ChangeNetwork -AccessMode Corporate -ListenAddress 10.20.30.40 -AllowedHosts 'lens.example.org,10.20.30.40' -ApproveFirewall -FirewallSources 10.20.0.0/16 -FirewallProfiles Domain -Yes
# Underlying installed entry point (same validation and transaction):
& '<Root>\app\setup\<package>\tools\deploy\Deploy-AuthLens.ps1' -Action ChangeNetwork -ConfigFile <Root>\config\deploy.json -Port 18796 -DryRun
```

Settings: access mode (Local, Corporate, ReverseProxy), listening IP, port, allowed hosts, public proxy hosts, trusted proxies (lists are
comma-separated; `-` in Service Manager clears a list). Data directory, identity, paths and certificate are refused here (certificates use
`ReplaceCertificate`). Validation before any change: the access-mode rules of Setup and the runtime (`Get-ALServerAccessPlan`: loopback for Local,
private interface and explicit hosts for Corporate, backend hosts, public proxy hosts and explicit trusted peers for Reverse Proxy, no wildcard
binding), host syntax (no wildcards, URLs or paths), the address must be assigned to this machine, the port free or held by the service itself, and
the packaged host's read-only `--server-preflight` with the proposed arguments (the **existing certificate** must cover the new hosts and the new
listen IP; in 2.0.0 the preflight requires the bind address even when no client uses it, defect D-004, so replace the certificate first with one
that covers both the current and the new names and addresses).
An unchanged proposal is refused. An installer-owned firewall rule that would no longer match a moved listener requires an explicit decision
(`-ApproveFirewall -FirewallSources … [-FirewallProfiles Domain]` or `-RemoveFirewall`); administrator-created rules are never touched.

The change uses the same recorded transaction as certificate replacement: `configuration-pending.json` keeps the previous configuration bytes,
hash and command line; only the changed settings are replaced in the configuration file; the service command line is rebuilt from it (one
configuration source; no manual ImagePath edit); the service restarts and readiness, listener ownership (the service process holds the new
listener) and the release identity are verified on the new listener with the pinned existing certificate. Any failure before that restores the
previous configuration and command line, restarts on them and reports the original error. The firewall step runs after readiness through the
existing owned-firewall transaction; if it fails the service stays ready on the new configuration and the result reports
`firewall_recovery_required` (recover with `Install-AuthLens.ps1 -Mode Server -Operation Firewall …`). An interrupted change is restored by the next
`ChangeNetwork` or `ReplaceCertificate`, or explicitly by `Deploy-AuthLens.ps1 -Action Recover`. `InstallService -Reconfigure` remains for repository
deployments and expert recovery only.

### Installed certificate replacement

Status: implemented; Pester-tested with the platform layer mocked (`Server-CertificateReplacement.Tests.ps1`, including a Setup-shaped
configuration); native SCM/TLS acceptance pending (8.13).

```powershell
# Elevated. -DryRun validates the new PFX with the packaged host and changes nothing.
.\Deploy-AuthLens.ps1 -Action ReplaceCertificate -CertificateFile 'D:\private-tls\renewed.pfx' -CertificatePasswordFile 'D:\private-tls\renewed-password' -DryRun
.\Deploy-AuthLens.ps1 -Action ReplaceCertificate -CertificateFile 'D:\private-tls\renewed.pfx' -CertificatePasswordFile 'D:\private-tls\renewed-password' -Yes
```

One recorded transaction: it refuses an interrupted deployment, a service outside the managed release link, a different service identity and a
service command line that differs from the configuration. The packaged host's read-only `--server-preflight` validates the new PFX against the
**unchanged** listener, hosts and proxies (SANs, private key, validity, EKU, key size) before anything changes. The PFX and password file are then
imported create-only into a new protected `Root\tls\renew-<id>` directory and validated again; `configuration-pending.json` (deployment state)
records the previous configuration bytes, their hash and the previous command line. The configuration's two certificate settings are replaced
atomically, the service identity receives read on the new files (`Grant-ALAccess`), the service restarts with the new command line and readiness
is pinned to the new certificate and the current release identity. Any failure restores the previous configuration and command line, restarts on
the previous certificate and reports the original error. An interrupted run is restored by the next `ReplaceCertificate` before anything else; a
record for another configuration or with a damaged hash is retained for manual recovery. Previous TLS files are never deleted. Network settings,
access mode, firewall, identity, data, accounts and keys are not changed, and no trusted root is added: distributing the new certificate to clients
remains an administrator decision. Network settings change through [the network configuration change](#installed-network-configuration-change).

`-Action Status` additionally reports `execution_context`, the current network settings and certificate, `configuration_change_pending` (an
interrupted network or certificate change awaits restoration) and
`backup_key_service_access`: `not_configured`, `readable`, `not_readable` (no explicit Allow read for the configured service identity, or a Deny),
`missing`, `identity_unresolved` or `unknown` (the key's DACL is not readable by this session; run elevated). It reads the key file's DACL only and
never opens the key. Status: Pester-tested on synthetic files (`Server-Diagnostics.Tests.ps1`).

## Logs and artifacts

| Where | What |
| --- | --- |
| `${XDG_STATE_HOME:-~/.local/state}/authlens-deploy/<UTC>-<mode>-<host>.log` (Linux) | Complete remote output of each run |
| `WorkRoot\runs\<run id>\` | `deploy.log`, `build.log`, `RECOVERY-REQUIRED.txt` when needed |
| `WorkRoot\deployment-journal.json`, `WorkRoot\deployment.lock` | Phase history of the last run; one operation at a time |
| `WorkRoot\worktrees\<sha12>`, `WorkRoot\builds\<sha12>` | Isolated build checkouts and builder output |
| `ReleasesRoot\AuthLens-<version>-<UTC>-<sha7>-win-x64`, `ReleasesRoot\current` | Verified server deployment packages ([release packages](#release-packages-and-integrity)) and the junction the service runs |
| `ReleasesRoot\.staging\<release>` | Only after a failed publication: the unverified copy, kept for inspection |
| `BackupRoot` | Encrypted, verified pre-deployment backups (`.slbak`) |
| `<DataDirectory>\logs\server-*.log` | The server's own log when it runs as a service |

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Exit 64, nothing sent | Fix the option named in the message (`--help`) |
| Exit 255 / `No result line` | SSH or PowerShell failed: check `ssh -o BatchMode=yes deployer@host`, the key in `administrators_authorized_keys`, and `powershell.exe` on the host |
| `Deployment configuration not found` | Create the file in one of the lookup locations or pass `--config` |
| `needs an elevated session` | Use an administrator account for SSH |
| `runs …, not the managed release link` | First deployment: `--adopt-service`; arguments must match the configuration |
| `interrupted in phase …` | `--mode status`, then `--mode recover --yes` |
| `did not stop within …` (exit 4) | Investigate the service (Event Viewer, `<data-dir>\logs`); it was not killed. Retry when it is stopped |
| `Rollback is not safe` (exit 4) | Read `RECOVERY-REQUIRED.txt`: fix forward, or restore the pre-deployment backup into a new data directory with the previous release |
| Windows PowerShell 5.1 `[System.Char] … 'Trim'` | Fixed in c772eef; deploy a commit from after it |

## Installers

Built on Windows with Inno Setup 6 from a release folder written by `build-release.ps1`:

```powershell
cd C:\Users\example\Git\AuthLens\backend
powershell -NoProfile -File .\scripts\build-release.ps1 -Output C:\AuthLens-Build\builds
$release = Get-ChildItem C:\AuthLens-Build\builds -Directory -Filter 'AuthLens-*-win-x64' | Sort-Object Name | Select-Object -Last 1
powershell -NoProfile -File .\scripts\build-installers.ps1 -ReleasePath $release.FullName -Output C:\AuthLens-Build\installers
```

| Installer | Scope and folder | Behavior |
| --- | --- | --- |
| `AuthLens-<version>-Setup.exe` (Desktop) | Per user, `%LOCALAPPDATA%\Programs\AuthLens Desktop`; data `%LOCALAPPDATA%\AuthLens\data` | New AppId, closed-application check, private recovery journal, encrypted protective backup, atomic executable replacement and readiness-verified binary rollback |
| `AuthLens-Server-<version>-Setup.exe` | Machine, `<Root>\app`; executable under `<Root>\releases\current\server` | Validated configuration/managed discovery, derived program directory, read-only package/TLS/database preflight, protected provisioning and the existing verified service transaction |

Full release installer execution and privileged service acceptance are **not verified here**. The PowerShell adapter has native isolated Desktop evidence;
the Inno definitions have contract tests and synthetic native compiler checks. Installers are unsigned; approved transport, signing, publication and deployment are separate steps.
Do not run the examples against an existing installation during development.

The shared `AuthLens-Transaction.iss` is included inside each installer's [Pascal Script `[Code]` section](https://jrsoftware.org/ishelp/topic_scriptcreating.htm). Its comments must use Pascal syntax (`//` or block
comments), not Setup-section `;` comments. Native acceptance of fdb7e87 exposed a `'BEGIN' expected` error at the include's first `;` header.
The headers now use `//`; the include placement and all transaction/security logic are unchanged. Focused installer contracts expand the include
in both callers, check that its context is `[Code]`, and reject Setup-style comments there. This guard detects the reported defect but is not a
Pascal compiler. Recompile **both** variants with Inno Setup 6 using a newly verified release and helpers from the same fixed commit; preserve the
failed build and use a new empty installer output directory. ISCC was unavailable at that earlier checkpoint; the callback isolation checks below
now have local Inno Setup 6.7.4 compiler evidence.

### Fresh Server extraction ownership and early failure evidence

Build `8c6ea68` refused a first installation after extraction: its fresh `app` guard allowed only `setup`,
but Inno had legitimately created `unins000.exe` and `unins000.dat` before `ssPostInstall`. The refusal occurred
before release publication, service registration and deployment-journal creation; it was not an ACL failure.

Fresh Server Setup now records a create-only `setup-metadata.ini` beneath the current immutable Setup stage.
It binds the verified package manifest and the exact bytes of those two Inno files with SHA-256. Only that
stage-bound receipt permits these names through the fresh-root guard. A name alone, another receipt path,
changed bytes, another staged payload, unknown files or previous operation results still cause refusal.
The private root ACL and complete package/helper integrity checks remain required. The receipt is captured
and checked while Inno waits at `ssPostInstall`; the uninstall data may change after Setup resumes.
Desktop does not receive this Server-only metadata argument.

Operation reports distinguish `deployment_journal_expected`, `deployment_journal_exists` and
`deployment_journal_status`. `deployment_journal` is null until a journal actually exists. The failure message
also states the journal's status; an expected path does not prove deployment or rollback
ran. Setup asks for the operation result, Setup log, staged tools and any existing journal, rather than promising a journal.
User-run focused validation passed 48 tests, including native compilation of both installer scripts with synthetic payloads.
Actual fresh/upgrade installation and recovery acceptance for a newly packaged build remain required.
Retain `operation-result.json`, `transaction-diagnostic.txt`, the Setup log,
the staged payload/tools and configuration/TLS publication receipts. Same-payload retries never overwrite
these files. A different package does not make an interrupted/unregistered populated root clean.

Native metadata timing is tested using a uniquely identified, disposable per-user Inno probe and the actual
read-only receipt verifier. This is not full Server/SCM acceptance. Desktop alpha-to-stable upgrade ordering
is decided by the verified manifest's semantic product version, not the Windows file revision (`.1` to `.0`).
Both the wizard and Desktop transaction defer channel ordering to that semantic guard. Desktop recovery preserves
the displaced candidate with a short unique filename; program paths whose recovery-tool inventory would exceed
Windows PowerShell's file-path budget are refused before provisioning. No long-path policy is changed globally.
The opt-in native Desktop adapter test accepts `AUTHLENS_INSTALLER_TEST_RELEASE` and optional
`AUTHLENS_INSTALLER_BASELINE_RELEASE` (verified full release directories) to exercise an actual alpha-to-stable
update and binary recovery in a disposable fixture. It does not register or test the installed GUI shortcuts/ARP entry.

#### Recovery of the failed production installation (manual, not automatic)

The empty-data byte measurement defect is reproduced on Windows PowerShell 5.1 with StrictMode:
`(@() | Measure-Object Length -Sum).Sum` raises `PropertyNotFoundException`. Installer storage planning now
uses an explicit `Int64` accumulator for both payload and data files, returning numeric zero for empty
collections. No other `Measure-Object`/`.Sum` expressions were found in the installer/deployment tooling.
This is the leading explanation for the reported `4be34cb` fresh-install failure, **not proven historical
causation**: its original exception stack was not retained. The packaged Server preflight and configuration
wrapper contract are unchanged; callers still pass the wrapper to planning and its `Config` to service arguments.

Unexpected adapter failures now retain sanitized structural diagnostics in the diagnostic file, structured
result and console, including exception type/message, error ID/category, source script/line, stack frames,
stage, operation ID and verified manifest identity (or explicitly unavailable before verification).
Arbitrary exception messages, error IDs, target objects, invocation text, external paths/functions and
potential secret-bearing values are redacted; literal product errors extracted from verified helper source
and the known empty-`Sum` runtime message are retained verbatim. Interpolated product errors are redacted too.
The transaction dialog shows only the concise first line. Evidence is create-only and independent of a
deployment journal. A diagnostic/result write failure is reported without overwriting earlier evidence.

New adapters can write `preflight-failure.json` only after a pre-deployment Server preflight refusal,
with a newly written diagnostic/result and the original valid Setup metadata. The receipt binds the
operation ID and exact configuration, release manifest, helper manifest, seven helper files, metadata,
result and diagnostic hashes. It requires administrative ownership, no non-administrative mutation rights,
private ACL checks and physical paths. It is an ownership/integrity receipt within the trusted administrator
boundary, not a signature or proof against a malicious administrator. Failure to record it leaves normal refusal in place.

An explicit **read-only diagnostic retry** may select that receipt, without changing the original evidence:

```powershell
# On a disposable acceptance VM only, after reviewing the retained evidence; use its actual stage/config.
Set-Location C:\Users\arkasa\Git\authlens
$stage = 'C:\ProgramData\AuthLens\app\setup\REVIEWED-PACKAGE-NAME'
powershell.exe -NoProfile -NonInteractive -File "$stage\tools\Install-AuthLens.ps1" `
  -Mode Server -Operation Install -PreflightOnly `
  -ConfigFile 'C:\ProgramData\AuthLens\config\deploy.json' `
  -Package "$stage\payload\REVIEWED-PACKAGE-NAME" `
  -SetupMetadataFile "$stage\setup-metadata.ini" `
  -FailedPreflightReceipt "$stage\preflight-failure.json"
```

No output-file paths are needed: stdout reports the retry. Package verification, empty fresh-data checks,
service identity, configuration, ACL, TLS/runtime/schema and storage checks still run. An actual journal,
unknown stage files, changed bytes, unsafe ownership or missing receipt refuses. A journal's expected path
is never evidence that a transaction exists. This option cannot deploy, prepare, recover or repair.
Same-payload GUI Setup still refuses overwrite. Old failures without a receipt are not retroactively certified.
Inno may update `unins000.dat` after the receipt checkpoint; changed metadata must refuse rather than be
rehashed to manufacture ownership. Use the manual preservation/recovery procedure below in those cases.

Fresh Inno uninstall registration cannot be deferred while retaining its supported uninstall lifecycle and
the metadata checkpoint. New Server installers therefore use the uninstall display name
`AuthLens Server (pending verification; recovery required)` and product `SetupState=pending-verification`.
Only the successful shared transaction callback publishes the normal display name, version/discovery hints
and verified state. A failure or crash leaves an explicit incomplete state when registration survives;
Setup does not delete data, remove registration or declare a service deployment successful. Existing
verified upgrade registration is not marked as a fresh install. Native timing, failure/exit behavior and
final registry state still require acceptance; pending registration is not permission to uninstall or rerun Setup.

Focused validation for this fix uses Windows PowerShell 5.1 (Pester 5.9.1). From the repository root:

```powershell
Set-Location C:\Users\arkasa\Git\authlens
Import-Module Pester -MinimumVersion 5.9.1
$checks = New-PesterConfiguration
$checks.Run.Path = @(
  'backend/scripts/tests/Installer-FailureRecovery.Tests.ps1',
  'backend/scripts/tests/Server-Setup.Tests.ps1',
  'backend/scripts/tests/Installer-Preflight.Tests.ps1'
)
$checks.Run.PassThru = $true
$checks.Output.Verbosity = 'Detailed'
# These files do not use TestRegistry; useful in a registry-restricted test sandbox.
$checks.TestRegistry.Enabled = $false
$result = Invoke-Pester -Configuration $checks
if ($result.FailedCount -or $result.FailedContainersCount) { throw 'Focused installer checks failed.' }
python scripts/check-docs.py
git diff --check
```

The six-file focused set (the three files above plus `AuthLens.Installer.Tests.ps1`,
`InnoIsolation.Tests.ps1` and `Installer-PublishedRelease.Tests.ps1`) passed 94 tests with one opt-in native
Desktop acceptance case skipped on Windows PowerShell 5.1. Both installer scripts compiled with synthetic
alpha/stable payloads; none was executed. Pester's initial XML export was blocked by sandbox WMI access;
the host rerun exported its report successfully. The final helper-inventory tightening passed all 57 tests
in the two affected planning/recovery files. The documentation checker passed all 44 Markdown files.

These checks cover byte accounting, read-only planning, diagnostics, evidence integrity and source registration
contracts; they do not establish SCM/GUI acceptance. After separate approval to build and accept a fixed package,
use a snapshotted disposable Windows VM and retain Setup logs/results. Test absent and existing-empty data
directories; inject a preflight exception before journal creation and verify nonzero failure, useful sanitized
evidence, pending ARP/product registration and no service/database/journal. Test receipt retry with unchanged
bytes, then altered diagnostics/helpers/metadata, an unrelated file and a real journal; every unsafe variant
must refuse and preserve evidence. Verify the unchanged wrapper contract and packaged read-only preflight
identity/schema flags. Finally test successful fresh install and verified upgrade with populated synthetic
data, normal registration, HTTPS/SCM readiness and unchanged data. Check post-Setup registry state, not just
the callback checkpoint. A complete release rebuild and native installer execution are awaiting approval;
do not run these acceptance cases on the affected server.

For operation `ffa76a83733446358f2a708a65e27c67`, **do not rerun Setup, invoke the uninstaller, delete files,
invent a deployment journal or use deployment recovery against a nonexistent journal**. First preserve an
independent, access-protected copy of the complete failed root, including TLS private material/password files,
keys, configuration, staged helpers/payload, Inno metadata and logs. Preserve the original installer/checksum.
Verify every copied file's SHA-256 and retain a verified off-server copy before moving any path.

An administrator must establish all of these facts before a fresh retry: `AuthLens` is absent from SCM;
no AuthLens process/listener exists; no release pointer or published release exists; the configured data
directory contains no database or retained user data; no deployment/repair/uninstall/firewall journal exists.
Inspect advanced external data/backup directories separately. If any assertion fails, **stop** and review
the real installation/recovery state; do not use the empty-install procedure below.

After independent backup and explicit operator approval, the exact canonical failed root can be renamed
in place (not deleted), preserving its DACL and all recovery evidence:

```powershell
# MANUAL ONLY. Run after all checks above, never against a running/previously installed Server.
$failed = 'C:\ProgramData\AuthLens'
$retained = 'C:\ProgramData\AuthLens.failed-ffa76a83733446358f2a708a65e27c67'
if ((Get-Service AuthLens -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $retained)) {
    throw 'Service exists or retained path already exists; no rename is permitted.'
}
if ((Get-Item -LiteralPath $failed -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'The failed root is a reparse point; review before any move.'
}
Rename-Item -LiteralPath $failed -NewName (Split-Path $retained -Leaf)
```

This command is **not sufficient preflight on its own**; the database, listener, directory, journal and
independent-backup checks above are mandatory. Review any partial Add/Remove Programs and `Software\AuthLens\Server`
registration with the installer owner before retrying; do not erase registry entries blindly. Keep the failed
root and exported registration evidence. Use only an approved fixed installer, explicitly configure the fresh
canonical root, and import preserved certificates through the supported wizard where appropriate. Never reuse
an old JSON file without reviewing its absolute paths. Verify HTTPS/SCM/data readiness and administrator access.
If retry fails before readiness, stop; preserve both roots and all new evidence. Do not restore files over a live
service. A verified rollback of an installed service is a separate, backup-bound recovery operation.

### Read-only upgrade readiness

`Test-AuthLensUpgradeReadiness.ps1` is an operator script, separate from the seven packaged installer helpers.
Adding or changing this inspection wrapper alone does not require rebuilding an already verified package. It verifies
the packaged helper bytes against the reviewed repository helper files; a changed packaged helper requires a matching
reviewed build, not an override. Existing release artifacts are never rewritten.

Run manually in Administrator PowerShell on the acceptance VM:

```powershell
Set-Location C:\Users\arkasa\Git\authlens
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\backend\scripts\Test-AuthLensUpgradeReadiness.ps1 `
  -BuildDirectory 'C:\AuthLens\REVIEWED-BUILD-DIRECTORY' `
  -ExpectedSourceSha ((git rev-parse HEAD).Trim())
```

Select the actual verified build directory; no latest-build inference, rebuild, UAC request or prompt occurs.
The example expects a build of the current checkout's committed SHA. Exact helper comparison intentionally
refuses the older `4be34cb` package after installer fix `21987b3` changed packaged helpers. Preserve that
package unchanged; use a new manually built, verified package matching the reviewed helpers. Updating this
operator wrapper alone does not require repackaging when the seven helper files are unchanged.
`-ConfigFile` optionally selects an existing configuration through the normal registration/ownership checks.
`-RecoveryReport` optionally selects an existing backup-result JSON; otherwise the newest report in
`build/lifecycle-work` is selected, and a failed latest report never silently falls back to an older successful one.

The wrapper verifies build/installer identity and hashes, binds packaged helpers to the build summary and repository,
checks the Running/Automatic virtual-account service, owned active release and terminal deployment journal,
and verifies the independent recovery bundle's ACL, archive hash, selected config/TLS/recovery-key copies and
unchanged protected source files. Recovery storage must not overlap installation, data, backup, build or repository
storage. Retained recovery program metadata must match the active release. The supported
`Install-AuthLens.ps1 -Mode Server -Operation Upgrade -PreflightOnly` then performs existing release, ACL, TLS-policy,
database-integrity/foreign-key and schema/rollback checks. No preparation, transaction, file-output or approval flags are passed.
The structured preflight result must use schema 1 and bind both its actual and expected journal paths to the
installation's observed journal. New `SetupState=pending-verification` registration refuses readiness;
older installations without that marker remain subject to the existing service, ownership and journal checks.
Registration fingerprints also cover the new state marker and installer file version.

Service PID/state/startup/identity/command line, registration, release pointer and observed protected file hashes
are compared again, including after a caught failure. Raw exceptions, command lines, child output, private inventory
and secret values are not printed. Only fixed diagnostic codes and a console JSON line prefixed
`AUTHLENS-UPGRADE-READINESS:` are emitted. Exit `0` means the observed checks passed; exit `1` means failure/refusal.
Missing input is a structured refusal, not an interactive prompt. The script itself creates no report files.

**PASS does not authorize cutover or approve a release.** Unsigned diagnostic installers are reported as `NotSigned`;
invalid signatures refuse. Snapshot availability is external and not inspected. A prior verified backup plus unchanged
archive hash is not proof of backup freshness, successful restore or current business-record preservation. Those checks,
a fresh backup when needed and actual native upgrade/recovery acceptance remain mandatory. The live database is not
copied or hashed; normal concurrent application writes cannot be treated as a consistent file fingerprint.
Focused Windows PowerShell 5.1 tests cover the wrapper contracts; no native acceptance is claimed.

Metadata contracts are distinct: `build-summary.json` and the release `build-manifest.json` use schema 1;
the current `build-installers.ps1` emits an unversioned installer manifest with exactly product, version, source SHA,
branch, build timestamp, dirty-source flag, executable mapping and artifact inventory. Readiness validates that known
contract instead of accessing a nonexistent installer `schema` property. Unsupported fields/schema declarations still
refuse, and identity, dirty-source, executable isolation and hash binding remain mandatory. The original 20 wrapper
tests passed but did not cover this producer contract; the actual VM run stopped before observing the installed service.
The correction has regression coverage using the real metadata-construction block with synthetic inputs.
The producer fixture runs in its own function scope: its `$field` loop must not overwrite Pester's case variables
(PowerShell variable names are case-insensitive). Identity mismatch tests preserve a valid executable object;
null/string/array mappings and missing executable members have separate structural-refusal tests. The first corrected
contract test run reported 25 passed and three fixture-scope failures; the corrected focused suite now passes.

Build checks now identify separate summary, inventory, release identity, installer identity, checksum and signature stages.
Missing required fields and identity mismatches produce fixed field-specific codes (for example
`installer_manifest_field_missing_source_sha` or `installer_manifest_mismatch_version`). Malformed JSON is reported as
`metadata_json_invalid`. Unexpected failures include only exception type and script line number, never exception text,
metadata values, invocation text or stack traces. No verified build output needs rewriting for this wrapper correction.

Finalization validation on Windows PowerShell 5.1 passed 44 readiness tests, 10 build-helper tests and nine
installer-preflight tests (63 total), with zero failures or skips. These tests use synthetic files, mocked
service/registry reads and the current installer result writer; they never build or run an installer or
inspect the installed Server. PowerShell parsing and the 44-file documentation-link check passed.
Native readiness, recovery freshness and actual upgrade acceptance remain pending.

To repeat only this focused selection from the repository root with Pester 5:

```powershell
Set-Location C:\Users\arkasa\Git\authlens
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path @(
  'backend/scripts/tests/Upgrade-Readiness.Tests.ps1',
  'backend/scripts/tests/Build-Workflow.Tests.ps1',
  'backend/scripts/tests/Installer-Preflight.Tests.ps1'
) -Output Detailed
```

### Desktop and Server callback isolation

Each entry script includes only its own Pascal callbacks (`AuthLens-Desktop-Code.iss` or `AuthLens-Server-Code.iss`) before
`AuthLens-Transaction.iss`. Shared events retain the immutable-payload refusal and transaction exit handling; they do not contain conditional
Desktop/Server validation. Desktop preparation requires no `/CONFIGFILE`, uses per-user privileges and the selected HKCU data profile
(default `%LOCALAPPDATA%\AuthLens\data`). Server alone reads reviewed/discovered deployment configuration, derives `Root\app`, validates the temporary package before confirmation and provisions its protected root before permanent payload staging.
Backup, rollback, recovery journals and installation boundaries are unchanged.

Focused checks: `dotnet test backend/tests/AuthLens.Tests -c Release --filter FullyQualifiedName~InstallerTests` and
`Invoke-Pester backend/scripts/tests/InnoIsolation.Tests.ps1`. The latter uses Inno Setup 6 when installed to compile both actual entry scripts
with synthetic payload bytes and inspect their preprocessed code. It never executes Setup; a skip means native compiler verification is deferred.
These fixtures are not release artifacts. On this workstation Inno Setup **6.7.4** also correctly isolated the original `e16b9d3` branches;
indented directives were **not proven to cause** the reported acceptance failure. Preserve the failing EXE, SHA-256, compiler version,
build command and Setup log to reconcile artifact provenance. The callback split removes shared conditional validation but does not establish
the cause of that particular executable's behavior.

Rebuild a clean release and matching installers from the committed correction into fresh output paths. On a disposable Windows VM/user,
confirm Desktop proceeds without `/CONFIGFILE`, keeps its selected per-user data on update/uninstall, and launches WebView2; confirm Server
refuses missing/invalid configuration before staging and accepts only reviewed explicit configuration. Repeat update/failure/recovery and
installation isolation checks in the acceptance procedure below. Neither existing unrelated installations nor preserved recovery artifacts may be changed.

### Manual installer transaction

The builder requires a clean release and helper sources at the **same Git commit**, plus an empty output directory. It copies only the seven
runtime helper files and records their SHA-256 inventory in `installer-tools.json`; no host configuration or secret is embedded. Both installers
stage the unchanged full release and tools under `app\setup\<package-name>`. An existing exact package directory is refused, including an incomplete
one. This costs additional disk space (Desktop includes the Server maintenance executable); no second backup engine or installer framework is used.
The entry point verifies every helper before importing code, then verifies the complete release before replacement. Checksums detect corruption;
they do not replace an approved distribution/signing trust boundary. The release manifest is never rewritten.

Desktop uses `/DATADIR="absolute private fixture data path"` optionally; otherwise it retains the registry's selected profile or uses the canonical
default. Shortcuts and post-install launch pass that same directory. Updating an existing journal with a different data directory is refused.
Close the selected Desktop first: neither installer nor helper kills it. Existing data must pass a private ACL audit; new dedicated directories
are created with protected DACLs before files. Global Windows directories and protected earlier-product paths are rejected. New private directories
retain SYSTEM, Administrators and the installing user. Broad binary read is allowed, broad write is refused.

Before updating, Desktop verifies the old executable against its installed manifest, refuses a downgrade or any pending schema migration,
retains the old executable/manifest, creates and verifies an encrypted `--backup-local` archive, and probes the old version. A configured private
host key is required; it is never created, replaced or exported by Setup. The candidate is staged, hashed, atomically replaced, then run with
`--self-check` against the selected data directory. Failure restores and probes the old executable only if the schema still matches the recorded
history. Binary rollback never restores an older database automatically. An incompatible schema, unverified recovery file, busy application or
failed rollback leaves exit 4 and preserved evidence for an operator. A fresh install has no previous version: failed readiness retains its
diagnostics for manual review. A probe timeout records its owned PID and leaves it running for inspection rather than terminating it.

Server Setup accepts `/CONFIGFILE="absolute reviewed deployment config"`; without it, validated registration or a managed service's canonical configuration is discovered, then the known default is used only when no service exists. Ordinary installs/upgrades do not need `/DIR`.
The selected configuration owns `Root\app`; an explicit conflicting `/DIR` is refused. `UsePreviousAppDir=no` prevents stale uninstall registration
from overriding that contract. Configuration, TLS, credentials and existing host keys must already be provisioned securely. No unrelated service is adopted.
An existing service must use the managed link and identical configured arguments/account, its previous release must verify and open the data,
and the new release must have no pending migration. Its **previous executable** creates and verifies the predeployment backup before any stop.
Retained managed releases require the same rollback proof even if the service registration is missing; `FirstInstall` does not bypass it.
The existing deployment journal, lock, graceful stop, expected listener PID/version/commit readiness and rollback/recovery rules then apply.
Installer updates involving schema changes fail before stopping; they require a separately reviewed migration/recovery procedure.

### Interrupted Setup and recovery

Desktop status is under `app\.setup-state\journal.json`; each run has a unique private directory, immutable previous executable/manifest,
verified archive, hashed `recovery-tools` and unique journal checkpoints. The lock prevents concurrent transactions. A nonfinal journal blocks
another installation. Preserve the whole run and its package; do not delete it, edit hashes or retry Setup over its existing payload.
After inspecting the journal and closing the selected Desktop, use the recorded recovery tools and exact original paths:

```powershell
# Isolated acceptance fixture only; substitute the journal's reviewed run/root/data/package paths.
powershell -NoProfile -File '<run>\recovery-tools\Install-AuthLens.ps1' -Mode Desktop `
  -Package '<verified full release>' -InstallRoot '<program root>' -DataDirectory '<data>' -Recover -Yes
# Server: same reviewed configuration; privileged isolated SCM acceptance only.
powershell -NoProfile -File '<run>\recovery-tools\Install-AuthLens.ps1' -Mode Server -Recover `
  -ConfigFile '<config>' -InstallRoot '<configured Root>\app' -Yes
```

Desktop recovery verifies recorded paths, old hashes and unchanged schema, then restores/probes the old program. It does not overwrite keys,
TLS, configuration or data. Inno's own rollback can remove its new payload, so recovery tools and proof live outside that payload. Keep a separately
verified complete package available. Uninstall removes tracked Setup payloads/shortcuts/registry entries; Desktop program/recovery files and
Server managed releases/state, services and all persistent data are deliberately retained. Cleanup requires separate review.
Server uninstall now refuses while **any** canonical `AuthLens` service registration exists, including its normal `releases\current` binary path
outside `app`. A directory-prefix test cannot prove that the service is unrelated. Review `UninstallPlan`, verify backup/ownership and obtain
separate authorization for service removal. No automatic recursive data removal is offered.

## Local Service Manager

The release includes `Service-Manager.ps1` beside `server/`; the Server installer adds a local administration shortcut. It invokes the packaged
server binary directly, needs no SDK and opens no listener; only the network change restarts the service (through the installed deployment
tools). Without `-DataDirectory` it resolves the installation from Setup's verified registration (`HKLM\Software\AuthLens\Server` `ConfigFile`,
then its `DataDirectory` or `Root\data` and `ServiceName`), so custom roots and data directories are honored; previously the shortcut always used
`C:\ProgramData\AuthLens\data` (defect D-002). Select the exact data directory and executable explicitly when operating an older installation.
Network status and changes (options 8 and 9) need the Start-menu copy beside the installed tools. Key export/provisioning stays local-only; no browser export endpoint exists.

```powershell
$manager='C:\ProgramData\AuthLens\releases\current\Service-Manager.ps1'
$exe='C:\ProgramData\AuthLens\releases\current\server\AuthLens.Api.exe'
$data='C:\ProgramData\AuthLens\data'
& $manager -Action Status -DataDirectory $data -Executable $exe
# Elevated, explicit local operations. Export refuses an existing destination.
& $manager -Action ExportKey -DataDirectory $data -Executable $exe -Path 'D:\private-recovery\host-copy.key' -Yes
& $manager -Action VerifyKey -DataDirectory $data -Executable $exe -Path 'D:\private-recovery\host-copy.key' -Yes
# One-use codes are shown locally; never transcript or redirect these commands:
& $manager -Action ActivationCode -DataDirectory $data -Executable $exe -Yes
& $manager -Action RecoveryCode -DataDirectory $data -Executable $exe -Username 'existing-admin' -Yes
```

Known 2.0.0 limitation (defect D-005): `-Path` and the menu prompt need a complete file name, for example
`E:\AuthLens-recovery\AuthLens-DASH1-recovery.key`. A directory is refused with access denied and ends Service Manager; the Start-menu window
then closes. Each start runs one action. A guided export with verification, grouped menus and certificate and recovery workflows are planned in
WP19 and WP20 ([work packages](../validation/WORK_PACKAGES.md#fourth-round-service-manager-usability-and-tls-lifecycle-wp19-wp20)).

`CreateKey` is for an unconfigured installation only and never replaces a configured key. Export to separately secured recovery storage,
then verify that copy before enabling automatic backups. Protect the full key directory; keep host and recovery keys out of data/releases/Git.
`CreateKey` resolves the installed service's logon identity (Win32_Service `StartName`: virtual account, LocalService, NetworkService, local or
domain account, gMSA) and adds one explicit, non-inherited **Read** rule for it on the new key file only (no directory grant; LocalSystem needs
none); an unresolvable identity is refused and nothing is granted. `Status` also reports whether the service identity can read the key (elevated).
For an existing installation whose key predates this, run `& $manager -Action GrantKeyAccess -DataDirectory $data -Yes` (elevated; an optional
`-Path` must be the configured key). Deployment and restore keep granting the same read access through `Grant-ALAccess`. Status: Pester-verified on
a synthetic file ACL (LocalService SID); native service-identity read under SCM is acceptance 8.10.
Do not change the service identity, regenerate a live key or weaken ACLs to make a key operation succeed. Accounts activation/recovery uses the
existing one-use-code mechanism; a missing data directory or invalid administrator is refused. The browser can verify an entered recovery copy
only after administrator/current-password reauthentication, with a session-bound one-use proof and CSRF; it cannot export or create the host key.

## Privacy and secrets

- Never commit `deploy.local.json`, certificates, password files, API tokens, backup keys, `.slbak` backups, data directories or real SAP extracts;
  `.gitignore` covers `*.local.json`, `*.key`, `*.pfx`, `*.sqlite3`, `api-token` and `cert-password`.
- Real host names, addresses, user names and paths belong only in the host's configuration and in your SSH configuration (`~/.ssh/config`).
- The scripts print paths, addresses, versions and commits, never a password, token or key. Server logs record method, path and peer, never
  headers, cookies or tokens.
- Before pushing: `python scripts/check-secrets.py` (tracked files) and `git diff --check`.

## Acceptance checklist (Windows, pending)

**Status: partial.** Native nonprivileged evidence is recorded in [release status](../validation/STATUS.md). This operator checklist still
requires isolated elevated SCM, compiled installer and interactive WebView2 acceptance. Record each result; no production acceptance is implied.

Ground rules: an elevated **Windows PowerShell 5.1** prompt in a clean checkout of `experiment/dotnet-backend`; synthetic data first, a real backup
only as a **copy** in an isolated root; existing installations, their folders, ports, certificates and
firewall rules are never stopped, changed or reused. Keep the evidence files of each step under `C:\AuthLens\acceptance\<run directory name>`
(no secrets, codes, passwords or keys in them).

### 0. Baseline of the existing installations (read only)

```powershell
$ev = 'C:\AuthLens\acceptance\<run directory name>'
New-Item -ItemType Directory -Force $ev | Out-Null
Get-CimInstance Win32_Service | Where-Object Name -eq 'AuthLens' |
  Select-Object Name, DisplayName, State, StartMode, StartName, PathName | ConvertTo-Json | Set-Content "$ev\00-services-before.json"
Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess | Sort-Object LocalPort | Out-File "$ev\00-ports-before.txt"
```

For a fresh install, stop if the intended service/root already exists. For an update, preserve the captured service and data baseline. Use a separate free port and supported isolated identity for acceptance.

### 1. Release build, verification and installers

```powershell
git status --short; git rev-parse HEAD                                      # clean, expected commit
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)
$run = '<C:\AuthLens\AuthLens-2.0.0-... run directory printed as "Summary: passed | ...">'
$release = (Get-ChildItem "$run\build" -Directory -Filter 'AuthLens-*-win-x64').FullName
& .\backend\scripts\verify-release.ps1 -ReleasePath $release *>&1 | Tee-Object "$ev\01-verify.txt"
Get-ChildItem "$release\server", "$release\desktop", "$run\installer" | Select-Object Name, Length | Out-File "$ev\01-files.txt"
```

Pass: `Release verified` for win-x64; `server\AuthLens.Api.exe` and `desktop\AuthLens.exe` exist; manifest product `AuthLens`, version
`2.0.0`; `AuthLens-2.0.0-Setup.exe` and `AuthLens-Server-2.0.0-Setup.exe` are produced.

### 2. Native test suites

```powershell
Invoke-Pester .\backend\scripts\tests -Output Detailed *>&1 | Tee-Object "$ev\02-pester.txt"   # includes the Windows-only ACL, junction and native tests
dotnet test .\backend\tests\AuthLens.Tests -c Release *>&1 | Tee-Object "$ev\02-dotnet.txt"
```

Pass: no failures. The native ACL restore round trip needs elevation; record any skip with its reason.

### 3. Fresh installation (canonical service and root)

Create `C:\ProgramData\AuthLens\config\deploy.json` from `deploy.example.json` with `Root` `C:\ProgramData\AuthLens`, this checkout as
`RepositoryPath`, the VM's own address as `ListenAddress`, the free port, `AllowedHosts` with that address (and a test host name). Put a TLS
certificate for that name in `C:\ProgramData\AuthLens\tls` (`server.pfx`, `cert-password`; see
[certificates](SERVER_NETWORK_ACCESS.md#1-hosting-boundary)).

```powershell
$entry = '.\backend\scripts\deploy\Deploy-AuthLens.ps1'; $config = 'C:\ProgramData\AuthLens\config\deploy.json'
& $entry -Action Deploy -FirstInstall -ConfigFile $config -DryRun                      # plan only
& $entry -Action Deploy -FirstInstall -ConfigFile $config -Tests focused -Yes *>&1 | Tee-Object "$ev\03-install.txt"
& $entry -Action Status -ConfigFile $config | Tee-Object "$ev\03-status.txt"
& $entry -Action AuditAcl -ConfigFile $config | Tee-Object "$ev\03-acl.txt"; "exit $LASTEXITCODE"
Get-CimInstance Win32_Service -Filter "Name='AuthLens'" | Select-Object Name, DisplayName, State, StartMode, StartName, PathName | Format-List
Get-ChildItem C:\ProgramData\AuthLens, C:\ProgramData\AuthLens\data | Select-Object FullName
foreach ($d in 'data','tls','keys','backups\predeploy','deployment','releases','config') { icacls "C:\ProgramData\AuthLens\$d" } | Out-File "$ev\03-icacls.txt"
Invoke-WebRequest -UseBasicParsing "https://<host>:<port>/health/ready" | Select-Object StatusCode, Content
```

Pass:

| Check | Expected |
| --- | --- |
| Service | Name `AuthLens`, DisplayName `AuthLens`, `Auto` start, `NT SERVICE\AuthLens`, running `C:\ProgramData\AuthLens\releases\current\server\AuthLens.Api.exe` |
| Layout | `releases`, `data`, `config`, `tls`, `keys`, `backups\predeploy`, `deployment` under `C:\ProgramData\AuthLens` |
| Database | `data\authlens.sqlite3` (plus `-wal`/`-shm`), `/health/ready` 200 |
| ACLs | `AuditAcl` exit 0; root protected (SYSTEM, Administrators); service modify on `data`, read on `tls` and `keys`, read/execute on `releases`; no Users/Authenticated Users write anywhere and no read on private folders or `config` |
| TLS and network | HTTPS on the configured address and port only; an unlisted host name is refused; unrelated ports are unchanged |

### 4. Service lifecycle

```powershell
Restart-Service AuthLens; (Get-Service AuthLens).Status
Get-Content C:\ProgramData\AuthLens\data\logs\server-*.log -Tail 20     # graceful stop, then start and ready
Restart-Computer                                                       # then, after sign-in:
(Get-Service AuthLens).Status; Invoke-WebRequest -UseBasicParsing "https://<host>:<port>/health/ready"
```

Pass: stop is graceful (log shows shutdown, no integrity warning), the service starts automatically after a reboot and is ready.

### 5. Backup and restore (synthetic first)

On the fresh installation: activate the first administrator, import the synthetic CSVs from `examples\`, create a manual backup in
Settings > Backup & Restore, download it and export the recovery key (Service Manager). Then:

```powershell
& $entry -Action Restore -ConfigFile $config -Backup <synthetic AuthLens.slbak> -KeyFile <exported.key> -Yes; "exit $LASTEXITCODE"
& $entry -Action Restore -ConfigFile $config -Backup <verified AuthLens .slbak copy> -KeyFile <recovery key copy> -Yes; "exit $LASTEXITCODE"
Get-ChildItem C:\ProgramData\AuthLens\data -Filter *.sqlite3; Get-ChildItem C:\ProgramData\AuthLens\data\backups\archives -Filter 'destination-*'
```

Pass: exit 0; `authlens.sqlite3` only; a `destination-*` recovery backup of the replaced data; users, roles, account reviews, SoD decisions,
saved filters and settings match the source; Data Health shows no integrity finding; `/health/ready` 200. Source paths of the source host may
not exist here: the imported records are still present, and a refresh reports such a source as failed without replacing its data.

Failure cases (each must leave the current data unchanged and no `data\restore\pending.json`):

| Case | How | Expected |
| --- | --- | --- |
| Wrong key | `-KeyFile` of another installation | Refused, exit 1 or 2 |
| Missing key | No `-KeyFile`, key not configured | Refused |
| Corrupted backup | A copy with one changed byte | Refused before staging |
| Newer schema | Covered by `ApplicationBackupTests` on Linux; not reproducible with a real archive | — |
| Interrupted restore | `Stop-Service AuthLens` right after the restore stage, then `Start-Service` | Applied or rolled back as a whole |
| Existing data | Restore over the installation that already has data | Recovery backup first, then replaced |

### 6. Updates, rollback and earlier products

```powershell
& $entry -Action Deploy -ConfigFile $config -Tests focused -Yes          # a newer commit
& $entry -Action Rollback -ConfigFile $config -Yes
Get-CimInstance Win32_Service | Where-Object Name -eq 'AuthLens' |
  Select-Object Name, DisplayName, State, StartMode, StartName, PathName | ConvertTo-Json | Set-Content "$ev\06-services-after.json"
Compare-Object (Get-Content "$ev\00-services-before.json") (Get-Content "$ev\06-services-after.json")    # no output
```

Pass: data kept across update and rollback; unrelated installations are unchanged.

### 7. Installers and Desktop

Use a disposable VM/user without an existing AuthLens installer registration. Compile approved packages first; the following is an operator
acceptance procedure, **not executed compiled-Setup evidence**. Use new fixture paths and an explicitly isolated service name/account/port.
The Server configuration must already specify the fixture root, private data/TLS/key locations and equivalent service arguments; never use a
legacy configuration or production service. Root security preparation does not create or replace certificates, keys or credentials.

```powershell
$fixture = 'C:\AuthLens\server-test\installer-' + [guid]::NewGuid().ToString('N')
$program = Join-Path $fixture 'desktop-program'
$data = Join-Path $fixture 'desktop-data'
$serverRoot = Join-Path $fixture 'server'
# Substitute the reviewed private configuration and freshly compiled Setup executable paths.
$serverConfig = '<absolute isolated deployment config>'
$desktopSetup = '<absolute Desktop Setup.exe>'
$serverSetup = '<absolute Server Setup.exe>'
$desktopArgs = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="{0}"' -f $program),('/DATADIR="{0}"' -f $data))
(Start-Process -FilePath $desktopSetup -ArgumentList $desktopArgs -WindowStyle Hidden -Wait -PassThru).ExitCode
$serverArgs = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="{0}\app"' -f $serverRoot),('/CONFIGFILE="{0}"' -f $serverConfig))
(Start-Process -FilePath $serverSetup -ArgumentList $serverArgs -WindowStyle Hidden -Wait -PassThru).ExitCode
# Read the exact selected fixture; Desktop GUI readiness was already checked by Setup's owned probe.
Get-Content (Join-Path $program '.setup-state\journal.json') -Raw
Get-ChildItem $data -Force
```

Pass: both Setup exit codes are 0; Desktop journal is complete; the configured isolated service is ready with the expected identity and listener
PID. AuthLens services, folders and installer registrations are unchanged. Launch the fixture Desktop shortcut and verify its selected data
directory, window, synthetic imports and CSV/PDF/DOCX/backup downloads. Explicit data profiles log under `<data>\.desktop\logs`.

Provision a synthetic private host key/recovery copy before testing updates. Use a **different verified build/package name** with the same schema;
repeat Setup against the same fixture and configuration. Verify the protective archive, retained old executable/release, unchanged configuration,
key/TLS hashes and business records. Exercise controlled candidate readiness failure and interrupted recovery in this disposable fixture only;
verify the old version actually becomes ready, and test refusal for corrupt recovery proof or a changed schema. Use the
[recorded recovery procedure](#interrupted-setup-and-recovery), never overwrite the old payload or recovery artifacts to retry. Schema-changing
updates are refused before replacement/service stop. Re-running the identical Setup payload is also refused, preserving incomplete evidence.

Uninstall removes tracked Setup payloads, shortcuts and registry entries; Desktop executable/recovery files, Server releases/state/services and
all persistent data remain for separate reviewed cleanup. Do not use uninstall as rollback. Compiled Setup execution, native SCM and interactive
WebView2 acceptance remain pending until the operator records those results.

### 8. Server sources, recovery-key service access and Reviews (2.0.0 remediation)

Run on a disposable installation from step 3, never on DASH1. Use synthetic CSVs (`backend/tests/AuthLens.Tests` fixtures or the CSV schemas)
in a dedicated export folder such as `C:\AuthLens\server-test\sources` and, for UNC, a share on the same server
(`\\<host>\authlens-src`) and one on a second server. Grant the actual service identity (`NT SERVICE\AuthLens`, or for remote shares the
computer account `DOMAIN\HOST$`; for custom/managed service accounts that account) **read** on the share and NTFS folder only. Record
dataset counts/fingerprints and SoD period checksums before every failure step.

| # | Scenario | Procedure | Expected | Evidence |
| --- | --- | --- | --- | --- |
| 8.1 | Source authority folder | After install: `icacls (Join-Path (Split-Path C:\ProgramData\AuthLens\data) '.authlens-source-policy-*')` | Protected; SYSTEM, Administrators and service identity Modify only; no data inside the backup set | `08-authority-acl.txt` |
| 8.2 | Local file, each source, Static and Dynamic | Settings → Data Sources → source → **Local server file** → path → authorize checkbox → **Test connection and validate source** → **Activate validated source** | Validation reports record count without activating; activation imports; status `Authorization: … exact file` | Screenshot + `/api/server/sources/<src>` JSON |
| 8.3 | Same-server and remote UNC | As 8.2 with **Network file (UNC)** and both shares; no mapped drive, no interactive session | Reads succeed as the service identity; `\\host\c$\…` and `\\host@SSL\…` are refused before any SMB traffic | Packet capture or SMB server audit showing no request for refused targets |
| 8.4 | Dynamic and Global Refresh | Change the CSV, run individual refresh, then Global Refresh | Changes appear only after validation; Static sources are skipped | Refresh history export |
| 8.5 | Denied and unavailable | Remove the service identity's NTFS read; then disconnect the share; then make the CSV empty/malformed | Each refresh fails with `access_denied` / `missing` or `network_unavailable` / validation error; snapshot counts unchanged | Refresh history + counts before/after |
| 8.6 | Revocation | **Revoke authorization**, then refresh | `policy_prohibited`; path, mode and snapshot retained; status `required` | `/api/server/sources/<src>` JSON |
| 8.7 | Restart and reboot | `Restart-Service AuthLens`; then reboot | Dynamic configuration and exact authority persist; refresh succeeds without browser uploads | Status JSON after each |
| 8.8 | Restore to a fresh instance | Encrypted backup → restore into a second disposable instance | Paths, modes and snapshots restored; status `required` until re-authorized on the destination; nothing read before that | Status JSON + refresh history |
| 8.9 | Recovery key under the service identity | Create a key with the server CLI (`AuthLens.Api.exe --backup-key create <file> --data-dir <data>`, which grants nothing) as administrator, then Service Manager `Status` | Backup Overview shows **Configured but inaccessible** (`state: inaccessible`), not "Not configured"; key material and path absent from API/logs | `/api/backups` `key_provider` JSON, log grep |
| 8.10 | Recovery key provisioning | `Service-Manager.ps1 -Action GrantKeyAccess -Yes` (or a fresh `CreateKey` after installation); `icacls` shows one explicit read for the service identity only; restart; verify recovery copy | `state: usable`, then `escrow_verified: true`; upgrade/repair keep the key and ACL | `icacls` of key file before/after upgrade |
| 8.11 | Reviews navigation | Sign in as Administrator and as Reviewer; open Reviews, each page, legacy `#/sod/reviews`, `#/sod/periods`, `#/sod/reports` bookmarks; turn SoD off and confirm Reviews keeps the Overview with Account reviews | Reviews visible for both; Bulk Review entry only with `review`; admin period operations hidden for Reviewer; legacy links land on Reviews | Screenshots light/dark at 375/1280 px |
| 8.12 | Filtering and evidence integrity | Filter by Functional Group, Manager and exact usernames on Dashboard, User Access, Reviews and a frozen period; open **Open in Reviews** | Same scope at destination; frozen period checksum (`/api/sod/periods/<id>`) unchanged | Checksums before/after |

| 8.13 | Certificate replacement | `Deploy-AuthLens.ps1 -Action ReplaceCertificate … -DryRun`, then `-Yes`; repeat with a certificate lacking the configured host SAN | Dry run changes nothing; replacement restarts on the new certificate (pinned readiness); the invalid certificate is refused before any change; a forced readiness failure restores the previous certificate | `operation-result.json`, `icacls` of the new TLS folder, `certificate-pending.json` absent |
| 8.15 | Network configuration change | Service Manager option 9 (or `-Action ChangeNetwork`): add an allowed host; change the port with a firewall decision; propose an address not on the machine and a host the certificate lacks; force a readiness failure (occupy the new port after validation) | Summary shown before `YES`; valid changes restart and answer on the new listener; invalid proposals refused before any change; readiness failure restores the previous configuration; `configuration_change_pending: false` | Service Manager output, `Status` JSON before/after, `Get-NetFirewallRule` |
| 8.14 | Setup review and progress | Run the Server wizard (fresh and upgrade) to the Ready page and through installation | Ready page lists storage, access mode, listener, hosts, certificate, firewall, service name/identity and (fresh) the post-install steps; Installing page explains the running transaction | Screenshots |

Failure in 8.3, 8.5, 8.8, 8.9, 8.10, 8.13 or 8.15 is a release blocker. Recovery: restore the pre-step backup of the disposable instance; never edit the
authority file by hand (it is HMAC-bound to the host token and data path and fails closed when modified).

## Post-installation infrastructure verification

Active tooling resolves the current checkout under `backend/`; only the historical
commit resolver recognizes `experiments/dotnet-backend` for older releases. No
service executable path, installed release, data directory, TLS setting, recovery
key or service name is changed by this infrastructure stabilization. Existing
semantic service-command comparison, manifest hashes, verified backup before
replacement and rollback gates remain in place. Frontend and backend now share
`backend/product-version.json`; no product version was incremented.

Safe native follow-up commands from the repository root (no service operations):

```powershell
git switch experiment/dotnet-backend
git pull --ff-only origin experiment/dotnet-backend
node scripts/product-version.mjs
powershell -NoProfile -File .\backend\scripts\check-powershell.ps1
powershell -NoProfile -Command "Import-Module Pester -MinimumVersion 5.7.1; Invoke-Pester -Path backend/scripts/tests -CI"
dotnet build backend/AuthLens.slnx -c Release
dotnet test backend/tests/AuthLens.Tests -c Release --no-build --filter "FullyQualifiedName~StartupTests|FullyQualifiedName~NetworkTests|FullyQualifiedName~ReverseProxyTests|FullyQualifiedName~DesktopLocationTests|FullyQualifiedName~InstallerTests|FullyQualifiedName~VersioningTests"
```

Pester requires version 5.7.1 or newer (Windows continuation used 5.9.1; `Install-Module Pester -RequiredVersion 5.9.1 -Scope
CurrentUser` through the approved repository, if not already available). Respect
corporate signing/execution policy; do not disable WDAC or bypass script policy.
These checks do not certify native service restart, Desktop/WebView2, installer,
ACL/firewall, backup recovery or real-data migration acceptance. Those remain the
separate existing checklist above, and must use disposable installations/data.
The running service and all existing release/backup directories must stay untouched.

The complete browser checkpoint for this development round is **DEFERRED** by explicit instruction. Preserve its interrupted partial log; it
does not establish a pass. Continue with focused checks only. A new consolidated full regression requires implementation completion and explicit
approval; CI configuration and the browser tests remain unchanged.


### Isolated Desktop acceptance resources

An explicit `AuthLens.exe --data-dir <absolute fresh fixture> --self-check` now places logs and WebView2 runtime files under `<fixture>/.desktop` and derives its mutex from that data directory. It neither shares the normal Desktop mutex/profile nor writes into earlier product folders. The default Desktop path and mutex stay unchanged, including when that exact default data path is passed explicitly. Relative/empty/drive-root/linked paths and earlier product profiles are refused before log creation. Use a new GUID fixture, never a directory selected because its name sounds disposable. Self-check verifies the private loopback host and embedded UI without a window; it does not prove WebView2 interactions, downloads or installer acceptance.

The publish acceptance tests now run the single-file Server smoke workflow on Windows as well as Linux, and a Windows-only Desktop `--self-check` against a fresh temporary data directory. These checks never register an SCM service. Startup deadline tests run in the existing nonparallel process collection because they clear global SQLite pools and must not compete with unrelated host/build fixtures; their deadlines are unchanged. Final execution results are recorded in [release status](../validation/STATUS.md).

## Canonical Windows build

### Installer reliability remediation: local readiness

The `8ec7f77` fresh-install report exposed a deployment-probe defect: `Get-ALServiceArguments` correctly
omitted `--network` for loopback, but `Invoke-ALConfiguredHttp` selected a corporate AllowedHosts value.
The runtime intentionally accepts only loopback authorities without network access (`HostSettings.HostAllowed`
and `RequestBoundary`); its HTTP 421 rejection is correct. Probes now use the loopback literal for local-only
bindings and a configured allowed authority for a specific LAN binding. Unknown hosts remain rejected.
Wildcard listeners are refused before probing, consistent with the runtime's specific-private-interface policy.

The local probe now requires the exact configured TLS leaf certificate and current validity. A request-local
CLR callback compares the received certificate bytes to the configured PFX's public certificate; the password
stays in its protected file and the key is loaded ephemerally. No unrestricted certificate-validation callback,
redirect, default credentials, system proxy or global certificate bypass is used. TLS 1.2 is selected for the
synchronous probe and the prior PowerShell process protocol setting is restored afterward. This proves local
backend certificate identity, not corporate DNS/client trust or external reachability. Those remain separate
acceptance checks. Deterministic HTTP 400/401/403/404/421 and TLS trust failures stop readiness immediately;
startup/503 conditions retain the bounded readiness wait. Listener PID, product version and full SHA checks remain.

Focused PowerShell coverage exercises the reported local/corporate-host mismatch, LAN and IPv6 authorities,
wildcard refusal, immediate policy failure and exact/changed/expired certificate identity. Native HTTPS and
installer acceptance are pending; this change has not been applied to the live server or packaged in a new release.

### Installation state and program quarantine

The read-only `Install-AuthLens.ps1 -Mode Server -Operation InspectState` classifies the selected normalized
configuration as a clean program target, an owned installation still requiring readiness verification,
an actual interrupted deployment, protected application data, verified failed Setup artifacts, or unknown/
ambiguous state. Legacy presence is reported separately without adoption or changes. An expected journal
path alone never establishes a transaction. Unknown state and protected data have no cleanup action.

For a **verified pre-deployment failure only**, inspection may advertise `quarantine_program`. Supply the
original Package, SetupMetadataFile and FailedPreflightReceipt to inspection; exact package, metadata,
helper, ownership and diagnostic hashes must pass the existing Setup planner. Old failures without a valid
receipt, changed uninstall data, running services/listeners, actual deployment journals or populated data/
release/work storage refuse quarantine. A post-start failure such as the reported running service/database
case requires recovery, never program cleanup.

After reviewing the exact source and destination on a disposable acceptance VM, the supported CLI action is:

```powershell
# Replace every placeholder with the reviewed paths. Inspect first; -Yes explicitly authorizes the move.
powershell.exe -NoProfile -NonInteractive -File '<reviewed-tools>\Install-AuthLens.ps1' `
  -Mode Server -Operation QuarantineFailedSetup -ConfigFile '<selected-config.json>' `
  -Package '<original-staged-package>' -SetupMetadataFile '<original-setup-metadata.ini>' `
  -FailedPreflightReceipt '<original-preflight-failure.json>' `
  -EvidenceDirectory 'C:\AuthLens-Recovery\NEW-OPERATION' -Yes
```

The evidence directory must be new, separate, on the same volume and beneath an existing administrator-only
parent. The host deployment mutex serializes the action without populating a fresh WorkRoot. Before the
atomic `Root\app` move, a private intent record saves every program-file hash. The fixed source and target
are validated as disjoint from data, backups, configuration, certificates and keys. Nothing is deleted or
merged. Interrupted intent can resume with the same evidence directory; completed intent is idempotent
only while every retained hash and the unchanged configuration still verify. Unknown/tampered evidence
refuses. Program files are re-inventoried after the move and the source must remain absent.

Registry entries are **not deleted**. A retained pending-verification Inno entry is recovery evidence and
remains explicitly incomplete until a successful supported Setup retry. Native same-AppId retry behavior
after quarantine is awaiting acceptance; it is not yet certified to eliminate every manual registration
review. Existing populated installations and unproved historical remnants are never forced through this path.

### State-aware deployment recovery

`manual_recovery_required` is now a recovery barrier for status, Setup, repair, uninstall and subsequent
deployment. It is not a successful terminal state. Recovery instructions record the observed service state
and distinguish an absent backup/previous release from a retained but still-to-be-reverified prerequisite.
They no longer claim a running service was stopped or suggest moving live data for an unproved rollback.

Use `Deploy-AuthLens.ps1 -Action Recover -RecoveryAction <choice> -ConfigFile <reviewed-config> -Yes`, or
the same `-RecoveryAction` with `Install-AuthLens.ps1 -Mode Server -Recover -Yes`:

| Choice | Supported boundary |
| --- | --- |
| `VerifyCandidate` | Revalidates an already running owned candidate and the original transaction identity; no service start or data restore |
| `Resume` | Same checks, with explicit permission to start an existing stopped owned candidate |
| `Rollback` | Requires a retained verified previous package, unchanged verified encrypted backup, and current-schema compatibility |
| `Cancel` | Only at prepared/backup checkpoints with unchanged service/release identity; retains all data and evidence |
| `Auto` | Preserves interrupted-update recovery; a fresh interrupted candidate must prove fix-forward invariants rather than inventing a previous release |

Candidate validation proves the unchanged configuration/arguments, private ACL plan, exact published package
and pointer, original version/SHA, retained fresh-data ownership marker, read-only TLS/key/database/schema
preflight with no pending migrations, listener PID and exact HTTPS runtime identity. Configuration is compared
again before completion. Failed checks retain the manual-recovery barrier. A successful fresh installer
revalidation writes its installed-product receipt from the existing instance identity. It does not fabricate
an Inno success callback, rotate keys, restore data or silently repair partial registry entries.

An absent service, missing/invalid data marker, changed package, incompatible schema, absent rollback backup
or ambiguous identity remains a refusal. Fix-forward of older packages still requires the configured host
key for read-only preflight; administrator key readability alone is not proof of service key usability.
Recovery-key provisioning and native service backup/restore acceptance are separate mandatory gates. Native
SCM and Inno recovery acceptance are pending; the live failed installation has not been modified.

### Reconciling an interrupted first installation that was corrected manually

Status: procedure prepared from source inspection and a read-only self-test of R1 on VM130; not yet executed on the affected host.

Case (DASH1, 2026-11-24): a fresh Setup of a `8ec7f77` package installed and started the service, then readiness failed (HTTP 421) and the
journal stopped at `manual_recovery_required` with no previous release and no pre-deployment backup. An operator then corrected the listener
and service arguments by hand and restored data. The service is ready, but the journal still blocks Setup, repair and later deployments.

Root cause: in `8ec7f77` the readiness probe used the first configured allowed host as the Host authority even for a loopback listener, and
that build had no access-mode consistency rules, so a loopback listener with corporate allowed hosts was accepted by preflight and refused only
by the started service (421 misdirected request). Current sources probe a loopback listener with its own address and Setup-authored
configurations carry an explicit access mode whose rules refuse that combination (`Get-ALServerAccessPlan`); configurations without
`AccessMode` (Auto) still are not checked for that combination.

`8ec7f77` treats `manual_recovery_required` as final and has no `-RecoveryAction`, so its own staged tools cannot reconcile. Use the
hash-verified packaged tools of a newer verified candidate (RC3-VM130 `19a1113`, copied unchanged to `C:\AuthLens\<run directory>`). They
reconcile the **installed** release in place with `-RecoveryAction VerifyCandidate`; they install nothing. Do not delete, rename or edit the
journal, and do not edit the Setup registry key.

| Batch | Changes | Purpose |
| --- | --- | --- |
| R1 | None (evidence folder only) | Every VerifyCandidate precondition plus the additional checks below, as one unit; any failure stops |
| R2 | A new encrypted backup in `BackupRoot` | Recoverable copy of the current data, verified, before the journal changes |
| R3 | The journal phase (history appended) and `config\installed-product.json` | `Install-AuthLens.ps1 -Mode Server -Recover -RecoveryAction VerifyCandidate`; the running service is not stopped or restarted |
| R4 | None | Journal `complete`, history preserved, Status `recovery_needed: false`, read-only upgrade preflight |

R1 checks: RC3 tool inventory and helper hashes; journal run, commit, version, phase and history (copied to evidence); no repair, uninstall,
firewall or configuration pending operation; active release pointer equals the journal's `to_release`, inside `ReleasesRoot`, published-release
verification and manifest identity; service exists, runs as the configured identity, and its command line equals the configuration; the
service process owns the listener; access plan and probe authority; NTFS audit; the data-ownership marker written by the original fresh
install; the installed release's read-only `--server-preflight` (TLS, key, database integrity, schema, no pending migrations); HTTPS readiness
and runtime identity pinned to the configured certificate; key status, newest backups, installed-product receipt and Setup registration
(informational).

```powershell
# DASH1 reconciliation, batch R1: read-only precondition check for Recover -RecoveryAction VerifyCandidate. Changes nothing on the installation.
$rc3       = 'C:\AuthLens\AuthLens-2.0.0-2026-11-24_2021-19a1113'      # RC3-VM130 run directory copied unchanged to DASH1 (only its packaged tools are used)
$config    = 'C:\ProgramData\AuthLens\config\deploy.json'               # DASH1 deployment configuration
$evidence  = 'C:\AuthLens\acceptance\DASH1-reconcile-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force $evidence | Out-Null
& {
  $ErrorActionPreference = 'Stop'
  $journalRun    = '20261124-101158-installer-840e61e7'
  $journalCommit = '8ec7f77b35b23d8c295e119bc6e4128b0681f67d'
  $toolsInventorySha = '41ed60a8df9e711ece1bd98d33e1c2c7685e0422c07f7d7d51eced9f3fa40ff5'   # RC3 installer-tools.json
  $results = [Collections.Generic.List[object]]::new()
  function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) { $results.Add([pscustomobject]@{ check = $Name; ok = $Ok; detail = $Detail }); '{0,-4} {1}: {2}' -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail }
  function Test-Step([string]$Name, [scriptblock]$Body) { try { $r = & $Body; Add-Check $Name ([bool]$r.ok) ([string]$r.detail) } catch { Add-Check $Name $false ("error: " + $_.Exception.Message) } }
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { throw 'STOP: run elevated.' }
  "DASH1 reconciliation R1 (read-only) on $env:COMPUTERNAME at $([DateTime]::UtcNow.ToString('o'))"

  # 1. RC3 packaged tools: exact inventory and helper hashes, before any of them is loaded.
  $toolsDirs = @(Get-ChildItem -LiteralPath (Join-Path $rc3 'installer') -Directory -Filter 'installer-tools-*')
  if ($toolsDirs.Count -ne 1) { throw "STOP: expected one installer-tools folder under $rc3\installer." }
  $tools = $toolsDirs[0].FullName
  if ((Get-FileHash -LiteralPath (Join-Path $tools 'installer-tools.json') -Algorithm SHA256).Hash.ToLower() -ne $toolsInventorySha) { throw 'STOP: installer-tools.json is not the RC3-VM130 inventory.' }
  foreach ($entry in @(([IO.File]::ReadAllText((Join-Path $tools 'installer-tools.json')) | ConvertFrom-Json).files)) {
    if ((Get-FileHash -LiteralPath (Join-Path $tools ($entry.path -replace '/', '\')) -Algorithm SHA256).Hash.ToLower() -ne $entry.sha256) { throw "STOP: packaged helper $($entry.path) differs from its inventory." }
  }
  'PASS tools: RC3 packaged helpers verified'
  Import-Module (Join-Path $tools 'deploy\AuthLens.Deploy.psm1') -Force
  $cfg = Read-AuthLensSettings $config
  "Configuration: context=$($cfg.ExecutionContext) root=$($cfg.Root) service=$($cfg.ServiceName) identity=$($cfg.ServiceAccount) listen=$($cfg.ListenAddress):$($cfg.Port) hosts=$(@($cfg.AllowedHosts).Count) proxies=$(@($cfg.TrustedProxies).Count) access_mode=$($cfg.AccessMode)"

  # 2. Journal identity and state (a copy is kept as evidence; the original is not touched).
  $journalPath = Get-ALJournalPath $cfg
  Copy-Item -LiteralPath $journalPath -Destination (Join-Path $evidence 'journal-before.json')
  $j = Read-ALJournal $cfg
  Test-Step 'journal identity' { @{ ok = ($j.run -eq $journalRun -and $j.commit -eq $journalCommit -and $j.version -eq '2.0.0'); detail = "run=$($j.run) commit=$($j.commit) version=$($j.version)" } }
  Test-Step 'journal state' { @{ ok = ($j.phase -eq 'manual_recovery_required' -and -not $j.from_release -and -not $j.service_binary_before -and $j.service_state_before -eq 'Missing'); detail = "phase=$($j.phase) from_release='$($j.from_release)' service_before=$($j.service_state_before) backup=$(if ($j.backup) { 'present' } else { 'none' }) history=$((@($j.history) | ForEach-Object { $_.phase }) -join '>')" } }

  # 3. No competing operation.
  Test-Step 'no pending operations' {
    $markers = @('repair-pending.json', 'uninstall-pending.json', 'firewall-pending.json', 'configuration-pending.json', 'certificate-pending.json') | Where-Object { Test-Path -LiteralPath (Join-Path $cfg.WorkRoot $_) }
    $fw = Test-ALInstallerFirewallRecoveryNeeded $cfg
    @{ ok = (-not $markers -and -not $fw); detail = "markers=$($markers -join ',') firewall_recovery=$fw" } }

  # 4. Active release target, manifest and artifact integrity.
  Test-Step 'active release' {
    $current = Get-ALLink (Get-ALCurrentLink $cfg); $target = [IO.Path]::GetFullPath([string]$j.to_release)
    $m = Get-Content -LiteralPath (Join-AL $target 'build-manifest.json') -Raw | ConvertFrom-Json
    $verified = (Test-ALPublishedRelease $target).Verified
    @{ ok = ($current -ieq $target -and (Test-ALPathWithin $target $cfg.ReleasesRoot) -and $verified -and $m.product -ceq 'AuthLens' -and $m.source_sha -ceq $journalCommit -and $m.version -ceq '2.0.0'); detail = "current=$current to_release=$target verified=$verified manifest=$($m.version) $($m.source_sha)" } }

  # 5. Windows service: identity, managed command line and listener ownership.
  $svc = Get-ALService $cfg.ServiceName
  Test-Step 'service' { @{ ok = ($svc.Exists -and $svc.State -eq 'Running' -and $svc.Account -ieq $cfg.ServiceAccount -and (Test-ALServiceBinary $svc.PathName $cfg)); detail = "exists=$($svc.Exists) state=$($svc.State) account=$($svc.Account) command_line_matches_config=$(Test-ALServiceBinary $svc.PathName $cfg)" } }
  Test-Step 'listener ownership' { $pids = @(Get-ALListener $cfg.ListenAddress ([int]$cfg.Port)); @{ ok = ($pids.Count -ge 1 -and @($pids | Where-Object { $_ -ne $svc.ProcessId }).Count -eq 0); detail = "listener pids=$($pids -join ',') service pid=$($svc.ProcessId)" } }

  # 6. Network access mode and the host boundary the readiness probe will use.
  Test-Step 'access mode' { $a = Get-ALServerAccessPlan $cfg; @{ ok = $true; detail = "mode=$($a.access_mode) network=$($a.network_access) probe_authority=$($a.probe_authority) (Auto = configuration without AccessMode; rules are not enforced in Auto)" } }

  # 7. NTFS: no broad access to private state; required SYSTEM/Administrators access.
  Test-Step 'ACL audit' { $r = Get-ALAclReport (Get-ALAclPlan $cfg); @{ ok = [bool]$r.safe; detail = $(if ($r.safe) { 'safe' } else { Format-ALAclFindings $r }) } }

  # 8. Data ownership evidence written by the original fresh install (required: data is never adopted).
  Test-Step 'data ownership marker' {
    $marker = Join-AL $cfg.DataDirectory '.authlens-owned-data.json'
    if (-not (Test-Path -LiteralPath $marker)) { return @{ ok = $false; detail = 'missing (VerifyCandidate refuses; see gap G-006 in the tracker)' } }
    $o = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    @{ ok = ($o.schema -eq 1 -and $o.product -ceq 'AuthLens' -and $o.root -ieq $cfg.Root -and $o.data_directory -ieq $cfg.DataDirectory -and $o.instance_id -match '^[a-f0-9]{32}$'); detail = "root=$($o.root) data=$($o.data_directory) instance=$($o.instance_id)" } }

  # 9. Read-only TLS, key and database/schema proof by the installed release itself (the same probe VerifyCandidate uses).
  $exe = Join-AL ([IO.Path]::GetFullPath([string]$j.to_release)) 'server\AuthLens.Api.exe'
  Test-Step 'server preflight' {
    $p = Invoke-ALMaintenance $exe (@('--server-preflight') + @(Get-ALServiceArguments $cfg))
    @{ ok = ($p.validated -and $p.read_only -and $p.data_modified -eq $false -and $p.source_sha -ceq $journalCommit -and $p.version -ceq '2.0.0' -and $p.schema.compatible -and @($p.schema.pending).Count -eq 0); detail = "validated=$($p.validated) read_only=$($p.read_only) data_modified=$($p.data_modified) schema_compatible=$($p.schema.compatible) pending=$(@($p.schema.pending).Count) applied=$(@($p.schema.applied).Count)" } }

  # 10. Pinned HTTPS readiness and runtime identity (certificate pinned to the configured PFX).
  Test-Step 'pinned readiness' {
    $ready = Invoke-ALConfiguredHttp $cfg '/health/ready'; $id = Invoke-ALConfiguredHttp $cfg '/product-version.json'
    $identity = if ($id.Status -eq 200) { $id.Body | ConvertFrom-Json } else { $null }
    @{ ok = ($ready.Status -eq 200 -and $identity -and $identity.source_sha -ceq $journalCommit -and $identity.version -ceq '2.0.0'); detail = "ready=$($ready.Status) identity=$(if ($identity) { "$($identity.version) $($identity.source_sha)" } else { $id.Status })" } }

  # 11. Data protection (informational here; R2 requires a verified backup taken after these checks).
  try { $k = Invoke-ALMaintenance $exe @('--backup-key', 'status', '--data-dir', $cfg.DataDirectory); "INFO key status: $(($k | ConvertTo-Json -Compress -Depth 3) -replace '"fingerprint":"[0-9a-f]+"', '"fingerprint":"<recorded>"')" } catch { "INFO key status: unavailable ($($_.Exception.Message))" }
  $latest = Get-ChildItem -LiteralPath (Join-AL $cfg.DataDirectory 'backups') -Filter '*.slbak' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
  "INFO newest application backup: $(if ($latest) { "$($latest.Name) $($latest.LastWriteTimeUtc.ToString('o'))" } else { 'none' }); predeploy backups: $(@(Get-ChildItem -LiteralPath $cfg.BackupRoot -ErrorAction SilentlyContinue).Count)"
  "INFO installed-product.json present: $(Test-Path -LiteralPath (Join-AL (Join-AL $cfg.Root 'config') 'installed-product.json'))"
  $reg = try { Get-ItemProperty 'HKLM:\Software\AuthLens\Server' -ErrorAction Stop } catch { $null }
  "INFO Setup registration: $(if ($reg) { "SetupState=$($reg.PSObject.Properties['SetupState'].Value) ConfigFile=$([bool]$reg.PSObject.Properties['ConfigFile'])" } else { 'none' })"

  $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'R1-checks.json') -Encoding UTF8
  $failed = @($results | Where-Object { -not $_.ok })
  if ($failed.Count) { throw "STOP: $($failed.Count) precondition(s) failed: $(($failed.check) -join ', '). Do not run R2/R3; send this transcript." }
  'R1 RECONCILIATION PRECONDITIONS MET. Next: R2 (verified backup), then R3 (VerifyCandidate) with operator approval.'
} *>&1 | Tee-Object -FilePath (Join-Path $evidence 'R1-transcript.txt')
```

R2, R3 and R4 reuse `$rc3`, `$config` and set `$evidence` to the R1 evidence folder. Run each only after the previous one ended without `STOP`.

```powershell
# R2: verified encrypted backup of the current data with the installed release (the same commands a deployment runs before it stops anything).
& {
  $ErrorActionPreference = 'Stop'
  $tools = (Get-ChildItem -LiteralPath (Join-Path $rc3 'installer') -Directory -Filter 'installer-tools-*').FullName
  Import-Module (Join-Path $tools 'deploy\AuthLens.Deploy.psm1') -Force
  $cfg = Read-AuthLensSettings $config; $j = Read-ALJournal $cfg
  $exe = Join-AL ([IO.Path]::GetFullPath([string]$j.to_release)) 'server\AuthLens.Api.exe'
  $b = Invoke-ALMaintenance $exe @('--backup-local', $cfg.BackupRoot, '--data-dir', $cfg.DataDirectory)
  $v = Invoke-ALMaintenance $exe @('--backup-verify', $b.file, '--data-dir', $cfg.DataDirectory)
  if (-not $v.verified -or $v.sha256 -ne $b.sha256) { throw 'STOP: the backup could not be verified; do not continue.' }
  "R2 backup verified: $($b.file) sha256=$($b.sha256) size=$($b.size)"
} *>&1 | Tee-Object -FilePath (Join-Path $evidence 'R2-transcript.txt')

# R3: supported reconciliation (operator-approved). A refusal keeps manual_recovery_required and changes nothing else.
& {
  $ErrorActionPreference = 'Stop'
  $tools = (Get-ChildItem -LiteralPath (Join-Path $rc3 'installer') -Directory -Filter 'installer-tools-*').FullName
  $result = Join-Path $evidence 'R3-result.json'; $diagnostic = Join-Path $evidence 'R3-diagnostic.txt'
  $ErrorActionPreference = 'Continue'
  & (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $tools 'Install-AuthLens.ps1') -Mode Server -Recover -RecoveryAction VerifyCandidate -ConfigFile $config -ResultFile $result -DiagnosticFile $diagnostic -Yes
  $code = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
  "Install-AuthLens exit $code"; if (Test-Path -LiteralPath $result) { Get-Content -LiteralPath $result }
  if ($code -ne 0) { throw "STOP: VerifyCandidate refused (exit $code). The journal remains manual_recovery_required; send $result and $diagnostic." }
} *>&1 | Tee-Object -FilePath (Join-Path $evidence 'R3-transcript.txt')

# R4: read-only confirmation.
& {
  $ErrorActionPreference = 'Stop'
  $tools = (Get-ChildItem -LiteralPath (Join-Path $rc3 'installer') -Directory -Filter 'installer-tools-*').FullName
  Import-Module (Join-Path $tools 'deploy\AuthLens.Deploy.psm1') -Force
  $cfg = Read-AuthLensSettings $config; $j = Read-ALJournal $cfg
  "journal phase=$($j.phase) history=$((@($j.history) | ForEach-Object { $_.phase }) -join '>')"
  if ($j.phase -ne 'complete') { throw 'STOP: the journal is not complete.' }
  $s = Get-ALStatus $cfg
  "status ready=$($s.ready) recovery_needed=$($s.recovery_needed) managed=$($s.binary_path_matches) running=$($s.running_identity.version) $($s.running_identity.source_sha)"
  "installed-product.json present: $(Test-Path -LiteralPath (Join-AL (Join-AL $cfg.Root 'config') 'installed-product.json'))"
} *>&1 | Tee-Object -FilePath (Join-Path $evidence 'R4-transcript.txt')
```

If the data-ownership marker is missing (for example because data was copied back manually), VerifyCandidate refuses by design ("data is
never adopted"); that case is gap G-006 in the [acceptance tracker](../validation/ACCEPTANCE_TRACKER.md#defects-and-gaps) and has no supported
reconciliation yet. After R3 the Setup registry key still shows the pending-verification state written by the failed Setup (gap G-005); the
next successful Setup upgrade rewrites it. Do not edit it by hand.

If R1's `server preflight` check refuses the TLS certificate (for example a listener address added after the certificate was generated, defect
D-004), stop: R3 would refuse in the same check, and `ReplaceCertificate` and `ChangeNetwork` refuse while the journal requires recovery, so the
current tools offer no supported route (gap G-007). Do not activate a replacement certificate by overwriting the PFX or editing the configuration,
service command line or journal. A replacement can be proved read-only beforehand with the installed release's `--server-preflight` and the
proposed `--cert`/`--cert-password-file`; keep it in protected storage until a candidate with the G-007 correction can apply it inside recovery.

### Access-mode details

Deployment configuration accepts `AccessMode`: `Local`, `Corporate`, `ReverseProxy`, or compatibility
default `Auto` when omitted. Local requires loopback binding and loopback-only host values without proxy
trust. Corporate requires one specific private interface and explicit backend hosts without proxy fields;
it is the recommended choice for a shared Server, subject to explicit exposure/firewall review. ReverseProxy
requires a private backend interface, backend hosts, public proxy hosts and explicit trusted peers. All modes
use HTTPS in the installer. The packaged host remains the authority for TLS SAN/expiry/private-key checks,
proxy network/hop policy, schema and integrity. `Auto` preserves existing configuration semantics; it does
not add network access to loopback. Existing service command-line comparison remains semantic and unchanged.

`Install-AuthLens.ps1 -Mode Server -NetworkSuggestions` is read-only and requires no configuration or
package. It suggests local hostname/FQDN and active private interfaces, preferring a non-link-local IPv4
address. Suggestions do not prove DNS resolution or client trust and are not automatically approved.
Corporate DNS, client trust and reachability must be checked independently. The wizard bridge can request
the same suggestions through its private INI plan. Corporate exposure never implies a wildcard firewall
scope; literal reviewed source addresses/subnets remain mandatory.

**Runtime constraint:** the current server intentionally rejects all-interface binds and loopback network/
trusted-proxy mode. These inputs are refused, not silently mapped to a different interface. Offering an
all-IPv4 option or a loopback proxy backend remains blocked on an explicit runtime security design decision;
no host, Origin, forwarded-header or Desktop restriction was relaxed.

From a clean committed checkout, run `.\build.ps1`. Windows PowerShell 5.1 or PowerShell 7,
Git, .NET SDK 10, Node 24/25, npm, Python 3 and Inno Setup 6 are required. Use `-Iscc <absolute ISCC.exe>` for a nonstandard installation.
The entry point orchestrates the existing release builder, verifier, release secret scan and installer builder. It never installs software or
changes services. CI triggers, product version and runtime configuration are unchanged.

**Mandatory standard.** Every Windows build and release candidate uses this script with the output root `C:\AuthLens`:

```powershell
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)
```

| Rule | Value |
| --- | --- |
| Build entry point | Root-level `build.ps1` only; it orchestrates `build-release.ps1`, `verify-release.ps1`, the release secret scan, `build-installers.ps1` and branding verification. Do not run those directly for a candidate |
| Output root | `C:\AuthLens` (the default). No RC, acceptance, development or user-profile roots without explicit approval |
| Run directory | `C:\AuthLens\AuthLens-<version>-<UTC yyyy-MM-dd_HHmm>-<sha7>` (suffix `-02`, `-03` on a same-minute collision), containing `build\<release folder>`, `installer\`, `build-summary.json` (identity, tools, test filter and status, verification flags, relative artifact paths and hashes) and `build.log` |
| Standard tests | `-TestFilter (Get-ALTestFilter focused)`: the deployment focused classes; record any additional classes explicitly in the acceptance tracker. FULL runs only with approval |
| Acceptance evidence | `C:\AuthLens\acceptance\<run directory name>\` (beside, never inside, the run directory) |
| Installed Server | `C:\ProgramData\AuthLens` (unchanged) |
| Retention | Earlier run directories and their evidence are never overwritten, moved or deleted; a build moved from elsewhere keeps the canonical run-directory name derived from its `build-summary.json` identity |

`-SkipTests` exists for local packaging experiments only and never produces a candidate.

`-TestFilter` selects focused backend validation; the default release command runs the existing backend release test selection.
Do not use a development build as evidence that full release acceptance passed.

Each invocation generates one UTC timestamp and keeps its full Git SHA. The top-level run directory is
`AuthLens-{version}-{yyyy-MM-dd_HHmm}-{shortSha}`: the canonical product version (including any prerelease
suffix), UTC date/minute and first seven SHA characters. For example,
`C:\AuthLens\AuthLens-2.0.0-2026-11-24_0948-8ec7f77`. An occupied name advances to `-02`, `-03`, etc.,
including when another process claims it during creation. Existing files and directories are never reused,
overwritten or renamed; non-collision creation failures stop the build. The exclusive `.build-claim` remains.
The minute display affects only this directory name: summary, release and installer metadata retain the
complete SHA and round-trip UTC timestamp with seven fractional-second digits. Internal release directory
names, installer filenames and the layout below are unchanged:

```text
C:\AuthLens\AuthLens-<version>-<yyyy-MM-dd_HHmm>-<shortSha>\
  build\AuthLens-<version>-<timestamp>-<sha>-win-x64\
    desktop\AuthLens.exe
    server\AuthLens.Api.exe
    symbols\
    build-manifest.json
    SHA256SUMS
  installer\
    AuthLens-<version>-Setup.exe
    AuthLens-Server-<version>-Setup.exe
    installer-manifest.json
    installers-SHA256SUMS
    installer-tools-<unique-id>\
  build-summary.json
  build.log
  .build-claim
```

The run's `build` subdirectory also contains `branding-verification.json`. Canonical packaging checks the actual PE icon resources of Desktop, Server
and both installers against the canonical multi-size ICO, plus exact web-image bytes in each embedded UI and frontend output. A mismatch fails
the build even with `-SkipTests`; see [branding sources](../architecture/DESIGN_SYSTEM.md#branding-source-assets).

The summary records tools, test status, checks, artifact hashes and failure reason. The release and installer manifests carry identical product,
version, full SHA, branch and timestamp. A failure returns nonzero and retains partial outputs/logs. Dirty checkout rejection happens before
creating a build directory. Start a new build after a failure; never overwrite a partial directory. This is traceable orchestration, not a claim
of byte-for-byte reproducible executable timestamps or compression output.

Previously generated `<UTC-timestamp>-<short-sha>` run directories remain valid inputs to explicit-path
inspection/readiness tooling. Consumers discover manifests and verify metadata rather than parsing the run
directory name. They are not renamed or upgraded in place; older second-precision timestamp metadata remains
accepted. Focused build-workflow tests cover stable/prerelease names, UTC/calendar independence, collision
suffixes and a real provider creation race, retained legacy artifacts and precise metadata expressions. Native
release packaging with this convention awaits a manual build; no application or installer was built for this change.

### Preparation diagnostics and remaining acceptance

Setup previously hid PowerShell output behind `Server root security preparation refused (exit 2)`. That exit code covers configuration,
helper integrity, path, elevation and ACL failures; it does not identify an ACL defect. The ordinary ACL plan does not audit the installation root
itself, while Setup checks that root as private storage before staging executable helpers. Therefore a safe ordinary audit does not prove that
Setup preparation passes. Keep the stronger root check; do not grant broad access or bypass preparation.

Preparation now preserves a diagnostic in Setup's private temporary directory and displays/logs its stage and safe refusal. Transaction failures
also retain a diagnostic next to the immutable staged payload. Arbitrary parser/configuration exception content is suppressed; known adapter
refusals and deployment-policy exceptions are reported with credential assignments redacted. Retain the Setup log, diagnostic and transaction
journal. An existing diagnostic/payload is never overwritten. A fresh Setup invocation supplies a new temporary directory for a preparation retry;
interrupted transactions require the existing explicit recovery procedure.

Server preparation checks managed service ownership, account, argument equivalence, release-pointer verification and interrupted journals before
provisioning directories. It identifies fresh installation versus upgrade. The locked deployment transaction still verifies schema compatibility,
rollback, backup and readiness before service replacement. Same-version Server updates require a different, newer verified build timestamp;
version downgrades are refused. Desktop uses the same identity check when its installed manifest carries version metadata and retains its
existing schema/backup checks. Native same-version upgrade acceptance remains required.

The subsequently reported `Server Setup program directory must be the configured installation root app directory` has a confirmed source cause:
Inno previously selected `app` independently from defaults, previous registration and `/DIR`, while PowerShell required `Root\app`. The resolver
now synchronizes that path before staging, retains strict mismatch rejection and fingerprints the reviewed JSON. Custom-root/no-DIR tests and
native synthetic Inno compilation cover the correction; actual production upgrade acceptance remains unperformed. ACL checks are unchanged.

### Manual installer upgrade commands

Use disposable acceptance installations and copied synthetic/test data only. Do not select the running production root or change its service.
Run Setup acceptance in a separate disposable Windows VM/snapshot without the production installation: the installers retain their canonical
AppIds and uninstall registrations. A different directory/service name alone does not isolate those machine/user installer registrations.
Before upgrading, verify backups and the old build, record fingerprints and verify rollback. Close the selected Desktop. Example commands after
replacing the build-folder variable with the actual successful output:

```powershell
$built = 'C:\AuthLens\AuthLens-<version>-<yyyy-MM-dd_HHmm>-<shortSha>'
# Desktop: current user, selected isolated data profile, no service
& "$built\installer\AuthLens-2.0.0-alpha.1-Setup.exe" /DIR="C:\AuthLens-Desktop-Acceptance\app" /DATADIR="C:\AuthLens-Desktop-Acceptance\data" /LOG="C:\AuthLens-Desktop-Acceptance\setup-upgrade.log"
# Server: elevated operator, explicit isolated root/service/port/TLS in this configuration
& "$built\installer\AuthLens-Server-2.0.0-alpha.1-Setup.exe" /CONFIGFILE="C:\AuthLens-Server-Acceptance\config\deploy.json" /OPERATION=Upgrade /LOG="C:\AuthLens-Server-Acceptance\setup-upgrade.log"
```

Use a configuration already validated for the disposable Server service and certificate; placeholders are not an initialization recipe.
After each fresh install and same-version/different-build upgrade, verify data/account/evidence fingerprints, HTTPS, permissions, backup,
restart persistence and explicit interrupted-run recovery. Neither synthetic ISCC compilation nor mocked Pester tests certify native upgrades.

### Server Setup configuration review and automation

This is a partial lifecycle modernization, not native installation certification. The existing PowerShell deployment engine still owns
backup, locking, atomic release switching, service changes, readiness and schema-aware binary rollback. The wizard and silent Setup call the same
hash-verified adapter; neither bypasses those checks. Configuration is never rewritten during upgrades.

Detection uses the reviewed configuration plus managed service arguments, verified release pointer/metadata and, when available, installer-owned
registration. Registration hints are saved only after a successful deployment. Conflicting identities, relocation, populated unregistered data,
Desktop profiles and earlier-product paths are refused. A missing/invalid registration is not permission to overwrite an installation.

Setup supports one canonical `AuthLens` service per machine. `Root` owns `app`, `releases`, `config`, `tls`, `keys` and `deployment` conventions;
existing nonstandard releases/deployment layouts need separate review rather than automatic relocation. Custom data and predeployment backup
paths are preserved and may be external, but cannot overlap each other or program/configuration/TLS/key/deployment storage. Long staged paths
are rejected before permanent writes. Disk estimates include immutable staging/publication, backup size and temporary verification workspace.

The Ready page is the consolidated configuration review: storage paths, access mode (fresh) or "existing configuration (preserved)" (upgrade),
HTTPS listener and allowed hosts, proxy hosts and trusted peers when configured, certificate (with a note for generated self-signed certificates),
firewall decision, Windows Service name and identity, what is created or preserved and, for a fresh installation, the post-install steps (activation,
host key with service read access, recovery-copy verification). During the hidden transaction the Installing page states what is running and where
its sanitized diagnostics are written. While a wizard step runs the hidden helper (local certificate generation, configuration resolution,
read-only preflight, preparation), a marquee progress page names the running check instead of leaving the window unresponsive-looking; silent
Setup and the initial network suggestion are unchanged. Status: compile-checked with ISCC on a probe that includes the production Pascal code and
by `InnoIsolation.Tests.ps1`; native wizard run pending (8.14).

Interactive Setup can author fresh root/data/backup paths, listening IP/port, host/proxy boundaries and existing PFX/password-file locations.
Select **Configure a fresh Server through this wizard**. The temporary draft uses the same strict contract and host preflight as silent
deployment. After approval, protected preparation publishes the exact reviewed bytes to `Root\config\deploy.json` using create-only semantics.
A matching retry is allowed; an existing different file is preserved and refused. Upgrades preserve existing configuration; editing installed
network/service settings remains unimplemented. A stale `UsePreviousAppDir` value never wins over
that configuration. An explicit conflicting `/DIR` fails; do not remove the PowerShell path guard to work around it.

Fresh GUI TLS has two implemented choices: select an existing PFX/password file, or generate a local certificate with a new 3072-bit RSA key,
server-authentication EKU, explicit DNS/IP SANs and one-year validity. The packaged host validates the generated material. Generation stages
create-only files beneath administratively owned `C:\ProgramData\AuthLensSetup\TLS-<id>`; no installation database is initialized and no
trusted store is changed. A generated certificate is self-signed: browsers/clients require an explicit trust decision outside automatic Setup.
Cancelled/failed drafts remain protected for review and are never reused or overwritten.

After confirmation, both fresh choices import PFX/password bytes through read leases into a **new** protected `Root\tls\setup-<id>` directory.
The source is preserved; public-only `server.cer` is exported alongside the imported material. Configuration publication records an immutable
private receipt binding the reviewed draft to the canonical configuration and imported file hashes. A matching retry reuses the same files;
changed configuration or key material refuses recovery rather than replacing keys. The service receives read access through the existing ACL
transaction. Existing PEM configurations may retain explicit external files; fresh import deliberately requires PKCS12 and never relabels PEM.
These paths have focused crypto/import/compiler checks; elevated ACL, native GUI/service TLS and cancellation/recovery acceptance remain pending.
Replacement of an installed service certificate is a separate transaction ([installed certificate replacement](#installed-certificate-replacement)); fresh import is not advertised as renewal.

`--server-preflight` is a non-listening command of the packaged Server. It uses the actual host/TLS policy, ephemeral certificate keys and read-only
schema, SQLite integrity and foreign-key checks. It validates certificate SANs for configured backend hosts/listen IP (public proxy hosts are not
required backend SANs), private-key material, validity/EKU/key size, host/proxy policy and existing backup-key readability. It never creates a token,
initializes a data directory/database, changes existing keys or binds a listener. Local HTTPS omits the LAN `--network` flag and omits an empty
extra-host list rather than emitting a valueless option; the loopback Host/Origin boundary is unchanged. LAN/proxy mode still requires explicit hosts and keeps
one assigned private address, explicit hosts/proxies and HTTPS; no unrestricted HTTP or TLS-verification bypass is introduced. Actual service-account
key access, certificate chain/Windows TLS and client trust still need post-deployment/native checks.

The preparation stage is distinct: `-PrepareOnly` **does** provision protected directories after successful read-only checks and explicit `-Yes`.
It is not a synonym for `-PreflightOnly`. Full release verification and the configuration fingerprint are checked again before deployment.
Pending schema changes or an incompatible/unverified previous release refuse installer upgrades. Product channel order is
`alpha < beta < rc < stable`; Windows' numeric file revision alone is not an authoritative product version comparison. Older versions remain refused;
only a separately approved, compatible rollback/recovery procedure may downgrade. Same-version/different-build updates retain the newer-build and
rollback checks.

#### Supported adapter operations

Firewall configuration is opt-in. GUI confirmation lists local IP/TCP port, explicit source IP/CIDR scopes and Private/Domain profiles.
Silent Setup requires `/APPROVEFIREWALL=Yes /FIREWALLSOURCES=10.0.7.10 /FIREWALLPROFILES=Private`; the adapter equivalents are
`-ApproveFirewall -FirewallSources '10.0.7.10' -FirewallProfiles Private`. These are examples, not discovered trusted peers.
No exception is created for loopback, no rule is created by default, and administrator-created rules are not changed. The native rule is
created only after deployment readiness succeeds. Receipts under the protected deployment directory record intent before mutation; failed
rule creation attempts compensating deletion of only that unpredictable rule ID and preserves evidence. Firewall failure does not undo an
already successful application deployment; retain the healthy instance and inspect the receipt.

Standalone `-Operation Firewall -FirewallSources <approved list> -FirewallProfiles Private -ApproveFirewall -Yes` creates or updates only a proven
owned rule; `-Operation FirewallRemove -ApproveFirewall -Yes` removes only that owned rule. Both require a verified managed service/configuration;
`-PreflightOnly` reviews without applying and needs no release package for these two operations. Ownership is the private receipt plus the exact
native name/group, service binding, protocol/ports, addresses, profiles, interface/security filters and edge policy. Changed administrator definitions
are preserved and refused. CIDR/netmask normalization compares equivalent scopes without treating wildcards as identities.

Updates disable the old rule **before** creating a new one, verify the new definition, remove the old rule and retain superseded receipts.
There is no temporary union of old/new allowed sources. Failures retain `deployment\firewall-pending.json` and receipts; ordinary deployment/
rollback refuses this barrier. `-Recover -Yes` completes the latest approved intent after validating actual native state; it does not silently reopen
a superseded broader scope. Explicit `-Recover -FirewallRollback -ApproveFirewall -Yes` requests restoration of the previous approved scope and
reports rollback verified only after the native definition matches. Prepared creation receipts are resolved only against proven matching native
state or proven absence. Administrator-created rules and unrelated resources are never enumerated for deletion. Native elevated rule lifecycle
acceptance remains pending; focused tests use mocked NetSecurity calls. Uninstall integration remains incomplete.

Offline repair is intentionally distinct from upgrade: the damaged previous payload cannot prove a working rollback. It requires a stopped,
owned service, byte-identical installed/replacement manifest, existing database, compatible schema without pending migrations, existing keys
and a newly verified encrypted backup. A uniquely named replacement release is verified and activated; old bytes are retained. Missing service
registration/manifest/database is refused. Activation failure attempts to stop only a repair-activated service and leaves an explicit recovery
barrier. Recovery of an interrupted repair remains a manual reviewed operation, not an automatic rollback to possibly damaged executables.

These changes have source-level tests and compile-only Inno coverage; native provisioning, GUI interaction and repair/recovery acceptance are
pending. The existing local health probe does not establish client certificate-chain trust; validate chain/name from an actual client separately.

Use the packaged `installer-tools-<id>/Install-AuthLens.ps1`, not an unverified checkout copy. Parameters apply with `-Mode Server`:

| Option | Actual behavior |
| --- | --- |
| `-ResolveOnly` | Read configuration/identity, derive `Root\app`, fingerprint JSON; no system provisioning |
| `-PreflightOnly -Package <verified full release>` | Read-only installation, network/TLS/database/schema/key, path/ACL/address/port/storage checks |
| `-Operation Auto` | Detect fresh install or upgrade; never adopt unrelated service/data |
| `-Operation Install` / `Upgrade` | Explicitly require the matching detected state; `-Package` and `-Yes` required to apply |
| `-Operation Repair -Package ... -Yes` | Offline component repair: owned service must already be stopped; exact installed manifest and existing database required. Missing registration can be recreated only for the default virtual account with a matching installed-product receipt and unchanged configuration. Verifies an encrypted backup, publishes an immutable replacement, switches the pointer and checks service readiness. Retains damaged payload and recovery evidence |
| `-Operation UninstallPlan` | Read-only receipt/configuration/release/service/firewall ownership verification; all resources remain untouched |
| `-Operation Uninstall -Yes` | Verify encrypted backup, stop/remove only the proven owned service and installer-owned firewall rules; preserve all persistent data, configuration, certificates, keys, releases and recovery evidence |
| `-Recover -Yes` | Existing journal-driven recovery; retain exact configuration and recovery tools |
| `-ResultFile <new absolute path>` | Immutable JSON envelope, schema/operation ID/status/exit/stage/journal location; no overwrite |
| `-PlanFile <new path>` | Private Unicode INI bridge for resolve/preflight results used by Inno; not a configuration file |
| `-ExpectedConfigSha256 <reviewed hash>` | Refuse changes between review, preparation and deployment |
| `-PrepareOnly -CommitNewConfiguration -Yes` | After complete preflight/protected preparation, publish the exact reviewed draft to `Root\config\deploy.json`; never overwrite a different configuration or publish over an existing service/release |
| `-GenerateTlsDraft -Package ... -Yes` | Explicit fresh-only private TLS generation using reviewed configuration paths beneath `AuthLensSetup\TLS-<id>`; requires no existing AuthLens service and validates through the packaged host; does not install/trust/start anything |
| `-PrepareOnly -CommitNewConfiguration -ImportTls -Yes` | Validate first, copy existing/generated PFX/password into new protected versioned files, export public certificate and publish bound configuration/receipt; original material stays untouched |
| `-ApproveFirewall -FirewallSources <IP/CIDR list> -FirewallProfiles Private,Domain` | Explicit restricted-rule approval; preflight checks scope, final deployment applies only after readiness. Existing rule receipts refuse automatic updates |

Adapter exit codes: `0` completed selected operation (a read-only plan/repair check is not installation success), `1` worker/verification failure,
`2` policy/configuration refusal, `4` manual recovery/review required. Unclassified transaction failures use `4`, never claim that nothing changed.
PowerShell syntax/binding failures occur before this envelope and must be treated as invocation failures. Inno retains its own standard process
exit codes; use the adapter JSON/report and Setup log for the underlying code. Automatic Setup logging is enabled. Logs contain no certificate
password, recovery-key bytes or business records. Temporary planning reports are logged; the final operation report lives next to the staged
payload and points to the persistent deployment journal outside that payload. Preserve journals, backups, recovery tools and failed payloads.
The completion page/open-URL action is gated on transaction success, not extraction alone. Fresh installs still need administrator activation and
host recovery-key provisioning/escrow; external proxy/DNS/firewall/client trust are separate checks.

#### Explicit remaining lifecycle limits

Successful Server deployment now records `config/installed-product.json`, binding the instance, configuration hash,
service identity and verified release manifest. Fresh, initially empty data directories additionally receive an ownership
marker; upgrades never retroactively mark existing databases as disposable. Matching fresh-install retries reuse the marker.
Advanced storage paths are created with protected ACLs without changing existing shared parent permissions.
New services receive their identity while still Manual, before automatic startup is enabled. Existing SCM passwords are
preserved when the identity is unchanged; changing an existing identity requires a separate credential transaction.

Schema-2 offline repair journals support explicit `-Recover -Yes`: recovery validates configuration/service bindings,
both retained manifest identities, the complete replacement package, encrypted backup and read-only TLS/database/schema
preflight before service changes. It completes the approved replacement and clears the barrier only after readiness.
It never restores older database content or claims the damaged payload is a working rollback. Legacy unbound repair
journals require manual review. Source tests cover these guards; native SCM interruption/recovery acceptance remains pending.

Server uninstall now has a receipt-bound, preservation-only transaction. Inno performs a read-only ownership plan and
an explicit interactive confirmation before file removal; silent uninstall preserves data by default. The helper verifies
an encrypted backup before stopping the service, removes only matching installer-owned firewall rules and the matching
service registration, then verifies absence. A pending SCM deletion, failed verification or interruption leaves
`deployment/uninstall-pending.json`; explicit `-Recover -Yes` revalidates bindings and backup before completing it.
No database, TLS file, key, configuration, release or recovery artifact is deleted. Optional deletion of installer-owned
test data is not implemented. Uninstall of older installations without the modern receipt is refused safely; first perform
a verified supported upgrade. Native execution and failure-interruption acceptance remain pending.

Recovery and uninstall validate published Server releases with the verifier's explicit `Server` scope: Desktop/symbol
artifacts are intentionally omitted by publication. Original manifests, checksums and the deployment declaration remain
required and unchanged; a missing or modified Server artifact still fails verification. Initial installer payloads retain
full-scope verification. A synthetic publish-to-lifecycle regression exercises the real verifier without SCM changes.

| Requirement | Status and reason | Next action |
| --- | --- | --- |
| Fresh configuration and TLS | Fresh generation/selection/import and create-only bound publication implemented; installed-certificate replacement implemented (`-Action ReplaceCertificate`); no automatic trusted-store modification | Native GUI, ACL/service-key access, replacement under SCM and client-trust acceptance pending |
| Dedicated account / gMSA creation | Blocked: existing SCM adapter has no secure password transport, account-logon-right or managed-password validation contract | Add validated credential/logon provisioning; preserve existing identities meanwhile |
| Automatic firewall configuration | Source implementation covers approved creation, ownership-verified update/removal, retained transition journals and explicit completion/rollback recovery; loopback/wildcards/Public/Any refused | Native elevated rule/policy acceptance and uninstall integration remain pending |
| Repair missing/corrupt components/service | Partial: CLI payload replacement, receipt-bound missing virtual-account registration and schema-2 interrupted-repair recovery implemented; damaged files retained | Older installations without receipts, missing manifests and password-backed missing accounts require manual review; GUI selection and native interruption/recovery rehearsal remain pending |
| Uninstall | Source implementation supports CLI and Inno service/owned-firewall removal, verified encrypted backup, retained journal and explicit recovery; all persistent data preserved | Native lifecycle acceptance and optional independently verified test-data deletion remain pending; older installations need a modern ownership receipt |
| Downgrade in Setup | Refused safely; schema compatibility alone does not prove safe data/version rollback | Use separately authorized verified rollback/recovery; no `allow downgrade` bypass |
| Legacy migration wizard | Partial: known service/root presence is reported read-only and protected paths are refused; supported backup conversion remains explicit | Rehearse supported preview/run/activate or fresh restore separately; never auto-adopt/modify/delete legacy resources |
| Native lifecycle acceptance | Not performed by source/unit/compiler checks | Execute the isolated Windows matrix below with separate authorization; preserve production |

### Proposed isolated Server lifecycle acceptance

Run only in a disposable Windows VM/snapshot without the production instance or conflicting installer registrations. Never execute these steps
against the current service. Pre-provision a private lab configuration/TLS/password files using the existing deployment contract; use an actual
assigned address and certificate-valid hosts (or loopback HTTPS). Keys/credentials must never enter transcripts. Obtain explicit approval before
any full regression; the packaging command below deliberately skips it.

```powershell
# Repository: clean, committed experiment/dotnet-backend; native prerequisites from the canonical build section
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force
.\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)
# Select an explicit output whose build-summary.json status and verification fields passed; never blindly select the newest partial folder
$built = 'C:\AuthLens\<verified-build-directory>'
$release = (Get-ChildItem "$built\build" -Directory | Where-Object Name -Like 'AuthLens-*-win-x64').FullName
$tools = (Get-ChildItem "$built\installer" -Directory -Filter 'installer-tools-*').FullName
$config = 'C:\AuthLens-Server-Acceptance\config\deploy.json'
# Elevated lab operator; each result path must be new. These two steps do not provision the target.
& "$tools\Install-AuthLens.ps1" -Mode Server -ResolveOnly -ConfigFile $config -ResultFile "$env:TEMP\authlens-resolve-unique.json"
& "$tools\Install-AuthLens.ps1" -Mode Server -PreflightOnly -Operation Install -Package $release -ConfigFile $config -ResultFile "$env:TEMP\authlens-preflight-unique.json"
# Fresh GUI: no DIR workaround. Repeat later with Upgrade and a newer compatible build.
& "$built\installer\AuthLens-Server-2.0.0-alpha.1-Setup.exe" "/CONFIGFILE=$config" /OPERATION=Install
# Silent upgrade of the lab instance only; same engine and safety checks
& "$built\installer\AuthLens-Server-2.0.0-alpha.1-Setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART "/CONFIGFILE=$config" /OPERATION=Upgrade
# Read-only offline same-build repair preflight (owned lab service must already be stopped) / uninstall planning
& "$tools\Install-AuthLens.ps1" -Mode Server -PreflightOnly -Operation Repair -Package $release -ConfigFile $config -ResultFile "$env:TEMP\authlens-repair-unique.json"
& "$tools\Install-AuthLens.ps1" -Mode Server -Operation UninstallPlan -ConfigFile $config -ResultFile "$env:TEMP\authlens-uninstall-plan-unique.json"
```

Use a **newer** verified package for upgrade, not an already-staged identical payload. For repair checks, select the exact currently installed
package. Applying CLI repair requires the same arguments without `-PreflightOnly`, plus `-Yes`; it starts the repaired service. A failed/interrupted activation preserves `deployment\repair-pending.json` pointing to the retained repair journal. Deploy/Recover/Rollback refuse that barrier: manually review the journal, verified encrypted backup, database/schema and both payloads before authorizing recovery; never simply delete the marker to retry. No generic automatic recovery is claimed for a damaged previous payload. Verify before/after application/account/evidence fingerprints, SQLite integrity/foreign keys, backup decrypt/verify and separate clean
restore, TLS/health/build identity, virtual-account access, startup/restart persistence and journal/recovery behavior. Negative cases must include:
custom root without `/DIR`, stale previous Setup directory, conflicting `/DIR`, registry/service disagreement, changed config after review,
occupied port, invalid/expired/wrong-name certificate, unavailable key/space, Desktop/legacy paths, pending/newer schema, older SemVer,
identical payload retry, interrupted update and uninstall while the service still exists. Verify the default preserved-data uninstall only after
an approved ownership/backup/service-removal procedure. Do not delete rollback artifacts or automatically restore an older database.
