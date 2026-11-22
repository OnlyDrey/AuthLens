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
    It 'uses the UTC timestamp once and retains the short SHA in the directory' {
        $path=New-AuthLensBuildDirectory $output $stamp $identity.source_sha
        Split-Path $path -Leaf | Should -Be '20261122T1011121234567Z-aaaaaaa'
    }
    It 'gives repeated builds of the same commit separate paths and never reuses a collision' {
        $first=New-AuthLensBuildDirectory $output $stamp $identity.source_sha
        $second=New-AuthLensBuildDirectory $output ($stamp.AddTicks(1)) $identity.source_sha
        $first | Should -Not -Be $second
        Set-Content (Join-Path $first 'sentinel') 'preserved'
        {New-AuthLensBuildDirectory $output $stamp $identity.source_sha} | Should -Throw '*already exists*'
        Get-Content (Join-Path $first 'sentinel') | Should -Be 'preserved'
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
        $directory=New-AuthLensBuildDirectory $output $stamp $identity.source_sha
        Set-Content (Join-Path $directory 'partial.exe') 'synthetic partial output'
        Set-Content (Join-Path $directory 'build.log') 'diagnostics'
        $artifacts=@(Get-AuthLensBuildArtifacts $directory)
        $artifacts.Count | Should -Be 1
        $artifacts[0].sha256 | Should -Be ((Get-FileHash (Join-Path $directory 'partial.exe')).Hash.ToLowerInvariant())
        Test-Path (Join-Path $directory 'partial.exe') | Should -BeTrue
    }
}
