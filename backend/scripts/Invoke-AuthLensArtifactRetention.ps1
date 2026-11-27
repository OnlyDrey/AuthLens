<#
.SYNOPSIS
  WP34 artifact inventory and reviewed retention for the build output root (C:\AuthLens): Build, Installer, Acceptance and Packages.
.DESCRIPTION
  Default: a read-only preview (dry run, nothing is created, changed or deleted) by category, version and build id, with the reason every
  item is preserved or eligible, the reclaimable storage and a selection_sha256 over the selected items.
  Deletion only with -Remove -Item <ids from the preview> -ExpectedSelectionSha256 <preview hash> -Yes. Acceptance evidence, legacy run
  directories (RC5 and earlier), builds with acceptance evidence, incomplete builds, artifacts whose Build record is missing, the newest
  -KeepPassed passed builds and anything unrecognized are never eligible. A package (.zip with its .zip.sha256) is one item; later package revisions
  (AuthLens-<version>-<build-id>-pkg<N>.zip) are separate items (package:<version>/<build-id>-pkg<N>). Builds never call
  this script; nothing is deleted automatically. Exit 0 success, 1 refused or failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\scripts\Invoke-AuthLensArtifactRetention.ps1 -OutputRoot C:\AuthLens
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\backend\scripts\Invoke-AuthLensArtifactRetention.ps1 -Remove -Item 'package:2.0.0/2026-11-25_2145-b10dd50' -ExpectedSelectionSha256 <hash> -Yes
#>
[CmdletBinding()]
param([string]$OutputRoot = 'C:\AuthLens', [int]$KeepPassed = 3, [string[]]$Preserve = @(), [string[]]$Item = @(), [switch]$Remove,
    [string]$ExpectedSelectionSha256 = '', [switch]$Yes)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build-Workflow.ps1')
try {
    if ($Remove) {
        $result = Remove-AuthLensBuildArtifacts $OutputRoot $Item $ExpectedSelectionSha256 $KeepPassed $Preserve -Approve:$Yes
        Write-Host "Deleted $(@($result.deleted).Count) item(s); reclaimed $($result.reclaimed_bytes) bytes (free $($result.available_before) -> $($result.available_after))."
    } else {
        $result = Get-AuthLensBuildInventory $OutputRoot $KeepPassed $Preserve $Item
        foreach ($entry in $result.items) { Write-Host ('{0,-10} {1,-60} {2,14} {3}' -f $entry.state, $entry.id, $entry.bytes, (@($entry.reasons) -join ', ')) }
        Write-Host "Eligible: $($result.eligible_bytes) bytes; selected $(@($result.selection).Count) item(s), $($result.selection_bytes) bytes; selection_sha256 $($result.selection_sha256)"
        Write-Host 'Preview only (dry run): nothing was changed.'
    }
    Write-Host ('AUTHLENS-RETENTION: ' + ($result | ConvertTo-Json -Compress -Depth 6))
    exit 0
} catch {
    Write-Host "Retention refused or failed: $($_.Exception.Message)"
    exit 1
}
