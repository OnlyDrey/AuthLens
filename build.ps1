<# Builds and verifies both Windows products and installers. Never installs or operates services. #>
[CmdletBinding()]
param([string]$OutputRoot='C:\AuthLens',[switch]$SkipTests,[string]$TestFilter='', [string]$Iscc='')
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backend/scripts/Build-Workflow.ps1')
$directory=$null; $transcribing=$false; $status='failed'; $failure=$null
$summary=[ordered]@{schema=1;identity=$null;tools=@{};tests=@{status='not_run';filter=$TestFilter};verification=@{release=$false;installers=$false;secrets=$false};status='failed';failure_reason=$null;artifacts=@()}
try {
    if ($env:OS -ne 'Windows_NT') { throw 'This entry point requires Windows.' }
    foreach ($command in 'git','dotnet','node','npm.cmd','python') { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Missing prerequisite: $command" } }
    $sha=(& git -C $PSScriptRoot rev-parse HEAD).Trim(); if ($LASTEXITCODE) { throw 'Cannot identify Git HEAD.' }
    if (@(& git -C $PSScriptRoot status --porcelain).Count) { throw 'Commit or preserve working-tree changes before building. Dirty builds are refused.' }
    $branch=(& git -C $PSScriptRoot branch --show-current).Trim()
    $version=(Get-Content (Join-Path $PSScriptRoot 'backend/product-version.json') -Raw | ConvertFrom-Json).version
    $timestamp=[datetime]::UtcNow
    $directory=New-AuthLensBuildDirectory $OutputRoot $timestamp $sha
    $summary.identity=[ordered]@{product='AuthLens';version=$version;source_sha=$sha;branch=$branch;build_timestamp_utc=$timestamp.ToString('yyyy-MM-ddTHH:mm:ssZ')}
    Start-Transcript -Path (Join-Path $directory 'build.log') -NoClobber | Out-Null; $transcribing=$true
    if (-not $Iscc) { $Iscc=@("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe","$env:ProgramFiles\Inno Setup 6\ISCC.exe","$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
    $summary.tools=@{powershell=$PSVersionTable.PSVersion.ToString();git=(& git --version | Out-String).Trim();dotnet=(& dotnet --version | Out-String).Trim();node=(& node --version | Out-String).Trim();npm=(& npm.cmd --version | Out-String).Trim();python=(& python --version | Out-String).Trim();iscc='unavailable'}
    if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) { throw 'Inno Setup 6 ISCC.exe is required; pass -Iscc if installed elsewhere.' }
    $summary.tools.iscc=(Get-Item -LiteralPath $Iscc).VersionInfo.FileVersion
    if ($summary.tools.node -notmatch '^v(24|25)\.' -or $summary.tools.dotnet -notmatch '^10\.') { throw 'Node 24/25 and .NET SDK 10 are required.' }
    $shell=Join-Path $PSHOME 'powershell.exe'; if ($PSVersionTable.PSEdition -eq 'Core') { $shell=Join-Path $PSHOME 'pwsh.exe' }
    $build=Join-Path $directory 'build'; $installer=Join-Path $directory 'installer'
    $arguments=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/build-release.ps1'),'-Output',$build,'-BuildTimestampUtc',$timestamp.ToString('o'))
    if ($SkipTests) { $arguments+='-SkipTests'; $summary.tests.status='skipped' } else { $summary.tests.status='running'; if ($TestFilter) { $arguments+=@('-TestFilter',$TestFilter) } }
    $code=Invoke-AuthLensBuildProcess $shell $arguments
    if ($code) { throw "Release build failed (exit $code). See build.log; partial outputs retained." }
    if (-not $SkipTests) { $summary.tests.status='passed' }
    $manifests=@(Get-ChildItem -LiteralPath $build -Filter build-manifest.json -Recurse)
    if ($manifests.Count -ne 1) { throw 'Expected exactly one release manifest.' }
    $manifest=Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
    Assert-AuthLensBuildIdentity $manifest ([pscustomobject]$summary.identity)
    $code=Invoke-AuthLensBuildProcess $shell @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/verify-release.ps1'),'-ReleasePath',$manifests[0].DirectoryName)
    if ($code) { throw 'Release verification failed.' }; $summary.verification.release=$true
    # The existing release builder owns the required secret scan. Python is mandatory here, so it cannot be skipped.
    $summary.verification.secrets=$true
    $code=Invoke-AuthLensBuildProcess $shell @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/build-installers.ps1'),'-ReleasePath',$manifests[0].DirectoryName,'-Output',$installer,'-Iscc',$Iscc)
    if ($code) { throw 'Installer build failed.' }
    $metadata=Get-Content -LiteralPath (Join-Path $installer 'installer-manifest.json') -Raw | ConvertFrom-Json
    Assert-AuthLensBuildIdentity $metadata ([pscustomobject]$summary.identity)
    foreach ($artifact in $metadata.artifacts) { if ((Get-FileHash -LiteralPath (Join-Path $installer $artifact.path) -Algorithm SHA256).Hash -ine $artifact.sha256) { throw 'Installer checksum mismatch.' } }
    if (@(& git -C $PSScriptRoot status --porcelain).Count -or (& git -C $PSScriptRoot rev-parse HEAD).Trim() -ne $sha) { throw 'Source changed during the build.' }
    $summary.verification.installers=$true; $status='passed'
} catch { $failure=$_.Exception.Message; Write-Host "Build failed: $failure" }
finally {
    if ($directory) {
        $summary.status=$status; $summary.failure_reason=$failure
        if ($summary.tests.status -eq 'running') { $summary.tests.status='failed_or_incomplete' }
        $summary.artifacts=@(Get-AuthLensBuildArtifacts $directory)
        [IO.File]::WriteAllText((Join-Path $directory 'build-summary.json'),($summary | ConvertTo-Json -Depth 12))
        Write-Host "Summary: $status | $directory"
    }
    if ($transcribing) { Stop-Transcript | Out-Null }
}
if ($status -ne 'passed') { exit 1 }
exit 0
