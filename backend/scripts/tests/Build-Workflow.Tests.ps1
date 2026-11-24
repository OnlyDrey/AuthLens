BeforeAll {
    . (Join-Path $PSScriptRoot '../Build-Workflow.ps1')
}
Describe 'Canonical Windows build identity and collision boundaries' {
    BeforeEach {
        $output=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $stamp=[datetime]::Parse('2026-11-22T10:11:12.1234567Z').ToUniversalTime()
        $identity=[pscustomobject]@{product='AuthLens';version='2.0.0-alpha.1';source_sha=('a'*40);branch='experiment/dotnet-backend';build_timestamp_utc='2026-11-22T10:11:12Z'}
        $manifest=$identity | ConvertTo-Json | ConvertFrom-Json
        $manifest | Add-Member source_dirty $false
        $manifest | Add-Member executables ([pscustomobject]@{desktop='desktop/AuthLens.exe';server='server/AuthLens.Api.exe'})
    }
    It 'uses the branded UTC name with the canonical <Version> and first seven SHA characters' -ForEach @(
        @{Version='2.0.0'},@{Version='2.0.0-alpha.1'},@{Version='2.0.0-rc.12'}) {
        $commit='8ec7f77b35b23d8c295e119bc6e4128b0681f67d'
        $example=[datetime]::Parse('2026-11-24T09:48:59.9999999Z').ToUniversalTime()
        $path=New-AuthLensBuildDirectory $output $example $commit -Version $Version
        Split-Path $path -Leaf | Should -Be ('AuthLens-'+$Version+'-2026-11-24_0948-8ec7f77')
        Test-Path -LiteralPath (Join-Path $path '.build-claim')|Should -BeTrue
    }
    It 'gives repeated builds of the same commit separate paths and never reuses a collision' {
        $first=New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version
        Set-Content (Join-Path $first 'sentinel') 'preserved'
        $claim=(Get-FileHash (Join-Path $first '.build-claim')).Hash
        $second=New-AuthLensBuildDirectory $output ($stamp.AddTicks(1)) $identity.source_sha -Version $identity.version
        $third=New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version
        $second | Should -Be ($first+'-02')
        $third | Should -Be ($first+'-03')
        Get-Content (Join-Path $first 'sentinel') | Should -Be 'preserved'
        (Get-FileHash (Join-Path $first '.build-claim')).Hash|Should -Be $claim
    }
    It 'skips both existing directories and files without adopting them' {
        $first=New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version
        Set-Content ($first+'-02') 'unrelated file preserved'
        New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version|Should -Be ($first+'-03')
        Get-Content ($first+'-02')|Should -Be 'unrelated file preserved'
    }
    It 'advances safely if another process claims a candidate after the existence check' {
        $script:racedPath=Join-Path $output 'AuthLens-2.0.0-2026-11-22_1011-aaaaaaa'
        $script:createDirectory=Get-Command New-Item -CommandType Cmdlet
        Mock New-Item {
            param($Path,$ItemType)
            if($Path -eq $script:racedPath){
                $null=[IO.Directory]::CreateDirectory($Path)
                Set-Content (Join-Path $Path 'other-process') 'retained'
            }
            # Invoke the native cmdlet object directly; a module-qualified name still resolves
            # to Pester's mock and recurses. This exercises the real provider's collision error.
            & $script:createDirectory -ItemType $ItemType -Path $Path -ErrorAction Stop
        }
        New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version '2.0.0'|Should -Be ($script:racedPath+'-02')
        Get-Content (Join-Path $script:racedPath 'other-process')|Should -Be 'retained'
        Test-Path (Join-Path $script:racedPath '.build-claim')|Should -BeFalse
    }
    It 'propagates non-collision failures instead of retrying another name' {
        Mock New-Item {throw [UnauthorizedAccessException]::new('Synthetic access denied')}
        {New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version}|Should -Throw '*Synthetic access denied*'
        Should -Invoke New-Item -Times 1 -Exactly
    }
    It 'converts local time to UTC and formats it independently of the current calendar' {
        $culture=[Globalization.CultureInfo]::CurrentCulture
        try{
            [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('th-TH')
            $path=New-AuthLensBuildDirectory $output ($stamp.ToLocalTime()) $identity.source_sha -Version '2.0.0'
            Split-Path $path -Leaf|Should -Be 'AuthLens-2.0.0-2026-11-22_1011-aaaaaaa'
        }finally{[Globalization.CultureInfo]::CurrentCulture=$culture}
    }
    It 'rejects invalid SHA or unsafe noncanonical version before creating any output' {
        {New-AuthLensBuildDirectory $output $stamp 'aaaaaaa' -Version '2.0.0'}|Should -Throw '*full Git SHA*'
        foreach($version in @('','../other','2.0.0/other','02.0.0','2.0.0-alpha.0')){
            {New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $version}|Should -Throw '*canonical AuthLens product version*'
        }
        Test-Path $output|Should -BeFalse
    }
    It 'continues to inspect artifacts in legacy build directories without renaming them' {
        $legacy=Join-Path $output '20261122T1011121234567Z-aaaaaaa'
        $null=New-Item -ItemType Directory -Path $legacy
        Set-Content (Join-Path $legacy 'sentinel.txt') 'legacy retained'
        $path=New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version
        $path|Should -Not -Be $legacy
        @(Get-AuthLensBuildArtifacts $legacy)[0].path|Should -Be 'sentinel.txt'
        Get-Content (Join-Path $legacy 'sentinel.txt')|Should -Be 'legacy retained'
    }
    It 'preserves full timestamp precision and SHA in summary and release metadata expressions' {
        $timestamp=$stamp;$built=$stamp;$sha='8ec7f77b35b23d8c295e119bc6e4128b0681f67d'
        foreach($file in @((Join-Path $PSScriptRoot '../../../build.ps1'),(Join-Path $PSScriptRoot '../build-release.ps1'))){
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count|Should -Be 0
            $expressions=@(foreach($table in $ast.FindAll({param($node)$node -is [Management.Automation.Language.HashtableAst]},$true)){
                foreach($pair in $table.KeyValuePairs){if($pair.Item1.Value -eq 'build_timestamp_utc'){$pair.Item2.Extent.Text}}
            })
            $expressions.Count|Should -Be 1
            # Evaluate only the timestamp expression, never the build entry point.
            $value=& ([scriptblock]::Create($expressions[0]))
            $value|Should -Be '2026-11-22T10:11:12.1234567Z'
            ([datetime]::Parse($value).ToUniversalTime()).Ticks|Should -Be $stamp.Ticks
            $shaExpressions=@(foreach($table in $ast.FindAll({param($node)$node -is [Management.Automation.Language.HashtableAst]},$true)){
                foreach($pair in $table.KeyValuePairs){if($pair.Item1.Value -eq 'source_sha'){$pair.Item2.Extent.Text}}
            })
            $shaExpressions.Count|Should -Be 1
            (& ([scriptblock]::Create($shaExpressions[0])))|Should -Be $sha
        }
        $identity.build_timestamp_utc=$stamp.ToString('o');$manifest.build_timestamp_utc=$identity.build_timestamp_utc
        $identity.source_sha=$sha;$manifest.source_sha=$sha
        {Assert-AuthLensBuildIdentity $manifest $identity}|Should -Not -Throw
        # Exercise only the installer's real metadata producer with synthetic input files.
        $null=New-Item -ItemType Directory -Path $output
        $names=@('synthetic-desktop.exe','synthetic-server.exe')
        foreach($name in $names){Set-Content (Join-Path $output $name) 'synthetic metadata input; never execute'}
        $producer=Get-Content (Join-Path $PSScriptRoot '../build-installers.ps1') -Raw
        $construction=[regex]::Match($producer,'(?s)\$metadata=\[ordered\]@\{\}.*?(?=\[IO.File\]::WriteAllText)').Value
        $construction|Should -Not -BeNullOrEmpty
        $installer=& {
            param($manifest,$names,$Output,$construction)
            . ([scriptblock]::Create($construction))
            $metadata|ConvertTo-Json -Depth 6|ConvertFrom-Json
        } $manifest $names $output $construction
        $installer.build_timestamp_utc|Should -Be $stamp.ToString('o')
        $installer.source_sha|Should -Be $sha
    }
    It 'accepts identical release, installer and summary identities' { {Assert-AuthLensBuildIdentity $manifest $identity} | Should -Not -Throw }
    It 'refuses a changed <Field>' -ForEach @(@{Field='source_sha'},@{Field='branch'},@{Field='version'},@{Field='build_timestamp_utc'}) {
        $manifest.$Field='different'
        {Assert-AuthLensBuildIdentity $manifest $identity} | Should -Throw '*identity mismatch*'
    }
    It 'rejects swapped Desktop and Server artifacts' {
        $manifest.executables.desktop='server/AuthLens.Api.exe'
        {Assert-AuthLensBuildIdentity $manifest $identity} | Should -Throw '*isolation mismatch*'
    }
    It 'hashes and preserves partial artifacts after a failure without including mutable logs' {
        $directory=New-AuthLensBuildDirectory $output $stamp $identity.source_sha -Version $identity.version
        Set-Content (Join-Path $directory 'partial.exe') 'synthetic partial output'
        Set-Content (Join-Path $directory 'build.log') 'diagnostics'
        $artifacts=@(Get-AuthLensBuildArtifacts $directory)
        $artifacts.Count | Should -Be 1
        $artifacts[0].sha256 | Should -Be ((Get-FileHash (Join-Path $directory 'partial.exe')).Hash.ToLowerInvariant())
        Test-Path (Join-Path $directory 'partial.exe') | Should -BeTrue
    }
    It 'captures native child output in the transcript and preserves its nonzero exit code' {
        $log=Join-Path $TestDrive 'native-output.log'
        $child=Join-Path $TestDrive 'synthetic-child.ps1'
        Set-Content -LiteralPath $child "Write-Output 'synthetic native diagnostic'; exit 7"
        $shell=Join-Path $PSHOME 'powershell.exe'
        if ($PSVersionTable.PSEdition -eq 'Core') { $shell=Join-Path $PSHOME 'pwsh.exe' }
        Start-Transcript -Path $log -NoClobber | Out-Null
        try { $code=Invoke-AuthLensBuildProcess $shell @('-NoProfile','-NonInteractive','-File',$child) } finally { Stop-Transcript | Out-Null }
        $code | Should -Be 7
        Get-Content -LiteralPath $log -Raw | Should -Match 'synthetic native diagnostic'
    }
}
