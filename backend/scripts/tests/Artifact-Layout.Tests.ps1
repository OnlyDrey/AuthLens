# WP32 (BUILD-001 to BUILD-010) and WP34 build-host retention: artifact layout, candidate resolution, packaging and safe extraction.
# Synthetic files in TestDrive only; nothing is built, signed, installed or written outside TestDrive.
BeforeAll {
    . (Join-Path $PSScriptRoot '../Build-Workflow.ps1')
    $script:Expand = (Resolve-Path (Join-Path $PSScriptRoot '../Expand-AuthLensPackage.ps1')).ProviderPath
    function script:New-SyntheticCandidate([string]$Root, [datetime]$Stamp, [string]$Sha = ('a' * 40), [string]$Status = 'passed') {
        $c = New-AuthLensBuildLayout $Root $Stamp $Sha -Version '2.0.0'
        $identity = [ordered]@{ product = 'AuthLens'; version = '2.0.0'; source_sha = $Sha; branch = 'experiment/dotnet-backend'; build_timestamp_utc = $Stamp.ToString('o') }
        foreach ($relative in 'server\AuthLens.Api.exe', 'desktop\AuthLens.exe') { $file = Join-Path $c.BuildDirectory $relative; New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null; [IO.File]::WriteAllBytes($file, [byte[]](1..64)) }
        $manifest = [ordered]@{ schema = 1; target_platform = 'win-x64'; source_dirty = $false; executables = [ordered]@{ server = 'server/AuthLens.Api.exe'; desktop = 'desktop/AuthLens.exe' } }
        foreach ($key in $identity.Keys) { $manifest[$key] = $identity[$key] }
        [IO.File]::WriteAllText((Join-Path $c.BuildDirectory 'build-manifest.json'), ($manifest | ConvertTo-Json -Depth 4))
        $names = Get-AuthLensSetupNames $c '2.0.0'
        foreach ($name in $names.server, $names.desktop) { [IO.File]::WriteAllBytes((Join-Path $c.InstallerDirectory $name), [byte[]](65..120)) }
        $tools = Join-Path $c.InstallerDirectory ('installer-tools-' + ('b' * 32))
        $entries = foreach ($relative in $script:AuthLensPackagedHelpers) { $file = Join-Path $tools $relative; New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null; Set-Content -LiteralPath $file "synthetic $relative"; [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() } }
        [IO.File]::WriteAllText((Join-Path $tools 'installer-tools.json'), (@{ schema = 1; files = @($entries) } | ConvertTo-Json -Depth 4))
        $metadata = [ordered]@{ source_dirty = $false; executables = $manifest.executables; artifacts = @(foreach ($name in $names.desktop, $names.server) { @{ path = $name; sha256 = (Get-FileHash -LiteralPath (Join-Path $c.InstallerDirectory $name)).Hash.ToLowerInvariant() } }) }
        foreach ($key in $identity.Keys) { $metadata[$key] = $identity[$key] }
        [IO.File]::WriteAllText((Join-Path $c.InstallerDirectory 'installer-manifest.json'), ($metadata | ConvertTo-Json -Depth 4))
        Set-Content -LiteralPath (Join-Path $c.InstallerDirectory 'installers-SHA256SUMS') 'synthetic sums'
        Set-Content -LiteralPath (Join-Path $c.InstallerDirectory 'DEPLOY.txt') 'synthetic instructions'
        Copy-Item -LiteralPath $script:Expand -Destination (Join-Path $c.InstallerDirectory 'Expand-AuthLensPackage.ps1')
        $summary = [ordered]@{ schema = 2; layout = 'category'; version = '2.0.0'; id = $c.Id; identity = $identity; verification = @{ release = $true; installers = $true; secrets = $true; branding = $true }; status = $Status; artifacts = @(Get-AuthLensCandidateArtifacts $c) }
        [IO.File]::WriteAllText($c.SummaryFile, ($summary | ConvertTo-Json -Depth 6))
        $c
    }
    function script:Invoke-Expand([string[]]$Arguments) {
        $named = @{}; for ($i = 0; $i -lt $Arguments.Count; $i++) { $key = $Arguments[$i].TrimStart('-'); if ($key -eq 'VerifyOnly') { $named[$key] = $true } else { $named[$key] = $Arguments[++$i] } }
        $output = @(& $script:Expand @named 6>&1 | ForEach-Object { "$_" })
        $line = @($output | Where-Object { $_ -like 'AUTHLENS-PACKAGE: *' }) | Select-Object -Last 1
        $line.Substring(18) | ConvertFrom-Json
    }
}

Describe 'WP32 layout and immutable build identity (BUILD-001 to BUILD-008)' {
    BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); $stamp = [datetime]::Parse('2026-11-25T21:45:12.1234567Z').ToUniversalTime(); $sha = 'b10dd507cca629a0b5ccd8d91ca460871deb196c' }
    It 'generates one build id (UTC yyyy-MM-dd_HHmm and sha7) used by Build, Installer, Acceptance and Packages' {
        $c = New-AuthLensBuildLayout $root $stamp $sha -Version '2.0.0'
        $c.Id | Should -Be '2026-11-25_2145-b10dd50'
        $c.BuildDirectory | Should -Be (Join-Path $root 'Build\2.0.0\2026-11-25_2145-b10dd50')
        $c.InstallerDirectory | Should -Be (Join-Path $root 'Installer\2.0.0\2026-11-25_2145-b10dd50')
        $c.AcceptanceDirectory | Should -Be (Join-Path $root 'Acceptance\2.0.0\2026-11-25_2145-b10dd50')
        $c.PackageFile | Should -Be (Join-Path $root 'Packages\AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip')
        $c.ReleaseDirectory | Should -Be $c.BuildDirectory -Because 'no nested release folder'
        Test-Path (Join-Path $c.BuildDirectory '.build-claim') | Should -BeTrue
        Test-Path $c.InstallerDirectory | Should -BeTrue
        Test-Path $c.AcceptanceDirectory | Should -BeFalse -Because 'acceptance runs create their own evidence'
    }
    It 'never reuses an occupied id in any category or a legacy run directory and keeps the occupant unchanged (<Occupied>)' -ForEach @(
        @{ Occupied = 'Build\2.0.0\2026-11-25_2145-b10dd50' }, @{ Occupied = 'Installer\2.0.0\2026-11-25_2145-b10dd50' },
        @{ Occupied = 'Acceptance\2.0.0\2026-11-25_2145-b10dd50' }, @{ Occupied = 'Packages\AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip' },
        @{ Occupied = 'AuthLens-2.0.0-2026-11-25_2145-b10dd50' }) {
        $path = Join-Path $root $Occupied
        if ($Occupied -like '*.zip') { New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null; Set-Content $path 'existing package' } else { New-Item -ItemType Directory -Force $path | Out-Null; Set-Content (Join-Path $path 'sentinel') 'kept' }
        $c = New-AuthLensBuildLayout $root $stamp $sha -Version '2.0.0'
        $c.Id | Should -Be '2026-11-25_2145-b10dd50-02'
        if ($Occupied -like '*.zip') { Get-Content $path | Should -Be 'existing package' } else { @(Get-ChildItem $path).Name | Should -Be @('sentinel') }
    }
    It 'stops instead of reusing an installer directory that appears after the build claim' {
        $script:installerPath = Join-Path $root 'Installer\2.0.0\2026-11-25_2145-b10dd50'
        $script:createDirectory = Get-Command New-Item -CommandType Cmdlet
        Mock New-Item { param($Path, $ItemType) if ($Path -eq $script:installerPath) { $null = [IO.Directory]::CreateDirectory($Path) }; & $script:createDirectory -ItemType $ItemType -Path $Path -ErrorAction Stop }
        { New-AuthLensBuildLayout $root $stamp $sha -Version '2.0.0' } | Should -Throw '*never reused or overwritten*'
        Test-Path (Join-Path $root 'Build\2.0.0\2026-11-25_2145-b10dd50\.build-claim') | Should -BeTrue
    }
    It 'refuses a noncanonical version or SHA before creating anything' {
        { New-AuthLensBuildLayout $root $stamp $sha -Version '2.0.0/../x' } | Should -Throw '*canonical AuthLens product version*'
        { New-AuthLensBuildLayout $root $stamp 'abc' -Version '2.0.0' } | Should -Throw '*full Git SHA*'
        Test-Path $root | Should -BeFalse
    }
    It 'resolves a candidate from Build, Installer, Acceptance run and version-id paths with identical identity' {
        $c = New-SyntheticCandidate $root $stamp $sha
        $run = Join-Path $c.AcceptanceDirectory 'B13-1'; New-Item -ItemType Directory -Force $run | Out-Null
        foreach ($path in $c.BuildDirectory, $c.InstallerDirectory, $run) { $r = Resolve-AuthLensCandidate $path; $r.Layout | Should -Be 'category'; $r.Id | Should -Be $c.Id; $r.Version | Should -Be '2.0.0' }
        (Resolve-AuthLensCandidate "2.0.0\$($c.Id)" $root).BuildDirectory | Should -Be $c.BuildDirectory
        @(Get-AuthLensCandidateArtifacts $c | ForEach-Object { $_.path }) | Should -Contain 'installer/installer-manifest.json'
        @(Get-AuthLensCandidateArtifacts $c | ForEach-Object { $_.path }) | Should -Contain 'build/build-manifest.json'
        Resolve-AuthLensCandidateArtifact $c 'installer/installer-manifest.json' | Should -Be (Join-Path $c.InstallerDirectory 'installer-manifest.json')
        { Resolve-AuthLensCandidateArtifact $c '../escape' } | Should -Throw
    }
    It 'resolves RC5 and older legacy run directories in place without moving anything' {
        $legacy = Join-Path $root 'AuthLens-2.0.0-2026-11-25_1442-b10dd50'
        $release = Join-Path $legacy 'build\AuthLens-2.0.0-20261125-144246-b10dd50-win-x64'
        New-Item -ItemType Directory -Force $release, (Join-Path $legacy 'installer') | Out-Null
        Set-Content (Join-Path $release 'build-manifest.json') '{}'
        @{ schema = 1; status = 'passed'; identity = @{ version = '2.0.0' } } | ConvertTo-Json | Set-Content (Join-Path $legacy 'build-summary.json')
        $before = @(Get-ChildItem $root -Recurse | ForEach-Object FullName)
        $r = Resolve-AuthLensCandidate $legacy
        $r.Layout | Should -Be 'legacy'; $r.Id | Should -Be '2026-11-25_1442-b10dd50'; $r.ReleaseDirectory | Should -Be $release
        $r.AcceptanceDirectory | Should -Be (Join-Path $root 'acceptance\AuthLens-2.0.0-2026-11-25_1442-b10dd50')
        (Get-AuthLensSetupNames $r '2.0.0').server | Should -Be 'AuthLens-Server-2.0.0-Setup.exe'
        @(Get-ChildItem $root -Recurse | ForEach-Object FullName) | Should -Be $before
        { Resolve-AuthLensCandidate (Join-Path $root 'unknown') } | Should -Throw '*No AuthLens build candidate*'
    }
    It 'keeps the installed release name convention for a Build directory, identical in the build and deployment tools' {
        $c = New-SyntheticCandidate $root $stamp $sha
        Get-AuthLensReleaseName $c.BuildDirectory | Should -Be 'AuthLens-2.0.0-20261125-214512-b10dd50-win-x64'
        Get-AuthLensReleaseName 'C:\x\AuthLens-2.0.0-20261125-144246-b10dd50-win-x64' | Should -Be 'AuthLens-2.0.0-20261125-144246-b10dd50-win-x64'
        $module = Get-Content (Join-Path $PSScriptRoot '../deploy/AuthLens.Deploy.psm1') -Raw
        $definition = [regex]::Match($module, '(?s)function Get-ALReleaseName.*?\r?\n}\r?\n').Value
        $definition | Should -Not -BeNullOrEmpty
        function Join-AL([string]$Path, [string]$Child) { [IO.Path]::Combine($Path, $Child) }
        . ([scriptblock]::Create($definition))
        Get-ALReleaseName $c.BuildDirectory | Should -Be (Get-AuthLensReleaseName $c.BuildDirectory)
    }
}

Describe 'Portable deployment package and safe extraction (BUILD-009, BUILD-010)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $c = New-SyntheticCandidate $root ([datetime]::Parse('2026-11-25T21:45:00Z').ToUniversalTime()) 'b10dd507cca629a0b5ccd8d91ca460871deb196c'
        $target = Join-Path $TestDrive ('t' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    }
    It 'packages an existing verified build without changing it and extracts it into Installer\version\build-id' {
        $before = @(Get-ChildItem $c.BuildDirectory, $c.InstallerDirectory -Recurse -File | ForEach-Object { (Get-FileHash $_.FullName).Hash })
        $p = New-AuthLensPackage $c
        $p.status | Should -Be 'passed'
        $p.path | Should -Be $c.PackageFile
        (Get-Content $c.PackageChecksumFile) | Should -Be ($p.sha256 + ' *AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip')
        $p.independent_extraction | Should -Be 'verified'
        @(Get-ChildItem (Join-Path $root 'Packages')).Name | Should -Be @('AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip', 'AuthLens-2.0.0-2026-11-25_2145-b10dd50.zip.sha256')
        @(Get-ChildItem $c.BuildDirectory, $c.InstallerDirectory -Recurse -File | ForEach-Object { (Get-FileHash $_.FullName).Hash }) | Should -Be $before
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($p.path)
        try { @($zip.Entries | Where-Object { -not $_.FullName.StartsWith('Installer/2.0.0/2026-11-25_2145-b10dd50/') }).Count | Should -Be 0 } finally { $zip.Dispose() }
        $result = Invoke-Expand @('-Package', $p.path, '-Destination', $target)
        $result.reason | Should -BeNullOrEmpty
        $result.status | Should -Be 'verified'
        $extracted = Join-Path $target 'Installer\2.0.0\2026-11-25_2145-b10dd50'
        Test-Path (Join-Path $extracted 'AuthLens-2.0.0-Server-Setup.exe') | Should -BeTrue
        Test-Path (Join-Path $target 'Build') | Should -BeFalse -Because 'the package never depends on the Build directory'
        (Invoke-Expand @('-VerifyOnly', '-ExtractedDirectory', $extracted)).status | Should -Be 'verified'
        $again = Invoke-Expand @('-Package', $p.path, '-Destination', $target)
        $again.status | Should -Be 'refused'; $again.reason | Should -BeLike '*never overwritten*'
        Add-Content (Join-Path $extracted 'DEPLOY.txt') 'tampered'
        (Invoke-Expand @('-VerifyOnly', '-ExtractedDirectory', $extracted)).reason | Should -BeLike '*differs*'
        { New-AuthLensPackage $c } | Should -Throw '*never overwritten*'
    }
    It 'refuses a modified installer artifact, leaves no partial package and keeps the build unchanged' {
        Add-Content (Join-Path $c.InstallerDirectory 'DEPLOY.txt') 'changed after the build'
        { New-AuthLensPackage $c } | Should -Throw '*differs from the build summary*'
        Test-Path (Join-Path $root 'Packages') | Should -BeFalse
        Set-Content -LiteralPath (Join-Path $c.InstallerDirectory 'DEPLOY.txt') 'synthetic instructions'
        Set-Content (Join-Path $c.InstallerDirectory 'extra.txt') 'added later'
        { New-AuthLensPackage $c } | Should -Throw '*not bound to the build summary*'
    }
    It 'refuses failed builds and legacy run directories' {
        $summary = Get-Content $c.SummaryFile -Raw | ConvertFrom-Json; $summary.status = 'failed'; $summary | ConvertTo-Json -Depth 6 | Set-Content $c.SummaryFile
        { New-AuthLensPackage $c } | Should -Throw '*not a passed WP32 build*'
        { New-AuthLensPackage ([pscustomobject]@{ Layout = 'legacy' }) } | Should -Throw '*legacy run directories*'
    }
    It 'refuses a wrong checksum, traversal, absolute and unexpected archive entries before writing anything (<Case>)' -ForEach @(
        @{ Case = 'traversal'; Entry = 'Installer/2.0.0/2026-11-25_2145-b10dd50/../../evil.txt' },
        @{ Case = 'absolute'; Entry = 'C:/evil.txt' },
        @{ Case = 'outside'; Entry = 'Build/2.0.0/2026-11-25_2145-b10dd50/server/AuthLens.Api.exe' },
        @{ Case = 'unexpected'; Entry = 'Installer/2.0.0/2026-11-25_2145-b10dd50/unexpected.txt' },
        @{ Case = 'checksum'; Entry = '' }) {
        $p = New-AuthLensPackage $c
        if ($Entry) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::Open($p.path, [IO.Compression.ZipArchiveMode]::Update)
            try { $writer = [IO.StreamWriter]::new($zip.CreateEntry($Entry).Open()); $writer.Write('synthetic'); $writer.Dispose() } finally { $zip.Dispose() }
            Set-Content $p.checksum_file ((Get-FileHash $p.path).Hash.ToLowerInvariant() + ' *' + (Split-Path $p.path -Leaf)) -Encoding ASCII
        } else { Add-Content $p.path 'x' }
        $result = Invoke-Expand @('-Package', $p.path, '-Destination', $target)
        $result.status | Should -Be 'refused'
        Test-Path (Join-Path $target 'Installer\2.0.0\2026-11-25_2145-b10dd50') | Should -BeFalse
        Test-Path (Join-Path $TestDrive 'evil.txt') | Should -BeFalse
        @(Get-ChildItem $target -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe 'Build-host artifact inventory and retention (WP34: Build, Installer, Acceptance, Packages)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $old = New-SyntheticCandidate $root ([datetime]'2026-11-20T10:00:00Z').ToUniversalTime() ('1' * 40)
        $accepted = New-SyntheticCandidate $root ([datetime]'2026-11-21T10:00:00Z').ToUniversalTime() ('2' * 40)
        $failed = New-SyntheticCandidate $root ([datetime]'2026-11-22T10:00:00Z').ToUniversalTime() ('3' * 40) 'failed'
        $newest = New-SyntheticCandidate $root ([datetime]'2026-11-23T10:00:00Z').ToUniversalTime() ('4' * 40)
        $null = New-AuthLensPackage $old
        New-Item -ItemType Directory -Force (Join-Path $accepted.AcceptanceDirectory 'B13-1') | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $root 'AuthLens-2.0.0-2026-11-25_1442-b10dd50\build'), (Join-Path $root 'AuthLens-2.0.0-2026-11-25_1442-b10dd50\installer') | Out-Null
        Set-Content (Join-Path $root 'AuthLens-2.0.0-2026-11-25_1442-b10dd50\build-summary.json') '{"schema":1}'
        New-Item -ItemType Directory -Force (Join-Path $root 'Installer\2.0.0\2026-11-24_1000-5555555') | Out-Null
        Set-Content (Join-Path $root 'Packages\AuthLens-2.0.0-2026-11-24_1000-6666666.zip') 'orphan without checksum'
    }
    It 'classifies by category, version and build id without changing anything' {
        $before = @(Get-ChildItem $root -Recurse -Force | ForEach-Object FullName)
        $inventory = Get-AuthLensBuildInventory $root 1
        $state = @{}; foreach ($item in $inventory.items) { $state[$item.id] = $item }
        $state["build:2.0.0/$($newest.Id)"].reasons | Should -Contain 'retention_keep_newest_passed'
        $state["build:2.0.0/$($accepted.Id)"].state | Should -Be 'preserved'
        $state["build:2.0.0/$($accepted.Id)"].reasons | Should -Contain 'acceptance_evidence_exists'
        $state["acceptance:2.0.0/$($accepted.Id)"].reasons | Should -Contain 'review_evidence_never_deleted'
        $state["build:2.0.0/$($failed.Id)"].reasons | Should -Contain 'failed_build'
        $state["build:2.0.0/$($old.Id)"].state | Should -Be 'eligible'
        $state["package:2.0.0/$($old.Id)"].state | Should -Be 'eligible'
        @($state["package:2.0.0/$($old.Id)"].paths).Count | Should -Be 2 -Because 'the zip and its checksum are one item'
        $state['installer:2.0.0/2026-11-24_1000-5555555'].reasons | Should -Contain 'ownership_not_established_no_build_record'
        $state['package:2.0.0/2026-11-24_1000-6666666'].reasons | Should -Contain 'incomplete_package_or_checksum'
        $state['legacy_run_directory:AuthLens-2.0.0-2026-11-25_1442-b10dd50'].reasons | Should -Contain 'legacy_layout_retained'
        @(Get-ChildItem $root -Recurse -Force | ForEach-Object FullName) | Should -Be $before
    }
    It 'deletes only the reviewed selection with approval and the preview hash, and reports reclaimed storage' {
        $ids = @("package:2.0.0/$($old.Id)", "installer:2.0.0/$($old.Id)")
        $preview = Get-AuthLensBuildInventory $root 1 @() $ids
        { Remove-AuthLensBuildArtifacts $root $ids $preview.selection_sha256 1 } | Should -Throw '*explicit approval*'
        { Remove-AuthLensBuildArtifacts $root $ids ('0' * 64) 1 -Approve } | Should -Throw '*differs from the reviewed preview*'
        { Remove-AuthLensBuildArtifacts $root @("build:2.0.0/$($accepted.Id)") $preview.selection_sha256 1 -Approve } | Should -Throw '*Not eligible*'
        $result = Remove-AuthLensBuildArtifacts $root $ids $preview.selection_sha256 1 -Approve
        $result.reclaimed_bytes | Should -Be $preview.selection_bytes
        Test-Path $old.PackageFile | Should -BeFalse; Test-Path $old.PackageChecksumFile | Should -BeFalse; Test-Path $old.InstallerDirectory | Should -BeFalse
        Test-Path $old.BuildDirectory | Should -BeTrue
        Test-Path (Join-Path $accepted.AcceptanceDirectory 'B13-1') | Should -BeTrue
        Test-Path (Join-Path $root 'Build\retention-audit.jsonl') | Should -BeTrue
    }
}

Describe 'Root build orchestration contract (BUILD-009)' {
    It 'keeps .\build.ps1 -OutputRoot C:\AuthLens, makes -ZipPackage optional and packages only after a passed build' {
        $file = Join-Path $PSScriptRoot '../../../build.ps1'
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $parameters = @{}; foreach ($parameter in $ast.ParamBlock.Parameters) { $parameters[$parameter.Name.VariablePath.UserPath] = $parameter }
        $parameters['OutputRoot'].DefaultValue.Value | Should -Be 'C:\AuthLens'
        $parameters['ZipPackage'].StaticType | Should -Be ([switch])
        $parameters['ZipPackage'].DefaultValue | Should -BeNullOrEmpty
        $source = Get-Content -LiteralPath $file -Raw
        $source | Should -Match 'New-AuthLensBuildLayout \$OutputRoot'
        $source | Should -Match "layout='category'"
        $source | Should -Match "if \(\`$ZipPackage -and \`$status -eq 'passed'\)"
        $source | Should -Match "if \(\`$packageResult.status -ne 'passed'\) \{ \`$status='failed' \}"
        $source | Should -Not -Match 'New-AuthLensBuildDirectory'
    }
}
