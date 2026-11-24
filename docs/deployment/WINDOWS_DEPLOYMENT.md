# Windows deployment: SSH-driven test server and installers

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
  (inherited), read and execute on `ReleasesRoot`, read on the certificate, its password file and the backup key file.
- Command line (no secret): `AuthLens.Api.exe --data-dir … --network --listen … --port … --allowed-hosts … --cert … --cert-password-file … [--trusted-proxies …]`.
  TLS, the Host allow-list, Origin/CSRF checks and the trusted-proxy restriction are the server's own and unchanged by the deployment.
- Processes: only the service is stopped, through the SCM. A port held by another process (for example `start-server-test.ps1`) is reported and left alone.

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
server binary directly, needs no SDK, opens no listener and never controls the service. Select the exact data directory and executable explicitly
when operating an older installation. Key export/provisioning stays local-only; no browser export endpoint exists.

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

`CreateKey` is for an unconfigured installation only and never replaces a configured key. Export to separately secured recovery storage,
then verify that copy before enabling automatic backups. Protect the full key directory; keep host and recovery keys out of data/releases/Git.
For virtual accounts provision before service installation grants read access; existing-service grants require explicit reviewed Reconfigure.
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
firewall rules are never stopped, changed or reused. Keep the evidence files of each step under `C:\AuthLens-Acceptance\evidence` (no secrets,
codes, passwords or keys in them).

### 0. Baseline of the existing installations (read only)

```powershell
New-Item -ItemType Directory -Force C:\AuthLens-Acceptance\evidence | Out-Null
$ev = 'C:\AuthLens-Acceptance\evidence'
Get-CimInstance Win32_Service | Where-Object Name -eq 'AuthLens' |
  Select-Object Name, DisplayName, State, StartMode, StartName, PathName | ConvertTo-Json | Set-Content "$ev\00-services-before.json"
Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess | Sort-Object LocalPort | Out-File "$ev\00-ports-before.txt"
```

For a fresh install, stop if the intended service/root already exists. For an update, preserve the captured service and data baseline. Use a separate free port and supported isolated identity for acceptance.

### 1. Release build, verification and installers

```powershell
git status --short; git rev-parse HEAD                                      # clean, expected commit
Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force; $filter = Get-ALTestFilter focused
& .\backend\scripts\build-release.ps1 -Output C:\AuthLens-Acceptance\builds -TestFilter $filter
$release = Get-ChildItem C:\AuthLens-Acceptance\builds -Directory -Filter 'AuthLens-*-win-x64' | Sort-Object Name | Select-Object -Last 1
& .\backend\scripts\verify-release.ps1 -ReleasePath $release.FullName *>&1 | Tee-Object "$ev\01-verify.txt"
& .\backend\scripts\build-installers.ps1 -ReleasePath $release.FullName -Output C:\AuthLens-Acceptance\installers
Get-ChildItem $release.FullName\server, $release.FullName\desktop | Select-Object Name, Length | Out-File "$ev\01-files.txt"
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
$fixture = 'C:\AuthLens-Acceptance\installer-' + [guid]::NewGuid().ToString('N')
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

From a clean committed checkout, run `.\build.ps1`. Windows PowerShell 5.1 or PowerShell 7,
Git, .NET SDK 10, Node 24/25, npm, Python 3 and Inno Setup 6 are required. Use `-Iscc <absolute ISCC.exe>` for a nonstandard installation.
The entry point orchestrates the existing release builder, verifier, release secret scan and installer builder. It never installs software or
changes services. CI triggers, product version and runtime configuration are unchanged.

```powershell
.\build.ps1
.\build.ps1 -SkipTests                            # development only; summary explicitly records skipped tests
.\build.ps1 -TestFilter 'FullyQualifiedName~VersioningTests' -OutputRoot C:\AuthLens-Development
```

`-TestFilter` selects focused backend validation; the default release command runs the existing backend release test selection.
Do not use a development build as evidence that full release acceptance passed.

Each invocation generates one UTC timestamp and keeps its full Git SHA. Outputs are never reused:

```text
C:\AuthLens\<UTC-timestamp>-<short-sha>\
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

The build directory also contains `branding-verification.json`. Canonical packaging checks the actual PE icon resources of Desktop, Server
and both installers against the canonical multi-size ICO, plus exact web-image bytes in each embedded UI and frontend output. A mismatch fails
the build even with `-SkipTests`; see [branding sources](../architecture/DESIGN_SYSTEM.md#branding-source-assets).

The summary records tools, test status, checks, artifact hashes and failure reason. The release and installer manifests carry identical product,
version, full SHA, branch and timestamp. A failure returns nonzero and retains partial outputs/logs. Dirty checkout rejection happens before
creating a build directory. Start a new build after a failure; never overwrite a partial directory. This is traceable orchestration, not a claim
of byte-for-byte reproducible executable timestamps or compression output.

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
$built = 'C:\AuthLens\<UTC-timestamp>-<short-sha>'
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
Renewal/replacement of an installed service certificate is still unimplemented; fresh import is not advertised as renewal.

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
| Fresh configuration and TLS | Fresh generation/selection/import and create-only bound publication implemented; no automatic trusted-store modification | Installed-certificate renewal/replacement transaction remains incomplete; native GUI, ACL/service-key access and client-trust acceptance pending |
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
.\build.ps1 -SkipTests
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
