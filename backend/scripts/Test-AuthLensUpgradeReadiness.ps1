<#
.SYNOPSIS
Read-only Windows Server upgrade checks. Never authorizes or performs an upgrade.
.DESCRIPTION
Uses the existing packaged -Operation Upgrade -PreflightOnly contract. Child output is held in memory, never logged.
Recovery checks verify the previous verification report and current file hashes, not an actual restore or backup freshness.
No report files, directories, locks, configuration, keys or databases are created. Run from an administrator terminal.
-BuildDirectory accepts the WP32 category layout (C:\AuthLens\Build\<version>\<build-id> or C:\AuthLens\Installer\<version>\<build-id>; summary schema 2) and legacy run
directories (C:\AuthLens\<id> with build\ and installer\ inside; summary schema 1, RC5 and earlier), read in place.
#>
[CmdletBinding()]
param(
    [string]$BuildDirectory='',
    [string]$ExpectedSourceSha='',
    [string]$ConfigFile='',
    [string]$RecoveryReport='',
    # WP31 (SEC-5): a strict gate also refuses REVIEW_REQUIRED and UNSAFE installation ACL status; without it the status is reported as a warning.
    [switch]$StrictAcl
)
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'

function Stop-Readiness([string]$Code) {
    $failure=[InvalidOperationException]::new($Code)
    $failure.Data['AuthLensReadinessCode']=$Code
    throw $failure
}
function Test-ReadinessTrue($Value) { $Value -is [bool] -and $Value }
function Assert-ReadinessFields($Value,[string[]]$Fields,[string]$Context) {
    if($null -eq $Value -or $Value -isnot [pscustomobject]){Stop-Readiness ($Context+'_object_required')}
    foreach($field in $Fields){
        if(-not $Value.PSObject.Properties[$field]){Stop-Readiness ($Context+'_field_missing_'+$field)}
    }
}
function Assert-ReadinessManifestIdentity($Manifest,$Identity,[ValidateSet('release_manifest','installer_manifest')][string]$Context) {
    $fields=@('product','version','source_sha','branch','build_timestamp_utc','source_dirty','executables')
    Assert-ReadinessFields $Manifest $fields $Context
    Assert-ReadinessFields $Identity @('product','version','source_sha','branch','build_timestamp_utc') 'build_identity'
    Assert-ReadinessFields $Manifest.executables @('desktop','server') ($Context+'_executables')
    if($Manifest.source_dirty -isnot [bool]){Stop-Readiness ($Context+'_source_dirty_type_invalid')}
    if($Manifest.source_dirty){Stop-Readiness ($Context+'_source_dirty')}
    if($Context -eq 'installer_manifest'){
        # build-installers.ps1 emits this unversioned contract, not release-manifest schema 1.
        Assert-ReadinessFields $Manifest @('artifacts') $Context
        if(@($Manifest.PSObject.Properties.Name|Where-Object{$_ -notin ($fields+@('artifacts'))}).Count){
            Stop-Readiness 'installer_manifest_contract_unsupported'
        }
    }else{
        Assert-ReadinessFields $Manifest @('schema','target_platform') $Context
        if($Manifest.schema -ne 1){Stop-Readiness 'release_manifest_schema_unsupported'}
        if($Manifest.target_platform -cne 'win-x64'){Stop-Readiness 'release_manifest_platform_refused'}
    }
    try{Assert-AuthLensBuildIdentity $Manifest $Identity}
    catch{
        if($_.Exception.Message -cmatch '^Build identity mismatch: (product|version|source_sha|branch|build_timestamp_utc)$'){
            Stop-Readiness ($Context+'_mismatch_'+$Matches[1])
        }
        Stop-Readiness ($Context+'_identity_or_executable_mismatch')
    }
}
# WP31 (SEC-5): installation ACL status with the AuditAcl semantics (read-only). Broad access already fails the existing gates; named
# principals that are unreviewed or have unauthorized binary write make the status REVIEW_REQUIRED or UNSAFE. Strict mode refuses anything
# but SAFE; otherwise the status is returned for the report and printed as a warning. Nothing is changed.
function Get-ReadinessAclStatus($Config,[bool]$Strict) {
    try{$report=Get-ALAclReport (Get-ALAclPlan $Config) -ExpectedSids (Get-ALAclExpectedSids $Config) -Authorizations (Get-ALAclAuthorizations $Config)}
    catch{if($Strict){Stop-Readiness 'acl_status_unverifiable'};return 'UNVERIFIABLE'}
    $status=if($report.PSObject.Properties['status']){[string]$report.status}elseif(Test-ReadinessTrue $report.safe){'SAFE'}else{'UNSAFE'}
    if($status -cne 'SAFE' -and $Strict){Stop-Readiness ('acl_status_'+$status.ToLowerInvariant())}
    $status
}
function Resolve-ReadinessPath([string]$Path,[string]$Within='') {
    if(-not $Path -or $Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2).Contains(':')){Stop-Readiness 'invalid_local_path'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    Assert-ALInstallerPath $full
    if($Within -and (-not(Test-ALPathWithin $full $Within) -or $full -ieq $Within.TrimEnd('\','/'))){Stop-Readiness 'path_outside_expected_directory'}
    $full
}
function Read-ReadinessJson([string]$Path) {
    $full=Resolve-ReadinessPath $Path
    if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -gt 8MB){Stop-Readiness 'metadata_missing_or_oversized'}
    try{$text=Get-Content -LiteralPath $full -Raw -Encoding UTF8 -ErrorAction Stop}catch{Stop-Readiness 'metadata_unreadable'}
    try{$text|ConvertFrom-Json -ErrorAction Stop}catch{Stop-Readiness 'metadata_json_invalid'}
}
function Get-ReadinessHash([string]$Path) {
    $full=Resolve-ReadinessPath $Path
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){Stop-Readiness 'required_file_missing'}
    (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
}
# QA-017/021: a mismatch names the protected file's category, side (bundle copy or installation source) and its path relative to the bundle or
# installation root; never its content or hash material beyond this file's identity.
$script:ReadinessMismatch=$null
function Add-ReadinessFile($Baseline,[string]$Path,[string]$ExpectedHash='',$Context=$null) {
    $full=Resolve-ReadinessPath $Path
    $hash=Get-ReadinessHash $full
    if($ExpectedHash -and ($ExpectedHash -notmatch '^[a-fA-F0-9]{64}$' -or $hash -ine $ExpectedHash)){
        if($Context){$script:ReadinessMismatch=$Context}
        Stop-Readiness 'protected_file_hash_mismatch'
    }
    if($Baseline.files.ContainsKey($full) -and $Baseline.files[$full] -cne $hash){Stop-Readiness 'protected_file_changed_during_check'}
    $Baseline.files[$full]=$hash
}
function Get-ReadinessRegistration {
    $registration=Get-ALServerSetupRegistration
    $state='not_recorded';$version=''
    $key='Registry::HKEY_LOCAL_MACHINE\Software\AuthLens\Server'
    if(Test-Path -LiteralPath $key){
        $record=Get-ItemProperty -LiteralPath $key
        if($record.PSObject.Properties['SetupState']){
            if($record.SetupState -isnot [string] -or $record.SetupState -cne 'verified'){Stop-Readiness 'installer_registration_not_verified'}
            $state=$record.SetupState
        }
        if($record.PSObject.Properties['FileVersion']){$version=$record.FileVersion}
    }
    # Older verified installations may have no SetupState. An explicit pending marker must refuse.
    [ordered]@{registration=$registration;setup_state=$state;file_version=$version}|ConvertTo-Json -Depth 4 -Compress
}
function Assert-ReadinessBaseline($Baseline,$Config) {
    $now=Get-ALService 'AuthLens'
    foreach($field in 'Exists','State','StartMode','Account','PathName','ProcessId'){
        if($now.$field -cne $Baseline.service.$field){Stop-Readiness 'service_changed_during_check'}
    }
    if((Get-ReadinessRegistration) -cne $Baseline.registration -or (Get-ALLink (Get-ALCurrentLink $Config)) -cne $Baseline.release){Stop-Readiness 'installation_identity_changed_during_check'}
    foreach($file in $Baseline.files.Keys){if((Get-ReadinessHash $file) -cne $Baseline.files[$file]){Stop-Readiness 'protected_file_changed_during_check'}}
}
# WP32: $Root is a legacy run directory path (artifact paths relative to it) or a resolved candidate (Resolve-AuthLensCandidate), whose
# build/... and installer/... artifact paths map to build\<id> and installer\<id> in the split layout or to the run directory's subfolders.
function Resolve-ReadinessArtifactPath($Root,[string]$Relative) {
    if($Root -is [string]){return (Resolve-ReadinessPath (Join-Path $Root $Relative) $Root)}
    $parts=@($Relative.Split('/'))
    $base=switch($parts[0]){'build'{$Root.BuildDirectory}'installer'{$Root.InstallerDirectory}default{$null}}
    if(-not $base -or $parts.Count -lt 2){Stop-Readiness 'invalid_build_artifact_inventory'}
    $base=Resolve-ReadinessPath $base
    Resolve-ReadinessPath (Join-Path $base (($parts[1..($parts.Count-1)]) -join '\')) $base
}
function Get-ReadinessArtifactMap($Summary,$Root) {
    $map=@{}
    foreach($entry in @($Summary.artifacts)){
        Assert-ReadinessFields $entry @('path','size','sha256') 'build_artifact'
        $relative=([string]$entry.path).Replace('\','/')
        if(-not $relative -or $relative -match '(^/|[:*?"<>|])' -or @($relative.Split('/')|Where-Object{$_ -in @('','.', '..')}).Count -or
            $map.ContainsKey($relative) -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $entry.size -lt 0){Stop-Readiness 'invalid_build_artifact_inventory'}
        $null=Resolve-ReadinessArtifactPath $Root $relative
        $map[$relative]=$entry
    }
    if(-not $map.Count){Stop-Readiness 'empty_build_artifact_inventory'}
    $map
}
function Assert-ReadinessArtifact($Map,$Root,[string]$Relative) {
    $relative=$Relative.Replace('\','/')
    if(-not $Map.ContainsKey($relative)){Stop-Readiness 'artifact_not_bound_to_build_summary'}
    $path=Resolve-ReadinessArtifactPath $Root $relative
    if((Get-ReadinessHash $path) -ine $Map[$relative].sha256 -or (Get-Item -LiteralPath $path).Length -ne $Map[$relative].size){Stop-Readiness 'build_artifact_checksum_mismatch'}
}
function Invoke-ReadinessPreflight([string]$Tools,[string]$Package,[string]$Configuration,[string]$Fingerprint,$Identity,[string]$ExpectedJournal) {
    # Fixed approved entry point and flags only. No -Yes, PrepareOnly, PlanFile, ResultFile or recovery operation.
    $child=Invoke-ALProcess (Get-ALShell) @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
        (Join-Path $Tools 'Install-AuthLens.ps1'),'-Mode','Server','-Operation','Upgrade','-PreflightOnly',
        '-Package',$Package,'-ConfigFile',$Configuration,'-ExpectedConfigSha256',$Fingerprint) ''
    if($child.ExitCode -ne 0){Stop-Readiness 'supported_upgrade_preflight_refused'}
    $prefix='AUTHLENS-INSTALLER-RESULT: '
    $lines=@($child.Output|Where-Object{$_ -is [string] -and $_.StartsWith($prefix,[StringComparison]::Ordinal)})
    if($lines.Count -ne 1){Stop-Readiness 'preflight_result_missing_or_ambiguous'}
    $proof=$lines[0].Substring($prefix.Length)|ConvertFrom-Json
    Assert-ReadinessFields $proof @('schema','status','exit_code','deployment_journal_exists','deployment_journal','deployment_journal_expected','result') 'preflight_result'
    Assert-ReadinessFields $proof.result @('read_only','operation','package_network_database_verified','source_sha','version','config_sha256','config_file') 'preflight_plan'
    if($proof.schema -isnot [int] -or $proof.schema -ne 1 -or $proof.status -cne 'completed' -or $proof.exit_code -ne 0 -or -not(Test-ReadinessTrue $proof.result.read_only) -or
        $proof.result.operation -cne 'upgrade' -or -not(Test-ReadinessTrue $proof.result.package_network_database_verified) -or
        $proof.result.source_sha -cne $Identity.source_sha -or $proof.result.version -cne $Identity.version -or
        $proof.result.config_sha256 -ine $Fingerprint -or $proof.result.config_file -ine $Configuration -or
        -not(Test-ReadinessTrue $proof.deployment_journal_exists) -or -not $ExpectedJournal -or
        $proof.deployment_journal -ine $ExpectedJournal -or $proof.deployment_journal_expected -ine $ExpectedJournal){Stop-Readiness 'preflight_result_binding_mismatch'}
    # WP34: the read-only preflight's storage breakdown (volume, available, required, deficit, categories) is reported, never acted on.
    if($proof.result.PSObject.Properties['storage_summary']){[string]$proof.result.storage_summary}else{''}
}

$result=[ordered]@{schema=1;operation_id=[guid]::NewGuid().ToString('N');started_utc=[DateTime]::UtcNow.ToString('o');completed_utc='';
    status='FAIL';stage='prerequisites';failure_code='';post_check_failure_code='';error_type='';failure_line=0;checks=@();service_and_protected_files='not_observed';
    source_sha='';version='';recovery_report_utc='';protected_files=0;signature_status='not_checked';
    snapshot_verification='external_not_checked';backup_freshness='not_proven';restore_rehearsal='not_verified_by_this_check';
    upgrade_authorized=$false;release_status='NO-GO'}
$baseline=$null;$config=$null;$passed=$false
try {
    if($env:OS -ne 'Windows_NT' -or -not $BuildDirectory){Stop-Readiness 'windows_and_build_directory_required'}
    if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Stop-Readiness 'administrator_read_access_required'}
    if($ExpectedSourceSha -and $ExpectedSourceSha -cnotmatch '^[a-f0-9]{40}$'){Stop-Readiness 'invalid_expected_source_sha'}
    Import-Module (Join-Path $PSScriptRoot 'deploy/AuthLens.Deploy.psm1') -Force
    . (Join-Path $PSScriptRoot 'Build-Workflow.ps1')
    $requested=Resolve-ReadinessPath $BuildDirectory
    # WP32: C:\AuthLens\Build\<version>\<build-id> (or Installer\... / Acceptance\...), or a legacy run directory C:\AuthLens\AuthLens-<version>-<id>
    # (RC5 and earlier), read in place.
    $result.stage='build candidate layout'
    try{$candidate=Resolve-AuthLensCandidate $requested}catch{Stop-Readiness 'build_candidate_layout_unrecognized'}
    foreach($directory in $candidate.RecordDirectory,$candidate.BuildDirectory,$candidate.InstallerDirectory){$null=Resolve-ReadinessPath $directory}
    $build=Resolve-ReadinessPath $candidate.RecordDirectory
    $result.candidate_id=$candidate.Id;$result.candidate_layout=$candidate.Layout
    $result.stage='build summary identity'
    $summary=Read-ReadinessJson $candidate.SummaryFile
    Assert-ReadinessFields $summary @('schema','status','identity','verification','artifacts') 'build_summary'
    Assert-ReadinessFields $summary.identity @('product','version','source_sha','branch','build_timestamp_utc') 'build_identity'
    # Summary schema 1 is the legacy run directory; schema 2 is the WP32 category layout and names its own version and build id.
    $schemaLayout=if($summary.schema -eq 2 -and $summary.PSObject.Properties['layout'] -and $summary.layout -ceq 'category' -and $summary.PSObject.Properties['id'] -and $summary.id -ceq $candidate.Id -and $summary.PSObject.Properties['version'] -and $summary.version -ceq $candidate.Version){'category'}elseif($summary.schema -eq 1){'legacy'}else{''}
    if($schemaLayout -cne $candidate.Layout){Stop-Readiness 'build_summary_layout_mismatch'}
    if($summary.status -cne 'passed' -or $summary.identity.product -cne 'AuthLens' -or
        $summary.identity.source_sha -cnotmatch '^[a-f0-9]{40}$' -or
        ($ExpectedSourceSha -and $summary.identity.source_sha -cne $ExpectedSourceSha)){Stop-Readiness 'build_identity_refused'}
    Assert-ReadinessFields $summary.verification @('release','installers','secrets','branding') 'build_verification'
    foreach($check in 'release','installers','secrets','branding'){if(-not(Test-ReadinessTrue $summary.verification.$check)){Stop-Readiness ('build_verification_not_true_'+$check)}}
    $result.stage='build artifact inventory'
    $artifacts=Get-ReadinessArtifactMap $summary $candidate
    $result.stage='release manifest discovery'
    $buildPath=Resolve-ReadinessPath $candidate.BuildDirectory
    $manifests=@(Get-ALTreeFiles $buildPath|Where-Object Name -eq 'build-manifest.json')
    if($manifests.Count -ne 1){Stop-Readiness 'release_manifest_missing_or_ambiguous'}
    $package=$manifests[0].DirectoryName
    $manifest=Read-ReadinessJson $manifests[0].FullName
    $result.stage='release manifest identity'
    $relative='build/'+$manifests[0].FullName.Substring($buildPath.Length+1).Replace('\','/')
    Assert-ReadinessArtifact $artifacts $candidate $relative
    Assert-ReadinessManifestIdentity $manifest $summary.identity 'release_manifest'
    $product=Read-ReadinessJson (Join-Path $PSScriptRoot '../product-version.json')
    Assert-ReadinessFields $product @('version') 'product_version'
    if($manifest.version -cne $product.version){Stop-Readiness 'release_manifest_product_version_mismatch'}
    $result.source_sha=$manifest.source_sha;$result.version=$manifest.version
    $installer=Resolve-ReadinessPath $candidate.InstallerDirectory
    $result.stage='installer manifest identity'
    Assert-ReadinessArtifact $artifacts $candidate 'installer/installer-manifest.json'
    $metadata=Read-ReadinessJson (Join-Path $installer 'installer-manifest.json')
    Assert-ReadinessManifestIdentity $metadata $summary.identity 'installer_manifest'
    $result.stage='installer artifact checksums'
    # WP32 names AuthLens-<version>-Server-Setup.exe / -Desktop-Setup.exe; legacy candidates keep their earlier names.
    $setup=Get-AuthLensSetupNames $candidate $manifest.version
    $names=@($setup.desktop,$setup.server)
    if((@($metadata.artifacts.path|Sort-Object)-join '|') -cne (@($names|Sort-Object)-join '|')){Stop-Readiness 'installer_inventory_refused'}
    foreach($entry in $metadata.artifacts){
        Assert-ReadinessArtifact $artifacts $candidate ('installer/'+$entry.path)
        if($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-ReadinessHash (Join-Path $installer $entry.path)) -ine $entry.sha256){Stop-Readiness 'installer_checksum_mismatch'}
    }
    $result.stage='installer signature'
    $result.signature_status=[string](Get-AuthenticodeSignature -LiteralPath (Join-Path $installer $names[1])).Status
    if($result.signature_status -notin @('Valid','NotSigned')){Stop-Readiness 'installer_signature_invalid'}
    $result.checks+='build and installer identity/checksums';Write-Host 'PASS: build and installer identity/checksums'

    $result.stage='packaged helper integrity'
    $directories=@(Get-ChildItem -LiteralPath $installer -Directory -Filter 'installer-tools-*')
    if($directories.Count -ne 1){Stop-Readiness 'packaged_tools_missing_or_ambiguous'}
    $tools=Resolve-ReadinessPath $directories[0].FullName $installer
    $toolRelative='installer/'+$directories[0].Name+'/'
    Assert-ReadinessArtifact $artifacts $candidate ($toolRelative+'installer-tools.json')
    $proof=Read-ReadinessJson (Join-Path $tools 'installer-tools.json')
    $helperFiles=@('Install-AuthLens.ps1','verify-release.ps1','deploy/AuthLens.Deploy.psm1','deploy/Deploy-AuthLens.ps1',
        'deploy/AuthLens.Paths.ps1','deploy/AuthLens.Acl.ps1','deploy/AuthLens.Installer.ps1')
    # QA-028: current packages also carry the recovery scripts; packages built before it carry exactly the seven deployment helpers.
    $recoveryHelpers=@('recovery/New-AuthLensRecoveryBundle.ps1','recovery/Test-AuthLensRestoreRehearsal.ps1','acceptance/AuthLens.Acceptance.psm1')
    $packed=(@($proof.files.path|Sort-Object)-join '|')
    if($proof.schema -ne 1 -or ($packed -cne (@($helperFiles|Sort-Object)-join '|') -and $packed -cne (@(@($helperFiles)+@($recoveryHelpers)|Sort-Object)-join '|'))){Stop-Readiness 'packaged_helper_inventory_refused'}
    $result.packaged_recovery_tools=($packed -cne (@($helperFiles|Sort-Object)-join '|'))
    foreach($entry in $proof.files){
        Assert-ReadinessArtifact $artifacts $candidate ($toolRelative+$entry.path)
        $packed=Get-ReadinessHash (Join-Path $tools $entry.path)
        if($packed -ine $entry.sha256 -or $packed -cne (Get-ReadinessHash (Join-Path $PSScriptRoot $entry.path))){Stop-Readiness 'packaged_helpers_differ_from_reviewed_source'}
    }
    $result.checks+='packaged helper integrity';Write-Host 'PASS: packaged helper integrity'

    $result.stage='existing installation and journal'
    $resolved=Resolve-ALServerSetupConfiguration $ConfigFile ''
    $config=$resolved.Config
    if($config.ServiceName -cne 'AuthLens'){Stop-Readiness 'noncanonical_service_refused'}
    $service=Get-ALService 'AuthLens'
    if(-not $service.Exists -or $service.State -cne 'Running' -or $service.StartMode -cne 'Auto' -or
        $service.Account -ine 'NT SERVICE\AuthLens' -or $service.ProcessId -le 0){Stop-Readiness 'service_state_or_identity_refused'}
    $active=Get-ALLink (Get-ALCurrentLink $config)
    if(-not $active){Stop-Readiness 'active_release_missing'}
    $active=Resolve-ReadinessPath $active $config.ReleasesRoot
    $baseline=[pscustomobject]@{service=$service;registration=(Get-ReadinessRegistration);release=$active;files=@{}}
    foreach($file in @($config.ConfigFile,$config.CertificatePath,$config.CertificatePasswordFile)){
        Add-ReadinessFile $baseline $file
    }
    if($baseline.files[(Resolve-ReadinessPath $config.ConfigFile)] -ine $resolved.ConfigSha256){Stop-Readiness 'configuration_changed_during_resolution'}
    $old=Read-ReadinessJson (Join-Path $active 'build-manifest.json')
    $owned=Get-ALInstallerServerIdentity $config
    if(-not $owned -or $owned.release -ine $active -or $owned.manifest_sha256 -ine (Get-ReadinessHash (Join-Path $active 'build-manifest.json'))){Stop-Readiness 'installed_ownership_receipt_refused'}
    foreach($file in @((Join-Path $active 'build-manifest.json'),(Join-Path $config.Root 'config/installed-product.json'))){Add-ReadinessFile $baseline $file}
    foreach($file in @((Join-Path $config.DataDirectory 'authlens.sqlite3'),(Join-Path $config.DataDirectory 'security/accounts.sqlite3'))){
        if(-not(Test-Path -LiteralPath (Resolve-ReadinessPath $file) -PathType Leaf)){Stop-Readiness 'existing_database_missing'}
    }
    Assert-ALNoPendingRepair $config
    $journalPath=Get-ALJournalPath $config
    Add-ReadinessFile $baseline $journalPath
    $journal=Read-ALJournal $config
    if($journal.phase -notin @('complete','rolled_back','aborted')){Stop-Readiness 'deployment_journal_requires_review'}
    $journalRelease=if($journal.phase -eq 'complete'){$journal.to_release}else{$journal.from_release}
    if([IO.Path]::GetFullPath($journalRelease).TrimEnd('\','/') -ine $active){Stop-Readiness 'deployment_journal_active_release_mismatch'}
    $result.checks+='existing installation and terminal journal';Write-Host 'PASS: existing installation and terminal journal'

    $result.stage='independent recovery evidence'
    # QA-023: the selection is always reported; controlled acceptance passes -RecoveryReport explicitly (the acceptance harness requires it).
    $result.recovery_report_selection='explicit'
    if(-not $RecoveryReport){
        $reports=Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'build/lifecycle-work'
        $latest=Get-ChildItem -LiteralPath $reports -File -Filter 'backup-result-*.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
        if(-not $latest){Stop-Readiness 'recovery_report_missing'}
        $RecoveryReport=$latest.FullName
        $result.recovery_report_selection='latest_in_build_lifecycle_work (pass -RecoveryReport explicitly for controlled acceptance)'
        Write-Host "WARNING: no -RecoveryReport given; using the newest report $($latest.Name). Pass -RecoveryReport explicitly for controlled acceptance."
    }
    $result.recovery_report=Split-Path $RecoveryReport -Leaf
    $recovery=Read-ReadinessJson $RecoveryReport
    Add-ReadinessFile $baseline $RecoveryReport
    if($recovery.status -cne 'passed' -or -not(Test-ReadinessTrue $recovery.verified) -or
        $recovery.service_changed -isnot [bool] -or $recovery.service_changed){Stop-Readiness 'recovery_report_not_verified'}
    $bundle=Resolve-ReadinessPath $recovery.bundle
    foreach($target in @($config.Root,$config.DataDirectory,$config.BackupRoot,$config.ReleasesRoot,$config.WorkRoot,$build,$candidate.BuildDirectory,$candidate.InstallerDirectory,(Split-Path (Split-Path $PSScriptRoot)))){
        if(Test-ALPathOverlap $bundle $target){Stop-Readiness 'recovery_bundle_overlaps_upgrade_or_developer_storage'}
    }
    $audit=Get-ALAclReport @([pscustomobject]@{Path=$bundle;Class='private';Role='independent recovery';Recurse=$true})
    if(-not $audit.safe){Stop-Readiness 'recovery_acl_unverified'}
    $inventoryFile=Join-Path $bundle 'private-inventory.json'
    $inventory=Read-ReadinessJson $inventoryFile;Add-ReadinessFile $baseline $inventoryFile
    # QA-022: recovery program identity against the active program, recorded before any comparison so a stale bundle is explained.
    $recoveryManifestPath=Join-Path $bundle 'program/build-manifest.json'
    $recoveryIdentity=if(Test-Path -LiteralPath $recoveryManifestPath){Read-ReadinessJson $recoveryManifestPath}else{$null}
    $result.recovery_program=[ordered]@{source_sha=$(if($recoveryIdentity){$recoveryIdentity.source_sha}else{''});version=$(if($recoveryIdentity){$recoveryIdentity.version}else{''})}
    $result.active_program=[ordered]@{source_sha=$old.source_sha;version=$old.version}
    $result.recovery_program_matches_active=[bool]($recoveryIdentity -and $recoveryIdentity.source_sha -ceq $old.source_sha)
    if(-not @($inventory.files).Count -or @($inventory.files).Count -ne $recovery.private_files_verified){Stop-Readiness 'recovery_inventory_count_mismatch'}
    $pointerFile=Join-Path $config.DataDirectory 'backup-key-location.json'
    $pointer=Read-ReadinessJson $pointerFile;Add-ReadinessFile $baseline $pointerFile
    $key=Resolve-ReadinessPath $pointer.path
    $selected=@{'selected/deploy.json'=$config.ConfigFile;'selected/server.pfx'=$config.CertificatePath;
        'selected/cert-password'=$config.CertificatePasswordFile;'selected/host-recovery.key'=$key}
    $copies=@{}
    foreach($entry in $inventory.files){
        $copy=Resolve-ReadinessPath $entry.copy $bundle
        $source=Resolve-ReadinessPath $entry.source
        if($copies.ContainsKey($copy) -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$'){Stop-Readiness 'recovery_inventory_refused'}
        if(-not(Test-ALPathWithin $source $config.Root) -and -not(Test-ALPathWithin $source $config.ReleasesRoot) -and $source -notin @($selected.Values)){Stop-Readiness 'recovery_source_outside_reviewed_paths'}
        $relative=$copy.Substring($bundle.Length).TrimStart('\','/')
        $category=($relative -split '[\\/]')[0]
        $sourceRelative=if(Test-ALPathWithin $source $config.Root){$source.Substring($config.Root.TrimEnd('\','/').Length).TrimStart('\','/')}else{Split-Path $source -Leaf}
        Add-ReadinessFile $baseline $copy $entry.sha256 ([ordered]@{category=$category;side='bundle copy';file=$relative})
        Add-ReadinessFile $baseline $source $entry.sha256 ([ordered]@{category=$category;side='installation source (changed since the bundle was captured)';file=$sourceRelative})
        $copies[$copy]=$source
    }
    foreach($relative in $selected.Keys){
        $copy=Resolve-ReadinessPath (Join-Path $bundle $relative) $bundle
        if(-not $copies.ContainsKey($copy) -or $copies[$copy] -ine $selected[$relative]){Stop-Readiness 'recovery_critical_material_missing'}
    }
    $archive=Resolve-ReadinessPath $inventory.backup.file $bundle
    if([IO.Path]::GetExtension($archive) -ine '.slbak' -or $inventory.backup.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $inventory.backup.sha256 -ine $recovery.archive_sha256){Stop-Readiness 'recovery_archive_binding_mismatch'}
    Add-ReadinessFile $baseline $archive $inventory.backup.sha256
    $recoveryManifest=Read-ReadinessJson (Join-Path $bundle 'program/build-manifest.json')
    if($recoveryManifest.source_sha -cne $old.source_sha -or
        (Get-ReadinessHash (Join-Path $bundle 'program/build-manifest.json')) -cne (Get-ReadinessHash (Join-Path $active 'build-manifest.json'))){Stop-Readiness 'recovery_program_differs_from_active_release'}
    $result.recovery_report_utc=(Get-Item -LiteralPath $RecoveryReport).LastWriteTimeUtc.ToString('o')
    $result.checks+='independent recovery ACL, archive and protected file hashes';Write-Host 'PASS: independent recovery ACL, archive and protected file hashes'

    $result.stage='installation ACL status'
    $result.acl_status=Get-ReadinessAclStatus $config ([bool]$StrictAcl)
    $result.acl_gate=if($StrictAcl){'strict'}else{'report'}
    if($result.acl_status -ceq 'SAFE'){$result.checks+='installation ACL status SAFE';Write-Host 'PASS: installation ACL status SAFE'}
    else{Write-Host "WARNING: installation ACL status is $($result.acl_status); review it with Deploy-AuthLens.ps1 -Action AuditAcl (use -StrictAcl to refuse)."}

    $result.stage='supported read-only upgrade preflight'
    $result.storage_preflight=Invoke-ReadinessPreflight $tools $package $config.ConfigFile $resolved.ConfigSha256 $manifest $journalPath
    $result.checks+='supported read-only upgrade preflight';Write-Host 'PASS: supported read-only upgrade preflight'
    $passed=$true
}catch{
    $result.failure_code=if($_.Exception.Data.Contains('AuthLensReadinessCode')){[string]$_.Exception.Data['AuthLensReadinessCode']}else{'unexpected_validation_error'}
    if($result.failure_code -eq 'protected_file_hash_mismatch' -and $script:ReadinessMismatch){
        $result.mismatch=$script:ReadinessMismatch
        $hint=if($result.Contains('recovery_program_matches_active') -and -not $result.recovery_program_matches_active){'The recovery bundle captured another release; create a new bundle of the active installation.'}else{'The installation changed after the bundle was captured; create a new bundle.'}
        $result.mismatch['action']=$hint
        Write-Host "FAIL detail: $($script:ReadinessMismatch.category) / $($script:ReadinessMismatch.side) / $($script:ReadinessMismatch.file). $hint"
    }
    $result.error_type=$_.Exception.GetType().Name
    $result.failure_line=$_.InvocationInfo.ScriptLineNumber
    # No exception text, invocation, stack, raw child output, configuration or private inventory is printed.
}finally{
    if($null -ne $baseline){
        try{
            Assert-ReadinessBaseline $baseline $config
            $result.service_and_protected_files='unchanged';$result.protected_files=$baseline.files.Count
        }catch{
            $passed=$false;$result.service_and_protected_files='changed_or_unverifiable'
            $result.post_check_failure_code='post_check_state_changed_or_unverifiable'
            if(-not $result.failure_code){$result.failure_code=$result.post_check_failure_code}
        }
    }
}
if($passed){$result.status='PASS';$result.stage='completed';$result.checks+='service/configuration/TLS/recovery unchanged'}
$result.completed_utc=[DateTime]::UtcNow.ToString('o')
Write-Host ($result.status+': '+$result.stage+$(if($result.failure_code){' ['+$result.failure_code+']'}else{''}))
Write-Host ('AUTHLENS-UPGRADE-READINESS: '+($result|ConvertTo-Json -Depth 5 -Compress))
if(-not $passed){exit 1}
exit 0
