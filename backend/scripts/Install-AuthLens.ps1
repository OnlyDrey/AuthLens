<#
.SYNOPSIS
  Inno Setup's explicit manual install/update adapter. Uses verified versioned Server deployment and the existing application backup engine.
.DESCRIPTION
  No Git, SDK, download, service discovery or legacy adoption. Desktop requires a closed application and an external data directory.
  Server requires an explicit deployment configuration and elevation. -Yes is mandatory. Native SCM acceptance uses isolated test names/roots only.
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
    [string]$DiagnosticFile='',
    [switch]$Yes
)
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
$stage='helper verification'
try {
    if (-not $Yes) { throw 'Installation requires explicit -Yes after reviewing the selected paths and configuration.' }
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
        if (-not $ConfigFile) { throw 'Server Setup requires an explicit -ConfigFile; it never infers a running installation.' }
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Server Setup requires an elevated operator session.' }
        $config=Read-AuthLensSettings $ConfigFile -Packaged
        if (-not $InstallRoot -or [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') -ine [IO.Path]::GetFullPath((Join-Path $config.Root 'app')).TrimEnd('\')) { throw 'Server Setup program directory must be the configured installation root app directory.' }
        if ($Recover -and $PrepareOnly) { throw 'Recover and PrepareOnly cannot be combined.' }
        if ($Recover) { $result=Invoke-ALInstallerServer $config '' -Recover }
        elseif ($PrepareOnly) {
            $stage='Server upgrade preflight'; $operation=Assert-ALInstallerServerPreflight $config
            $stage='Server root preparation'; Initialize-ALInstallerServerRoot $config
            $result=@{prepared=$true;operation=$operation}
        }
        else { if (-not $Package) { throw 'A verified package is required.' }; $result=Invoke-ALInstallerServer $config $Package }
    } else {
        if ($PrepareOnly) { throw 'PrepareOnly applies to Server directory provisioning only.' }
        if (-not $Package) { throw 'A verified package is required.' }
        if (-not $InstallRoot -or -not $DataDirectory) { throw 'Desktop Setup requires explicit program and data directories.' }
        $result=Invoke-ALInstallerDesktop $InstallRoot $DataDirectory $Package -Recover:$Recover
    }
    Write-Host ('AUTHLENS-INSTALLER: '+($result | ConvertTo-Json -Depth 8 -Compress))
    exit 0
} catch {
    # Never include invocation text, configuration content, stack dumps or arbitrary parser errors.
    $known=@('Packaged installer helper integrity manifest is missing.','Installer helper integrity verification failed.','Installer helper inventory is incomplete or unexpected.','Invalid installer helper path.','Server Setup requires an explicit -ConfigFile; it never infers a running installation.','Server Setup requires an elevated operator session.','Server Setup program directory must be the configured installation root app directory.','Recover and PrepareOnly cannot be combined.')
    $reason=if ($_.Exception.GetType().Name -eq 'DeployException' -or $_.Exception.Message -in $known) { $_.Exception.Message } else { 'Prerequisite/helper/configuration error ('+$_.Exception.GetType().Name+'). Review the explicit configuration and packaged helper integrity.' }
    $reason=[regex]::Replace($reason,'(?i)(password|token|secret|credential|passphrase)\s*[:=]\s*[^\s;,]+','$1=[REDACTED]')
    $diagnostic="Stage: $stage. $reason"
    Write-Host ('Installer refused or failed: '+$diagnostic)
    if ($DiagnosticFile) {
        try { $stream=[IO.File]::Open($DiagnosticFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $writer=[IO.StreamWriter]::new($stream); try { $writer.Write($diagnostic) } finally { $writer.Dispose() } } catch { Write-Host 'Diagnostic file could not be created; existing evidence was not overwritten.' }
    }
    $code=2
    if ($_.Exception.PSObject.Properties['ExitCode']) { $code=$_.Exception.ExitCode }
    exit $code
}
