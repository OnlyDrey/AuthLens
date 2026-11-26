<#
.SYNOPSIS
  Verifies and extracts an AuthLens portable deployment package (WP32 BUILD-009/010) without overwriting anything. Windows PowerShell 5.1 and 7.
.DESCRIPTION
  Extraction (default): -Package <dir>\AuthLens-<version>-<build-id>.zip with <zip>.sha256 beside it (or -ChecksumFile).
    1. The ZIP SHA-256 must equal the checksum file. This proves integrity against that digest, not publisher authenticity.
    2. Every entry is validated before anything is written: relative, no drive, no '..' or '.', no duplicates (case-insensitive), all under
       Installer/<version>/<build-id>/ of this package name, and exactly the files package-manifest.json lists (unexpected content is refused).
    3. The target <Destination>\Installer\<version>\<build-id> must not exist (it is never overwritten). Files are extracted into a new sibling
       folder .x-<random>, each size and SHA-256 is verified, the release identity of package-manifest.json and
       installer-manifest.json must agree, and only then the folder is renamed into place. A failure removes only this run's temporary folder;
       an interrupted run leaves a .x-* folder that is never treated as a package (it is reported by the next run).
  -VerifyOnly -ExtractedDirectory <Installer\<version>\<build-id>>: re-verifies an extracted folder against its package-manifest.json (exact
  file set, sizes, hashes, identity). A folder that merely exists is never treated as a complete extraction.
  Reports the Authenticode status of each Setup program. Last line: AUTHLENS-PACKAGE: <json>. Exit 0 verified, 1 refused or failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Expand-AuthLensPackage.ps1 -Package C:\AuthLens\AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip -Destination C:\AuthLens
#>
[CmdletBinding()]
param(
    [string]$Package = '',
    [string]$Destination = 'C:\AuthLens',
    [string]$ChecksumFile = '',
    # The package file name to validate against (the packager verifies its own *.partial file under the final name).
    [string]$ArchiveName = '',
    [switch]$VerifyOnly,
    [string]$ExtractedDirectory = ''
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$versionPattern = '^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})(-(alpha|beta|rc)\.([1-9]\d{0,4}))?$'
$idPattern = '^\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(-\d{2})?$'
$result = [ordered]@{ schema = 1; tool = 'Expand-AuthLensPackage'; mode = $(if ($VerifyOnly) { 'verify' } else { 'extract' }); status = 'refused'; reason = ''
    version = ''; build_id = ''; source_sha = ''; target = ''; files_verified = 0; signatures = @(); leftover_extractions = @()
    authenticity = 'SHA-256 checksums prove integrity against the recorded digests only, not publisher authenticity.' }

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Stop-Package([string]$Reason) { throw [InvalidOperationException]::new($Reason) }
function Read-PackageManifest([string]$Text, [string]$Version, [string]$Id) {
    try { $manifest = $Text | ConvertFrom-Json } catch { Stop-Package 'package-manifest.json is not valid JSON.' }
    foreach ($field in 'schema', 'product', 'version', 'build_id', 'source_sha', 'build_timestamp_utc', 'files') { if (-not $manifest.PSObject.Properties[$field]) { Stop-Package "package-manifest.json lacks $field." } }
    if ($manifest.schema -ne 1 -or $manifest.product -cne 'AuthLens' -or $manifest.version -cne $Version -or $manifest.build_id -cne $Id -or [string]$manifest.source_sha -cnotmatch '^[0-9a-f]{40}$') { Stop-Package 'package-manifest.json does not describe this package (product, version, build id or commit).' }
    if (([string]$manifest.source_sha).Substring(0, 7) -cne ($Id -replace '-\d{2}$', '').Substring(16)) { Stop-Package 'The build id does not carry the recorded commit.' }
    $seen = @{}
    foreach ($file in @($manifest.files)) {
        $path = [string]$file.path
        if (-not $path -or $path -match '(^/|\\|:|(^|/)\.{1,2}(/|$))' -or $seen.ContainsKey($path.ToLowerInvariant()) -or [string]$file.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$file.size -lt 0) { Stop-Package "package-manifest.json lists an invalid or duplicate file '$path'." }
        $seen[$path.ToLowerInvariant()] = $true
    }
    $manifest
}
function Test-Identity([string]$Folder, $Manifest) {
    $installer = Join-Path $Folder 'installer-manifest.json'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { Stop-Package 'installer-manifest.json is missing.' }
    $metadata = Get-Content -LiteralPath $installer -Raw -Encoding UTF8 | ConvertFrom-Json
    $stamp = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime().Ticks } else { [DateTime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal).Ticks } }
    if ($metadata.product -cne 'AuthLens' -or $metadata.version -cne $Manifest.version -or $metadata.source_sha -cne $Manifest.source_sha -or (& $stamp $metadata.build_timestamp_utc) -ne (& $stamp $Manifest.build_timestamp_utc) -or $metadata.source_dirty) {
        Stop-Package 'installer-manifest.json and package-manifest.json name different releases.'
    }
    foreach ($entry in @($metadata.artifacts)) {
        $file = Join-Path $Folder ([string]$entry.path)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Sha256 $file) -cne ([string]$entry.sha256).ToLowerInvariant()) { Stop-Package "Setup program $($entry.path) differs from installer-manifest.json." }
    }
    @(foreach ($entry in @($metadata.artifacts)) { [ordered]@{ file = [string]$entry.path; status = [string](Get-AuthenticodeSignature -LiteralPath (Join-Path $Folder ([string]$entry.path))).Status } })
}
function Test-Folder([string]$Folder, $Manifest) {
    $base = [IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $expected = @{}
    foreach ($file in @($Manifest.files)) { $expected[([string]$file.path).ToLowerInvariant()] = $file }
    $expected['package-manifest.json'] = $null
    foreach ($item in @(Get-ChildItem -LiteralPath $base -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-Package "Reparse point in the package folder: $($item.Name)." }
        if ($item.PSIsContainer) { continue }
        $relative = $item.FullName.Substring($base.Length + 1).Replace('\', '/')
        if (-not $expected.ContainsKey($relative.ToLowerInvariant())) { Stop-Package "Unexpected file in the package folder: $relative." }
    }
    $count = 0
    foreach ($file in @($Manifest.files)) {
        $path = Join-Path $base (([string]$file.path).Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Package "Missing file: $($file.path)." }
        if ((Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Get-Sha256 $path) -cne [string]$file.sha256) { Stop-Package "File differs from package-manifest.json: $($file.path)." }
        $count++
    }
    $count
}

$staging = $null
try {
    if ($VerifyOnly) {
        if (-not $ExtractedDirectory) { Stop-Package '-VerifyOnly needs -ExtractedDirectory <...\Installer\<version>\<build-id>>.' }
        $folder = [IO.Path]::GetFullPath($ExtractedDirectory).TrimEnd('\', '/')
        $id = Split-Path $folder -Leaf; $version = Split-Path (Split-Path $folder -Parent) -Leaf
        if ($id -notmatch $idPattern -or $version -notmatch $versionPattern -or (Split-Path (Split-Path (Split-Path $folder -Parent) -Parent) -Leaf) -ne 'Installer') { Stop-Package 'The folder is not Installer\<version>\<build-id>.' }
        if (-not (Test-Path -LiteralPath (Join-Path $folder 'package-manifest.json') -PathType Leaf)) { Stop-Package 'package-manifest.json is missing; this folder was not extracted from a verified package.' }
        $manifest = Read-PackageManifest (Get-Content -LiteralPath (Join-Path $folder 'package-manifest.json') -Raw -Encoding UTF8) $version $id
        $result.version = $version; $result.build_id = $id; $result.source_sha = $manifest.source_sha; $result.target = $folder
        $result.files_verified = Test-Folder $folder $manifest
        $result.signatures = @(Test-Identity $folder $manifest)
        $result.status = 'verified'
    } else {
        if (-not $Package) { Stop-Package 'Select the package with -Package <AuthLens-<version>-<build-id>.zip>.' }
        $zipPath = [IO.Path]::GetFullPath($Package)
        if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { Stop-Package 'The package file does not exist.' }
        $name = if ($ArchiveName) { $ArchiveName } else { Split-Path $zipPath -Leaf }
        if ($name -notmatch '^AuthLens-(?<version>.+)-(?<id>\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(?:-\d{2})?)\.zip$') { Stop-Package 'The package name is not AuthLens-<version>-<build-id>.zip.' }
        $version = $Matches['version']; $id = $Matches['id']
        if ($version -notmatch $versionPattern) { Stop-Package 'The package name does not carry a canonical AuthLens version.' }
        $result.version = $version; $result.build_id = $id
        if (-not $ChecksumFile) { $ChecksumFile = $zipPath + '.sha256' }
        if (-not (Test-Path -LiteralPath $ChecksumFile -PathType Leaf)) { Stop-Package 'The .sha256 checksum file is missing; the package is not verified.' }
        $line = @(Get-Content -LiteralPath $ChecksumFile | Where-Object { $_.Trim() })
        if ($line.Count -ne 1 -or $line[0].Trim() -notmatch '^(?<sha>[0-9a-fA-F]{64}) [ *](?<file>.+)$' -or $Matches['file'] -cne $name) { Stop-Package 'The checksum file does not name exactly this package.' }
        $expectedSha = $Matches['sha'].ToLowerInvariant()
        if ((Get-Sha256 $zipPath) -cne $expectedSha) { Stop-Package 'The package SHA-256 differs from its checksum file.' }
        $prefix = 'Installer/' + $version + '/' + $id + '/'
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
        $parent = Join-Path (Join-Path $root 'Installer') $version
        $target = Join-Path $parent $id
        $result.target = $target
        if (Test-Path -LiteralPath $parent) { $result.leftover_extractions = @(Get-ChildItem -LiteralPath $parent -Directory -Force -Filter '.x-*' | ForEach-Object Name) }
        if (Test-Path -LiteralPath $target) { Stop-Package "The target $target exists and is never overwritten. Verify it with -VerifyOnly -ExtractedDirectory, or extract elsewhere." }
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @{}; $total = [long]0
            foreach ($entry in $zip.Entries) {
                $full = $entry.FullName.Replace('\', '/')
                if (-not $full -or $full.StartsWith('/') -or $full.Contains(':') -or @($full.Split('/') | Where-Object { $_ -in @('.', '..') }).Count) { Stop-Package "Refused archive entry '$full' (absolute, drive or traversal path)." }
                if (-not $full.StartsWith($prefix, [StringComparison]::Ordinal)) { Stop-Package "Refused archive entry '$full' outside $prefix." }
                if ($full.EndsWith('/')) { continue }
                $relative = $full.Substring($prefix.Length)
                if (-not $relative -or $entries.ContainsKey($relative.ToLowerInvariant())) { Stop-Package "Refused duplicate or empty archive entry '$full'." }
                $entries[$relative.ToLowerInvariant()] = $entry; $total += $entry.Length
            }
            if ($entries.Count -gt 20000 -or $total -gt 8GB) { Stop-Package 'The archive is larger than any AuthLens package.' }
            if (-not $entries.ContainsKey('package-manifest.json')) { Stop-Package 'package-manifest.json is missing from the archive.' }
            $reader = [IO.StreamReader]::new($entries['package-manifest.json'].Open())
            try { $manifest = Read-PackageManifest $reader.ReadToEnd() $version $id } finally { $reader.Dispose() }
            $listed = @{ 'package-manifest.json' = $true }; foreach ($file in @($manifest.files)) { $listed[([string]$file.path).ToLowerInvariant()] = $true }
            foreach ($key in $entries.Keys) { if (-not $listed.ContainsKey($key)) { Stop-Package "Unexpected archive content: $key." } }
            foreach ($key in $listed.Keys) { if (-not $entries.ContainsKey($key)) { Stop-Package "The archive lacks $key." } }
            $result.source_sha = $manifest.source_sha
            # WP34: extraction needs the uncompressed contents once on the destination volume (the ZIP itself is already present) plus a margin.
            $volume = [IO.Path]::GetPathRoot($root)
            $available = [IO.DriveInfo]::new($volume).AvailableFreeSpace; $required = $total + 64MB
            $result.storage = [ordered]@{ volume = $volume; available_bytes = $available; required_bytes = $required; deficit_bytes = [Math]::Max([long]0, [long]($required - $available)) }
            if ($available -lt $required) { Stop-Package ("Insufficient free storage on {0}: available {1} bytes, required {2} bytes (package contents plus a 64 MB margin), deficit {3} bytes. Nothing was extracted." -f $volume, $available, $required, ($required - $available)) }
            $null = [IO.Directory]::CreateDirectory($parent)
            # Short temporary name: Windows PowerShell 5.1 keeps the classic 260-character path limit.
            $staging = Join-Path $parent ('.x-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            foreach ($key in $entries.Keys) { if ((Join-Path $target ($entries[$key].FullName.Substring($prefix.Length))).Length -ge 248) { Stop-Package 'The destination path is too long for Windows PowerShell; choose a shorter -Destination. Nothing was extracted.' } }
            $null = New-Item -ItemType Directory -Path $staging
            $stagingFull = [IO.Path]::GetFullPath($staging).TrimEnd('\', '/') + '\'
            foreach ($key in $entries.Keys) {
                $entry = $entries[$key]
                $out = [IO.Path]::GetFullPath((Join-Path $staging ($entry.FullName.Substring($prefix.Length).Replace('/', '\'))))
                if (-not $out.StartsWith($stagingFull, [StringComparison]::OrdinalIgnoreCase)) { Stop-Package "Refused archive entry '$($entry.FullName)' leaving the extraction folder." }
                $null = [IO.Directory]::CreateDirectory((Split-Path $out -Parent))
                $in = $entry.Open(); $file = [IO.File]::Open($out, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $in.CopyTo($file) } finally { $file.Dispose(); $in.Dispose() }
            }
        } finally { $zip.Dispose() }
        $result.files_verified = Test-Folder $staging $manifest
        $result.signatures = @(Test-Identity $staging $manifest)
        if (Test-Path -LiteralPath $target) { Stop-Package "The target $target appeared during extraction; nothing was overwritten." }
        [IO.Directory]::Move($staging, $target); $staging = $null
        $result.status = 'verified'
    }
} catch {
    $result.status = 'refused'; $result.reason = $_.Exception.Message
} finally {
    if ($staging -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
Write-Host ("Package {0}: {1} {2}" -f $result.mode, $result.status, $result.reason)
foreach ($signature in @($result.signatures)) { Write-Host ("Authenticode {0}: {1}" -f $signature.file, $signature.status) }
Write-Host $result.authenticity
Write-Host ('AUTHLENS-PACKAGE: ' + ($result | ConvertTo-Json -Compress -Depth 5))
if ($result.status -eq 'verified') { exit 0 } else { exit 1 }
