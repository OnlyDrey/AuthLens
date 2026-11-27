<#
.SYNOPSIS
  Independent recovery bundle of an installed AuthLens Server (WP22, QA-019/020/024/026/031/032). Elevated, read-only for the installation.
.DESCRIPTION
  Creates <RecoveryRoot>\<UTC>-<id> with private ACLs (SYSTEM, Administrators, the operator) and captures, without stopping or reconfiguring
  the service: a verified encrypted online backup (the installed release's --backup-local/--backup-verify), the deployment configuration, the
  configured TLS material and its password file, the configured recovery key, the config/tls/keys folders, and the active release (program).
  The archive is then verified again with the COPIED key in a separate private probe directory. Every copied file is hashed before and after
  and compared with its source at the end; service state, process, command line, account and configuration must be unchanged.
  Writes one machine-readable report (never overwritten; secrets, raw exceptions and native output are omitted) and exits 0 only when
  everything verified. Existing bundles are never modified or overwritten.

  This proves archive integrity and that the copied key opens it. It does not prove backup freshness beyond its own timestamp, an external
  escrow copy, a restore rehearsal (Test-AuthLensRestoreRehearsal.ps1) or a hypervisor snapshot.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File backend\scripts\recovery\New-AuthLensRecoveryBundle.ps1 -ReportDirectory C:\AuthLens-Recovery\reports
#>
[CmdletBinding()]
param(
    [string]$ConfigFile = 'C:\ProgramData\AuthLens\config\deploy.json',
    [string]$RecoveryRoot = 'C:\AuthLens-Recovery',
    [string]$ReportDirectory = '',
    [string]$ServiceName = '',
    # QA-028: re-verify an existing bundle (private inventory hashes, archive hash, private ACL and decryption of the archive with the bundle's
    # COPIED key and program in a new private temporary probe folder). Read-only for the installation and the bundle; it is not a restore
    # rehearsal (Test-AuthLensRestoreRehearsal.ps1). A report is written only when -ReportDirectory is given.
    [string]$VerifyBundle = ''
)
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
$started = [DateTime]::UtcNow
$stamp = $started.ToString('yyyyMMddTHHmmssfffffffZ')
if ($VerifyBundle) {
    $check = [ordered]@{ schema = 1; tool = 'New-AuthLensRecoveryBundle -VerifyBundle'; status = 'failed'; verified = $false; started_utc = $started.ToString('o'); failure_stage = 'elevation'; bundle = ''
        scope = 'Bundle integrity, private ACL and decryption of the archive with the copied key. Not a restore rehearsal; nothing is restored.' }
    $probe = $null
    try {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator terminal required.' }
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'deploy\AuthLens.Deploy.psm1') -Force
        $bundle = [IO.Path]::GetFullPath($VerifyBundle).TrimEnd('\', '/'); $check.bundle = $bundle
        $check.failure_stage = 'private inventory'
        $inventory = Get-Content -LiteralPath (Join-Path $bundle 'private-inventory.json') -Raw | ConvertFrom-Json
        if ($inventory.schema -ne 2 -or -not @($inventory.files).Count) { throw 'The private inventory is not a schema-2 recovery bundle inventory.' }
        foreach ($file in @($inventory.files)) {
            if (-not (Test-ALPathWithin $file.copy $bundle) -or -not (Test-Path -LiteralPath $file.copy -PathType Leaf) -or (Get-FileHash -LiteralPath $file.copy -Algorithm SHA256).Hash -ine $file.sha256) { throw "A recovery copy is missing or changed ($($file.category))." }
        }
        foreach ($required in 'selected\deploy.json', 'selected\server.pfx', 'selected\cert-password', 'selected\host-recovery.key', 'program\server\AuthLens.Api.exe', 'program\build-manifest.json') {
            if (-not (Test-Path -LiteralPath (Join-Path $bundle $required) -PathType Leaf)) { throw "Critical recovery material is missing ($required)." }
        }
        $check.failure_stage = 'archive'
        $archive = [string]$inventory.backup.file
        if (-not (Test-ALPathWithin $archive $bundle) -or -not (Test-Path -LiteralPath $archive -PathType Leaf) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $inventory.backup.sha256) { throw 'The archive is missing or differs from the inventory.' }
        $check.failure_stage = 'bundle ACL'
        $audit = Get-ALAclReport @([pscustomobject]@{ Path = $bundle; Class = 'private'; Role = 'recovery bundle'; Recurse = $true }) -ExpectedSids @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $check.acl_safe = $audit.safe; $check.named_principal_access = $audit.named_principal_access
        if (-not $audit.safe -or $audit.named_principal_access) { throw 'Recovery bundle ACL verification failed (broad or unexpected named access).' }
        $check.failure_stage = 'independent key verification'
        $probe = Join-Path ([IO.Path]::GetTempPath()) ('authlens-bundle-verify-' + [guid]::NewGuid().ToString('N'))
        New-ALInstallerPrivateDirectory $probe
        $env:AUTHLENS_BACKUP_KEY_FILE = $null; $env:AUTHLENS_BACKUP_PASSPHRASE = $null
        $copied = Join-Path $bundle 'program\server\AuthLens.Api.exe'
        $null = Invoke-ALMaintenance $copied @('--backup-key', 'use', (Join-Path $bundle 'selected\host-recovery.key'), '--data-dir', $probe)
        $independent = Invoke-ALMaintenance $copied @('--backup-verify', $archive, '--data-dir', $probe)
        if (-not $independent.verified -or $independent.sha256 -ine $inventory.backup.sha256) { throw 'The archive did not verify with the copied key.' }
        $check.files_verified = @($inventory.files).Count; $check.archive_sha256 = ([string]$inventory.backup.sha256).ToLowerInvariant()
        $check.status = 'passed'; $check.verified = $true; $check.failure_stage = ''
    } catch {
        $check.error_type = $_.Exception.GetType().Name
        $check.error = if ($_.Exception.Message.Length -lt 200 -and $_.Exception.Message -notmatch '[A-Za-z]:\\') { $_.Exception.Message } else { '' }
    } finally {
        if ($probe -and (Test-Path -LiteralPath $probe)) { Remove-Item -LiteralPath $probe -Recurse -Force }
        $check.completed_utc = [DateTime]::UtcNow.ToString('o')
        if ($ReportDirectory -and (Test-Path -LiteralPath $ReportDirectory -PathType Container)) {
            $file = Join-Path $ReportDirectory "verify-result-$stamp.json"
            if (-not (Test-Path -LiteralPath $file)) { [IO.File]::WriteAllText($file, ($check | ConvertTo-Json -Depth 5)) }
        }
        Write-Host ('Recovery bundle verification: ' + $check.status + $(if ($check.failure_stage) { ' at ' + $check.failure_stage } else { '' }))
        Write-Host ('AUTHLENS-RECOVERY-BUNDLE-VERIFY: ' + ($check | ConvertTo-Json -Compress -Depth 5))
    }
    if ($check.verified) { exit 0 } else { exit 1 }
}
if (-not $ReportDirectory) { $ReportDirectory = Join-Path $RecoveryRoot 'reports' }
$report = Join-Path $ReportDirectory "backup-result-$stamp.json"
$result = [ordered]@{ schema = 2; tool = 'New-AuthLensRecoveryBundle'; status = 'failed'; verified = $false; started_utc = $started.ToString('o'); failure_stage = 'elevation'
    service_changed = $null; snapshot_verified = $false; destructive_testing_allowed = $false }
try {
    $result.elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $result.elevated) { throw 'Administrator terminal required.' }
    $result.operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $result.failure_stage = 'module import'
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'deploy\AuthLens.Deploy.psm1') -Force
    $result.failure_stage = 'configuration'
    $config = Read-AuthLensSettings $ConfigFile
    if (-not $ServiceName) { $ServiceName = $config.ServiceName }
    $service = Get-ALService $ServiceName
    if (-not $service.Exists -or -not (Test-ALServiceBinary $service.PathName $config)) { throw 'Service/configuration mismatch.' }
    $before = [ordered]@{ state = $service.State; pid = $service.ProcessId; account = $service.Account; path = $service.PathName; config_sha256 = (Get-FileHash -LiteralPath $config.ConfigFile -Algorithm SHA256).Hash.ToLowerInvariant() }
    $result.service_before = $before
    $release = Get-ALLink (Get-ALCurrentLink $config)
    if (-not (Test-ALPublishedRelease $release).Verified) { throw 'Installed program verification failed.' }
    $manifest = Get-Content -LiteralPath (Join-AL $release 'build-manifest.json') -Raw | ConvertFrom-Json
    $result.program = [ordered]@{ release = (Split-Path $release -Leaf); version = $manifest.version; source_sha = $manifest.source_sha; manifest_sha256 = (Get-FileHash -LiteralPath (Join-AL $release 'build-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant() }
    $result.failure_stage = 'private storage'
    foreach ($folder in $RecoveryRoot, $ReportDirectory) {
        if (-not (Test-Path -LiteralPath $folder)) { New-ALInstallerPrivateDirectory $folder }
        $null = Assert-ALAclPlan @([pscustomobject]@{ Path = $folder; Class = 'private'; Role = 'independent recovery'; Recurse = $false }) 'Recovery storage'
    }
    foreach ($inside in $config.Root, $config.DataDirectory) { if ((Test-ALPathWithin $RecoveryRoot $inside) -or (Test-ALPathWithin $inside $RecoveryRoot)) { throw 'Recovery storage overlaps the installation.' } }
    if (Test-Path -LiteralPath $report) { throw 'Report collision.' }
    $bundle = Join-Path $RecoveryRoot ($stamp + '-' + [guid]::NewGuid().ToString('N'))
    New-ALInstallerPrivateDirectory $bundle
    $result.bundle = $bundle
    $exe = Join-AL $release 'server\AuthLens.Api.exe'
    $result.failure_stage = 'encrypted online backup'
    $backup = Invoke-ALMaintenance $exe @('--backup-local', $bundle, '--data-dir', $config.DataDirectory)
    $verified = Invoke-ALMaintenance $exe @('--backup-verify', $backup.file, '--data-dir', $config.DataDirectory)
    if (-not $verified.verified -or $verified.sha256 -ine $backup.sha256) { throw 'Backup verification failed.' }
    $result.failure_stage = 'private recovery material'
    $files = [Collections.Generic.List[object]]::new()
    function Copy-VerifiedFile([string]$Source, [string]$Destination, [string]$Category) {
        Assert-ALInstallerPath $Source
        $hash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $null = New-Item -ItemType Directory -Path (Split-Path $Destination) -Force
        if (Test-Path -LiteralPath $Destination) { throw 'Recovery file collision.' }
        [IO.File]::Copy($Source, $Destination, $false)
        if ($hash -ine (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -or $hash -ine (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash) { throw 'Recovery copy changed during capture.' }
        $files.Add([pscustomobject]@{ category = $Category; source = $Source; copy = $Destination; sha256 = $hash.ToLowerInvariant() })
    }
    foreach ($name in 'config', 'tls', 'keys') {
        $source = Join-AL $config.Root $name
        if (Test-Path -LiteralPath $source) { foreach ($file in @(Get-ALTreeFiles $source)) { Copy-VerifiedFile $file.FullName (Join-Path (Join-Path $bundle $name) $file.FullName.Substring($source.Length).TrimStart('\', '/')) $name } }
    }
    Copy-VerifiedFile $config.ConfigFile (Join-Path $bundle 'selected\deploy.json') 'selected configuration'
    Copy-VerifiedFile $config.CertificatePath (Join-Path $bundle 'selected\server.pfx') 'selected TLS certificate'
    Copy-VerifiedFile $config.CertificatePasswordFile (Join-Path $bundle 'selected\cert-password') 'selected TLS password'
    $pointer = Join-AL $config.DataDirectory 'backup-key-location.json'
    if (-not (Test-Path -LiteralPath $pointer)) { throw 'No recovery key is configured; a bundle without its key cannot be restored.' }
    Copy-VerifiedFile ((Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json).path) (Join-Path $bundle 'selected\host-recovery.key') 'recovery key'
    foreach ($file in @(Get-ALTreeFiles $release)) { Copy-VerifiedFile $file.FullName (Join-Path (Join-Path $bundle 'program') $file.FullName.Substring($release.Length).TrimStart('\', '/')) 'program' }
    $result.failure_stage = 'independent key verification'
    $probe = Join-Path $bundle 'verification-data'
    $null = New-Item -ItemType Directory -Path $probe
    $env:AUTHLENS_BACKUP_KEY_FILE = $null; $env:AUTHLENS_BACKUP_PASSPHRASE = $null
    $copied = Join-Path $bundle 'program\server\AuthLens.Api.exe'
    $null = Invoke-ALMaintenance $copied @('--backup-key', 'use', (Join-Path $bundle 'selected\host-recovery.key'), '--data-dir', $probe)
    $independent = Invoke-ALMaintenance $copied @('--backup-verify', $backup.file, '--data-dir', $probe)
    if (-not $independent.verified -or $independent.sha256 -ine $backup.sha256) { throw 'Independent key/archive verification failed.' }
    $result.failure_stage = 'source stability'
    foreach ($file in $files) { if ((Get-FileHash -LiteralPath $file.source -Algorithm SHA256).Hash -ine $file.sha256) { throw "Preserved source material ($($file.category)) changed during the capture; repeat the backup." } }
    $after = Get-ALService $ServiceName
    $result.service_after = [ordered]@{ state = $after.State; pid = $after.ProcessId; account = $after.Account; path = $after.PathName; config_sha256 = (Get-FileHash -LiteralPath $config.ConfigFile -Algorithm SHA256).Hash.ToLowerInvariant() }
    $result.service_changed = ($after.State -ne $before.state -or $after.ProcessId -ne $before.pid -or $after.Account -ne $before.account -or $after.PathName -ne $before.path -or $result.service_after.config_sha256 -ne $before.config_sha256)
    if ($result.service_changed) { throw 'The service or its configuration changed during the capture.' }
    [IO.File]::WriteAllText((Join-Path $bundle 'private-inventory.json'), (@{ schema = 2; files = @($files); service = $service; backup = $backup; program = $result.program; created_utc = $started.ToString('o') } | ConvertTo-Json -Depth 8))
    $result.failure_stage = 'bundle ACL'
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $audit = Get-ALAclReport @([pscustomobject]@{ Path = $bundle; Class = 'private'; Role = 'recovery bundle'; Recurse = $true }) -ExpectedSids @($me)
    $result.acl_safe = $audit.safe; $result.named_principal_access = $audit.named_principal_access
    if (-not $audit.safe -or $audit.named_principal_access) { throw 'Recovery bundle ACL verification failed (broad or unexpected named access).' }
    $result.status = 'passed'; $result.verified = $true; $result.failure_stage = ''
    $result.archive = Split-Path $backup.file -Leaf; $result.archive_sha256 = $backup.sha256.ToLowerInvariant()
    $result.private_files_verified = $files.Count
    $result.file_categories = @($files | Group-Object category | ForEach-Object { [pscustomobject]@{ category = $_.Name; files = $_.Count } })
} catch {
    # Deliberately omit raw exceptions, native output and all private material.
    $result.error_type = $_.Exception.GetType().Name
    $result.error = if ($_.Exception -is [System.Management.Automation.RuntimeException] -and $_.Exception.Message.Length -lt 200 -and $_.Exception.Message -notmatch '[A-Za-z]:\\') { $_.Exception.Message } else { '' }
    $result.error_line = $_.InvocationInfo.ScriptLineNumber
} finally {
    $result.completed_utc = [DateTime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $ReportDirectory) { [IO.File]::WriteAllText($report, ($result | ConvertTo-Json -Depth 6)) }
    Write-Host ('Recovery bundle: ' + $result.status + '. Report: ' + $report)
    Write-Host ('AUTHLENS-RECOVERY-BUNDLE: ' + ([pscustomobject]@{ status = $result.status; report = $report; failure_stage = $result.failure_stage } | ConvertTo-Json -Compress))
}
if (-not $result.verified) { exit 1 }
