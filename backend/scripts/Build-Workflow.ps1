# Pure helpers shared by the canonical Windows build and its focused tests.
# The packaging tooling (Expand-AuthLensPackage.ps1, package-README.txt) is taken from the folder this file was loaded from.
$script:AuthLensToolingRoot=$PSScriptRoot
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
$script:AuthLensVersionPattern='^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})(-(alpha|beta|rc)\.([1-9]\d{0,4}))?$'
# WP32 build identifier: <UTC yyyy-MM-dd_HHmm>-<sha7>, without product name or version (the version is its own directory level). Generated once
# per build; a collision suffix -02, -03 ... is added by New-AuthLensBuildLayout. Manifests keep the full SHA and the full-precision timestamp.
$script:AuthLensBuildIdPattern='^\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(-\d{2})?$'
function Get-AuthLensBuildId([datetime]$Timestamp, [string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'A full Git SHA is required.' }
    $Timestamp.ToUniversalTime().ToString('yyyy-MM-dd_HHmm',[Globalization.CultureInfo]::InvariantCulture)+'-'+$Commit.Substring(0,7)
}
function Assert-AuthLensVersion([string]$Version) { if ($Version -notmatch $script:AuthLensVersionPattern) { throw 'A canonical AuthLens product version is required.' } }
# Legacy (RC5 and earlier) nested run directory <root>\AuthLens-<version>-<UTC yyyy-MM-dd_HHmm>-<sha7> with build\ and installer\ inside. build.ps1
# no longer creates it; it stays for the compatibility tests and explicit diagnostic callers. New builds use New-AuthLensBuildLayout.
function New-AuthLensBuildDirectory([string]$OutputRoot, [datetime]$Timestamp, [string]$Commit, [string]$Version) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'A full Git SHA is required.' }
    Assert-AuthLensVersion $Version
    $name='AuthLens-'+$Version+'-'+(Get-AuthLensBuildId $Timestamp $Commit)
    $root=[IO.Path]::GetFullPath($OutputRoot)
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

# ---- WP32 artifact layout (BUILD-001 to BUILD-010)
# <root>\Build\<version>\<build-id>\       the verified release itself (server\, desktop\, symbols\, build-manifest.json, SHA256SUMS, README.txt,
#                                          Service-Manager.ps1) plus the build record build-summary.json, build.log, .build-claim, branding-verification.json
# <root>\Installer\<version>\<build-id>\   AuthLens-<version>-Server-Setup.exe, AuthLens-<version>-Desktop-Setup.exe, installer-manifest.json,
#                                          installers-SHA256SUMS, installer-tools-<unique id>\ (deployment, verification and recovery tooling), DEPLOY.txt,
#                                          Expand-AuthLensPackage.ps1
# <root>\Acceptance\<version>\<build-id>\<run>\   evidence of each acceptance run (several runs per build)
# <root>\Packages\AuthLens-<version>-<build-id>.zip and .zip.sha256   optional flat portable package (build.ps1 -ZipPackage or New-AuthLensPackage.ps1);
#                                          later package revisions of the same build: AuthLens-<version>-<build-id>-pkg<N>.zip
# The build id is generated once and reused by the installer, acceptance and package steps. Collision handling (documented): an id is used only
# when none of Build\<version>\<id>, Installer\<version>\<id>, Acceptance\<version>\<id>, Packages\AuthLens-<version>-<id>.zip(.sha256) or a legacy
# run directory AuthLens-<version>-<id> exists; otherwise -02, -03 ... is appended. The Build directory is claimed atomically (New-Item without
# -Force plus an exclusive .build-claim); an Installer directory that appears meanwhile stops the build. Nothing is reused, overwritten or moved.
$script:AuthLensBuildRecordFiles=@('build-summary.json','build.log','.build-claim','branding-verification.json')
$script:AuthLensPackagePattern='^AuthLens-(?<version>.+)-(?<id>\d{4}-\d{2}-\d{2}_\d{4}-[0-9a-f]{7}(?:-\d{2})?)(?:-pkg(?<revision>[2-9]|[1-9]\d))?\.zip$'
function New-AuthLensCandidateRecord([string]$Root, [string]$Version, [string]$Id, [ValidateSet('category','legacy')][string]$Layout, [string]$LegacyName='') {
    $root=$Root.TrimEnd('\','/')
    if($Layout -eq 'category'){
        $record=Join-Path (Join-Path (Join-Path $root 'Build') $Version) $Id
        $installer=Join-Path (Join-Path (Join-Path $root 'Installer') $Version) $Id
        $build=$record; $acceptance=Join-Path (Join-Path (Join-Path $root 'Acceptance') $Version) $Id
    } else {
        $record=Join-Path $root $LegacyName; $build=Join-Path $record 'build'; $installer=Join-Path $record 'installer'
        $acceptance=Join-Path (Join-Path $root 'acceptance') $LegacyName
    }
    $package='AuthLens-'+$Version+'-'+$Id+'.zip'
    [pscustomobject]@{Id=$Id;Version=$Version;Layout=$Layout;LegacyName=$LegacyName;OutputRoot=$root;RecordDirectory=$record;BuildDirectory=$build
        ReleaseDirectory=$(if($Layout -eq 'category'){$build}else{$null});InstallerDirectory=$installer;AcceptanceDirectory=$acceptance
        SummaryFile=(Join-Path $record 'build-summary.json');PackageFile=(Join-Path (Join-Path $root 'Packages') $package)
        PackageChecksumFile=(Join-Path (Join-Path $root 'Packages') ($package+'.sha256'))}
}
function Assert-AuthLensArtifactContainer([string]$Path) {
    if(Test-Path -LiteralPath $Path){
        $item=Get-Item -LiteralPath $Path -Force
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Artifact container $Path is not an ordinary directory; nothing was created."}
    }
}
function New-AuthLensBuildLayout([string]$OutputRoot, [datetime]$Timestamp, [string]$Commit, [string]$Version) {
    Assert-AuthLensVersion $Version
    $name=Get-AuthLensBuildId $Timestamp $Commit
    $root=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
    $containers=@((Join-Path $root 'Build'),(Join-Path (Join-Path $root 'Build') $Version),(Join-Path $root 'Installer'),(Join-Path (Join-Path $root 'Installer') $Version))
    foreach($container in $containers){Assert-AuthLensArtifactContainer $container}
    foreach($container in $containers){$null=[IO.Directory]::CreateDirectory($container)}
    for($attempt=1; ;$attempt++){
        if($attempt -gt 99){throw 'No free build id within 99 collision suffixes; nothing was created.'}
        $suffix=if($attempt -eq 1){''}else{'-'+$attempt.ToString('00',[Globalization.CultureInfo]::InvariantCulture)}
        $candidate=New-AuthLensCandidateRecord $root $Version ($name+$suffix) 'category'
        $occupied=@($candidate.BuildDirectory,$candidate.InstallerDirectory,$candidate.AcceptanceDirectory,$candidate.PackageFile,$candidate.PackageChecksumFile,(Join-Path $root ('AuthLens-'+$Version+'-'+$candidate.Id)))
        if(@($occupied|Where-Object{Test-Path -LiteralPath $_}).Count){continue}
        # New-Item without -Force refuses an existing directory even if another process wins after Test-Path; only that collision advances the suffix.
        try{$null=New-Item -ItemType Directory -Path $candidate.BuildDirectory -ErrorAction Stop}
        catch{
            if($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ResourceExists -and (Test-Path -LiteralPath $candidate.BuildDirectory)){continue}
            throw
        }
        $claim=[IO.File]::Open((Join-Path $candidate.BuildDirectory '.build-claim'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $claim.Dispose()
        try{$null=New-Item -ItemType Directory -Path $candidate.InstallerDirectory -ErrorAction Stop}
        catch{throw "Installer directory $($candidate.InstallerDirectory) appeared while build $($candidate.Id) was claimed; it is never reused or overwritten. The claimed build directory is retained; start a new build."}
        return $candidate
    }
}
function Read-AuthLensSummary([string]$SummaryFile) {
    try{Get-Content -LiteralPath $SummaryFile -Raw -Encoding UTF8 | ConvertFrom-Json}catch{throw "Build summary $SummaryFile is unreadable."}
}
function Get-AuthLensLegacyRelease([string]$BuildDirectory) {
    $found=@(Get-ChildItem -LiteralPath $BuildDirectory -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'build-manifest.json') -PathType Leaf })
    if($found.Count -eq 1){$found[0].FullName}else{$null}
}
function New-AuthLensLegacyRecord([string]$RunDirectory) {
    $full=[IO.Path]::GetFullPath($RunDirectory).TrimEnd('\','/')
    $summary=Read-AuthLensSummary (Join-Path $full 'build-summary.json')
    $leaf=Split-Path $full -Leaf
    $version=if($summary.PSObject.Properties['identity'] -and $summary.identity){[string]$summary.identity.version}else{''}
    $id=if($version -and $leaf.StartsWith('AuthLens-'+$version+'-')){$leaf.Substring(('AuthLens-'+$version+'-').Length)}else{$leaf}
    $record=New-AuthLensCandidateRecord (Split-Path $full -Parent) $version $id 'legacy' $leaf
    $record.ReleaseDirectory=Get-AuthLensLegacyRelease $record.BuildDirectory
    $record
}
# Resolves a build candidate in place, read-only: the WP32 layout from Build\<version>\<id>, Installer\<version>\<id> or
# Acceptance\<version>\<id>[\<run>] (the Build summary's layout, version and id must agree), or a legacy run directory <root>\<name> with build\
# and installer\ inside (RC5 and earlier; never moved, renamed or migrated). With -OutputRoot, '<version>\<id>' or a legacy run name is accepted.
function Resolve-AuthLensCandidate([string]$Path, [string]$OutputRoot='') {
    if(-not $Path){throw 'A build candidate path or id is required.'}
    $found=@()
    if(-not [IO.Path]::IsPathRooted($Path)){
        if(-not $OutputRoot){throw "Build candidate '$Path' is not an absolute path; pass -OutputRoot with '<version>\<build-id>'."}
        $root=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
        $parts=@($Path.Replace('/','\').Split('\')|Where-Object{$_})
        if($parts.Count -eq 2){$Path=Join-Path (Join-Path (Join-Path $root 'Build') $parts[0]) $parts[1]}
        elseif($parts.Count -eq 1 -and $parts[0] -match '\AAuthLens-[A-Za-z0-9._-]+\z'){$Path=Join-Path $root $parts[0]}
        else{throw "Build candidate '$Path' is neither '<version>\<build-id>' nor a legacy run directory name."}
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $own=Join-Path $full 'build-summary.json'
    if((Test-Path -LiteralPath $own -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $full 'build') -PathType Container) -and (Test-Path -LiteralPath (Join-Path $full 'installer') -PathType Container)){
        $summary=Read-AuthLensSummary $own
        if(-not ($summary.PSObject.Properties['layout'] -and $summary.layout -ceq 'category')){$found+=New-AuthLensLegacyRecord $full}
    }
    # Walk up at most two levels to find <root>\<Category>\<version>\<id> (an acceptance run directory sits one level below its id).
    $probe=$full
    for($level=0;$level -lt 2 -and $probe;$level++){
        $id=Split-Path $probe -Leaf; $versionDir=Split-Path $probe -Parent
        if($versionDir){
            $version=Split-Path $versionDir -Leaf; $categoryDir=Split-Path $versionDir -Parent
            if($categoryDir -and $id -match $script:AuthLensBuildIdPattern -and $version -match $script:AuthLensVersionPattern -and (Split-Path $categoryDir -Leaf) -in @('Build','Installer','Acceptance') -and ($level -eq 0 -or (Split-Path $categoryDir -Leaf) -eq 'Acceptance')){
                $candidate=New-AuthLensCandidateRecord (Split-Path $categoryDir -Parent) $version $id 'category'
                if(Test-Path -LiteralPath $candidate.SummaryFile -PathType Leaf){
                    $summary=Read-AuthLensSummary $candidate.SummaryFile
                    if($summary.PSObject.Properties['layout'] -and $summary.layout -ceq 'category' -and $summary.id -ceq $id -and $summary.version -ceq $version){$found+=$candidate}
                }
                break
            }
        }
        $probe=Split-Path $probe -Parent
    }
    if(-not $found.Count -and (Split-Path (Split-Path $full -Parent) -Leaf) -eq 'acceptance'){
        $legacy=Join-Path (Split-Path (Split-Path $full -Parent) -Parent) (Split-Path $full -Leaf)
        if((Test-Path -LiteralPath (Join-Path $legacy 'build-summary.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $legacy 'build') -PathType Container)){$found+=New-AuthLensLegacyRecord $legacy}
    }
    if($found.Count -eq 0){throw "No AuthLens build candidate with build-summary.json was found for '$Path' (Build\<version>\<build-id> or a legacy run directory)."}
    if($found.Count -gt 1){throw "Build candidate '$Path' is ambiguous; select the directory explicitly. Nothing was changed."}
    $found[0]
}
# The installed release name (releases\<name>, app\setup\<name>): unchanged convention AuthLens-<version>-<yyyyMMdd-HHmmss>-<sha7>-<platform>,
# derived from the manifest when the release directory is a WP32 Build\<version>\<build-id> folder. Deploy.psm1 Get-ALReleaseName is the same rule.
function Get-AuthLensReleaseName([string]$ReleaseDirectory, $Manifest=$null) {
    $leaf=Split-Path ([IO.Path]::GetFullPath($ReleaseDirectory).TrimEnd('\','/')) -Leaf
    if($leaf -notmatch $script:AuthLensBuildIdPattern){return $leaf}
    if(-not $Manifest){$Manifest=Get-Content -LiteralPath (Join-Path $ReleaseDirectory 'build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json}
    $built=ConvertTo-AuthLensUtc $Manifest.build_timestamp_utc
    'AuthLens-{0}-{1}-{2}-{3}' -f $Manifest.version,$built.ToString('yyyyMMdd-HHmmss',[Globalization.CultureInfo]::InvariantCulture),([string]$Manifest.source_sha).Substring(0,7),$Manifest.target_platform
}
function ConvertTo-AuthLensUtc($Value) { if($Value -is [datetime]){$Value.ToUniversalTime()}else{[DateTime]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)} }
# Setup file names: WP32 AuthLens-<version>-Server-Setup.exe / -Desktop-Setup.exe; legacy candidates keep AuthLens-Server-<version>-Setup.exe and
# AuthLens-<version>-Setup.exe.
function Get-AuthLensSetupNames($Candidate, [string]$Version) {
    if($Candidate.Layout -eq 'category'){[pscustomobject]@{server="AuthLens-$Version-Server-Setup.exe";desktop="AuthLens-$Version-Desktop-Setup.exe"}}
    else{[pscustomobject]@{server="AuthLens-Server-$Version-Setup.exe";desktop="AuthLens-$Version-Setup.exe"}}
}
# Maps a summary artifact path (build/<relative> or installer/<relative>, identical in both layouts) to its file.
function Resolve-AuthLensCandidateArtifact($Candidate, [string]$Relative) {
    $relative=$Relative.Replace('\','/')
    $parts=@($relative.Split('/'))
    if($parts.Count -lt 2 -or $relative -match '[:*?"<>|]' -or @($parts|Where-Object{$_ -in @('','.','..')}).Count){throw "Invalid candidate artifact path '$Relative'."}
    $base=switch($parts[0]){'build'{$Candidate.BuildDirectory}'installer'{$Candidate.InstallerDirectory}default{$null}}
    if(-not $base){throw "Candidate artifact path '$Relative' is outside build/ and installer/."}
    Join-Path $base (($parts[1..($parts.Count-1)]) -join [IO.Path]::DirectorySeparatorChar)
}
# Summary artifacts with the same logical paths in both layouts: build/... and installer/... (mutable logs and the claim are excluded).
function Get-AuthLensCandidateArtifacts($Candidate) {
    @(foreach($pair in @(@('build',$Candidate.BuildDirectory),@('installer',$Candidate.InstallerDirectory))){
        if(-not (Test-Path -LiteralPath $pair[1] -PathType Container)){continue}
        $base=[IO.Path]::GetFullPath($pair[1]).TrimEnd('\','/')
        Get-ChildItem -LiteralPath $base -Recurse -File -Force | Where-Object { $_.Name -notin @('build-summary.json','.build-claim','build.log') } | Sort-Object FullName | ForEach-Object {
            [ordered]@{path=$pair[0]+'/'+$_.FullName.Substring($base.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
    })
}

# ---- BUILD-009/010 portable deployment package (transport artifact, never a new build)
$script:AuthLensPackagedHelpers=@('Install-AuthLens.ps1','verify-release.ps1','deploy/AuthLens.Deploy.psm1','deploy/Deploy-AuthLens.ps1','deploy/AuthLens.Paths.ps1','deploy/AuthLens.Acl.ps1','deploy/AuthLens.Installer.ps1','recovery/New-AuthLensRecoveryBundle.ps1','recovery/Test-AuthLensRestoreRehearsal.ps1','acceptance/AuthLens.Acceptance.psm1')
function Get-AuthLensSha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
# Verifies an existing WP32 candidate for packaging without changing it: passed summary, identity of release/installer manifests, every
# Installer\<version>\<build-id> file bound by size and hash to the build summary, both Setup programs, the packaged tooling inventory (with the
# QA-028 recovery tooling), DEPLOY.txt and Expand-AuthLensPackage.ps1. Refuses legacy layouts, incomplete, modified or inconsistent candidates.
function Assert-AuthLensPackageSource($Candidate) {
    if($Candidate.Layout -ne 'category'){throw 'Only WP32 candidates (Build\<version>\<build-id>, RC6 and later) can be packaged; legacy run directories lack the packaged extraction tooling. Nothing was created.'}
    $summary=Read-AuthLensSummary $Candidate.SummaryFile
    if($summary.status -cne 'passed' -or $summary.layout -cne 'category' -or $summary.id -cne $Candidate.Id -or $summary.version -cne $Candidate.Version){throw 'The build summary is not a passed WP32 build of this version and build id.'}
    foreach($check in 'release','installers','secrets','branding'){if(-not ($summary.verification.$check -is [bool] -and $summary.verification.$check)){throw "Build verification '$check' did not pass; the candidate is not packaged."}}
    $identity=$summary.identity
    if($identity.version -cne $Candidate.Version -or (Get-AuthLensBuildId (ConvertTo-AuthLensUtc $identity.build_timestamp_utc) ([string]$identity.source_sha)) -cne ($Candidate.Id -replace '-\d{2}$','')){throw 'The build id does not follow from the recorded build timestamp and commit.'}
    $release=Get-Content -LiteralPath (Join-Path $Candidate.ReleaseDirectory 'build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AuthLensBuildIdentity $release $identity
    if(-not (Test-Path -LiteralPath $Candidate.InstallerDirectory -PathType Container)){throw 'The installer directory is missing; installers are never regenerated by packaging.'}
    $metadata=Get-Content -LiteralPath (Join-Path $Candidate.InstallerDirectory 'installer-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AuthLensBuildIdentity $metadata $identity
    $names=Get-AuthLensSetupNames $Candidate $Candidate.Version
    if((@($metadata.artifacts.path|Sort-Object) -join '|') -cne ((@($names.server,$names.desktop)|Sort-Object) -join '|')){throw 'The installer manifest does not list exactly the Server and Desktop Setup programs.'}
    foreach($entry in $metadata.artifacts){$file=Join-Path $Candidate.InstallerDirectory $entry.path;if(-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-AuthLensSha256 $file) -cne ([string]$entry.sha256).ToLowerInvariant()){throw "Setup program $($entry.path) is missing or differs from installer-manifest.json."}}
    $bound=@{}; foreach($entry in @($summary.artifacts)){$path=[string]$entry.path;if($path.StartsWith('installer/',[StringComparison]::Ordinal)){$bound[$path.Substring(10)]=$entry}}
    $base=[IO.Path]::GetFullPath($Candidate.InstallerDirectory).TrimEnd('\','/')
    $files=@(Get-ChildItem -LiteralPath $base -Recurse -Force | Where-Object { -not $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
    $inventory=foreach($file in $files){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'The installer directory contains a reparse point; it is not packaged.'}
        $relative=$file.FullName.Substring($base.Length+1).Replace('\','/')
        if(-not $bound.ContainsKey($relative)){throw "Installer file $relative is not bound to the build summary (added after the build)."}
        $hash=Get-AuthLensSha256 $file.FullName
        if([long]$bound[$relative].size -ne $file.Length -or $hash -cne ([string]$bound[$relative].sha256).ToLowerInvariant()){throw "Installer file $relative differs from the build summary."}
        [ordered]@{path=$relative;size=$file.Length;sha256=$hash}
    }
    foreach($relative in $bound.Keys){if(-not (Test-Path -LiteralPath (Join-Path $base $relative) -PathType Leaf)){throw "Installer file $relative recorded by the build summary is missing."}}
    foreach($required in 'DEPLOY.txt','Expand-AuthLensPackage.ps1','installer-manifest.json','installers-SHA256SUMS'){if(-not (Test-Path -LiteralPath (Join-Path $base $required) -PathType Leaf)){throw "Standalone dependency $required is missing."}}
    $tools=@(Get-ChildItem -LiteralPath $base -Directory -Filter 'installer-tools-*')
    if($tools.Count -ne 1){throw 'Exactly one packaged installer-tools directory is required.'}
    $proof=Get-Content -LiteralPath (Join-Path $tools[0].FullName 'installer-tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if((@($proof.files.path|Sort-Object) -join '|') -cne (@($script:AuthLensPackagedHelpers|Sort-Object) -join '|')){throw 'The packaged tooling inventory lacks the installation, verification or recovery helpers.'}
    foreach($entry in $proof.files){if((Get-AuthLensSha256 (Join-Path $tools[0].FullName $entry.path)) -cne ([string]$entry.sha256).ToLowerInvariant()){throw "Packaged helper $($entry.path) differs from installer-tools.json."}}
    $signatures=foreach($name in @($names.server,$names.desktop)){[ordered]@{file=$name;status=[string](Get-AuthenticodeSignature -LiteralPath (Join-Path $base $name)).Status}}
    [pscustomobject]@{summary=$summary;identity=$identity;files=@($inventory|Sort-Object {$_.path});signatures=@($signatures);names=$names}
}
# Package file names: revision 1 is Packages\AuthLens-<version>-<build-id>.zip, a later revision of the same build (new packaging only, identical
# installers) Packages\AuthLens-<version>-<build-id>-pkg<N>.zip; each with its .zip.sha256 for the build metadata. The revision is package metadata,
# never part of the build identity.
function Get-AuthLensPackagePaths($Candidate, [int]$Revision=1) {
    if($Revision -lt 1 -or $Revision -gt 99){throw 'The package revision must be between 1 and 99.'}
    $name='AuthLens-'+$Candidate.Version+'-'+$Candidate.Id+$(if($Revision -gt 1){'-pkg'+$Revision}else{''})+'.zip'
    $file=Join-Path (Split-Path $Candidate.PackageFile -Parent) $name
    [pscustomobject]@{Name=$name;File=$file;ChecksumFile=$file+'.sha256';Revision=$Revision}
}
function Get-AuthLensToolingCommit {
    $commit='unknown';$dirty=$null
    try{
        $git=Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $head=& $git.Source -C $script:AuthLensToolingRoot rev-parse HEAD 2>$null
        if($LASTEXITCODE -eq 0 -and [string]$head -match '^[0-9a-f]{40}$'){$commit=[string]$head
            $status=@(& $git.Source -C $script:AuthLensToolingRoot status --porcelain -- 'Expand-AuthLensPackage.ps1' 'package-README.txt' 'Build-Workflow.ps1' 2>$null)
            $dirty=[bool]($status.Count)}
    }catch{}
    [pscustomobject]@{commit=$commit;dirty=$dirty}
}
# Creates the flat portable package (WP32 amendment) from a verified candidate without rebuilding anything. Archive root: both Setup programs and
# installer-manifest.json (the verified Installer directory, hashes unchanged), Expand-AuthLensPackage.ps1 and README.txt (from this packaging
# tooling, because earlier Installer directories carry an extraction script that only knows the nested layout), package-manifest.json (package
# identity and revision) and SHA256SUMS.txt (every other entry); Tools\ holds the packaged helpers with installer-tools.json. DEPLOY.txt and
# installers-SHA256SUMS are superseded by README.txt and SHA256SUMS.txt and not packaged. Written as *.partial-<guid>, verified by an independent
# extraction with the packaging tooling's Expand-AuthLensPackage.ps1 into a private temporary folder, and only then renamed; the checksum file is
# renamed last. Existing packages are never overwritten; a failure removes only this run's partial files and never touches Build or Installer.
function New-AuthLensPackage($Candidate, [string]$TemporaryRoot='', [int]$Revision=1) {
    $source=Assert-AuthLensPackageSource $Candidate
    $target=Get-AuthLensPackagePaths $Candidate $Revision
    $packages=Split-Path $target.File -Parent
    foreach($existing in $target.File,$target.ChecksumFile){if(Test-Path -LiteralPath $existing){throw "$existing exists; packages are never overwritten. Choose another -PackageRevision. Nothing was created."}}
    $expandSource=Join-Path $script:AuthLensToolingRoot 'Expand-AuthLensPackage.ps1'
    $readmeSource=Join-Path $script:AuthLensToolingRoot 'package-README.txt'
    foreach($tool in $expandSource,$readmeSource){if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){throw "Packaging tooling $tool is missing."}}
    Assert-AuthLensArtifactContainer $packages
    $installerBase=[IO.Path]::GetFullPath($Candidate.InstallerDirectory).TrimEnd('\','/')
    $toolsDir=@(Get-ChildItem -LiteralPath $installerBase -Directory -Filter 'installer-tools-*')[0]
    $toolsPrefix=$toolsDir.Name+'/'
    # Payload: archive path -> source file (verified Installer files keep their bytes) or generated text.
    $payload=[Collections.Generic.List[object]]::new()
    foreach($name in @($source.names.server,$source.names.desktop,'installer-manifest.json')){$payload.Add([pscustomobject]@{path=$name;file=(Join-Path $installerBase $name);text=$null;sha256=($source.files|Where-Object{$_.path -ceq $name}).sha256})}
    foreach($file in @($source.files|Where-Object{$_.path.StartsWith($toolsPrefix,[StringComparison]::Ordinal)})){
        $payload.Add([pscustomobject]@{path='Tools/'+$file.path.Substring($toolsPrefix.Length);file=(Join-Path $installerBase ($file.path.Replace('/','\')));text=$null;sha256=$file.sha256})
    }
    $payload.Add([pscustomobject]@{path='Expand-AuthLensPackage.ps1';file=$expandSource;text=$null;sha256=(Get-AuthLensSha256 $expandSource)})
    $readme=[IO.File]::ReadAllText($readmeSource).Replace('{{VERSION}}',$Candidate.Version).Replace('{{BUILD_ID}}',$Candidate.Id).Replace('{{SHA}}',[string]$source.identity.source_sha).Replace('{{REVISION}}',[string]$Revision)
    $payload.Add([pscustomobject]@{path='README.txt';file=$null;text=$readme;sha256=$null})
    $tooling=Get-AuthLensToolingCommit
    $manifest=[ordered]@{schema=2;layout='flat';kind='AuthLens portable deployment package';product='AuthLens';version=$Candidate.Version;build_id=$Candidate.Id
        source_sha=$source.identity.source_sha;branch=$source.identity.branch;build_timestamp_utc=$source.identity.build_timestamp_utc;package=$target.Name
        release_directory=('AuthLens-'+$Candidate.Version+'-'+$Candidate.Id);package_revision=$Revision
        packaging=[ordered]@{tool='New-AuthLensPackage';tooling_commit=$tooling.commit;tooling_dirty=$tooling.dirty;created_utc=[DateTime]::UtcNow.ToString('o');expand_sha256=(Get-AuthLensSha256 $expandSource)}
        signatures=@($source.signatures)
        authenticity='SHA256SUMS.txt proves the files match each other''s recorded digests; only the ZIP SHA-256 from trusted build metadata detects a replaced package, and no checksum authenticates the publisher. Authenticode status is reported per Setup program.'}
    $payload.Add([pscustomobject]@{path='package-manifest.json';file=$null;text=($manifest|ConvertTo-Json -Depth 6);sha256=$null})
    $utf8=[Text.UTF8Encoding]::new($false)
    foreach($item in $payload){if($null -ne $item.text){$item.sha256=(([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($item.text)))).Replace('-','')).ToLowerInvariant()}}
    $sums=(@($payload|Sort-Object {$_.path}|ForEach-Object{$_.sha256+' *'+$_.path}) -join "`n")+"`n"
    $null=[IO.Directory]::CreateDirectory($packages)
    $token=[guid]::NewGuid().ToString('N')
    $partial=$target.File+'.partial-'+$token; $partialSum=$target.ChecksumFile+'.partial-'+$token
    $work=$null
    try{
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $stream=[IO.File]::Open($partial,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
            try{
                foreach($item in @($payload|Sort-Object {$_.path})+@([pscustomobject]@{path='SHA256SUMS.txt';file=$null;text=$sums})){
                    $entry=$zip.CreateEntry($item.path,[IO.Compression.CompressionLevel]::Optimal)
                    $out=$entry.Open()
                    try{
                        if($null -ne $item.text){$bytes=$utf8.GetBytes($item.text);$out.Write($bytes,0,$bytes.Length)}
                        else{$in=[IO.File]::OpenRead($item.file);try{$in.CopyTo($out)}finally{$in.Dispose()}}
                    }finally{$out.Dispose()}
                }
            }finally{$zip.Dispose()}
        }finally{$stream.Dispose()}
        # The verified sources must not have changed while they were read.
        foreach($item in $payload){if($item.file -and (Get-AuthLensSha256 $item.file) -cne $item.sha256){throw "$($item.path) changed while it was packaged."}}
        $sha=Get-AuthLensSha256 $partial
        [IO.File]::WriteAllText($partialSum,($sha+' *'+$target.Name+"`n"),[Text.Encoding]::ASCII)
        # Independent extraction and verification with the packaged operator script, into a new private temporary folder.
        if(-not $TemporaryRoot){$TemporaryRoot=[IO.Path]::GetTempPath()}
        $work=Join-Path $TemporaryRoot ('alpk-'+$token.Substring(0,8))
        $null=New-Item -ItemType Directory -Path $work
        $check=& $expandSource -Package $partial -ChecksumFile $partialSum -ArchiveName $target.Name -Destination $work 6>&1 | ForEach-Object { "$_" }
        $line=@($check|Where-Object{$_ -like 'AUTHLENS-PACKAGE: *'})|Select-Object -Last 1
        $verdict=if($line){$line.Substring(18)|ConvertFrom-Json}else{$null}
        if(-not $verdict -or $verdict.status -cne 'verified' -or $verdict.layout -cne 'flat'){throw ('Independent extraction of the package failed: '+$(if($verdict){$verdict.reason}else{'no result'}))}
        if((Get-AuthLensSha256 $partial) -cne $sha){throw 'The package changed during verification.'}
        [IO.File]::Move($partial,$target.File)
        [IO.File]::Move($partialSum,$target.ChecksumFile)
        [pscustomobject]@{status='passed';layout='flat';revision=$Revision;path=$target.File;checksum_file=$target.ChecksumFile;size=(Get-Item -LiteralPath $target.File).Length;sha256=$sha
            version=$Candidate.Version;build_id=$Candidate.Id;source_sha=$source.identity.source_sha;build_timestamp_utc=$source.identity.build_timestamp_utc
            release_directory=$manifest.release_directory;entries=$payload.Count+1;signatures=@($source.signatures);independent_extraction='verified';authenticity=$manifest.authenticity}
    } catch {
        foreach($file in $partial,$partialSum){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}
        throw
    } finally {
        if($work -and (Test-Path -LiteralPath $work)){Remove-Item -LiteralPath $work -Recurse -Force}
    }
}

# ---- WP34 build, installer, acceptance and package inventory and retention (INST-119 to INST-121, build host)
function Measure-AuthLensTree([string]$Path) {
    $bytes=[long]0;$reparse=$false
    if(-not (Test-Path -LiteralPath $Path)){return [pscustomobject]@{bytes=[long]0;reparse_points=$false}}
    $item=Get-Item -LiteralPath $Path -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){return [pscustomobject]@{bytes=[long]0;reparse_points=$true}}
    if(-not $item.PSIsContainer){return [pscustomobject]@{bytes=[long]$item.Length;reparse_points=$false}}
    $stack=[Collections.Generic.Stack[string]]::new();$stack.Push($item.FullName)
    while($stack.Count){
        foreach($child in @(Get-ChildItem -LiteralPath $stack.Pop() -Force)){
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){$reparse=$true;continue}
            if($child.PSIsContainer){$stack.Push($child.FullName)}else{$bytes+=$child.Length}
        }
    }
    [pscustomobject]@{bytes=$bytes;reparse_points=$reparse}
}
function Get-AuthLensSelectionHash([object[]]$Items) {
    $text=(@($Items|Sort-Object id|ForEach-Object{'{0}|{1}' -f $_.id,$_.bytes}) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
# Read-only inventory of <root> by category, version and build id (never mutates). Items: build:<version>/<id>, installer:<version>/<id>,
# package:<version>/<id> and package:<version>/<id>-pkg<N> (each .zip and its .zip.sha256 as one item), acceptance:<version>/<id>, plus legacy run directories, legacy acceptance
# evidence and everything else. Preserved: all acceptance evidence (review evidence), every legacy run directory (its evidence may hold absolute
# paths), builds/installers of an id with acceptance evidence, incomplete/running/unreadable builds, any artifact whose Build record is missing
# (ownership not established), the newest -KeepPassed passed ids, -Preserve ids, incomplete packages, a package that is the only remaining copy of
# its installers, reparse points and unrecognized entries. Eligible: the remaining build, installer and package items, and package leftovers
# (*.zip.partial-*) older than one day.
function Get-AuthLensBuildInventory([string]$OutputRoot='C:\AuthLens', [int]$KeepPassed=3, [string[]]$Preserve=@(), [string[]]$Item=@()) {
    if($KeepPassed -lt 1){throw 'At least the newest passed build is always kept (-KeepPassed 1 or more).'}
    $root=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
    if(-not (Test-Path -LiteralPath $root -PathType Container)){throw "Output root $root does not exist."}
    $items=[Collections.Generic.List[object]]::new()
    $add={param($Category,$Key,$Paths,$Version,$Id)
        $size=[long]0;$reparse=$false
        foreach($p in $Paths){$m=Measure-AuthLensTree $p;$size+=$m.bytes;if($m.reparse_points){$reparse=$true}}
        $entry=[pscustomobject]@{id=$Category+':'+$Key;category=$Category;version=$Version;build_id=$Id;paths=@($Paths|Where-Object{Test-Path -LiteralPath $_});bytes=$size;status='';state='preserved';reasons=[Collections.Generic.List[string]]::new()}
        if($reparse){$entry.reasons.Add('contains_reparse_point')}
        $items.Add($entry);$entry}
    $groups=@{}
    $group={param($Version,$Id) $key=$Version+'/'+$Id; if(-not $groups.ContainsKey($key)){$groups[$key]=[pscustomobject]@{version=$Version;id=$Id;key=$key;build=$null;installer=$null;packages=[Collections.Generic.List[object]]::new();acceptance=$null;status='missing';built=''}}; $groups[$key]}
    foreach($category in 'Build','Installer','Acceptance'){
        $categoryDir=Join-Path $root $category
        if(-not (Test-Path -LiteralPath $categoryDir -PathType Container)){continue}
        foreach($versionDir in @(Get-ChildItem -LiteralPath $categoryDir -Force)){
            if(-not $versionDir.PSIsContainer -or $versionDir.Name -notmatch $script:AuthLensVersionPattern){
                if($category -eq 'Acceptance' -and $versionDir.PSIsContainer){$e=& $add 'acceptance_legacy' $versionDir.Name @($versionDir.FullName) '' '';$e.reasons.Add('review_evidence_never_deleted')}
                elseif(-not ($category -eq 'Build' -and $versionDir.Name -eq 'retention-audit.jsonl')){$e=& $add 'other' ($category+'/'+$versionDir.Name) @($versionDir.FullName) '' '';$e.reasons.Add('unrecognized_never_touched')}
                continue
            }
            foreach($idDir in @(Get-ChildItem -LiteralPath $versionDir.FullName -Force)){
                if(-not $idDir.PSIsContainer -or $idDir.Name -notmatch $script:AuthLensBuildIdPattern){$e=& $add 'other' ($category+'/'+$versionDir.Name+'/'+$idDir.Name) @($idDir.FullName) $versionDir.Name '';$e.reasons.Add('unrecognized_never_touched');continue}
                $g=& $group $versionDir.Name $idDir.Name
                $kind=$category.ToLowerInvariant()
                $g.$kind=& $add $kind ($versionDir.Name+'/'+$idDir.Name) @($idDir.FullName) $versionDir.Name $idDir.Name
            }
        }
    }
    $packagesDir=Join-Path $root 'Packages'
    if(Test-Path -LiteralPath $packagesDir -PathType Container){
        $seen=@{}
        foreach($file in @(Get-ChildItem -LiteralPath $packagesDir -Force)){
            $name=$file.Name
            if(-not $file.PSIsContainer -and $name -match '^(?<zip>AuthLens-.+\.zip)(?:\.sha256)?$' -and $Matches['zip'] -match $script:AuthLensPackagePattern -and $Matches['version'] -match $script:AuthLensVersionPattern){
                $zipName=($name -replace '\.sha256$','')
                if($seen.ContainsKey($zipName)){continue}; $seen[$zipName]=$true
                $null=$zipName -match $script:AuthLensPackagePattern
                $g=& $group $Matches['version'] $Matches['id']
                $zip=Join-Path $packagesDir $zipName; $sum=$zip+'.sha256'
                $key=$g.version+'/'+$g.id+$(if($Matches['revision']){'-pkg'+$Matches['revision']}else{''})
                $packageItem=& $add 'package' $key @($zip,$sum) $g.version $g.id
                $g.packages.Add($packageItem)
                if(-not (Test-Path -LiteralPath $zip -PathType Leaf) -or -not (Test-Path -LiteralPath $sum -PathType Leaf)){$packageItem.reasons.Add('incomplete_package_or_checksum')}
            } elseif(-not $file.PSIsContainer -and $name -match '^AuthLens-.+\.zip(\.sha256)?\.partial-[0-9a-f]{32}$'){
                $e=& $add 'package_partial' $name @($file.FullName) '' ''
                if($file.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-1)){$e.reasons.Add('packaging_may_be_running')}
            } else {$e=& $add 'other' ('Packages/'+$name) @($file.FullName) '' '';$e.reasons.Add('unrecognized_never_touched')}
        }
    }
    foreach($dir in @(Get-ChildItem -LiteralPath $root -Force|Where-Object{$_.Name -notin @('Build','Installer','Acceptance','Packages')})){
        if($dir.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $dir.FullName 'build-summary.json') -PathType Leaf)){$e=& $add 'legacy_run_directory' $dir.Name @($dir.FullName) '' '';$e.reasons.Add('legacy_layout_retained')}
        else{$e=& $add 'other' $dir.Name @($dir.FullName) '' '';$e.reasons.Add('unrecognized_never_touched')}
    }
    foreach($g in $groups.Values){
        if($g.build){
            $summaryFile=Join-Path $g.build.paths[0] 'build-summary.json'
            if(Test-Path -LiteralPath $summaryFile -PathType Leaf){
                try{$s=Read-AuthLensSummary $summaryFile;$g.status=[string]$s.status;if($s.PSObject.Properties['identity'] -and $s.identity){$g.built=[string]$s.identity.build_timestamp_utc}}catch{$g.status='unreadable'}
            }else{$g.status='incomplete'}
        }
        foreach($member in @(@($g.build,$g.installer)+@($g.packages))){
            if(-not $member){continue}
            $member.status=$g.status
            if(-not $g.build){$member.reasons.Add('ownership_not_established_no_build_record')}
            elseif($g.status -notin @('passed','failed')){$member.reasons.Add('incomplete_running_or_unreadable_build')}
            if($g.id -in $Preserve -or $g.key -in $Preserve){$member.reasons.Add('operator_preserved')}
        }
        if($g.acceptance){$g.acceptance.reasons.Add('review_evidence_never_deleted');foreach($member in @($g.build,$g.installer)){if($member){$member.reasons.Add('acceptance_evidence_exists')}}}
        if($g.packages.Count -and -not $g.installer){$newestPackage=@($g.packages|Where-Object{-not $_.reasons.Contains('incomplete_package_or_checksum')}|Sort-Object {[IO.File]::GetLastWriteTimeUtc($_.paths[0])} -Descending)[0];if($newestPackage){$newestPackage.reasons.Add('only_copy_of_installers')}}
    }
    $passed=@($groups.Values|Where-Object{$_.status -eq 'passed'}|Sort-Object @{Expression={$_.built};Descending=$true},@{Expression={$_.id};Descending=$true})
    foreach($g in @($passed|Select-Object -First $KeepPassed)){foreach($member in @(@($g.build,$g.installer)+@($g.packages))){if($member){$member.reasons.Add('retention_keep_newest_passed')}}}
    foreach($entry in $items){
        if($entry.category -in @('build','installer','package','package_partial') -and $entry.reasons.Count -eq 0){
            $entry.state='eligible'
            $entry.reasons.Add($(switch($entry.category){'package'{'superseded_package'}'package_partial'{'interrupted_package_leftover'}default{if($entry.status -eq 'failed'){'failed_build'}else{'superseded_passed_build'}}}))
        }
    }
    $eligible=@($items|Where-Object state -eq 'eligible')
    $selection=if(@($Item).Count){@($eligible|Where-Object{$_.id -in $Item})}else{$eligible}
    $unknown=@($Item|Where-Object{$_ -notin @($eligible|ForEach-Object id)})
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    [pscustomobject]@{schema=1;tool='AuthLens artifact inventory (build host)';generated_utc=[DateTime]::UtcNow.ToString('o');output_root=$root;dry_run=$true
        volume=[pscustomobject]@{volume=$drive.Name;available_bytes=$drive.AvailableFreeSpace};keep_passed=$KeepPassed
        items=@($items|Sort-Object id|ForEach-Object{[pscustomobject]@{id=$_.id;category=$_.category;version=$_.version;build_id=$_.build_id;status=$_.status;bytes=$_.bytes;state=$_.state;reasons=@($_.reasons);paths=@($_.paths)}})
        eligible_bytes=[long](@($eligible|ForEach-Object bytes)|Measure-Object -Sum).Sum;selection=@($selection|ForEach-Object id);selection_bytes=[long](@($selection|ForEach-Object bytes)|Measure-Object -Sum).Sum
        selection_sha256=(Get-AuthLensSelectionHash $selection);not_eligible_requested=@($unknown)}
}
# Deletes exactly the previewed selection (explicit item ids, -Approve and the preview's selection hash). Acceptance evidence, legacy run
# directories and preserved items are never touched. Appends one line to <root>\Build\retention-audit.jsonl and reports the reclaimed storage.
function Remove-AuthLensBuildArtifacts([string]$OutputRoot, [string[]]$Item, [string]$ExpectedSelectionSha256, [int]$KeepPassed=3, [string[]]$Preserve=@(), [switch]$Approve) {
    if(-not $Approve){throw 'Removal requires explicit approval (-Yes) after reviewing the preview; nothing was deleted.'}
    if(-not @($Item).Count){throw 'Name the inventory items to delete explicitly (-Item); nothing was deleted.'}
    $inventory=Get-AuthLensBuildInventory $OutputRoot $KeepPassed $Preserve $Item
    if(@($inventory.not_eligible_requested).Count){throw "Not eligible for deletion (preserved or unknown): $(@($inventory.not_eligible_requested) -join ', '); nothing was deleted."}
    if($ExpectedSelectionSha256 -notmatch '^[a-f0-9]{64}$' -or $inventory.selection_sha256 -cne $ExpectedSelectionSha256){throw 'The selection differs from the reviewed preview (selection_sha256); review the preview again. Nothing was deleted.'}
    $allowedParents=@{build='Build';installer='Installer';package='Packages';package_partial='Packages'}
    $before=$inventory.volume.available_bytes;$deleted=[Collections.Generic.List[object]]::new();$failure=''
    foreach($entry in @($inventory.items|Where-Object{$_.id -in $inventory.selection})){
        try{
            foreach($path in $entry.paths){
                $full=[IO.Path]::GetFullPath($path).TrimEnd('\','/')
                $expected=if($entry.category -in @('build','installer')){Join-Path (Join-Path $inventory.output_root $allowedParents[$entry.category]) $entry.version}else{Join-Path $inventory.output_root 'Packages'}
                if((Split-Path $full -Parent) -ine $expected){throw "Refused unexpected path for $($entry.id)."}
                if((Measure-AuthLensTree $full).reparse_points){throw "Refused $($entry.id): it contains a reparse point."}
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
            }
            $deleted.Add([pscustomobject]@{id=$entry.id;bytes=$entry.bytes})
        }catch{$failure=$_.Exception.Message;break}
    }
    $after=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($inventory.output_root))).AvailableFreeSpace
    $result=[pscustomobject]@{schema=1;tool='AuthLens artifact retention (build host)';completed_utc=[DateTime]::UtcNow.ToString('o');output_root=$inventory.output_root
        selection_sha256=$inventory.selection_sha256;deleted=@($deleted);reclaimed_bytes=[long](@($deleted|ForEach-Object bytes)|Measure-Object -Sum).Sum;available_before=$before;available_after=$after;failure=$failure}
    $buildRoot=Join-Path $inventory.output_root 'Build'; $null=[IO.Directory]::CreateDirectory($buildRoot)
    [IO.File]::AppendAllText((Join-Path $buildRoot 'retention-audit.jsonl'),(($result|ConvertTo-Json -Compress -Depth 5)+"`n"),[Text.UTF8Encoding]::new($false))
    if($failure){throw "Retention stopped after $($deleted.Count) item(s): $failure Remaining items were kept."}
    $result
}
