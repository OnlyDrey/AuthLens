<#
.SYNOPSIS
  Inno Setup's explicit manual install/update adapter. Uses verified versioned Server deployment and the existing application backup engine.
.DESCRIPTION
  No Git, SDK, download or legacy adoption. Desktop requires a closed application and an external data directory.
  Server uses validated registered/managed configuration discovery or an explicit configuration, with elevation.
  ResolveOnly/PreflightOnly are read-only; provisioning/deployment requires -Yes. Native SCM acceptance must use a separate disposable VM.
  Interrupted updates require -Recover; Server recovery delegates to the existing deployment Recover action with the same configuration.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Desktop','Server')][string]$Mode,
    [string]$Package='',
    [string]$InstallRoot='',
    [string]$DataDirectory='',
    [string]$ConfigFile='',
    [switch]$Recover,
    [switch]$PrepareOnly,
    [switch]$ResolveOnly,
    [switch]$PreflightOnly,
    [switch]$CommitNewConfiguration,
    [string]$FirewallSources='',
    [string]$FirewallProfiles='Private',
    [switch]$ApproveFirewall,
    [string]$Operation='Auto',
    [string]$PlanFile='',
    [string]$ResultFile='',
    [string]$ExpectedConfigSha256='',
    [string]$DiagnosticFile='',
    [switch]$Yes
)
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
$stage='helper verification'
$operationId=[guid]::NewGuid().ToString('N')
$journalPath=''
function Write-InstallerResult($Value) {
    $json=$Value|ConvertTo-Json -Depth 12 -Compress
    Write-Host ('AUTHLENS-INSTALLER-RESULT: '+$json)
    if($ResultFile){
        $stream=[IO.File]::Open($ResultFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $writer=[IO.StreamWriter]::new($stream)
        try{$writer.Write($json)}finally{$writer.Dispose()}
    }
}
try {
    if($Operation -notin @('Auto','Install','Upgrade','Repair','UninstallPlan')){$stage='argument validation';throw 'Unknown installer operation. Use Auto, Install, Upgrade, Repair or UninstallPlan.'}
    if($ResultFile -and (Test-Path -LiteralPath $ResultFile)){throw 'A previous installer result exists; it will not be overwritten.'}
    if (-not $Yes -and -not ($ResolveOnly -or $PreflightOnly -or $Operation -eq 'UninstallPlan')) { throw 'Installation requires explicit -Yes after reviewing the selected paths and configuration.' }
    # Inno embeds these tools separately from the unchanged release manifest. Verify every helper before importing executable code.
    $proof = Join-Path $PSScriptRoot 'installer-tools.json'
    if (Test-Path -LiteralPath $proof) {
        $expected=@('Install-AuthLens.ps1','verify-release.ps1','deploy/AuthLens.Deploy.psm1','deploy/Deploy-AuthLens.ps1','deploy/AuthLens.Paths.ps1','deploy/AuthLens.Acl.ps1','deploy/AuthLens.Installer.ps1')
        $entries=@((Get-Content -LiteralPath $proof -Raw -Encoding UTF8 | ConvertFrom-Json).files)
        if ((@($entries.path | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|')) { throw 'Installer helper inventory is incomplete or unexpected.' }
        foreach ($entry in $entries) {
            if ($entry.path -notmatch '\A(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\z' -or $entry.path -match '(^|/)\.\.(/|$)') { throw 'Invalid installer helper path.' }
            $file = Join-Path $PSScriptRoot ($entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.sha256) { throw 'Installer helper integrity verification failed.' }
        }
    } else { throw 'Packaged installer helper integrity manifest is missing.' }
    Import-Module (Join-Path $PSScriptRoot 'deploy\AuthLens.Deploy.psm1') -Force
    $stage='configuration and prerequisites'
    if ($Mode -eq 'Server') {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Server Setup requires an elevated operator session.' }
        if (@(@($Recover,$PrepareOnly,$ResolveOnly,$PreflightOnly)|Where-Object{$_}).Count -gt 1){throw 'Select only one recovery, resolve, preflight or preparation mode.'}
        if($CommitNewConfiguration -and -not $PrepareOnly){Stop-AL 'New configuration publication requires explicit preparation and approval.'}
        $resolved=Resolve-ALServerSetupConfiguration $ConfigFile $InstallRoot
        $config=$resolved.Config; $InstallRoot=$resolved.ProgramDirectory
        $firewall=$null
        if($FirewallSources -or $ApproveFirewall){
            if(-not $ApproveFirewall){Stop-AL 'Firewall changes require explicit security approval.'}
            $firewall=Get-ALInstallerFirewallPlan $config $FirewallSources $FirewallProfiles
        }
        $journalPath=Get-ALJournalPath $config
        if(($PreflightOnly -or $PrepareOnly) -and -not $Package){Stop-AL 'Preflight/preparation requires a verified release Package. ResolveOnly is the read-only configuration inspection mode.'}
        Assert-ALServerSetupFingerprint $resolved $ExpectedConfigSha256
        if ($Recover -and $PrepareOnly) { throw 'Recover and PrepareOnly cannot be combined.' }
        if($ResolveOnly){
            $result=[pscustomobject]@{operation_id=$operationId;operation='configuration selected; preflight pending';root=$config.Root;program_directory=$InstallRoot;config_file=$config.ConfigFile;config_sha256=$resolved.ConfigSha256;data_directory=$config.DataDirectory;backup_directory=$config.BackupRoot;listen_address=$config.ListenAddress;port=$config.Port;service_name=$config.ServiceName;service_account=$config.ServiceAccount;certificate=$config.CertificatePath;allowed_hosts=@($config.AllowedHosts);proxy_hosts=@($config.ProxyHosts);trusted_proxies=@($config.TrustedProxies)}
        }
        elseif($PreflightOnly -or $Operation -eq 'UninstallPlan'){
            if($Operation -eq 'Repair'){$result=Get-ALServerRepairPlan $resolved $Package}
            else{$result=Get-ALServerSetupPlan $resolved $Package $(if($Operation -eq 'UninstallPlan'){'Auto'}else{$Operation})}
            if($Operation -eq 'UninstallPlan'){$result.operation='uninstall planning; all data preserved; service removal requires a separately reviewed procedure'}
        }
        elseif ($Recover) { $stage='Server recovery transaction'; $result=Invoke-ALInstallerServer $config '' -Recover }
        elseif ($PrepareOnly) {
            $stage='Server upgrade preflight'; $plan=Get-ALServerSetupPlan $resolved $Package $Operation; $operation=$plan.operation
            $stage='Server root preparation'; Initialize-ALInstallerServerRoot $config
            if($CommitNewConfiguration){
                $stage='fresh configuration publication'
                $resolved=Publish-ALServerSetupConfiguration $resolved
                $config=$resolved.Config
                $plan.config_file=$config.ConfigFile; $plan.config_sha256=$resolved.ConfigSha256
            }
            $result=$plan
        }
        elseif($Operation -eq 'Repair'){
            if(-not $Package){Stop-AL 'Repair requires the identical verified release package.'}
            $stage='Server offline repair transaction'
            $result=Invoke-ALInstallerServerRepair $resolved $Package
        }
        else {
            if (-not $Package) { throw 'A verified package is required.' }
            $null=Get-ALServerSetupPlan $resolved $Package $Operation
            $stage='Server deployment transaction'; $result=Invoke-ALInstallerServer $config $Package
            if($firewall){$stage='Server firewall transaction'; $null=Install-ALInstallerFirewallRule $config $firewall -Approved:$ApproveFirewall}
        }
    } else {
        if($CommitNewConfiguration -or $FirewallSources -or $ApproveFirewall){throw 'Server lifecycle options are not Desktop options.'}
        if($ResolveOnly -or $PreflightOnly -or $PlanFile -or $Operation -ne 'Auto'){throw 'Server lifecycle options are not Desktop options.'}
        if ($PrepareOnly) { throw 'PrepareOnly applies to Server directory provisioning only.' }
        if (-not $Package) { throw 'A verified package is required.' }
        if (-not $InstallRoot -or -not $DataDirectory) { throw 'Desktop Setup requires explicit program and data directories.' }
        $stage='Desktop transaction'; $result=Invoke-ALInstallerDesktop $InstallRoot $DataDirectory $Package -Recover:$Recover
    }
    if($Mode -eq 'Server' -and $null -ne $result){
        $legacy=Get-ALInstallerLegacyPresence
        if($result -is [Collections.IDictionary]){$result['legacy']=$legacy}else{$result|Add-Member -NotePropertyName legacy -NotePropertyValue $legacy}
    }
    if($PlanFile){Write-ALServerSetupPlan $PlanFile $result}
    Write-Host ('AUTHLENS-INSTALLER: '+($result | ConvertTo-Json -Depth 8 -Compress))
    Write-InstallerResult @{schema=1;operation_id=$operationId;status='completed';exit_code=0;deployment_journal=$journalPath;result=$result}
    if ($PrepareOnly -and $DiagnosticFile) {
        $stream=[IO.File]::Open($DiagnosticFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $writer=[IO.StreamWriter]::new($stream)
        try { $writer.Write('Server preflight verified: '+$operation) } finally { $writer.Dispose() }
    }
    exit 0
} catch {
    # Never include invocation text, configuration content, stack dumps or arbitrary parser errors.
    $known=@('Unknown installer operation. Use Auto, Install, Upgrade, Repair or UninstallPlan.','A previous installer result exists; it will not be overwritten.','Select only one recovery, resolve, preflight or preparation mode.','Server lifecycle options are not Desktop options.','Installation requires explicit -Yes after reviewing the selected paths and configuration.','Packaged installer helper integrity manifest is missing.','Installer helper integrity verification failed.','Installer helper inventory is incomplete or unexpected.','Invalid installer helper path.','Server Setup requires an elevated operator session.','Recover and PrepareOnly cannot be combined.')
    $reason=if ($_.Exception.GetType().Name -eq 'DeployException' -or $_.Exception.Message -in $known) { $_.Exception.Message } else { 'Prerequisite/helper/configuration error ('+$_.Exception.GetType().Name+'). Review the explicit configuration and packaged helper integrity.' }
    $reason=[regex]::Replace($reason,'(?i)(password|token|secret|credential|passphrase)\s*[:=]\s*[^\s;,]+','$1=[REDACTED]')
    $diagnostic="Stage: $stage. $reason"
    Write-Host ('Installer refused or failed: '+$diagnostic)
    if ($DiagnosticFile) {
        try { $stream=[IO.File]::Open($DiagnosticFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $writer=[IO.StreamWriter]::new($stream); try { $writer.Write($diagnostic) } finally { $writer.Dispose() } } catch { Write-Host 'Diagnostic file could not be created; existing evidence was not overwritten.' }
    }
    $code=if($stage -like '*transaction'){4}else{2}
    if ($_.Exception.PSObject.Properties['ExitCode']) { $code=$_.Exception.ExitCode }
    try{Write-InstallerResult @{schema=1;operation_id=$operationId;status='refused_or_failed';exit_code=$code;stage=$stage;message=$reason;diagnostic_file=$DiagnosticFile;deployment_journal=$journalPath}}catch{Write-Host 'Structured result could not be persisted; existing evidence was retained.'}
    exit $code
}
