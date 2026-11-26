# AuthLens 2.0.0 Windows acceptance tracker

**Current candidate: RC6** (`839123c`, build id `2026-11-26_0330-839123c`), built and verified, **native acceptance not started; NOT APPROVED for production.** This file records only results the operator actually
produced on the disposable Windows VM. A scenario is **Passed** only with operator evidence; otherwise it is Not run, Blocked (environment) or
Failed (product). Procedures: [VM acceptance runbook](WINDOWS_VM_ACCEPTANCE.md). Implementation status: [work packages](WORK_PACKAGES.md).

## Candidates

Internal identifiers only; the product version is 2.0.0 for every candidate and nothing is branded RC. Acceptance results belong to one exact
artifact identity and are never transferred between candidates.

### RC6 (consolidated candidate after WP29 to WP34 and QA-028; native acceptance not started)

Built by the agent session with the canonical `build.ps1 -ZipPackage` from `839123c`, the first candidate in the WP32 category layout; see
the [RC6 build record](#rc6-build-record). Product version 2.0.0. **NOT APPROVED**: no native acceptance has run on RC6; RC5 results do not
transfer to it.

### RC6 build record

| Item | Value |
| --- | --- |
| Source commit | `839123cd74d381add81468c25617cd204e507d5f` on `experiment/dotnet-backend` (pushed; working tree clean before the build) |
| Build | `Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force; .\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused) -ZipPackage`; UTC `2026-11-26T03:30:10.4341404Z`; win-x64; .NET SDK 10.0.404, Node.js 24.22.3, npm 11.19.1, Windows PowerShell 5.1.26100.9818 |
| Build id | `2026-11-26_0330-839123c` |
| Build | `C:\AuthLens\Build\2.0.0\2026-11-26_0330-839123c` (`build-summary.json` schema 2, layout `category`, status `passed`) |
| Installer | `C:\AuthLens\Installer\2.0.0\2026-11-26_0330-839123c` (both Setups, `installer-manifest.json`, `installers-SHA256SUMS`, `DEPLOY.txt`, `Expand-AuthLensPackage.ps1`, 10 packaged helpers) |
| Acceptance | `C:\AuthLens\Acceptance\2.0.0\2026-11-26_0330-839123c\<run>` (created by the first acceptance run; the folder does not exist yet) |
| Deployment package | `C:\AuthLens\Packages\AuthLens-2.0.0-2026-11-26_0330-839123c.zip`, 186,171,774 bytes, SHA-256 `f2ef8584f75ecb9dbd171f603c4c799bea3195601ed387b98a50a4a571e12d59` (checksum file `….zip.sha256`; original nested layout, kept unchanged) |
| Flat deployment package (WP32 amendment) | `C:\AuthLens\Packages\AuthLens-2.0.0-2026-11-26_0330-839123c-pkg2.zip`, 186,171,623 bytes, SHA-256 `4d1249800a735f1195da482633c2f4e42f10e0c4c1aaa859772f973c5c0c81f0`: the same build repackaged with `New-AuthLensPackage.ps1 -PackageRevision 2` (no rebuild; build id and commit unchanged). Agent verification on the build host: root holds both Setups, `Expand-AuthLensPackage.ps1`, `README.txt`, `installer-manifest.json`, `package-manifest.json`, `SHA256SUMS.txt` and 11 `Tools/` entries; hardened extraction into an empty temporary folder with `-ExpectedSha256`: `verified`, layout `flat`, revision 2, 17 files; `-VerifyOnly` of the extracted folder passed; both Setups and `installer-manifest.json` byte-identical to the Installer folder; the original ZIP still hashes to `f2ef8584…`. Extraction on a target machine pending |
| Tests run by the build | Standard focused filter: **155 passed, 0 failed, 0 skipped** |
| Build verification | installers, secrets, branding and release: all `true`; package: passed (independent extraction verified by the build) |
| Agent verification (read-only) | Manifest AuthLens 2.0.0, commit `839123c…`, not dirty; ZIP digest equals the checksum file; 18 entries, all under `Installer/2.0.0/2026-11-26_0330-839123c/`, none with keys, certificates, databases, backups, sources or tests; separate extraction with the packaged `Expand-AuthLensPackage.ps1` into an empty temporary folder: `verified`, 17 files, identical hashes to the Installer tree; a second extraction to the same place refused (never overwritten); the path-length guard refused a long destination before writing |
| Signature status | Both Setups **NotSigned** (Authenticode); checksums establish integrity only, not publisher authenticity |
| Not done | Signing, tagging, publishing (not authorized); deployment to VM130 or DASH1 (not authorized); native acceptance; FULL regression |

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `AuthLens-2.0.0-Server-Setup.exe` | 93,505,058 | `34c3f209451d6a89f970ab452eeb2a45f5c393aa8d6dba1f007e946e3d645cf9` |
| `AuthLens-2.0.0-Desktop-Setup.exe` | 93,510,735 | `c696f737f9c543b47937a3207a73d4bc9346a247476d190e5374243b02c12fc0` |
| `installer-manifest.json` | 924 | `a97baf6677a3bf85220ef3155b0320a6feed49ce1f1568e7c7793c517ef93dc5` |
| `installers-SHA256SUMS` | 371 | `67c58a3767b2369b6a63fe63e2d2f98d035f25abc3d7567114e0315c7f655a89` |
| `AuthLens-2.0.0-2026-11-26_0330-839123c.zip` | 186,171,774 | `f2ef8584f75ecb9dbd171f603c4c799bea3195601ed387b98a50a4a571e12d59` |
| `AuthLens-2.0.0-2026-11-26_0330-839123c-pkg2.zip` (flat) | 186,171,623 | `4d1249800a735f1195da482633c2f4e42f10e0c4c1aaa859772f973c5c0c81f0` |

**Known limits of RC6 (not acceptance results):** FILE-008 partial (no pre-import change indication); FULL regression not executed; both
Setup programs unsigned; RC5 and older cannot be packaged as ZIP. See [RC6 candidate status](STATUS.md#rc6-candidate-status).

**Acceptance to run on RC6** (it replaces RC5): A1 against this record; package transfer and extraction on the target (copy the ZIP and
`.zip.sha256` to `C:\AuthLens`, verify, extract with `Expand-AuthLensPackage.ps1`); B17 Lifecycle upgrade RC5 to RC6 with repair; readiness
with `-StrictAcl` (expected to refuse while the named operator account is unreviewed); B11 to B16, T-001, C11 to C14; D2 to D12 and R6-F1 to
R6-F4 (including remote UNC with the service identity); R6-S1, R6-M1 (real iPhone), R6-A1; storage preflight text in Setup and
`ArtifactInventory` / `PruneArtifacts -DryRun`; Service Manager recovery bundle creation and verification (QA-028); F1 to F10.

### RC5 (consolidated candidate after WP21 to WP28; native acceptance partly run)

Built on VM130 by the agent session with the canonical `build.ps1` from `b10dd50` (corrections D-007 and D-008, BUG-01 to BUG-10, the
acceptance and recovery tooling); see the [RC5 build record](#rc5-build-record). Product version 2.0.0. **NOT APPROVED**: native acceptance
is partial (below); RC4 results do not transfer to it.

**RC5 native results (operator evidence, reconciled in WP24).** Evidence: `C:\AuthLens\acceptance\AuthLens-2.0.0-2026-11-25_1442-b10dd50`
and `C:\AuthLens\acceptance\RC5-readiness.txt` on VM130.

| Host | Scenario | Result | Evidence |
| --- | --- | --- | --- |
| VM130 | Upgrade readiness (RC3-VM130 installed, RC5 candidate, explicit recovery report) | **Passed**: 5 checks, `status` PASS, 2026-11-25T15:12Z | `RC5-readiness.txt` |
| VM130 | B14 approval group (11 `-Yes`-less refusals, elevated) | **Passed** 11/11, exit 0 | `B14-approval-1
esults.json` |
| VM130 | B14 elevation group | Not run (no evidence on disk) | — |
| VM130 | B17 Lifecycle: upgrade RC3-VM130 to RC5, installed tools, identity, preserved data, C12 status/export/no-overwrite, C14 simulation and restart, B15 simulation without audit, repair plan, repair and preserved data | **Passed** 17/17, exit 0; fingerprints before/after upgrade and repair recorded | `Lifecycle-1
esults.json` |
| VM130 | D-007: `source_authority` after the upgrade | **Passed**: `present` | `Lifecycle-1\B17-status-after-upgrade.txt` |
| VM130 | D-008: named-account reporting in AuditAcl | **Passed** (reported; nothing removed). The WP31 development-source audit classifies one named operator account as UNSAFE (unauthorized named access); left for the operator to authorize or remove | `WP31-source\AuditAcl-VM130.txt` |
| DASH1 | Upgrade RC3 to RC5 | **Passed** after freeing storage: the first preflight refused with about 2 GB free (see WP34) | Operator report; evidence directory not on this host |
| DASH1 | CSV source usability | **Failed (product usability)**: separate local/UNC workflows and no host file selection; addressed in WP33 (source), native re-test pending | Operator report |
| VM130, DASH1 | B11, B12, B13, B15, B16, T-001, C11, C13, D2 to D7, D12, D3 (UNC/SMB), F1 to F10 with BUG-01 to BUG-10 | Not run on RC5 | — |

### RC4 (superseded by RC5 for new acceptance; artifacts and evidence preserved)

Built on VM130 by the agent session with the canonical `build.ps1` from `37eadd5`, the first candidate with the corrections for D-004 to D-006,
G-003 to G-005, G-007, WP19 and WP20; see the [RC4 build record](#rc4-build-record). Product version 2.0.0 (RC4 is an internal identifier).
**NOT APPROVED**: native acceptance ([runbook priority order](WINDOWS_VM_ACCEPTANCE.md#rc4-and-rc5-priority-order-historical)) and the final FULL regression are
outstanding; D3 (UNC/SMB with the service identity) is a release blocker.

### RC3-VM130 (superseded by RC4 for new acceptance; artifacts and evidence preserved)

Built on VM130 itself from `19a1113`; see the [RC3-VM130 build record](#rc3-vm130-build-record). Accepted for controlled testing only; NOT APPROVED.
Known defects present in this candidate (found 2026-11-25; corrected in the sources after RC3, not in this artifact): **D-006 (P0: `-DryRun` on
Recover, Restore, Rollback, InstallService and RestoreAcl runs the real action; never use it with these tools)**, D-004 (the preflight requires the
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

### RC5 build record

| Item | Value |
| --- | --- |
| Source commit | `b10dd507cca629a0b5ccd8d91ca460871deb196c` on `experiment/dotnet-backend` (pushed; working tree clean before the build) |
| Build | `Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force; .\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)` on VM130; UTC `2026-11-25T14:42:46.6873498Z`; win-x64; .NET SDK 10.0.404, Node.js 24.22.3, npm 11.19.1, Windows PowerShell 5.1.26100.9818 |
| Run directory | `C:\AuthLens\AuthLens-2.0.0-2026-11-25_1442-b10dd50` with `build\AuthLens-2.0.0-20261125-144246-b10dd50-win-x64`, `installer\`, `build-summary.json` (status `passed`), `build.log` |
| Tests run by the build | Standard focused filter (14 classes): **154 passed, 0 failed, 0 skipped** |
| Build verification | installers, secrets, branding and release: all `true` |
| Agent verification (read-only) | Manifest AuthLens 2.0.0, file version 2.0.0.0, commit `b10dd50…`, not dirty; all 32 artifacts match `build-summary.json`; packaged and repository `verify-release.ps1 -Scope Full`: 17 artifacts; `installers-SHA256SUMS` OK; 7 helpers match `installer-tools.json`; packaged tools contain the D-006 policy, G-004, G-005, restart, D-007 provisioning, `source_authority` status and D-008 named-account findings; the server executable has `--fingerprint-data`; `--schema-info`: compatible, 6 migrations; executables `2.0.0+b10dd50…`; installers unsigned |
| Not done | Signing, tagging, publishing (not authorized); native acceptance; FULL regression |

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `installer\AuthLens-Server-2.0.0-Setup.exe` | 93,443,648 | `77150b1af65b58a8b28cee634dfe170139da1b47b57d712278fde567129b2510` |
| `installer\AuthLens-2.0.0-Setup.exe` (Desktop) | 93,426,737 | `0957cf29d8c465a0a052b58d454e44c97f2ea29e1deeb0b88e445557ae0e825a` |
| `server\AuthLens.Api.exe` | 123,342,439 | `54c7738a5488ecad8a99fc44cfe8f6b0030af0881f80642a05d58600fcb9f25c` |
| `desktop\AuthLens.exe` | 178,543,230 | `523820b8629e8ff892f58e7d5441daefa4f903c5ff2a85472f970f0a7e0bbc4a` |
| `build-manifest.json` | 5,933 | `676e2cbfb74ffe5ad6f9c5ccfc885559fb2b5178553220642327cb1e58e956a7` |
| `installer\installer-manifest.json` | 916 | `9962f6fe7192ae17e631867d96a17f13857cfcc2722635677ad8131feb7e32c5` |
| `installer\installer-tools-63434c46f2394313a1a700e08bceb60f\installer-tools.json` | 1,484 | `f12bf1fb13e605046cf58aef70190dc6ceeb6ce639a23709e1f76b4818a650c7` |

**Acceptance to run on RC5** (it replaces RC4 for all of these): A1 against this record; B13 (terminal and interrupted state) and both
B14 groups with the WP21 harness; B17 Lifecycle (upgrade RC3-VM130 to RC5, repair) including the D-007 check (`source_authority: present`
after the upgrade) and AuditAcl named-account reporting; B11, B12, B15, B16, T-001; C11 to C14; D2 to D7, D12 and D3 (local, same-host UNC,
remote SMB); F1 to F10 including BUG-01 to BUG-10 and the BUG-04 inactivity warning with real sessions.

**Browser suite state (source level).** In the affected set of 19 spec files (131 tests) 113 passed; 3 failures came from this round's
intentional behaviour changes and their specs were updated (BUG-01 toggle in `sod-assignment-decisions`, BUG-08 in `investigation-ux` and
`global-navigation`, all passing afterwards); the other 15 (`investigation-ux` visual and import-source tests, `live-filters-polish`,
`navigation-modules` data-source focus tests, `startup-reliability` revision tests) fail identically on the unmodified RC4 frontend
(`ab30b0b`) on this host, so they predate this round. They are open test or product findings to resolve before FULL.

### RC4 build record

| Item | Value |
| --- | --- |
| Source commit | `37eadd529ba81bf3a3602d7352128ab5de8497e7` on `experiment/dotnet-backend` (pushed; working tree clean before the build) |
| Build | `Import-Module .\backend\scripts\deploy\AuthLens.Deploy.psm1 -Force; .\build.ps1 -OutputRoot C:\AuthLens -TestFilter (Get-ALTestFilter focused)` on VM130 from `C:\Users\arkasa\Git\AuthLens`; UTC `2026-11-25T08:07:58.1944720Z`; win-x64; .NET SDK 10.0.404, Node.js 24.22.3, npm 11.19.1, Windows PowerShell 5.1.26100.9818 |
| Run directory | `C:\AuthLens\AuthLens-2.0.0-2026-11-25_0807-37eadd5` with `build\AuthLens-2.0.0-20261125-080758-37eadd5-win-x64`, `installer\`, `build-summary.json` (status `passed`), `build.log` |
| Tests run by the build | Standard focused filter (14 classes): **151 passed, 0 failed, 0 skipped** |
| Build verification (`build-summary.json`) | installers, secrets (secret scan), branding and release: all `true` |
| Agent verification (read-only, 2026-11-25) | Manifest product AuthLens, version 2.0.0, file version 2.0.0.0, commit `37eadd5…`, not dirty, win-x64; all 32 artifacts in `build-summary.json` match size and SHA-256; packaged and repository `verify-release.ps1 -Scope Full`: 17 artifacts verified; `installers-SHA256SUMS` OK for both installers; 7 packaged helpers match `installer-tools.json`; the packaged tools contain the D-006 policy, G-004 audit, G-005 reconciliation and restart; `--schema-info` on an empty folder: compatible, 6 known migrations; executables report `2.0.0+37eadd5…`; installers unsigned, ProductVersion 2.0.0 |
| Packaged tools | `installer\installer-tools-c50faa4915564d788c81dd0a4ce54271`, `installer-tools.json` SHA-256 `25e49fd4dc85a43d594bd8746069dd89f16da59645816a110bc57490003a6f20` |
| Not done | Signing, tagging, publishing (not authorized); native acceptance; FULL regression |

| Artifact | Size (bytes) | SHA-256 |
| --- | --- | --- |
| `installer\AuthLens-Server-2.0.0-Setup.exe` | 93,446,379 | `c0a93d7542a7b8136d9d90a529d14c05a0d90ad8a30ae23c31c1a0e74fb0156a` |
| `installer\AuthLens-2.0.0-Setup.exe` (Desktop) | 93,408,097 | `d052972824abff450b6a36918604b29cbdcecb33ec09595215fb07e55a8b4b66` |
| `server\AuthLens.Api.exe` | 123,317,863 | `941722a823321f5c327218e7484173af498d6e9995713f2f65c8b5be51bcee71` |
| `desktop\AuthLens.exe` | 178,518,654 | `85f2ca1831014a3a45cc73c3a5e8b107626d14a179a90d5601aac8177b305223` |
| `build-manifest.json` | 5,933 | `74f07479de9a9763a80f719dda286c853eacf9202c8e86bee0a2b402adc27185` |
| `installer\installer-manifest.json` | 916 | `a1be5e99005e995dd7964b32411afefd108a2c031639924dd4d850626d55086a` |

Earlier run directories (`…_0948-8ec7f77`, `…_1815-c780ff6` RC1, `…_1926-af744c9` RC2, `…_2021-19a1113` RC3-VM130) are unchanged.

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
| Existing state | AuthLens 2.0.0 RC3-VM130 (`19a1113`) installed as a service (network mode, behind a trusted reverse proxy) with application data; port 18795 in use by it; journal terminal. Preserve its backups, keys and data. Independent recovery bundle `C:\AuthLens-Recovery\20261125T1218352809646Z-…` (verified, escrow verified, restore rehearsal passed) |
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
| 3 | D12 | Validation outcomes from the service (next candidate) | Not run | | | |
| 4 | B6 to B10 | Failed-install retry, upgrade, repair, interrupted deployment, cleanup | Not run | | | |
| 4 | E3 to E5 | Cross-instance restore, evidence integrity, SAP Lens backup migration | Not run | | | |
| 4 | F9 | Service restart and VM reboot | Not run | | | |

### RC4 native results on VM130 (2026-11-25)

Candidate RC4 `37eadd5` (run directory `C:\AuthLens\AuthLens-2.0.0-2026-11-25_0807-37eadd5`); installed baseline RC3-VM130 `19a1113` (not
upgraded); evidence `C:\AuthLens\acceptance\AuthLens-2.0.0-2026-11-25_0807-37eadd5\<scenario>`. Agent-run steps used a non-elevated session
unless stated; the operator ran the elevated read-only OP1 batch and the recovery capture. Statuses: PASS · FAIL · BLOCKED · NOT RUN · N/A.

| ID | Scope and context | Result | Evidence | Status |
| --- | --- | --- | --- | --- |
| A1 | RC4 artifact identity | All 32 artifacts match `build-summary.json`; both verifiers 17 artifacts at `37eadd5`; installer checksums OK; 7 helpers match; installers unsigned | `A1-verify\rc4-verify.txt`, `OP1\A1.txt` | PASS |
| B1 | Read-only network suggestions, RC4 tools | `10.0.7.50`, host `windows-vm`; nothing created under `C:\ProgramData\AuthLens` | `B1\` | PASS |
| B13 | Simulations on the installed terminal-journal state, RC4 packaged tools | 26/26 non-elevated and 26/26 elevated (original runner: exit, simulation fields and full state comparison per case); 26/26 again non-elevated with the WP21 harness asserting the exact reason, `simulation`, `changes_applied` and unchanged state. Interrupted-journal simulation (runbook B13 procedure on a `manual_recovery_required` install) not covered | `B13\`, `B13-elevated\`, `B13-wp21-nonelevated\results.json` | PASS (terminal state); interrupted state NOT RUN |
| B14 | Elevation refusals with `-Yes`, non-elevated, WP21 harness | 5/5 refused on the elevation gate (reason asserted; the approval reason forbidden), state unchanged | `B14-elevation-wp21\results.json` | PASS |
| B14 | Approval refusals without `-Yes`, elevated | Not run: needs the elevated `B14Approval` group (the original `B14\cases.json` mixed both and was never executed) | — | NOT RUN (operator) |
| B17 | Upgrade readiness and read-only upgrade preflight | Preflight exit 0 (OP1); readiness FAIL `protected_file_hash_mismatch` with the alpha-era bundle, then PASS twice with the new RC3 bundle (39 protected files; `upgrade_authorized: false`, `NO-GO`) | `OP1\B17-upgrade-preflight.*`, `B17-upgrade-readiness-recheck-*.txt` | PASS (readiness only) |
| B17 | Upgrade, repair and preservation | Not run: needs `-Operation Lifecycle` (snapshot attestation, operator authorization) | — | NOT RUN (operator) |
| WP22 | Isolated restore rehearsal of the RC3-VM130 bundle `20261125T1218352809646Z-…` | Archive verified with the copied key; actual restore activated in an owned loopback process (synthetic TLS, `--no-worker`); HTTPS, identity `19a1113` and frontend; integrity and foreign keys ok; 10 business/evidence tables and the accounts fingerprint identical across archive, restore and restart (1 user, 1 enabled administrator); active service (PID 152), configuration, certificate, key and archive unchanged | `WP22-restore-rehearsal\restore-result.json` | PASS |
| C12 | Certificate details and public export, RC4 server executable against the installed configuration | Identities `10.0.7.50`, `WINDOWS-VM`, `localhost` covered; public DER `.cer` without private key; second export refused, file unchanged | `C12\` | PASS (executable); installed Service Manager NOT RUN (RC3 installed; the build copy refuses without its installed tools, as designed) |
| D0 | Source authority folder | Absent on VM130 (alpha.1 install updated to RC3) | `D0\`, `WP23-source\Status.txt` | FAIL → D-007 |
| ACL | Named-account access to private material | `windows-vm\<operator>` explicit FullControl on `C:\ProgramData\AuthLens`, inherited by every private folder; RC4 AuditAcl `safe: true`; development source reports it (`named_principal_access: true`) | `phase1\AuditAcl.txt`, `WP23-source\AuditAcl.txt` | Finding → D-008 |
| B11, B12, B15, B16, T-001, C11, C13, C14 | Recovery, certificate, network, restart scenarios | Need interrupted or changed installation states, elevation and a retained snapshot | — | NOT RUN (operator) |
| D1–D12 | CSV and server sources through the installed service | Need an administrator sign-in on VM130 and source files; D-007 blocks server-source authorization on this installation until provisioned | — | BLOCKED |
| D3 remote | Remote SMB with the service identity | VM130 is a workgroup machine with no remote file server or domain computer account | — | BLOCKED (infrastructure) |
| F1–F10 | Functional acceptance in the installed UI | Need operator sign-in; source-level browser specs ran instead (not native acceptance) | — | NOT RUN |

### User feedback of 25 November 2026 (BUG-01 to BUG-10)

Source-level only (development source after RC4; browser specs against the isolated test host, not packaged native acceptance). Each item
needs native acceptance on a candidate that contains it (RC5).

| Item | Priority | Reproduction | Root cause | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- | --- | --- |
| BUG-01 Toggle review panel | Medium | Reproduced (source): row control only opened | `useSodReviewAction` exposed `open` only | Same control toggles (stable name, `aria-pressed`, icon/tooltip state); closing changes only the subject | `user-feedback-2026-11.spec.ts` BUG-01; `sod-evidence-modals.spec.ts` | Fixed (source) |
| BUG-02 Review from Release role details | High | Reproduced: plain identifier, no review action | Release drill table did not use the shared review action | **Review** per reviewable user opens the shared panel with the role highlighted; non-reviewable users show none | BUG-02 test | Fixed (source) |
| BUG-03 Functional Group navigation | Medium | Reproduced: groups were plain text | Dialog listed names only | Groups with an id open their member list (read-only without admin) | BUG-03 test | Fixed (source) |
| BUG-04 Inactivity timeout | High | Reproduced (source): `/api/auth/me` refresh every 30 s and every request moved the idle clock | No distinction between user activity and background reads; no warning | Passive reads, server timing and explicit continue, warning dialog, tab sync, cache clearing on expiry; server-enforced | `AccountsTests` (2 new), `session-timeout.spec.ts`, `session-timing.test.ts` | Fixed (source) |
| BUG-05 Personal theme | High | Not reproduced: already per user, `profile` permission, persistent | — | Verified; account-switching coverage added | `AccountsTests` (existing), `personal-preferences.spec.ts`, `session-timeout.spec.ts` | Verified (source) |
| BUG-06 Group cell width | Medium | Reproduced: fixed `width:17rem` and `min-width:18rem` | Fixed widths | Content-sized chips and column (max 20rem, labels max 14rem with tooltip) | BUG-06 assertion | Fixed (source) |
| BUG-07 Progress on profile | Medium | Reproduced: no progress outside the panel | — | Profile **Role review** from the same query and counting rule as the panel | BUG-07 test | Fixed (source) |
| BUG-08 Filter reset on navigation | Medium | Reproduced: pages stayed mounted with their filters | Kept-alive pages and history filters across main navigation | Main navigation is a page boundary (remount, clear temporary history filters); context links, Back/Forward and Saved Filters unaffected | BUG-08 test; navigation and filter specs | Fixed (source) |
| BUG-09 Sidebar horizontal scrollbar (reopened: username and role identifiers wrap, overflow and resize) | Medium | First round not reproduced (Role Lookup sidebar, 1440/1600 px). Reopened and reproduced with long synthetic role names: the role card (`div.role-entry`) scrolled sideways and the name left its box at 375 to 1280 px, and identifiers changed size while the filter sidebar opened or closed | `RoleIdentifier` scaled its font with a ResizeObserver and, below 9 px, marked itself `data-fit="overflow"`, which made the surrounding container scroll; the size was recomputed during each sidebar transition; the copy feedback took a full-width flex line and wrapped the row | One line inside the identifier box: fixed font size, `text-overflow: ellipsis` with the full name in the title, accessible name and copied value; copy and open icons never shrink; no container scrolling; copy feedback is an overlay. Tables and matrices keep their own scrolling | `role-codeblocks.spec.ts` (Role Lookup, Access Package, User Access, SoD at 375/800/1280 px; hover, focus and four sidebar toggles in light and dark; exact copy) | Fixed (source); Windows acceptance pending |
| BUG-10 Word wrapping | Medium | Reproduced by inspection: `overflow-wrap:anywhere` on labels | `anywhere` lowers min-content to one character | Labels use `break-word`; technical values keep `anywhere`; identifiers unchanged | BUG-10 assertion | Fixed (source) |

### RC6 mobile defects (WP29, BUG-011 and BUG-012)

Source-level only: Chromium touch emulation and narrow viewports against the isolated test host. **No iOS Safari acceptance has run**; desktop
WebKit or emulation is not evidence for iOS Safari. Native check: open Release Roles and a Settings select on a real iPhone (Safari), confirm
exactly one picker appears, and confirm the header is one row without clipped actions in portrait and landscape.

| Item | Reproduction | Root cause | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- | --- |
| BUG-011 Duplicate dropdown on iOS Safari | Reasoned from the code path; not reproducible without iOS Safari | Shared `Select` opened its custom popup on `mousedown`; iOS also shows the native picker for the touched `<select>`, so two lists appeared | Touch pointers (`pointerType` `touch`) leave the native picker alone and close the custom popup; mouse and keyboard are unchanged | `mobile-ui-wp29.spec.ts` (touch versus mouse), existing Select specs | Fixed (source), iOS pending |
| BUG-012 Mobile header and sticky areas | Reproduced: header wrapped to 116 px at 390 px | Brand and utilities wrapped onto two rows | One nowrap row below 768 px, brand ellipsized, 44 px touch targets kept, safe-area insets for the header and the Settings action bar | `mobile-ui-wp29.spec.ts` (≤ 64 px at 390/375/320, no horizontal scroll), `mobile-acceptance.spec.ts` touch targets | Fixed (source), iOS pending |

### RC6 Functional Group pill layout (BUG-013, P1, target 2.0.0)

Found during RC6 acceptance on DASH1: in the User directory and Account Review the Functional Group cell showed two stacked pills with the
**View groups** action drawn over them. Frontend-only; the RC6 backend already returns group id, name and status in `functional_groups` and
serves `/api/functional-groups/<id>/members` (no backend source change since `839123c`).

| Item | Root cause | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- |
| BUG-013 Functional Group pills overlap | `.fg-chip-stack` was a CSS grid whose auto track had the min-content of the nowrap label (up to 14rem), so it could not shrink inside the bounded cell; the two stacked pills overflowed and the ghost **View groups** button was laid over them | `Shared/FunctionalGroupPills`: one nowrap line, the first group as a named pill (ellipsis, full name in title and accessible name) that opens its member list, then `+X` (X = remaining groups) that never shrinks and opens the full list; 0 groups shows `Unassigned`; no fixed column width | `user-directory-scope.spec.ts` (0, 1, 2, 3, 5 groups, long name, narrow column, 390/1280 px, light/dark, keyboard and dialogs), `functional-groups.spec.ts` (User directory and Account Review), `user-feedback-2026-11.spec.ts` (BUG-03/BUG-06) | Fixed (source). Browser: the three specs passed 21/23, the two 390 px cases failed because the named pill was scrolled under the sticky username column (focus obscured); fixed with `scroll-padding-inline-start` on the table, then `user-directory-scope.spec.ts` 6/6. DASH1 recheck with RC7 |

Pills stay 28 px high (below the 44 px touch target guidance); no real iPhone check has run.

### Position Changes page and a pre-existing Account Review defect (after RC6)

| Item | Finding | Resolution | Tests | Status |
| --- | --- | --- | --- | --- |
| Position Changes page | The priority table took most of Account Review | Dedicated User Access page reusing the Account Review rows, decisions and dialog; Account Review keeps the metric, which opens the page | `PositionChangeTests` (filters, overlapping counts, shared decision, validation), Account Review classes 18/18; `position-changes.spec.ts`, `account-review-refinement.spec.ts` (tile navigation instead of filtering), navigation specs | Implemented (source) |
| Account Review *Review decision* filter returns no accounts | Reproduced at HEAD before this change: `account-review-completed.spec.ts:35` and `account-review-refinement.spec.ts:625` (expected 2 accounts, got 0) fail identically with and without the Position Changes change | Not fixed here; root cause to be investigated (recorded, not hidden) | — | **Open (pre-existing)** |
| Stale browser expectations found during the BUG-09 Level 2 run | Reproduced identically at HEAD `bbcfc0d` with the identifier change stashed: `access-investigation.spec.ts:35` (expects 4 main navigation links, there are 5 since Reviews) and `:152` (no *Back to Release Roles*), `refinement-completion.spec.ts:26` (8 layouts, no *Saved filters* in the User Access region), `:102` (PR matrix 199 against 200 buttons), `:115` (popover position), `refinement-search-layout.spec.ts:16` at 375 px (*SAP Modules* tab), `role-visuals.spec.ts:195` (*Theme* combobox), `data-aware-ux.spec.ts:119` and `consolidated-role-ui.spec.ts:136` at 800 px (no *User Access* link), `ui-polish-actions.spec.ts:107` (*Reports* link) and `:146` | Not caused by BUG-09; not changed here. Classified against code and history (obsolete navigation or count expectations, Settings navigation test defects, one order-dependent case, and an application defect in the Compare users table) and mapped to COR-1, COR-T and NAV-1/4/6/7 in the [navigation plan](WORK_PACKAGES.md#open-defects-from-the-bug-09-level-2-run-classified); assertions are not weakened | — | **Open (pre-existing)** |

### RC7 build preparation (Windows release build of `7e5a6e7`)

| Item | Root cause | Resolution | Tests | Status |
| --- | --- | --- | --- | --- |
| `build.ps1` failed in a clean detached-HEAD worktree (line 21, `InvokeMethodOnNull`) | `git branch --show-current` prints nothing for a detached HEAD, and `.Trim()` was called on null; `build-release.ps1` records `rev-parse --abbrev-ref HEAD` (`HEAD`), so the two identities would also have disagreed | `Get-AuthLensBranch` (Build-Workflow.ps1) reads the same `rev-parse --abbrev-ref HEAD` as the manifest and refuses an unidentifiable HEAD; dirty-tree refusal unchanged | Pester `Artifact-Layout.Tests.ps1` (real Git repository: branch, detached, dirty, not a repository) 37/37 | Fixed (source) |
| `SodRoutesTests.Read_routes_equal_python_v1` failed (population field) | The build used `7e5a6e7`, before the fix `c619224` (BUG-015 reported `population` on every matrix response) | `c619224` is in the branch; no further change | `SodRoutesTests`, heatmap and analysis tests 5/5 on the current code | Fixed; confirm in the next Windows build |

### RC6 scheduled refresh and source timestamps (no identifier assigned; target 2.0.0)

Reported from the installed Windows Server: daily 09:05 Europe/Oslo enabled, but the three upcoming runs and *Next run* showed *Not
available*, the outcome *Never*, the Dashboard *Last successful refresh: Not available*, and Role Catalogue (96 records, durable snapshot)
*Not yet loaded* / *Not yet checked*. Backend and frontend change; ships with RC7.

| Item | Finding | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- |
| Culture-dependent ISO timestamps | Confirmed in code and reproduced under .NET 10/ICU: `ToString("yyyy-MM-dd'T'HH:mm:ss...")` without a culture uses the regional time separator (`08.05.00` under da-DK, fi-FI). The UI shows *Not available* only when a value is present but unparseable (an absent `next_run` reads *Not scheduled*), so the reported screen matches this cause. Affected: scheduler runs and state (`V1RefreshSchedule.Iso`), source import/check stamps (`V1DataSources.Stamp`), refresh lifecycle, diagnostics, storage, backups, retention, data health, employee import, migration | Host runs culture-invariant (`AuthLensHost.UseInvariantCulture`, also Server and Desktop entry points); every custom format names `InvariantCulture`; `IsoTimestamp.Repair` reads earlier dotted values (scheduler state, diagnostics, dashboard) and the UI formatter accepts them | `RefreshTests` (da-DK formatting, repair, invariant host, Europe/Oslo daily with DST and three runs, runtime change, run-once, persisted state and restart, Dashboard and Diagnostics agreement, dotted state repaired, unusable schedules refused) 20/20; affected classes 170/170; `date-format.test.ts`; `scheduled-refresh.spec.ts` 4/4 | Fixed (source) |
| Did the scheduler run? | Not determinable from the report: with dotted timestamps the state file is discarded on read, so *Never* is shown whether or not a run happened; the schedule calculation itself works for Europe/Oslo on Windows | RC7 reads earlier state; the native check below establishes it | Windows procedure | Native pending |
| Silent failure | An enabled schedule that cannot be evaluated idled without a log entry | Logged once per definition; the status reports `error`, an enabled schedule without upcoming runs is never healthy; `scheduler_active` exposes `--no-worker` | `RefreshTests` | Fixed (source) |
| Unknown history | Not reproduced as a separate defect: with an active dataset the source reports its activation time; *Not yet loaded* came from an unparseable stored stamp | No fabricated timestamps; unchanged semantics of activation, check, attempt and refresh | — | Closed (explained) |

**Windows acceptance (after installing RC7; read-only first).** 1. Before the upgrade, record `Get-Content <data>\refresh-schedule.json`
and the Data Sources timestamps (dots between hours and minutes confirm the cause). 2. After the upgrade, Settings > Runtime & Scheduling
shows three upcoming runs and *Next run* as dates; earlier outcomes appear instead of *Never*. 3. Set the daily time 10 minutes ahead in
Europe/Oslo, Apply, and without a browser open wait past it: *Last attempted run* and *Last successful run* show that time; the Dashboard
*Last successful refresh* and each Dynamic source's *Last source attempt* update; Static sources are unchanged. 4. Restart the service: the
schedule and outcome remain. 5. Disable the schedule: no further run. Evidence: screenshots and the service log lines `Scheduled refresh
finished (status=...)`.

### RC6 SoD heatmap population (BUG-015, P1, target 2.0.0)

Found during RC6 acceptance on DASH1: with Functional Group *Controlling (7)* the SoD Overview reported 7 users with potential conflicts
while the **Conflicts by SAP User Group** heatmap still showed 249 distinct users. Backend and frontend change; ships with RC7.

| Item | Root cause | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- |
| BUG-015 Heatmap ignores the Overview filters | `SodGroupHeatmap` always requested `/api/sod/matrix/{kind}?group_by=group` and the CSV with `emptyFilters`, so it was global on every page, while the Overview key figures use `SubjectSelection` | New optional `population=overview` on `/api/sod/matrix/{kind}` and `/group-export`: the population is resolved by the same `SubjectSelection` call as `/api/sod/overview` and selects whole users after conflict evaluation (complete conflicts kept); without the parameter the routes are unchanged. The heatmap sends the page's population (Overview filters, or the page's own filters without its group and risk/activity selection) to the matrix and the CSV, and states Global or Filtered | `DashboardAndSavedFiltersTests.SoD_group_heatmap_and_export_follow_the_overview_population` (global equality, KPI = distinct total, complete user conflicts, group rows, CSV, empty population, invalid mode; risk and activity), `sod-heatmap-population.spec.ts` (filtered KPI and heatmap agree in both modes, multi-conflict user, empty population, clearing, filtered CSV, drill-down keeps the population) | Fixed (source); DASH1 recheck with RC7 |

Level 2 for BUG-015 (`sod-overview-heatmap`, `sod-shared-heatmap`, `filter-consistency`, `mobile-acceptance`, `consolidated-refinement`)
found pre-existing test defects, not product defects: four `sod-shared-heatmap` tests and one `consolidated-refinement` test still expected
Reviews, Review Periods and Reports inside the SoD workspace, but these moved to the top-level Reviews workspace, which intentionally has no
SoD heatmap. The expectations now cover the four SoD subtabs and assert the heatmap's absence in the Reviews workspace; one layout-timing
measurement (sidebar Clear/Close alignment, 3/3 alone, failing only under load) now waits for a settled layout with the same 2 px tolerance.
Result after the corrections: all affected files passed.

### RC6 Dashboard filter layout (BUG-014, P1, target 2.0.0)

Found during RC6 acceptance: the WP30 dashboard filters opened as a right-hand drawer over the cards instead of the integrated filter
sidebar every other module uses. WP35 found frontend-only deployment not feasible, so BUG-013 and BUG-014 ship with the next consolidated
candidate (RC7).

| Item | Root cause | Resolution | Regression tests | Status |
| --- | --- | --- | --- | --- |
| BUG-014 Dashboard filters overlay the cards | WP30 built a dashboard-specific `SidePanel` (right, 460 px, over the content) instead of reusing `Shared/FilterLayout` | Dashboard uses `FilterLayout` like User Access: integrated left sidebar from 1024 px (no dialog, backdrop or focus trap), the shared drawer below; closed by default with its own remembered state (`storageKey`, `defaultOpen`, backward compatible); `FilterSection` groups; Apply at the top and bottom of the sidebar; Clear (`Reset dashboard filters`) in the sidebar header and **Reset filters** in the toolbar; card columns follow the workspace width (container query) so an open sidebar reflows the cards. Filter semantics, queries and drill-down unchanged | `dashboard-filters.spec.ts` (closed default, integrated left sidebar, reflow and hide, no dialog, no page overflow, toggling keeps filters and requests no dashboard data, chips, Apply, both Resets, drill-down, Saved Filters round-trip, matching mode, 375 px drawer, light/dark), `filter-consistency.spec.ts`, `dashboard-user-transactions.spec.ts`, `startup-reliability.spec.ts`: 21 passed | Fixed (source); DASH1 recheck with RC7 |
| WP30 defect: saving dashboard filters failed (found by BUG-014) | `V1SavedFilters.Views` accepted `dashboard`, but `Allowed` had no field list for it, so every save raised `KeyNotFoundException` (HTTP 500) | Field list for `dashboard` (population dimensions, exact usernames, `access_scope`, Functional Group and Manager); a test asserts every accepted view has a field list. Backend change, so it needs RC7 | `DashboardAndSavedFiltersTests` 14/14 | Fixed (source) |

Baseline browser failures investigated in RC6 (all test defects with outdated expectations; no assertion was weakened):

| Spec | Root cause | Correction |
| --- | --- | --- |
| `live-filters-polish` catalogue exact OR filtering | Category pills became the shared multi-select dropdown in `8c6ea68`; the spec still clicked the old button | Selects MM through the `Role categories` dropdown; the same counts are asserted |
| `startup-reliability` loading and restart cases | Since `2a78dfc` the dashboard sent `/api/dashboard?…`; the route mock `**/api/dashboard` no longer matched, so the modelled states never reached the page | Route matches the endpoint with or without a query string (never `/filter-options`); the dashboard also omits an empty `?` |
| Visual specs at 375 px (`employee-directory`, `live-filters-polish`, `csv-lifecycle`) | Main navigation and Settings tabs move into drawers below 1024 and 768 px | Use the responsive `goTo` and `selectSettingsSection` helpers |
| `dashboard-user-transactions` KPI navigation | BUG-08 made main navigation a page boundary; the spec expected Role Lookup to keep its search | Expects the fresh page, then checks the KPI reset separately |
| `investigation-ux` (visual, import source) and `navigation-modules` (data-source focus) | The Desktop CSV path field sat inside a collapsed `<details>`, so the specs could not reach it (the RC4 and RC5 "CSV file location hidden" failures) | Fixed in the product by WP33 (the field is shown directly); both specs pass unchanged |

Regression run after these corrections (isolated test host, Chromium): `user-feedback-2026-11` (BUG-01 to BUG-10), `session-timeout`,
`global-navigation`, `investigation-ux`, `sod-assignment-decisions`, `personal-preferences`, `navigation-modules`: **40 passed, 0 failed**;
`startup-reliability`, `live-filters-polish`, `dashboard-user-transactions`, `dashboard-filters`: passed. FULL browser suite not run.

### Acceptance tooling and recovery requirements (QA-001 to QA-032)

| IDs | Status | Implementation |
| --- | --- | --- |
| QA-001, 004, 010, 012, 018 | Implemented | `backend/scripts/acceptance` (`Invoke-AcceptanceGroup`, Lifecycle `Assert-Step`): failed mandatory steps throw, groups stop on mutation, no completion after a failure, `results.json`, exit 0/1/2/3 (Pester `Acceptance-Harness`) |
| QA-002, 003, 016 | Implemented | `Test-AcceptanceMutationPrerequisites`: explicit passed recovery report, readiness PASS for the candidate within 24 h that used an explicit report, verified escrow, installed baseline, snapshot attestation recorded as not verified |
| QA-005, 011 | Implemented | `B14-approval.json` (elevated, no `-Yes`) and `B14-elevation.json` (non-elevated, `-Yes`); context checked before anything runs; `-Yes` cases refused in groups that may run elevated |
| QA-006, 013, 014, 015 | Implemented | Expected and forbidden refusal reasons, `simulation`, `changes_applied`, result fields asserted per case; exit-only cases refused |
| QA-007 | Implemented | `-Tools Installed` uses the staged `app\setup\<package>\tools`; Lifecycle uses the installed Service Manager and tools after the upgrade |
| QA-008, 009 | Implemented (Lifecycle, not run natively) | Fingerprints (`--fingerprint-data`) before/after upgrade and repair compared separately; certificate thumbprint, configuration hash and service account/start/command line checked |
| QA-017, 021, 022, 023 | Implemented | Readiness: mismatch category, side and file; recovery versus active program identity; explicit report selection reported, fallback warned |
| QA-019, 020, 024 to 027, 029, 031 | Implemented | `backend/scripts/recovery` bundle and rehearsal scripts; restore rehearsal PASS natively |
| QA-028 | Implemented, native verification pending | Recovery bundle and rehearsal scripts (with the acceptance module the rehearsal imports) are in the packaged helper inventory and the portable package; Service Manager `CreateRecoveryBundle`/`VerifyRecoveryBundle` (elevated, explicit destination outside the installation, private ACL, verification with the copied key, no restore) run the installed hash-verified tooling; Pester `Service-Manager`, `AuthLens.Installer`, `Upgrade-Readiness`; not yet run natively |
| QA-030 | Implemented | Lifecycle refuses without verified escrow; rehearsal uses only the bundle's copied key |
| QA-032 | Implemented | Bundle ACL check includes named principals; AuditAcl named-account findings (D-008) |

### WP25 release assessment (2026-11-25)

| Gate | State |
| --- | --- |
| Artifact identity and integrity (RC4) | PASS (A1); unsigned |
| Simulation and approval safety (D-006) | B13 PASS on the terminal state; B14 elevation PASS; B14 approval and interrupted-state B13 NOT RUN |
| Recovery and restore | Bundle verified, escrow verified, isolated restore rehearsal PASS; snapshot only operator-attested |
| Upgrade, repair, recovery scenarios on the installation | NOT RUN (operator authorization and snapshot required) |
| Session security | BUG-04 corrected in source (server-enforced idle expiry no longer extended by background reads); native acceptance pending |
| CSV and server sources | BLOCKED (sign-in; D-007 on VM130; remote SMB infrastructure) |
| Browser acceptance | Source-level specs only |
| Signing, AppLocker/deployment policy | Not done (not authorized); unsigned |
| FULL regression | Not run (not authorized) |

**RC5 decision.** The changes after RC4 alter runtime code (session handling, source authority API, `--fingerprint-data`), the frontend and the
packaged deployment tools (D-007, D-008), so a release needs a new consolidated candidate; RC4 evidence does not transfer to it. **RC5 was built** from `b10dd50` ([build record](#rc5-build-record)). **Release
recommendation: NO-GO** until native acceptance on that candidate, remote UNC (D3), the final FULL regression and signing are complete. DASH1
is not to be changed.

## Defects and gaps

"Corrected in implementation" means fixed in source with focused automated evidence on the development workstation; native acceptance on the
VM is still required and is tracked by the scenario rows above.

| ID | Class | Found | Description | Root cause | Correction | Status |
| --- | --- | --- | --- | --- | --- | --- |
| D-001 | Product defect (P0) | 2026-11-24, reproduced on the workstation with a Setup-shaped configuration | Installed `Deploy-AuthLens.ps1` refused Setup-published configurations ("Deployment setting 'RepositoryPath' is required"): Status, Health, InstallService, ReplaceCertificate (and its rollback), Restore, Rollback and Recover all failed on Setup-created servers | `Read-AuthLensSettings` required `RepositoryPath` unless the caller passed `-Packaged`; only the installer adapter did, `Deploy-AuthLens.ps1` and the certificate restoration did not. The `-Packaged` path also substituted the module folder as a fake repository path | Execution context derived from the configuration (`repository` with `RepositoryPath`, else `packaged`); no invented path; only source builds (`Resolve-ALCommit`, `New-ALWorktree`) refuse in packaged context; Status reports `execution_context` | Corrected in implementation: `Packaged-Runtime.Tests.ps1` (Setup-shaped configuration; installed tool layout copied from the `build-installers.ps1` inventory and run outside the repository from another working directory), `Server-CertificateReplacement.Tests.ps1` and `Server-NetworkChange.Tests.ps1` on Setup-shaped configurations; native pending (B3, C8, C9, E3) |
| D-002 | Product defect (P1) | 2026-11-24, packaged-runtime audit (source inspection) | The Start-menu Service Manager shortcut passes no `-DataDirectory`, and Service Manager defaulted to `C:\ProgramData\AuthLens\data`, so on a custom root or data directory key and code operations targeted the wrong (possibly new) directory | Hard-coded default instead of the installation's configuration | Without `-DataDirectory`, Service Manager resolves the configuration Setup registered (`HKLM\Software\AuthLens\Server` `ConfigFile`) and uses its `DataDirectory` (or `Root\data`) and `ServiceName` | Corrected in implementation (`Packaged-Runtime.Tests.ps1`); native pending (C3 to C7 on a custom root) |
| G-001 | Implementation gap (P1, original remediation scope) | Product owner, 2026-11-24 | No supported post-installation network configuration: manual JSON edit plus `InstallService -Reconfigure` without validation or rollback | Not implemented in the first remediation | Service Manager options 8/9 (`NetworkStatus`, `ChangeNetwork`) over `Deploy-AuthLens.ps1 -Action ChangeNetwork`: validation (access-mode rules, assigned address, port ownership, packaged-host preflight with the existing certificate), consolidated summary, explicit confirmation, recorded transaction shared with certificate replacement, readiness/listener/identity verification, automatic restoration, interrupted-run recovery (`Recover`), explicit owned-firewall decision | Implemented: `Server-NetworkChange.Tests.ps1` (7 tests); native pending (C9, 8.15) |
| D-004 | Product defect (P1) | 2026-11-25, DASH1 (operator, native) | The installer-generated certificate does not cover a listener IP configured later (`10.26.1.55`), and the installed release's `--server-preflight` refuses it, so every operation gated by that preflight (Setup, VerifyCandidate, ReplaceCertificate, ChangeNetwork) refuses the installation | Three inconsistent SAN requirement sets (source inspection): runtime startup (`HostSettings.Validate`) requires the allowed hosts in network mode only; `--server-preflight` (`MaintenanceCommands.ServerPreflight`, since `503b0f9`, also in `8ec7f77`) requires allowed hosts **plus the bind address** in every mode; generation (`New-ALServerTlsMaterial`) issues listen address + allowed hosts (+ `localhost` on loopback) once, at fresh install. A bind address that no client uses as Host is required anyway, and a later listener change invalidates an otherwise valid certificate | WP20: one shared endpoint-identity rule for generation, runtime, preflight, network change, replacement and recovery (allowed hosts in network mode, the readiness probe authority, the loopback address in Local mode; the bind address only when it is an intended HTTPS identity, that is, listed as an allowed host); hostname verification, pinning, trust and the Host filter unchanged | Corrected in implementation (WP20, `6fbfd48`; operator report INST-109 to INST-113): shared `RequiredIdentities` rule in runtime, preflight, network change, replacement and recovery; `--certificate-info`, `--certificate-export-public`, Status `certificate_status`, Setup review page. .NET `ServerPreflightTests` (DNS-only certificate with an IP listener accepted, allowed IP required, wildcard, loopback); Pester `Server-TlsLifecycle`, `Server-NetworkChange`. Native pending (C12, C13). DASH1 operational evidence: replacement certificate active since the manual remediation |
| D-005 | Product defect (P2, usability) | 2026-11-25, DASH1 (operator, native) | Service Manager recovery-key export with a directory instead of a file name ended Service Manager with an access-denied exception | One "absolute key file path" prompt validated only that the path is absolute; the packaged host opened the directory create-only (`UnauthorizedAccessException`, exit 3); the script rethrew at top level and ended (the Start-menu shortcut runs `powershell.exe -File` without `-NoExit`). `recovery.export_requested` is audited before the write; a failed export adds no failure audit entry | WP19: separate directory and file-name prompts, default `AuthLens-<ComputerName>-recovery.key`, extension normalization, destination validation before execution, automatic verification of the exported copy, menu loop with actionable errors | Corrected in implementation (WP19): separate folder and file-name prompts, default `AuthLens-<computer>-recovery`, `.key` added once, quotes and spaces, complete destination validation (folder as file, relative, invalid names, junctions, data directory, existing file, write access) before anything runs, confirmed protected folder creation, automatic verification after export, menu loop with actionable errors and a diagnostic log without secrets. `Service-Manager.Workflow.Tests.ps1`; native pending (C6, C11) |
| D-006 | Product defect (**P0, release blocker**) | 2026-11-25, DASH1 (operator, native; operator report INST-114 to INST-116) | `Deploy-AuthLens.ps1 -Action Recover -RecoveryAction VerifyCandidate -DryRun` (RC3-VM130 packaged tools) performed the real recovery: exit 0, `recovered: true, phase: complete`; the journal moved from `manual_recovery_required` to `complete` (new history entry 2026-11-25T06:48:03Z, earlier history kept), `recovery_needed` false; service PID 4944, runtime identity and readiness unchanged; no data restored. The same command without `-DryRun` had correctly refused for missing `-Yes` | The approval gate exempted every changing action when `-DryRun` was given (`$changing = ... -and -not $DryRun`), but only Deploy, ReplaceCertificate, ChangeNetwork and ProtectAcl implement a simulation. **Recover, Restore, Rollback, InstallService and RestoreAcl ignored `-DryRun` and ran for real without `-Yes` and without the elevation check**; Build also ignored it (no approval needed). Simulations also created the deployment lock file and a run folder | One action policy (`Get-ALActionPolicy`): read-only actions; simulated actions (Deploy, Recover, ReplaceCertificate, ChangeNetwork, ProtectAcl); every other action refuses `-DryRun` (exit 2) before anything runs; `-DryRun` never replaces `-Yes`, and `-DryRun -Yes` is a simulation. New read-only `Recover -DryRun` preview (`Get-ALRecoveryPreview`: the same decision as the real run, every check, `would_succeed`/`would_phase`, no journal, note, service or configuration change). Simulations take the host mutex only (no lock file, run folder or log file), every result carries `simulation: true, changes_applied: false` and a SIMULATION line, a result claiming a completed operation is turned into exit 4, and a persistent-state snapshot (configuration, installed-product record, WorkRoot state files, release pointer and folders, TLS and key folders, service registration and process, Setup registry values) taken before and after a simulation must be identical (else exit 4). Also: an explicit recovery action on a finished journal now reports nothing to recover instead of re-verifying it (and, on a refusal, downgrading it to `manual_recovery_required`) | Corrected in implementation: `Deployment-DryRun.Tests.ps1` (11 tests: policy matrix of every action with and without `-DryRun`/`-Yes`; read-only previews; the real entry point on a synthetic installation with state compared before and after); affected Pester files 109/109; native pending (B13). DASH1's journal is `complete` now; its recovery result stands (all checks passed before completion) but was not an approved action |
| D-007 | Product defect (P2, confirmed) | 2026-11-25, VM130 (agent, native read-only; source inspection) | Installations created before the web source authority existed and updated since have no `.authlens-source-policy-*` folder, so authorizing a server source fails (the service cannot create the folder in the protected root) | Only service installation, repair (on activation), restore and configuration changes call `Grant-ALAccess`/`Initialize-ALSourceAuthorityDirectory`; `Invoke-ALDeploy` (Setup and CLI updates) did not | `Invoke-ALDeploy` provisions it before any change (create-only, service Modify; existing folders validated, never widened); Status `source_authority`; API 409 with remediation | Corrected in implementation after RC4 (`AuthLens.Deploy.Tests`); native: confirmed missing on VM130 (Status `missing` with the source tools); fix pending native acceptance on RC5. Workaround on RC4: installer Repair or `InstallService -Reconfigure -Yes` |
| D-008 | Audit gap (P2) plus environmental configuration | 2026-11-25, VM130 (agent, native read-only) | AuditAcl reported `safe: true` while an explicit named operator account held FullControl on the installation root and thereby on keys, TLS password, API token and database | The audit evaluates broad principals only, by design; the named ACE was added outside the product (installation code grants only SYSTEM, Administrators and the service) | Named-account findings (`named_principals`, `named_principal_access`, `review_required`) without changing `safe` or removing anything; bundle ACL checks include them | Audit improvement implemented after RC4 (`Acl-NamedPrincipals.Tests`), confirmed natively with the source tools; the VM130 ACE is an environmental issue for the operator to review (`icacls C:\ProgramData\AuthLens /remove:g windows-vm\<operator>` only if not deliberately approved) |
| G-007 | Implementation gap (P1; workaround verified on DASH1) | 2026-11-25, DASH1 analysis (source inspection) | No supported route when the active certificate itself blocks recovery: VerifyCandidate runs the **candidate's** `--server-preflight` with the configured certificate (on DASH1 the installed `8ec7f77` executable, which has the D-004 rule), and ReplaceCertificate/ChangeNetwork refuse while the journal is in a critical phase (`Assert-ALConfigurationChangeAllowed`: "An interrupted deployment requires -Action Recover before the configuration can be changed"). Setup upgrade and repair stop at the same journal barrier | Recovery and configuration transactions were designed separately; neither accepts a certificate change for an interrupted fresh install | WP20: a recorded certificate step inside candidate recovery (`Recover -RecoveryAction VerifyCandidate` with an explicit replacement PFX): import create-only into `tls\renew-<id>`, candidate preflight against the final configuration, service read grant, configuration and command line replaced through `configuration-pending.json`, restart, readiness pinned to the new certificate, completion; any failure restores the previous certificate and command line and leaves `manual_recovery_required`. Because DASH1 runs `8ec7f77`, correcting D-004 alone does not unblock it | **Operational workaround verified on DASH1** (2026-11-25, manual, see the DASH1 section): not a supported or intended deployment workflow. Product correction implemented (WP20, `6fbfd48`): `Recover -RecoveryAction VerifyCandidate|Resume` with `-CertificateFile`/`-CertificatePasswordFile` (`Install-AuthLens.ps1 -RecoveryCertificateFile`, Service Manager group 6) through the recorded configuration transaction; preview with `-DryRun`; failure restores the previous certificate and keeps `manual_recovery_required`; an interrupted step is restored before any journal decision. Pester `Deployment-Recovery`; native pending (B12) |

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
| Manual certificate remediation (operator, 2026-11-25) | Installed release `8ec7f77`, root `C:\ProgramData\AuthLens`, service `AuthLens` as `NT SERVICE\AuthLens`, listener `10.26.1.55:18795`, allowed hosts `enp-emea-dash1.emea.ecm.era`, `enp-emea-dash1`. Replacement self-signed certificate covering the required DNS names and IP addresses in a separate protected TLS directory; service-account read verified; read-only preflight passed before activation; original certificate and rollback configuration preserved; controlled manual switch of the deployment configuration and the SCM service arguments; then service configuration, listener ownership, HTTPS readiness, runtime identity and active preflight verified (6 migrations applied, none pending, no certificate warnings). Browsers required new trust for the changed fingerprint. Escrow recovery-key copy created and verified; encrypted application backup created (restore-preview validation not yet confirmed in the evidence) |
| Journal completion | Completed by `Recover -RecoveryAction VerifyCandidate -DryRun`, which ran the real recovery because of D-006: journal `complete` (2026-11-25T06:48:03Z), history kept, service PID 4944 and runtime identity unchanged, no restore |
| Status | **Operational.** G-007 workaround verified on DASH1; the product defect stays open until WP20 is accepted natively. Open: restore-preview validation of the new backup; the Setup registration still shows the state of the failed Setup (G-005). Do not repeat the manual procedure elsewhere; use the WP20 recovery certificate step once accepted |

### VM130 upgrade alpha.1 to RC3-VM130 (observation)

Operator functional test passed; formal evidence pending. Agent read-only observation during the R1 self-test (2026-11-24T21:29Z): journal
`20261124-211931-installer-ab89b53f` phase `complete` (backup > stopping > switched > starting > verifying > complete) from
`AuthLens-2.0.0-alpha.1-20261123-120358-8c6ea68-win-x64` with a pre-deployment backup; service running as `NT SERVICE\AuthLens`, command line
equals the configuration, listener owned by the service, ACL audit safe, `--server-preflight` validated (schema compatible, 6 applied, none
pending), pinned readiness 200 with runtime identity `2.0.0 19a1113`, Setup registration `verified`. Host key usable, recovery copy not yet
verified (backups blocked until it is). B7 stays **Not run** until the operator's evidence batch.

## Required corrections for the next candidate

Gaps from the DASH1 investigation and their delivery for the next candidate (implemented items are in the sources after RC3; a candidate build
needs approval). They are delivered through two work packages ([work-package tracker](WORK_PACKAGES.md#fourth-round-service-manager-usability-and-tls-lifecycle-wp19-wp20)); each ID is listed
once and keeps its own focused tests:

| Work package | Includes | Status |
| --- | --- | --- |
| D-006 (P0) | Simulation and approval policy of every deployment action | Corrected in implementation (`c077eaf`); native pending (B13) |
| WP19 Service Manager usability | D-005, G-003 (guided deployment recovery) | Implemented (Pester); native pending (C6, C11, B11) |
| WP20 Installer and TLS lifecycle | D-004, G-007, D-003 (loopback listener host rule), the certificate parts of G-001 network changes; operator report INST-109 to INST-113 | Implemented (`6fbfd48`, .NET and Pester); native pending (B12, C12, C13) |
| Recovery records | G-004, G-005, G-006 | G-004 and G-005 implemented (seventh round, Pester); **G-006 deferred** to a later release (refusal kept, no automatic adoption) |
| T-001 | Older-journal recovery cases | Automated part implemented (`Recovery-AuditRegistration.Tests.ps1`: older-build journal shape, configuration without AccessMode, consistent correction completes, five inconsistent states refused); native T-001 against an installed older release pending |

| ID | Class | Gap | Proposed correction | Focused tests |
| --- | --- | --- | --- | --- |
| D-004 | Product defect (P1) | Preflight requires the bind address in the certificate SANs; SAN rules differ between generation, runtime and preflight | WP20 shared endpoint-identity rule (see [D-004](#defects-and-gaps)) | `CertificatePolicy`/`ServerPreflight` .NET tests per access mode; `Server-Tls`, `Server-NetworkChange`, `Installer-Preflight` |
| D-005 | Product defect (P2) | Recovery-key export accepts a directory and ends Service Manager on access denied | WP19 guided export | `Service-Manager.Tests.ps1` path, permission, cancellation and verification cases; `BackupCryptoTests` directory destination |
| D-006 | Product defect (P0) | `-DryRun` bypassed approval and ran Recover, Restore, Rollback, InstallService and RestoreAcl for real | One action policy, read-only Recover preview, state snapshot guard (corrected in implementation) | `Deployment-DryRun.Tests.ps1` |
| G-007 | Implementation gap (P1) | No certificate step inside candidate recovery; configuration changes refuse under the journal barrier | WP20 recorded certificate step in VerifyCandidate | `Deployment-Recovery.Tests.ps1`: recovery with certificate completes; failure restores the previous certificate and phase; ordinary ReplaceCertificate still refuses under the barrier |
| D-003 | Product defect (corrected in implementation, WP20: loopback listeners refuse non-loopback hosts in every mode; `Server-TlsLifecycle`) | Loopback listener with non-loopback allowed hosts passes preflight in Auto mode | Refuse in preflight when the probe authority the readiness check will use is not accepted by the configured host policy (all modes, including Auto); Setup shows the reason before installing | Access plan and `Wait-ALReady` probe authority for loopback + corporate hosts in Auto, Local and Corporate; Setup preflight refusal before any service change |
| G-003 | Implementation gap (P1; implemented, WP19: Service Manager group 6; `Service-Manager.Workflow`) | Service Manager had no deployment-recovery workflow; Setup only says recovery is required | Service Manager option: show journal phase/history and offer only the actions valid for the state (VerifyCandidate when running, owned, no previous release; Resume when stopped; Rollback only with a verified previous release and backup; Cancel only at prepared/backup); run `Install-AuthLens.ps1 -Recover -RecoveryAction` after a summary and confirmation | State-matrix tests: each journal shape offers exactly its valid actions; refused actions never change the journal |
| G-004 | Implementation gap (P2; implemented: `recovery-audit.jsonl` and history entries, see the deployment guide) | The completion entry records only the phase, not which recovery action or operator reconciled it | Append action, actor, configuration and manifest hashes and the result operation ID to the history entry | Journal history contents after VerifyCandidate, Resume and Rollback |
| G-005 | Implementation gap (P2; implemented: reconciliation with proven ownership, registry outcome reported) | After CLI recovery the Setup registry key keeps `SetupState=pending-verification` and lacks `ConfigFile`/`Root`; readiness refuses until a Setup run rewrites it | Bind a supported registration update to a successful VerifyCandidate (same values Setup writes), never a manual edit | Registration before/after recovery; readiness wrapper accepts the reconciled registration |
| G-006 | Implementation gap (P1, conditional; **deferred** to a later release, refusal kept) | No supported reconciliation when the fresh-install data-ownership marker is gone (for example data copied back manually) | Explicit, audited "adopt verified restored data" path bound to a verified backup identity and the existing instance, never automatic | Missing/invalid marker refusal stays; adoption only with matching verified backup evidence |
| T-001 | Test gap (automated part implemented; native pending) | VerifyCandidate is not tested against a journal written by an older build (`manual_recovery_required` as terminal, no `-RecoveryAction` era) with a configuration without `AccessMode`/`RepositoryPath` and service arguments changed manually afterwards | Add the cases: consistent manual correction completes and preserves history; inconsistent command line, changed pointer, manifest/commit mismatch, pending markers and missing marker refuse | `Deployment-Recovery.Tests.ps1` |

New findings from RC3 acceptance are added above and consolidated before any further candidate.
