<# Builds and verifies both Windows products and installers. Never installs or operates services.
   WP32 layout under -OutputRoot (default C:\AuthLens); one build id <UTC yyyy-MM-dd_HHmm>-<sha7> is generated once per build and reused:
     Build\<version>\<build-id>\       the verified release (server\, desktop\, symbols\, build-manifest.json, ...) and the build record
                                       (build-summary.json, build.log, .build-claim, branding-verification.json)
     Installer\<version>\<build-id>\   AuthLens-<version>-Server-Setup.exe, AuthLens-<version>-Desktop-Setup.exe, installer-manifest.json, tooling
     Acceptance\<version>\<build-id>\  reserved for acceptance runs (created later by the acceptance tooling)
     Packages\AuthLens-<version>-<build-id>.zip(.sha256)   only with -ZipPackage, after build, installers and verification passed
   Collisions append -02, -03 ...; existing ids, legacy run directories and their evidence are never reused, overwritten, moved or renamed. #>
[CmdletBinding()]
param([string]$OutputRoot='C:\AuthLens',[switch]$SkipTests,[string]$TestFilter='', [string]$Iscc='', [switch]$ZipPackage)
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backend/scripts/Build-Workflow.ps1')
$layout=$null; $directory=$null; $transcribing=$false; $status='failed'; $failure=$null
$summary=[ordered]@{schema=2;layout='category';version=$null;id=$null;directories=$null;identity=$null;tools=@{};tests=@{status='not_run';filter=$TestFilter};verification=@{release=$false;installers=$false;secrets=$false;branding=$false};package=@{requested=[bool]$ZipPackage;status=$(if($ZipPackage){'pending'}else{'not_requested'})};status='failed';failure_reason=$null;artifacts=@()}
try {
    if ($env:OS -ne 'Windows_NT') { throw 'This entry point requires Windows.' }
    foreach ($command in 'git','dotnet','node','npm.cmd','python') { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Missing prerequisite: $command" } }
    $sha=(& git -C $PSScriptRoot rev-parse HEAD).Trim(); if ($LASTEXITCODE) { throw 'Cannot identify Git HEAD.' }
    if (@(& git -C $PSScriptRoot status --porcelain).Count) { throw 'Commit or preserve working-tree changes before building. Dirty builds are refused.' }
    $branch=Get-AuthLensBranch $PSScriptRoot   # 'HEAD' for a clean detached release worktree; identity is the commit
    $version=(Get-Content (Join-Path $PSScriptRoot 'backend/product-version.json') -Raw | ConvertFrom-Json).version
    $timestamp=[datetime]::UtcNow
    $layout=New-AuthLensBuildLayout $OutputRoot $timestamp $sha -Version $version
    $directory=$layout.BuildDirectory
    $summary.version=$version; $summary.id=$layout.Id
    $summary.directories=[ordered]@{build=('Build/'+$version+'/'+$layout.Id);installer=('Installer/'+$version+'/'+$layout.Id);acceptance=('Acceptance/'+$version+'/'+$layout.Id);package=('Packages/AuthLens-'+$version+'-'+$layout.Id+'.zip')}
    $summary.identity=[ordered]@{product='AuthLens';version=$version;source_sha=$sha;branch=$branch;build_timestamp_utc=$timestamp.ToString('o')}
    Start-Transcript -Path (Join-Path $directory 'build.log') -NoClobber | Out-Null; $transcribing=$true
    if (-not $Iscc) { $Iscc=@("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe","$env:ProgramFiles\Inno Setup 6\ISCC.exe","$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
    $summary.tools=@{powershell=$PSVersionTable.PSVersion.ToString();git=(& git --version | Out-String).Trim();dotnet=(& dotnet --version | Out-String).Trim();node=(& node --version | Out-String).Trim();npm=(& npm.cmd --version | Out-String).Trim();python=(& python --version | Out-String).Trim();iscc='unavailable'}
    if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) { throw 'Inno Setup 6 ISCC.exe is required; pass -Iscc if installed elsewhere.' }
    $summary.tools.iscc=(Get-Item -LiteralPath $Iscc).VersionInfo.FileVersion
    if ($summary.tools.node -notmatch '^v(24|25)\.' -or $summary.tools.dotnet -notmatch '^10\.') { throw 'Node 24/25 and .NET SDK 10 are required.' }
    $shell=Join-Path $PSHOME 'powershell.exe'; if ($PSVersionTable.PSEdition -eq 'Core') { $shell=Join-Path $PSHOME 'pwsh.exe' }
    $release=$layout.ReleaseDirectory; $installer=$layout.InstallerDirectory
    # The release is published directly into Build\<version>\<build-id> (no nested release folder); the build record files stay outside its manifest.
    $arguments=@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/build-release.ps1'),'-ReleaseDirectory',$release,'-BuildTimestampUtc',$timestamp.ToString('o'))
    if ($SkipTests) { $arguments+='-SkipTests'; $summary.tests.status='skipped' } else { $summary.tests.status='running'; if ($TestFilter) { $arguments+=@('-TestFilter',$TestFilter) } }
    $code=Invoke-AuthLensBuildProcess $shell $arguments
    if ($code) { throw "Release build failed (exit $code). See build.log; partial outputs retained." }
    if (-not $SkipTests) { $summary.tests.status='passed' }
    if (-not (Test-Path -LiteralPath (Join-Path $release 'build-manifest.json') -PathType Leaf)) { throw 'Expected the release manifest in the build directory.' }
    $manifest=Get-Content -LiteralPath (Join-Path $release 'build-manifest.json') -Raw | ConvertFrom-Json
    Assert-AuthLensBuildIdentity $manifest ([pscustomobject]$summary.identity)
    $code=Invoke-AuthLensBuildProcess $shell @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/verify-release.ps1'),'-ReleasePath',$release)
    if ($code) { throw 'Release verification failed.' }; $summary.verification.release=$true
    # The existing release builder owns the required secret scan. Python is mandatory here, so it cannot be skipped.
    $summary.verification.secrets=$true
    $code=Invoke-AuthLensBuildProcess $shell @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'backend/scripts/build-installers.ps1'),'-ReleasePath',$release,'-Output',$installer,'-Iscc',$Iscc)
    if ($code) { throw 'Installer build failed.' }
    $code=Invoke-AuthLensBuildProcess (Get-Command node).Source @((Join-Path $PSScriptRoot 'scripts/verify-branding.mjs'),$release,$installer,(Join-Path $PSScriptRoot 'frontend/dist'),(Join-Path $release 'branding-verification.json'))
    if ($code) { throw 'Native executable/installer or frontend branding verification failed.' }
    $summary.verification.branding=$true
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
        if ($ZipPackage -and $status -ne 'passed') { $summary.package.status='not_run_build_failed' }
        $summary.artifacts=@(Get-AuthLensCandidateArtifacts $layout)
        [IO.File]::WriteAllText((Join-Path $directory 'build-summary.json'),($summary | ConvertTo-Json -Depth 12))
        Write-Host "Summary: $status | $directory"
        Write-Host "Installers: $($layout.InstallerDirectory)"
    }
    if ($transcribing) { Stop-Transcript | Out-Null; $transcribing=$false }
}
# BUILD-009: the optional portable package is a transport artifact of the verified build above, never a rebuild. Its outcome is added to
# build-summary.json (package field; the verified artifact inventory is unchanged). A packaging failure fails this -ZipPackage run and leaves
# Build and Installer untouched.
if ($ZipPackage -and $status -eq 'passed') {
    $packageResult=[ordered]@{requested=$true;status='failed';failure_reason=$null}
    try {
        $p=New-AuthLensPackage (Resolve-AuthLensCandidate $layout.BuildDirectory)
        foreach ($name in 'layout','revision','release_directory','path','checksum_file','size','sha256','version','build_id','source_sha','build_timestamp_utc','entries','signatures','independent_extraction','authenticity') { $packageResult[$name]=$p.$name }
        $packageResult.status='passed'
        Write-Host "Package: $($p.path) ($($p.size) bytes)"
        Write-Host "Package SHA-256: $($p.sha256) ($($p.checksum_file))"
        Write-Host "Release identity: AuthLens $($p.version) build $($p.build_id), commit $($p.source_sha), built $($p.build_timestamp_utc)"
        foreach ($signature in $p.signatures) { Write-Host "Signature: $($signature.file) $($signature.status) (checksums prove integrity, not publisher authenticity)" }
    } catch { $packageResult.failure_reason=$_.Exception.Message; Write-Host "Packaging failed: $($packageResult.failure_reason) Build and installer artifacts were preserved." }
    $summary.package=$packageResult
    [IO.File]::WriteAllText((Join-Path $directory 'build-summary.json'),($summary | ConvertTo-Json -Depth 12))
    if ($packageResult.status -ne 'passed') { $status='failed' }
    Write-Host "Package: $($packageResult.status) | -ZipPackage operation $(if ($status -eq 'passed') { 'passed' } else { 'FAILED' })"
}if ($status -ne 'passed') { exit 1 }
exit 0
