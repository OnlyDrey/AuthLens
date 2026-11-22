# Pure helpers shared by the canonical Windows build and its focused tests.
function New-AuthLensBuildDirectory([string]$OutputRoot, [datetime]$Timestamp, [string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'A full Git SHA is required.' }
    $path = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ($Timestamp.ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ')+'-'+$Commit.Substring(0,7))
    # CreateDirectory alone permits reuse. A new directory and exclusive claim file prevent concurrent reuse.
    if (Test-Path -LiteralPath $path) { throw "Build directory already exists: $path" }
    $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop
    $claim = [IO.File]::Open((Join-Path $path '.build-claim'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $claim.Dispose()
    $path
}
function Assert-AuthLensBuildIdentity($Manifest, $Identity) {
    foreach ($field in 'product','version','source_sha','branch','build_timestamp_utc') {
        if ($Manifest.$field -cne $Identity.$field) { throw "Build identity mismatch: $field" }
    }
    if ($Manifest.source_dirty) { throw 'Dirty release cannot be packaged.' }
    if ($Manifest.executables.desktop -ne 'desktop/AuthLens.exe' -or $Manifest.executables.server -ne 'server/AuthLens.Api.exe') { throw 'Desktop/Server artifact isolation mismatch.' }
}
function Get-AuthLensBuildArtifacts([string]$Directory) {
    @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Where-Object { $_.Name -notin @('build-summary.json','.build-claim','build.log') } | Sort-Object FullName | ForEach-Object {
        [ordered]@{path=$_.FullName.Substring($Directory.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
