BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Uninstall ownership review rejects adoption and preserves external paths' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $release=Join-Path $root 'releases/reviewed'
        New-Item -ItemType Directory -Path $release,(Join-Path $root 'config'),(Join-Path $root 'data') -Force|Out-Null
        $file=Join-Path $root 'config/deploy.json';Set-Content $file '{}'
        Set-Content (Join-Path $release 'build-manifest.json') '{"product":"AuthLens"}'
        Set-Content (Join-Path $root 'data/authlens.sqlite3') 'synthetic database'
        $config=[pscustomobject]@{Root=$root;ConfigFile=$file;DataDirectory=(Join-Path $root 'data');ReleasesRoot=(Join-Path $root 'releases');WorkRoot=(Join-Path $root 'deployment');BackupRoot=(Join-Path $root 'backups');ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens';CertificatePath=(Join-Path $root 'tls/server.pfx');CertificatePasswordFile=(Join-Path $root 'tls/password')}
        $resolved=[pscustomobject]@{Config=$config;ConfigSha256=(Get-FileHash $file).Hash.ToLowerInvariant();ProgramDirectory=(Join-Path $root 'app')}
        Write-ALInstallerServerIdentity $config ([pscustomobject]@{product='AuthLens'}) $release ('a'*32)
        Mock -ModuleName AuthLens.Deploy Assert-ALInstallerServerConfiguration {}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Get-ALAclPlan {@()}
        Mock -ModuleName AuthLens.Deploy Read-ALJournal {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink {'current'}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$release}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerPackage {[pscustomobject]@{product='AuthLens'}}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;Account='NT SERVICE\AuthLens';State='Running';PathName='synthetic'}}
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary {$true}
        Mock -ModuleName AuthLens.Deploy Compare-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALOwnedFirewallReceipts {@()}
    }
    It 'plans data preservation without requiring a populated firewall rule list' {
        $plan=Get-ALServerUninstallPlan $resolved
        $plan.data_retention|Should -Be 'preserve all'
        $plan.preserved_paths|Should -Contain $config.CertificatePath
        $plan.firewall_rules.Count|Should -Be 0
        $output=Join-Path $root 'plan.ini';Write-ALServerSetupPlan $output $plan
        Get-Content $output -Raw|Should -Match $resolved.ConfigSha256
    }
    It 'refuses absent ownership receipts rather than adopting a service' {
        Remove-Item (Join-Path $root 'config/installed-product.json')
        {Get-ALServerUninstallPlan $resolved}|Should -Throw '*matching installed-product receipt*'
    }
    It 'refuses an unrelated service identity' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;Account='LocalSystem';PathName='other'}}
        {Get-ALServerUninstallPlan $resolved}|Should -Throw '*unrelated service registration*'
    }
    It 'refuses a changed installed manifest' {
        Add-Content (Join-Path $release 'build-manifest.json') 'changed'
        {Get-ALServerUninstallPlan $resolved}|Should -Throw '*manifest disagrees*'
    }
}
Describe 'Server uninstall preserves persistent state and verifies recovery first' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $root|Out-Null
        $config=[pscustomobject]@{Root=$root;WorkRoot=$root;DataDirectory=$root;BackupRoot=$root;ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens';StopTimeoutSeconds=10}
        $resolved=[pscustomobject]@{Config=$config;ConfigSha256=('a'*64)}
        $script:removed=$false
        Mock -ModuleName AuthLens.Deploy Enter-ALLock {}
        Mock -ModuleName AuthLens.Deploy Exit-ALLock {}
        Mock -ModuleName AuthLens.Deploy Save-ALInstallerRecoveryTools {}
        Mock -ModuleName AuthLens.Deploy Get-ALServerUninstallPlan {
            [pscustomobject]@{release=$root;instance_id=('c'*32);service=@{Exists=$true};preserved_paths=@($root)}
        }
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {
            param($ExePath,$Arguments)
            if($Arguments[0] -eq '--backup-local'){[pscustomobject]@{file='verified.slbak';sha256=('b'*64)}}
            else{[pscustomobject]@{verified=$true;sha256=('b'*64)}}
        }
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange {@{changed=$false}}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=(-not $script:removed);State='Stopped';Account='NT SERVICE\AuthLens';PathName='synthetic'}}
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary {$true}
        Mock -ModuleName AuthLens.Deploy Invoke-ALProcess {$script:removed=$true;[pscustomobject]@{ExitCode=0;Output=@()}}
    }
    It 'removes only verified service/rules and keeps every persistent file' {
        $data=Join-Path $root 'authlens.sqlite3';Set-Content $data 'preserve exactly'
        $hash=(Get-FileHash $data).Hash
        $result=Invoke-ALInstallerServerUninstall $resolved
        $result.uninstalled|Should -BeTrue
        $result.data_retention|Should -Be 'preserve all'
        (Get-FileHash $data).Hash|Should -Be $hash
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALProcess -Times 1 -ParameterFilter {$File -eq 'sc.exe' -and ($Arguments -join '|') -ceq 'delete|AuthLens'}
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange -Times 1 -ParameterFilter {$Remove -and $Approved -and $LockHeld}
        Test-Path (Join-Path $root 'uninstall-pending.json')|Should -BeFalse
    }
    It 'never stops or removes anything when backup verification fails' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{file='failed.slbak';verified=$false;sha256=('b'*64)}}
        {Invoke-ALInstallerServerUninstall $resolved}|Should -Throw '*backup verification failed*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALProcess -Times 0
        Test-Path (Join-Path $root 'uninstall-pending.json')|Should -BeTrue
    }
    It 'preserves the journal if service deletion remains pending and safely resumes' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALProcess {[pscustomobject]@{ExitCode=0;Output=@()}}
        {Invoke-ALInstallerServerUninstall $resolved}|Should -Throw '*removal has not verified*'
        Test-Path (Join-Path $root 'uninstall-pending.json')|Should -BeTrue
        $script:removed=$true
        (Invoke-ALInstallerServerUninstall $resolved).uninstalled|Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter {$Arguments[0] -eq '--backup-local'}
    }
    It 'refuses changed recovery bindings before stopping a service' {
        Write-ALInstallerJournal (Join-Path $root 'uninstall-pending.json') @{schema=1;operation='uninstall';root='different'}
        {Invoke-ALInstallerServerUninstall $resolved}|Should -Throw '*bindings changed*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
    }
    It 'blocks ordinary deployment while uninstall is pending' {
        Set-Content (Join-Path $root 'uninstall-pending.json') '{}'
        {Assert-ALNoPendingRepair $config}|Should -Throw '*pending uninstall*'
    }
}
