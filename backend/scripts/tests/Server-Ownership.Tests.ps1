BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Installer ownership is specific and never adopts populated data' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $data=Join-Path $root 'data'
        $release=Join-Path $root 'releases/reviewed'
        New-Item -ItemType Directory -Path $data,$release,(Join-Path $root 'config') -Force|Out-Null
        $file=Join-Path $root 'config/deploy.json';Set-Content $file '{}'
        Set-Content (Join-Path $release 'build-manifest.json') '{"product":"AuthLens"}'
        $config=[pscustomobject]@{Root=$root;DataDirectory=$data;ReleasesRoot=(Join-Path $root 'releases');ConfigFile=$file;ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens'}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false}}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink {'current'}
    }
    It 'creates one instance marker and reuses it on a failed-install retry' {
        $id=Initialize-ALInstallerDataOwnership $config
        $id|Should -Match '^[a-f0-9]{32}$'
        Initialize-ALInstallerDataOwnership $config|Should -Be $id
        @(Get-ChildItem $data -Force).Count|Should -Be 1
    }
    It 'refuses a populated fresh directory without writing an ownership claim' {
        Set-Content (Join-Path $data 'unrelated.txt') 'preserve'
        {Initialize-ALInstallerDataOwnership $config}|Should -Throw '*populated*'
        Test-Path (Join-Path $data '.authlens-owned-data.json')|Should -BeFalse
    }
    It 'does not claim pre-existing database ownership during upgrade' {
        Set-Content (Join-Path $data 'authlens.sqlite3') 'preserve'
        $null=Initialize-ALInstallerDataOwnership $config
        Test-Path (Join-Path $data '.authlens-owned-data.json')|Should -BeFalse
    }
    It 'rejects a marker copied from a different installation' {
        $null=Initialize-ALInstallerDataOwnership $config
        $config.Root=Join-Path $root 'another'
        {Initialize-ALInstallerDataOwnership $config}|Should -Throw '*ownership marker is invalid*'
    }
    It 'records verified release/configuration identity and preserves instance identity' {
        $manifest=[pscustomobject]@{product='AuthLens';source_sha=('a'*40)}
        Write-ALInstallerServerIdentity $config $manifest $release ('b'*32)
        $first=Get-ALInstallerServerIdentity $config
        $first.instance_id|Should -Be ('b'*32)
        $first.config_sha256|Should -Be (Get-FileHash $file).Hash.ToLowerInvariant()
        Write-ALInstallerServerIdentity $config $manifest $release ('c'*32)
        (Get-ALInstallerServerIdentity $config).instance_id|Should -Be $first.instance_id
        {Write-ALInstallerServerIdentity $config $manifest $TestDrive}|Should -Throw '*outside its approved root*'
    }
}
Describe 'Advanced storage provisioning keeps existing parents intact' {
    It 'creates a protected dedicated tree for configured external storage' {
        $root=Join-Path $TestDrive 'installation'
        $external=Join-Path $TestDrive 'external/new/data'
        New-Item -ItemType Directory -Path $root,(Join-Path $TestDrive 'external') -Force|Out-Null
        $config=[pscustomobject]@{Root=$root;DataDirectory=$external;ReleasesRoot=(Join-Path $root 'releases');BackupRoot=(Join-Path $root 'backups');WorkRoot=(Join-Path $root 'deployment')}
        Mock -ModuleName AuthLens.Deploy Get-ALAclReport {[pscustomobject]@{safe=$true}}
        Mock -ModuleName AuthLens.Deploy Get-ALAclPlan {@()}
        Mock -ModuleName AuthLens.Deploy New-ALSecureDirectory {}
        Initialize-ALInstallation $config
        Should -Invoke -ModuleName AuthLens.Deploy New-ALSecureDirectory -Times 1 -ParameterFilter {$Path -eq $external -and $ApprovedRoots.Count -eq 1 -and $ApprovedRoots[0] -eq (Join-Path $TestDrive 'external/new')}
        Test-Path $external|Should -BeFalse # native creation is mocked; shared parent was not modified
    }
}
Describe 'SCM identity changes preserve credentials and fail safely' {
    BeforeEach {
        $config=[pscustomobject]@{ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens'}
        Mock -ModuleName AuthLens.Deploy New-Service {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALProcess {[pscustomobject]@{ExitCode=0;Output=@()}}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;Account=$config.ServiceAccount}}
    }
    It 'does not enable automatic startup after identity preparation fails' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALProcess {[pscustomobject]@{ExitCode=5;Output=@()}}
        {Set-ALServiceEntry $config 'reviewed' $false}|Should -Throw '*remains Manual*'
        Should -Invoke -ModuleName AuthLens.Deploy New-Service -Times 1 -ParameterFilter {$StartupType -eq 'Manual'}
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALProcess -Times 0 -ParameterFilter {$Arguments -contains 'start='}
    }
    It 'preserves existing SCM credentials instead of resetting the account password' {
        $config.ServiceAccount='LAB\dedicated'
        Set-ALServiceEntry $config 'reviewed' $true
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALProcess -Times 0 -ParameterFilter {$Arguments -contains 'obj='}
    }
    It 'refuses to reconfigure a different existing service identity' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;Account='LocalSystem'}}
        {Set-ALServiceEntry $config 'reviewed' $true}|Should -Throw '*separate validated credential transaction*'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALProcess -Times 0
    }
}
