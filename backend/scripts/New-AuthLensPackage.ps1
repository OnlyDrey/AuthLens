<#
.SYNOPSIS
  BUILD-010: packages an EXISTING verified AuthLens build as a flat portable package Packages\AuthLens-<version>-<build-id>.zip (or, for a
  later package revision of the same build, AuthLens-<version>-<build-id>-pkg<N>.zip) with its .zip.sha256, without rebuilding anything.
.DESCRIPTION
  Explicit selection only: -Candidate C:\AuthLens\Build\<version>\<build-id> (or Installer\<version>\<build-id>, or -OutputRoot C:\AuthLens with
  -Candidate <version>\<build-id>). Nothing is selected automatically. Before packaging, the passed build summary, the release and installer
  manifests, every installer-directory file (size and SHA-256 against build-summary.json), both Setup programs and the packaged installation,
  verification and recovery tooling are verified; incomplete, modified or inconsistent candidates and legacy run directories (RC5 and earlier)
  are refused, and missing installers are never regenerated. The archive root holds both Setup programs, installer-manifest.json,
  Expand-AuthLensPackage.ps1, README.txt, package-manifest.json and SHA256SUMS.txt; Tools\ holds the helpers. The extraction script and README come
  from this packaging tooling. -PackageRevision (default 1) is package metadata only; the build identity is unchanged. The archive is written as
  *.partial-<guid>, extracted and verified independently, and only then published with its .sha256 file. Existing packages are never
  overwritten; a failure removes only this run's partial files and never changes Build or Installer. Exit 0 packaged, 1 refused or failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\scripts\New-AuthLensPackage.ps1 -Candidate C:\AuthLens\Build\2.0.0\2026-11-25_2145-b10dd50
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\scripts\New-AuthLensPackage.ps1 -Candidate C:\AuthLens\Build\2.0.0\2026-11-26_0330-839123c -PackageRevision 2
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Candidate, [string]$OutputRoot = '', [ValidateRange(1, 99)][int]$PackageRevision = 1)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build-Workflow.ps1')
try {
    $resolved = Resolve-AuthLensCandidate $Candidate $OutputRoot
    $package = New-AuthLensPackage $resolved '' $PackageRevision
    Write-Host "Package: $($package.path) (layout $($package.layout), package revision $($package.revision); extracts to $($package.release_directory))"
    Write-Host "Size: $($package.size) bytes; SHA-256: $($package.sha256) ($($package.checksum_file))"
    Write-Host "Release identity: AuthLens $($package.version) build $($package.build_id), commit $($package.source_sha), built $($package.build_timestamp_utc)"
    foreach ($signature in $package.signatures) { Write-Host "Authenticode $($signature.file): $($signature.status)" }
    Write-Host $package.authenticity
    Write-Host ('AUTHLENS-PACKAGE-BUILD: ' + ($package | ConvertTo-Json -Compress -Depth 5))
    exit 0
} catch {
    Write-Host "Packaging refused or failed: $($_.Exception.Message) Build and installer artifacts were not changed."
    Write-Host ('AUTHLENS-PACKAGE-BUILD: ' + ([pscustomobject]@{ status = 'failed'; reason = $_.Exception.Message } | ConvertTo-Json -Compress))
    exit 1
}
