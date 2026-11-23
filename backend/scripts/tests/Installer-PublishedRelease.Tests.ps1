BeforeAll {
    . (Join-Path $PSScriptRoot 'ReleaseFixture.ps1')
    Import-TestDeploymentModule
}
Describe 'Lifecycle validation uses the actual published Server package contract' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $full=Join-Path $root 'full'
        New-VerifiableRelease $full
        $config=[pscustomobject]@{ReleasesRoot=(Join-Path $root 'releases')}
        $manifest=Get-ALInstallerPackage $full
        $published=Publish-ALRelease $config $full $manifest -RepairId ('a'*32)
    }
    It 'verifies a published repair release with omitted Desktop files and unchanged checksums' {
        Test-Path (Join-Path $published 'desktop')|Should -BeFalse
        Test-Path (Join-Path $published 'deployment-package.json')|Should -BeTrue
        (Get-ALInstallerPackage $published -PublishedServer).source_sha|Should -Be ('a'*40)
        {Get-ALInstallerPackage $published}|Should -Throw '*integrity verification failed*'
    }
    It 'still rejects changed Server files in published scope' {
        Add-Content (Join-Path $published 'server/AuthLens.Api.exe') 'tampered'
        {Get-ALInstallerPackage $published -PublishedServer}|Should -Throw '*integrity verification failed*'
    }
}
