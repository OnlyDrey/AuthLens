# Pure helpers shared by the canonical Windows build and its focused tests.
function Invoke-AuthLensBuildProcess([string]$Executable, [string[]]$Arguments) {
    # Out-Host is intentional: direct native console output is otherwise absent from PS 5.1 transcripts.
    $saved=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $Executable @Arguments 2>&1 | Out-Host
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$saved }
    $code
}
function New-AuthLensBuildDirectory([string]$OutputRoot, [datetime]$Timestamp, [string]$Commit, [string]$Version) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'A full Git SHA is required.' }
    if ($Version -notmatch '^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})(-(alpha|beta|rc)\.([1-9]\d{0,4}))?$') { throw 'A canonical AuthLens product version is required.' }
    $root=[IO.Path]::GetFullPath($OutputRoot)
    $name='AuthLens-'+$Version+'-'+$Timestamp.ToUniversalTime().ToString('yyyy-MM-dd_HHmm',[Globalization.CultureInfo]::InvariantCulture)+'-'+$Commit.Substring(0,7)
    for($attempt=1; ;$attempt++){
        $suffix=if($attempt -eq 1){''}else{'-'+$attempt.ToString('00',[Globalization.CultureInfo]::InvariantCulture)}
        $path=Join-Path $root ($name+$suffix)
        if(Test-Path -LiteralPath $path){continue}
        # New-Item without -Force refuses an existing directory even if another process wins
        # after Test-Path. Only that collision advances the suffix; all other failures propagate.
        try{$null=New-Item -ItemType Directory -Path $path -ErrorAction Stop}
        catch{
            if($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ResourceExists -and (Test-Path -LiteralPath $path)){continue}
            throw
        }
        $claim=[IO.File]::Open((Join-Path $path '.build-claim'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $claim.Dispose()
        return $path
    }
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
