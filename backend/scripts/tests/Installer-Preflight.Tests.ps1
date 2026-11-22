BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Installer preparation and same-version upgrade boundaries' {
    It 'exposes why a successful standard audit does not prove installer root preparation' {
        $config=[pscustomobject]@{Root=$TestDrive;DataDirectory="$TestDrive/data";BackupRoot="$TestDrive/backups";CertificatePath="$TestDrive/tls/server.pfx";WorkRoot="$TestDrive/state";ReleasesRoot="$TestDrive/releases";ConfigFile="$TestDrive/config/deploy.json"}
        @(Get-ALAclPlan $config | Where-Object Role -eq 'installation root').Count | Should -Be 0
        # The stronger dedicated root check remains in Initialize-ALInstallerServerRoot.
        (Get-Content (Join-Path $PSScriptRoot '../deploy/AuthLens.Installer.ps1') -Raw) | Should -Match "Class='private';Role='installation root';Recurse=\u0024false"
    }
    BeforeEach {
        $old=[pscustomobject]@{product='AuthLens';source_sha=('a'*40);file_version=@(2,0,0,1);build_timestamp_utc='2026-11-21T10:00:00Z'}
        $next=[pscustomobject]@{product='AuthLens';source_sha=('b'*40);file_version=@(2,0,0,1);build_timestamp_utc='2026-11-22T10:00:00Z'}
    }
    It 'accepts a newer same-version build identity while retaining schema and rollback preflight' { {Assert-ALInstallerUpgradeIdentity $old $next} | Should -Not -Throw }
    It 'refuses an older same-version build' { $next.build_timestamp_utc='2026-11-20T10:00:00Z'; {Assert-ALInstallerUpgradeIdentity $old $next} | Should -Throw '*newer verified build*' }
    It 'refuses a product downgrade' { $next.file_version=@(1,9,0,0); {Assert-ALInstallerUpgradeIdentity $old $next} | Should -Throw '*downgrades*' }
    It 'retains the exact preparation failure in the returned exception without initializing directories' {
        Mock -ModuleName AuthLens.Deploy Assert-ALInstallerServerConfiguration { }
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan { Stop-AL 'synthetic root audit refusal' }
        Mock -ModuleName AuthLens.Deploy Initialize-ALInstallation { }
        {Initialize-ALInstallerServerRoot ([pscustomobject]@{Root=$TestDrive})} | Should -Throw '*synthetic root audit refusal*'
        Should -Invoke -ModuleName AuthLens.Deploy Initialize-ALInstallation -Times 0
    }
    It 'refuses an unmanaged existing service before directory provisioning' {
        Mock -ModuleName AuthLens.Deploy Assert-ALInstallerServerConfiguration { }
        Mock -ModuleName AuthLens.Deploy Read-ALJournal { $null }
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{Exists=$true;PathName='synthetic foreign executable'} }
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink { 'synthetic-link' }
        Mock -ModuleName AuthLens.Deploy Get-ALLink { 'synthetic-previous' }
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $false }
        Mock -ModuleName AuthLens.Deploy Initialize-ALInstallation { }
        {Assert-ALInstallerServerPreflight ([pscustomobject]@{ServiceName='AuthLens-Acceptance'})} | Should -Throw '*outside the managed release link*'
        Should -Invoke -ModuleName AuthLens.Deploy Initialize-ALInstallation -Times 0
    }
}
