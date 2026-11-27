<#
.SYNOPSIS
  Verifies and extracts an AuthLens portable deployment package without overwriting anything. Windows PowerShell 5.1 and 7.
.DESCRIPTION
  Flat packages (WP32 amendment; package-manifest.json schema 2, layout 'flat'). The archive root holds AuthLens-<version>-Server-Setup.exe,
  AuthLens-<version>-Desktop-Setup.exe, Expand-AuthLensPackage.ps1, README.txt, installer-manifest.json, package-manifest.json, SHA256SUMS.txt
  and Tools\ (the installation, verification and recovery helpers with Tools\installer-tools.json). Extraction (default):
    1. Optional check of the ZIP against trusted build metadata: -ExpectedSha256 <hex> (from the build report), -ChecksumFile <file>, or
       <zip>.sha256 when it lies beside the ZIP. Without one the ZIP is reported as not checked externally (package_checksum: not_checked); the
       internal SHA256SUMS.txt then detects corruption, not a deliberately replaced package. Checksums never prove publisher authenticity.
    2. Every entry is validated before anything is written: relative, no drive, no '.' or '..', no backslash, no duplicates (case-insensitive),
       folders only below Tools/, and exactly the files SHA256SUMS.txt lists plus SHA256SUMS.txt itself.
    3. The target <Destination>\AuthLens-<version>-<build-id> must not exist (it is never overwritten). Files are written into a new sibling
       folder .x-<random>; every SHA-256 is checked against SHA256SUMS.txt, the release identity of package-manifest.json and
       installer-manifest.json must agree, both Setup programs must match installer-manifest.json and Tools\installer-tools.json its helpers;
       only then the folder is renamed into place. A failure removes only this run's temporary folder; an interrupted run leaves a .x-* folder
       that is never treated as a package and is reported by the next run.
  Original RC6 packages (schema 1, every entry below Installer/<version>/<build-id>/) are still verified and extracted to
  <Destination>\Installer\<version>\<build-id> with their package-manifest.json file list.
  -VerifyOnly -ExtractedDirectory <folder>: re-verifies an extracted folder (flat: any folder holding SHA256SUMS.txt, also one extracted with
  Windows Explorer; original RC6 packages: Installer\<version>\<build-id>). Exact file set, hashes and identity; a folder that merely exists is
  never treated as a complete extraction. Reports the Authenticode status of each Setup program. Last line: AUTHLENS-PACKAGE: <json>.
  Exit 0 verified, 1 refused or failed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Expand-AuthLensPackage.ps1 -Package C:\AuthLens\AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip -Destination C:\AuthLens
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\AuthLens\AuthLens-2.0.0-2026-11-25_2145-b10dd50\Expand-AuthLensPackage.ps1 -VerifyOnly -ExtractedDirectory C:\AuthLens\AuthLens-2.0.0-2026-11-25_2145-b10dd50
#>
[CmdletBinding()]
param(
    [string]$Package = '',
    [string]$Destination = 'C:\AuthLens',
    [string]$ChecksumFile = '',
    [string]$ExpectedSha256 = '',
    # The package file name to validate against (the packager verifies its own *.partial file under the final name).
    [string]$ArchiveName = '',
    [switch]$VerifyOnly,
    [string]$ExtractedDirectory = ''
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$versionPattern = '^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})(-(alpha|beta|rc)\.([1-9]\d{0,4}))?$'
$idPattern = '^\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(-\d{2})?$'
$namePattern = '^AuthLens-(?<version>.+)-(?<id>\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(?:-\d{2})?)(?:-pkg(?<revision>[2-9]|[1-9]\d))?\.zip$'
$flatRequired = @('package-manifest.json', 'installer-manifest.json', 'README.txt', 'Expand-AuthLensPackage.ps1', 'Tools/installer-tools.json')
$result = [ordered]@{ schema = 2; tool = 'Expand-AuthLensPackage'; mode = $(if ($VerifyOnly) { 'verify' } else { 'extract' }); status = 'refused'; reason = ''
    layout = ''; version = ''; build_id = ''; package_revision = 0; source_sha = ''; target = ''; package_checksum = 'not_checked'; files_verified = 0
    signatures = @(); leftover_extractions = @()
    authenticity = 'SHA-256 checksums prove integrity against the recorded digests only, not publisher authenticity.' }

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Stop-Package([string]$Reason) { throw [InvalidOperationException]::new($Reason) }
function Get-Stamp($Value) { if ($Value -is [datetime]) { $Value.ToUniversalTime().Ticks } else { [DateTime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal).Ticks } }
function Assert-RelativePath([string]$Path, [switch]$Flat) {
    if (-not $Path -or $Path.StartsWith('/') -or $Path.Contains('\') -or $Path.Contains(':') -or @($Path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) { Stop-Package "Refused path '$Path' (absolute, drive, empty or traversal path)." }
    if ($Flat -and $Path.Contains('/') -and -not $Path.StartsWith('Tools/', [StringComparison]::Ordinal)) { Stop-Package "Refused path '$Path': only Tools/ may hold folders." }
}
function Assert-Identity($Manifest, [string]$Version, [string]$Id) {
    if ($Manifest.product -cne 'AuthLens' -or $Manifest.version -cne $Version -or $Manifest.build_id -cne $Id -or [string]$Manifest.source_sha -cnotmatch '^[0-9a-f]{40}$') { Stop-Package 'package-manifest.json does not describe this package (product, version, build id or commit).' }
    if (([string]$Manifest.source_sha).Substring(0, 7) -cne ($Id -replace '-\d{2}$', '').Substring(16)) { Stop-Package 'The build id does not carry the recorded commit.' }
}
function Read-Manifest([string]$Text, [string]$Version, [string]$Id, [int]$Schema) {
    try { $manifest = $Text | ConvertFrom-Json } catch { Stop-Package 'package-manifest.json is not valid JSON.' }
    $fields = if ($Schema -eq 1) { @('schema', 'product', 'version', 'build_id', 'source_sha', 'build_timestamp_utc', 'files') } else { @('schema', 'layout', 'product', 'version', 'build_id', 'source_sha', 'build_timestamp_utc', 'package_revision') }
    foreach ($field in $fields) { if (-not $manifest.PSObject.Properties[$field]) { Stop-Package "package-manifest.json lacks $field." } }
    if ($manifest.schema -ne $Schema -or ($Schema -eq 2 -and $manifest.layout -cne 'flat')) { Stop-Package 'package-manifest.json has an unexpected schema or layout.' }
    if ($Version -eq '') { $Version = [string]$manifest.version; $Id = [string]$manifest.build_id }
    if ($Version -notmatch $versionPattern -or $Id -notmatch $idPattern) { Stop-Package 'package-manifest.json does not carry a canonical version and build id.' }
    Assert-Identity $manifest $Version $Id
    if ($Schema -eq 2 -and -not ([int]$manifest.package_revision -ge 1)) { Stop-Package 'package-manifest.json carries an invalid package revision.' }
    if ($Schema -eq 1) {
        $seen = @{}
        foreach ($file in @($manifest.files)) {
            $path = [string]$file.path
            if (-not $path -or $path -match '(^/|\\|:|(^|/)\.{1,2}(/|$))' -or $seen.ContainsKey($path.ToLowerInvariant()) -or [string]$file.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$file.size -lt 0) { Stop-Package "package-manifest.json lists an invalid or duplicate file '$path'." }
            $seen[$path.ToLowerInvariant()] = $true
        }
    }
    $manifest
}
# SHA256SUMS.txt: one '<sha256> *<relative/path>' line per payload file (forward slashes), never listing itself.
function Read-Sums([string]$Text) {
    $sums = [ordered]@{}
    foreach ($line in @($Text -split "`r?`n" | Where-Object { $_ -ne '' })) {
        if ($line -cnotmatch '^(?<sha>[0-9a-f]{64}) \*(?<path>.+)$') { Stop-Package "SHA256SUMS.txt has an invalid line: $line" }
        $path = $Matches['path']; $sha = $Matches['sha']
        Assert-RelativePath $path -Flat
        if ($path -ieq 'SHA256SUMS.txt' -or $sums.Contains($path.ToLowerInvariant())) { Stop-Package "SHA256SUMS.txt lists '$path' twice or lists itself." }
        $sums[$path.ToLowerInvariant()] = [pscustomobject]@{ path = $path; sha256 = $sha }
    }
    foreach ($required in $flatRequired) { if (-not $sums.Contains($required.ToLowerInvariant())) { Stop-Package "SHA256SUMS.txt does not list the required file $required." } }
    $sums
}
function Test-Identity([string]$Folder, $Manifest) {
    $installer = Join-Path $Folder 'installer-manifest.json'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { Stop-Package 'installer-manifest.json is missing.' }
    $metadata = Get-Content -LiteralPath $installer -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($metadata.product -cne 'AuthLens' -or $metadata.version -cne $Manifest.version -or $metadata.source_sha -cne $Manifest.source_sha -or (Get-Stamp $metadata.build_timestamp_utc) -ne (Get-Stamp $Manifest.build_timestamp_utc) -or $metadata.source_dirty) {
        Stop-Package 'installer-manifest.json and package-manifest.json name different releases.'
    }
    $setups = @($metadata.artifacts)
    if ($setups.Count -ne 2) { Stop-Package 'installer-manifest.json does not list exactly the Server and Desktop Setup programs.' }
    foreach ($entry in $setups) {
        $file = Join-Path $Folder ([string]$entry.path)
        if ([string]$entry.path -match '[\\/:]' -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Sha256 $file) -cne ([string]$entry.sha256).ToLowerInvariant()) { Stop-Package "Setup program $($entry.path) differs from installer-manifest.json." }
    }
    @(foreach ($entry in $setups) { [ordered]@{ file = [string]$entry.path; status = [string](Get-AuthenticodeSignature -LiteralPath (Join-Path $Folder ([string]$entry.path))).Status } })
}
function Get-Files([string]$Base) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Base -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-Package "Reparse point in the package folder: $($item.Name)." }
        if (-not $item.PSIsContainer) { $item.FullName.Substring($Base.Length + 1).Replace('\', '/') }
    }
}
function Test-LegacyFolder([string]$Folder, $Manifest) {
    $base = [IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $expected = @{ 'package-manifest.json' = $true }
    foreach ($file in @($Manifest.files)) { $expected[([string]$file.path).ToLowerInvariant()] = $true }
    foreach ($relative in @(Get-Files $base)) { if (-not $expected.ContainsKey($relative.ToLowerInvariant())) { Stop-Package "Unexpected file in the package folder: $relative." } }
    $count = 0
    foreach ($file in @($Manifest.files)) {
        $path = Join-Path $base (([string]$file.path).Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Package "Missing file: $($file.path)." }
        if ((Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Get-Sha256 $path) -cne [string]$file.sha256) { Stop-Package "File differs from package-manifest.json: $($file.path)." }
        $count++
    }
    $count
}
# Flat folder: exactly the SHA256SUMS.txt file set, every hash, and the Tools inventory the standalone helpers verify themselves.
function Test-FlatFolder([string]$Folder) {
    $base = [IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $sumsFile = Join-Path $base 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sumsFile -PathType Leaf)) { Stop-Package 'SHA256SUMS.txt is missing; this folder was not extracted from a flat AuthLens package.' }
    $sums = Read-Sums ([IO.File]::ReadAllText($sumsFile))
    foreach ($relative in @(Get-Files $base)) {
        if ($relative -ieq 'SHA256SUMS.txt') { continue }
        if (-not $sums.Contains($relative.ToLowerInvariant())) { Stop-Package "Unexpected file in the package folder: $relative." }
    }
    $count = 0
    foreach ($entry in $sums.Values) {
        $path = Join-Path $base ($entry.path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Package "Missing file: $($entry.path)." }
        if ((Get-Sha256 $path) -cne $entry.sha256) { Stop-Package "File differs from SHA256SUMS.txt: $($entry.path)." }
        $count++
    }
    $tools = Join-Path $base 'Tools'
    $proof = Get-Content -LiteralPath (Join-Path $tools 'installer-tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not @($proof.files).Count) { Stop-Package 'Tools\installer-tools.json lists no helpers.' }
    foreach ($helper in @($proof.files)) {
        $relative = [string]$helper.path; Assert-RelativePath $relative
        $path = Join-Path $tools ($relative.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Sha256 $path) -cne ([string]$helper.sha256).ToLowerInvariant()) { Stop-Package "Packaged helper Tools/$relative differs from Tools\installer-tools.json." }
    }
    $count
}
function Open-Text($Entry) { $reader = [IO.StreamReader]::new($Entry.Open()); try { $reader.ReadToEnd() } finally { $reader.Dispose() } }

$staging = $null
try {
    if ($VerifyOnly) {
        if (-not $ExtractedDirectory) { Stop-Package '-VerifyOnly needs -ExtractedDirectory <extracted package folder>.' }
        $folder = [IO.Path]::GetFullPath($ExtractedDirectory).TrimEnd('\', '/')
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { Stop-Package 'The extracted folder does not exist.' }
        $result.target = $folder
        if (Test-Path -LiteralPath (Join-Path $folder 'SHA256SUMS.txt') -PathType Leaf) {
            $result.layout = 'flat'
            if (-not (Test-Path -LiteralPath (Join-Path $folder 'package-manifest.json') -PathType Leaf)) { Stop-Package 'package-manifest.json is missing; this folder was not extracted from a verified package.' }
            $manifest = Read-Manifest (Get-Content -LiteralPath (Join-Path $folder 'package-manifest.json') -Raw -Encoding UTF8) '' '' 2
            $leaf = Split-Path $folder -Leaf
            if ($leaf -match '^AuthLens-(?<version>.+)-(?<id>\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(?:-\d{2})?)(?:-pkg\d{1,2})?$' -and ($Matches['version'] -cne $manifest.version -or $Matches['id'] -cne $manifest.build_id)) { Stop-Package "The folder name $leaf names another release than package-manifest.json." }
            $result.files_verified = Test-FlatFolder $folder
        } else {
            $result.layout = 'installer-tree'
            $id = Split-Path $folder -Leaf; $version = Split-Path (Split-Path $folder -Parent) -Leaf
            if ($id -notmatch $idPattern -or $version -notmatch $versionPattern -or (Split-Path (Split-Path (Split-Path $folder -Parent) -Parent) -Leaf) -ne 'Installer') { Stop-Package 'The folder holds neither SHA256SUMS.txt (flat package) nor is it Installer\<version>\<build-id> (original RC6 package).' }
            if (-not (Test-Path -LiteralPath (Join-Path $folder 'package-manifest.json') -PathType Leaf)) { Stop-Package 'package-manifest.json is missing; this folder was not extracted from a verified package.' }
            $manifest = Read-Manifest (Get-Content -LiteralPath (Join-Path $folder 'package-manifest.json') -Raw -Encoding UTF8) $version $id 1
            $result.files_verified = Test-LegacyFolder $folder $manifest
        }
        $result.version = $manifest.version; $result.build_id = $manifest.build_id; $result.source_sha = $manifest.source_sha
        if ($manifest.PSObject.Properties['package_revision']) { $result.package_revision = [int]$manifest.package_revision }
        $result.signatures = @(Test-Identity $folder $manifest)
        $result.status = 'verified'
    } else {
        if (-not $Package) { Stop-Package 'Select the package with -Package <AuthLens-<version>-<build-id>.zip>.' }
        $zipPath = [IO.Path]::GetFullPath($Package)
        if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { Stop-Package 'The package file does not exist.' }
        $name = if ($ArchiveName) { $ArchiveName } else { Split-Path $zipPath -Leaf }
        if ($name -notmatch $namePattern) { Stop-Package 'The package name is not AuthLens-<version>-<build-id>.zip (or -pkg<n>.zip).' }
        $version = $Matches['version']; $id = $Matches['id']; $revision = if ($Matches['revision']) { [int]$Matches['revision'] } else { 1 }
        if ($version -notmatch $versionPattern) { Stop-Package 'The package name does not carry a canonical AuthLens version.' }
        $result.version = $version; $result.build_id = $id; $result.package_revision = $revision
        # 1. Optional external integrity check against trusted build metadata.
        $actualSha = Get-Sha256 $zipPath
        if ($ExpectedSha256) {
            if ($ExpectedSha256.Trim().ToLowerInvariant() -cnotmatch '^[0-9a-f]{64}$') { Stop-Package '-ExpectedSha256 is not a SHA-256 value.' }
            if ($actualSha -cne $ExpectedSha256.Trim().ToLowerInvariant()) { Stop-Package 'The package SHA-256 differs from -ExpectedSha256.' }
            $result.package_checksum = 'verified_expected_sha256'
        } else {
            if (-not $ChecksumFile -and (Test-Path -LiteralPath ($zipPath + '.sha256') -PathType Leaf)) { $ChecksumFile = $zipPath + '.sha256' }
            if ($ChecksumFile) {
                if (-not (Test-Path -LiteralPath $ChecksumFile -PathType Leaf)) { Stop-Package 'The checksum file does not exist.' }
                $line = @(Get-Content -LiteralPath $ChecksumFile | Where-Object { $_.Trim() })
                if ($line.Count -ne 1 -or $line[0].Trim() -notmatch '^(?<sha>[0-9a-fA-F]{64}) [ *](?<file>.+)$' -or $Matches['file'] -cne $name) { Stop-Package 'The checksum file does not name exactly this package.' }
                if ($actualSha -cne $Matches['sha'].ToLowerInvariant()) { Stop-Package 'The package SHA-256 differs from its checksum file.' }
                $result.package_checksum = 'verified_checksum_file'
            }
        }
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $all = @($zip.Entries)
            $legacyPrefix = 'Installer/' + $version + '/' + $id + '/'
            $legacy = $all.Count -gt 0 -and @($all | Where-Object { $_.FullName.Replace('\', '/').StartsWith('Installer/', [StringComparison]::Ordinal) }).Count -eq $all.Count
            if ($legacy) { $prefix = $legacyPrefix; $parent = Join-Path (Join-Path $root 'Installer') $version; $target = Join-Path $parent $id; $result.layout = 'installer-tree' }
            else { $prefix = ''; $parent = $root; $target = Join-Path $root ('AuthLens-' + $version + '-' + $id); $result.layout = 'flat' }
            $result.target = $target
            if (Test-Path -LiteralPath $parent) { $result.leftover_extractions = @(Get-ChildItem -LiteralPath $parent -Directory -Force -Filter '.x-*' | ForEach-Object Name) }
            if (Test-Path -LiteralPath $target) { Stop-Package "The target $target exists and is never overwritten. Verify it with -VerifyOnly -ExtractedDirectory, or extract elsewhere." }
            # 2. Validate every entry before writing anything.
            $entries = @{}; $total = [long]0
            foreach ($entry in $all) {
                $full = $entry.FullName.Replace('\', '/')
                if (-not $full -or $full.StartsWith('/') -or $full.Contains(':') -or @($full.Split('/') | Where-Object { $_ -in @('.', '..') }).Count) { Stop-Package "Refused archive entry '$full' (absolute, drive or traversal path)." }
                if (-not $full.StartsWith($prefix, [StringComparison]::Ordinal)) { Stop-Package "Refused archive entry '$full' outside $prefix." }
                $relative = $full.Substring($prefix.Length)
                if ($full.EndsWith('/')) { if (-not $legacy -and $relative -ne 'Tools/' -and -not $relative.StartsWith('Tools/', [StringComparison]::Ordinal)) { Stop-Package "Refused folder entry '$full': only Tools/ may hold folders." }; continue }
                if (-not $legacy) { Assert-RelativePath $relative -Flat }
                if (-not $relative -or $entries.ContainsKey($relative.ToLowerInvariant())) { Stop-Package "Refused duplicate or empty archive entry '$full'." }
                $entries[$relative.ToLowerInvariant()] = $entry; $total += $entry.Length
            }
            if ($entries.Count -gt 20000 -or $total -gt 8GB) { Stop-Package 'The archive is larger than any AuthLens package.' }
            if (-not $entries.ContainsKey('package-manifest.json')) { Stop-Package 'package-manifest.json is missing from the archive.' }
            if ($legacy) {
                $manifest = Read-Manifest (Open-Text $entries['package-manifest.json']) $version $id 1
                $listed = @{ 'package-manifest.json' = $true }; foreach ($file in @($manifest.files)) { $listed[([string]$file.path).ToLowerInvariant()] = $true }
            } else {
                $manifest = Read-Manifest (Open-Text $entries['package-manifest.json']) $version $id 2
                if ([int]$manifest.package_revision -ne $revision) { Stop-Package 'The package file name and package-manifest.json carry different package revisions.' }
                if (-not $entries.ContainsKey('sha256sums.txt')) { Stop-Package 'SHA256SUMS.txt is missing from the archive.' }
                $listed = @{ 'sha256sums.txt' = $true }; foreach ($key in (Read-Sums (Open-Text $entries['sha256sums.txt'])).Keys) { $listed[$key] = $true }
            }
            foreach ($key in $entries.Keys) { if (-not $listed.ContainsKey($key)) { Stop-Package "Unexpected archive content: $key." } }
            foreach ($key in $listed.Keys) { if (-not $entries.ContainsKey($key)) { Stop-Package "The archive lacks $key." } }
            $result.source_sha = $manifest.source_sha
            # WP34: extraction needs the uncompressed contents once on the destination volume (the ZIP itself is already present) plus a margin.
            $volume = [IO.Path]::GetPathRoot($root)
            $available = [IO.DriveInfo]::new($volume).AvailableFreeSpace; $required = $total + 64MB
            $result.storage = [ordered]@{ volume = $volume; available_bytes = $available; required_bytes = $required; deficit_bytes = [Math]::Max([long]0, [long]($required - $available)) }
            if ($available -lt $required) { Stop-Package ("Insufficient free storage on {0}: available {1} bytes, required {2} bytes (package contents plus a 64 MB margin), deficit {3} bytes. Nothing was extracted." -f $volume, $available, $required, ($required - $available)) }
            foreach ($key in $entries.Keys) { if ((Join-Path $target ($entries[$key].FullName.Substring($prefix.Length))).Length -ge 248) { Stop-Package 'The destination path is too long for Windows PowerShell; choose a shorter -Destination. Nothing was extracted.' } }
            # 3. Extract into a new private sibling folder (short name: Windows PowerShell 5.1 keeps the 260-character limit), verify, then rename.
            $null = [IO.Directory]::CreateDirectory($parent)
            $staging = Join-Path $parent ('.x-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
        $result.files_verified = if ($legacy) { Test-LegacyFolder $staging $manifest } else { Test-FlatFolder $staging }
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
if ($result.status -eq 'verified') { Write-Host ("Layout {0}; release AuthLens {1} build {2}; folder {3}" -f $result.layout, $result.version, $result.build_id, $result.target) }
if ($result.mode -eq 'extract' -and $result.package_checksum -eq 'not_checked') { Write-Host 'The ZIP was not checked against external build metadata (-ExpectedSha256 or a .sha256 file); SHA256SUMS.txt proves internal consistency only.' }
foreach ($signature in @($result.signatures)) { Write-Host ("Authenticode {0}: {1}" -f $signature.file, $signature.status) }
Write-Host $result.authenticity
Write-Host ('AUTHLENS-PACKAGE: ' + ($result | ConvertTo-Json -Compress -Depth 5))
if ($result.status -eq 'verified') { exit 0 } else { exit 1 }
