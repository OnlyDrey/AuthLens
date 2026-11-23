BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Loopback HTTPS readiness preserves the default host boundary' {
    It 'uses the loopback address when no extra hosts are configured' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALHttp {[pscustomobject]@{Status=200}}
        $config=[pscustomobject]@{ListenAddress='127.0.0.1';Port=18795;AllowedHosts=@()}
        (Invoke-ALConfiguredHttp $config '/health/ready').Status|Should -Be 200
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 1 -ParameterFilter {$Url -eq 'https://127.0.0.1:18795/health/ready' -and $HostHeader -eq '127.0.0.1:18795'}
    }
    It 'brackets IPv6 loopback in both URL and Host' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALHttp {[pscustomobject]@{Status=200}}
        $config=[pscustomobject]@{ListenAddress='::1';Port=18795;AllowedHosts=@()}
        $null=Invoke-ALConfiguredHttp $config '/health/ready'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 1 -ParameterFilter {$Url -eq 'https://[::1]:18795/health/ready' -and $HostHeader -eq '[::1]:18795'}
    }
    It 'still refuses a LAN listener without explicit hosts' {
        $config=[pscustomobject]@{ListenAddress='10.0.7.50';Port=18795;AllowedHosts=@()}
        {Invoke-ALConfiguredHttp $config '/health/ready'}|Should -Throw '*allowed host*'
    }
}
Describe 'Approved source-restricted Server firewall provisioning' {
    BeforeEach {
        $work=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work|Out-Null
        $config=[pscustomobject]@{ListenAddress='10.0.7.50';Port=18795;ServiceName='AuthLens';Root=$TestDrive;WorkRoot=$work}
    }
    It 'keeps loopback closed without creating an exception' {
        $config.ListenAddress='127.0.0.1'
        (Get-ALInstallerFirewallPlan $config '').required|Should -BeFalse
        {Get-ALInstallerFirewallPlan $config '10.0.7.10'}|Should -Throw '*Loopback*'
    }
    It 'accepts explicit proxy peers and restricted IPv4/IPv6 subnets' {
        $plan=Get-ALInstallerFirewallPlan $config '10.0.7.10,10.0.8.0/24,fd00::/64' 'Private,Domain'
        $plan.remote_addresses.Count|Should -Be 3
        $plan.profiles.Count|Should -Be 2
        $plan.local_address|Should -Be '10.0.7.50'
        $plan.port|Should -Be 18795
    }
    It 'refuses unsafe sources <Source>' -ForEach @(@{Source=''},@{Source='Any'},@{Source='*'},@{Source='LocalSubnet'},@{Source='0.0.0.0/0'},@{Source='::/0'},@{Source='10.0.0.0/0'},@{Source='10.0.0.0/33'},@{Source='fd00::/129'},@{Source='proxy.example.org'}) {
        {Get-ALInstallerFirewallPlan $config $Source}|Should -Throw '*Firewall*'
    }
    It 'refuses unrestricted or public profiles' {
        {Get-ALInstallerFirewallPlan $config '10.0.7.10' 'Any'}|Should -Throw '*profiles*'
        {Get-ALInstallerFirewallPlan $config '10.0.7.10' 'Public'}|Should -Throw '*profiles*'
    }
    It 'requires approval before any mutation' {
        $plan=Get-ALInstallerFirewallPlan $config '10.0.7.10'
        {Install-ALInstallerFirewallRule $config $plan}|Should -Throw '*explicit security approval*'
        @(Get-ChildItem $config.WorkRoot -Filter 'firewall-*').Count|Should -Be 0
    }
    It 'refuses to duplicate or change scope while earlier owned-rule evidence exists' {
        Set-Content -LiteralPath (Join-Path $config.WorkRoot 'firewall-prior.json') 'retained recovery evidence'
        {Get-ALInstallerFirewallPlan $config '10.0.7.10'}|Should -Throw '*No rule was updated or duplicated*'
    }
    It 'records intent before creating a service-bound rule without touching existing rules' {
        Mock -ModuleName AuthLens.Deploy Assert-ALOwnedFirewallRule {}
        Mock -ModuleName AuthLens.Deploy New-NetFirewallRule {
            @(Get-ChildItem $work -Filter 'firewall-*.json').Count|Should -Be 1
        }
        Mock -ModuleName AuthLens.Deploy Remove-NetFirewallRule {}
        $result=Install-ALInstallerFirewallRule $config (Get-ALInstallerFirewallPlan $config '10.0.7.10') -Approved
        $result.changed|Should -BeTrue
        (Get-Content $result.receipt -Raw|ConvertFrom-Json).phase|Should -Be 'applied'
        Should -Invoke -ModuleName AuthLens.Deploy New-NetFirewallRule -Times 1 -ParameterFilter {
            $Service -eq 'AuthLens' -and $LocalAddress -eq '10.0.7.50' -and $LocalPort -eq 18795 -and $RemoteAddress -eq '10.0.7.10' -and $Profile -eq 'Private' -and $Name -like 'AuthLens-Setup-*'
        }
        Should -Invoke -ModuleName AuthLens.Deploy Remove-NetFirewallRule -Times 0
    }
    It 'rolls back only its unique new rule and retains intent on failure' {
        Mock -ModuleName AuthLens.Deploy New-NetFirewallRule {throw 'synthetic native failure'}
        Mock -ModuleName AuthLens.Deploy Remove-NetFirewallRule {}
        {Install-ALInstallerFirewallRule $config (Get-ALInstallerFirewallPlan $config '10.0.7.10') -Approved}|Should -Throw '*Firewall provisioning failed*'
        Should -Invoke -ModuleName AuthLens.Deploy Remove-NetFirewallRule -Times 1 -ParameterFilter {$Name -like 'AuthLens-Setup-*' -and $PolicyStore -eq 'PersistentStore'}
        @(Get-ChildItem $config.WorkRoot -Filter 'firewall-*.json').Count|Should -Be 1
    }
}
Describe 'Create-only fresh deployment configuration publication' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force|Out-Null
        $draft=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
        @{Root=$root;ListenAddress='127.0.0.1';Port=18799}|ConvertTo-Json|Set-Content -LiteralPath $draft -Encoding UTF8
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false}}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupRegistration {$null}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        $resolved=Resolve-ALServerSetupConfiguration $draft
    }
    It 'publishes exact reviewed bytes and supports a matching retry' {
        $published=Publish-ALServerSetupConfiguration $resolved
        $published.Config.ConfigFile|Should -Be (Join-Path $root 'config/deploy.json')
        $published.ConfigSha256|Should -Be $resolved.ConfigSha256
        (Publish-ALServerSetupConfiguration $resolved).ConfigSha256|Should -Be $resolved.ConfigSha256
    }
    It 'never overwrites an existing different configuration' {
        $target=Join-Path $root 'config/deploy.json';Set-Content $target 'preserve this'
        {Publish-ALServerSetupConfiguration $resolved}|Should -Throw '*differs*preserved*'
        (Get-Content $target -Raw).Trim()|Should -Be 'preserve this'
    }
    It 'refuses publication over an existing service' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true}}
        {Publish-ALServerSetupConfiguration $resolved}|Should -Throw '*existing service*'
        Test-Path (Join-Path $root 'config/deploy.json')|Should -BeFalse
    }
    It 'refuses a changed draft before publication' {
        Add-Content $draft ' '
        {Publish-ALServerSetupConfiguration $resolved}|Should -Throw '*changed*'
        Test-Path (Join-Path $root 'config/deploy.json')|Should -BeFalse
    }
}
Describe 'Offline component repair preserves damaged payload and recovery proof' {
    BeforeEach {
        $work=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work|Out-Null
        $config=[pscustomobject]@{Root=$work;ConfigFile=(Join-Path $work 'deploy.json');WorkRoot=$work;ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens';StopTimeoutSeconds=10;BackupRoot=$work;DataDirectory=$work}
        $resolved=[pscustomobject]@{Config=$config;ConfigSha256=('a'*64)}
        Mock -ModuleName AuthLens.Deploy Enter-ALLock {}
        Mock -ModuleName AuthLens.Deploy Exit-ALLock {}
        Mock -ModuleName AuthLens.Deploy Get-ALServerRepairPlan {
            [pscustomobject]@{previous='retained-damaged-release';manifest=[pscustomobject]@{source_sha=('a'*40);version='2.0.0-alpha.1'}}
        }
        Mock -ModuleName AuthLens.Deploy Save-ALInstallerRecoveryTools {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {
            param($ExePath,$Arguments)
            if($Arguments[0] -eq '--backup-local'){[pscustomobject]@{file='encrypted.slbak';sha256='verified';size=100}}
            else{[pscustomobject]@{verified=$true;sha256='verified'}}
        }
        Mock -ModuleName AuthLens.Deploy Publish-ALRelease {'new-verified-release'}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Stopped'}}
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink {'current'}
        Mock -ModuleName AuthLens.Deploy Set-ALLink {}
        Mock -ModuleName AuthLens.Deploy Grant-ALAccess {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Install-ALService {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady {}
    }
    It 'verifies backup before activation and retains old payload plus completed journal' {
        $result=Invoke-ALInstallerServerRepair $resolved $work
        $result.repaired|Should -BeTrue
        $result.preserved_damaged_release|Should -Be 'retained-damaged-release'
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALLink -Times 1 -ParameterFilter {$Target -eq 'new-verified-release'}
        (Get-Content (Join-Path $result.run 'repair-journal.json') -Raw|ConvertFrom-Json).phase|Should -Be 'complete'
        Test-Path (Join-Path $work 'repair-pending.json')|Should -BeFalse
    }
    It 'never publishes or switches after backup verification fails' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{file='encrypted.slbak';sha256='different';verified=$false}}
        {Invoke-ALInstallerServerRepair $resolved $work}|Should -Throw '*backup verification failed*'
        Should -Invoke -ModuleName AuthLens.Deploy Publish-ALRelease -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALLink -Times 0
    }
    It 'recreates missing registration only after the verified candidate is activated' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;State='Missing'}}
        Mock -ModuleName AuthLens.Deploy Install-ALService {
            Should -Invoke -ModuleName AuthLens.Deploy Set-ALLink -Times 1
        }
        (Invoke-ALInstallerServerRepair $resolved $work).repaired|Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Install-ALService -Times 1
    }
    It 'retains an explicit recovery barrier and attempts service stop on readiness failure' {
        Mock -ModuleName AuthLens.Deploy Wait-ALReady {throw 'synthetic readiness failure'}
        {Invoke-ALInstallerServerRepair $resolved $work}|Should -Throw '*did not verify readiness*'
        Test-Path (Join-Path $work 'repair-pending.json')|Should -BeTrue
        $journalPath=Get-Content (Join-Path $work 'repair-pending.json') -Raw
        (Get-Content $journalPath -Raw|ConvertFrom-Json).phase|Should -Be 'manual_recovery_required'
        {Assert-ALNoPendingRepair $config}|Should -Throw '*pending offline repair*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 1
    }
    It 'does not activate when a concurrent service start is detected' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Running'}}
        {Invoke-ALInstallerServerRepair $resolved $work}|Should -Throw '*did not verify readiness*'
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALLink -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        Test-Path (Join-Path $work 'repair-pending.json')|Should -BeTrue
    }
}
Describe 'Offline repair preflight refuses unsafe entry states' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $previous=Join-Path $root 'releases/old';$package=Join-Path $root 'package'
        New-Item -ItemType Directory -Path $previous,$package,(Join-Path $root 'data') -Force|Out-Null
        foreach($folder in $previous,$package){Set-Content -LiteralPath (Join-Path $folder 'build-manifest.json') 'same reviewed manifest'}
        $config=[pscustomobject]@{Root=$root;WorkRoot=(Join-Path $root 'deployment');ReleasesRoot=(Join-Path $root 'releases');ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens';DataDirectory=(Join-Path $root 'data')}
        $resolved=[pscustomobject]@{Config=$config;ConfigSha256='reviewed'}
        Mock -ModuleName AuthLens.Deploy Assert-ALServerSetupFingerprint {}
        Mock -ModuleName AuthLens.Deploy Assert-ALInstallerServerConfiguration {}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Get-ALAclPlan {@()}
        Mock -ModuleName AuthLens.Deploy Read-ALJournal {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Stopped';Account='NT SERVICE\AuthLens';PathName='synthetic'}}
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary {$true}
        Mock -ModuleName AuthLens.Deploy Compare-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink {'current'}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$previous}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerPackage {[pscustomobject]@{source_sha=('a'*40);version='2.0.0-alpha.1'}}
    }
    It 'refuses a running service before invoking a replacement host' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Running'}}
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*stopped explicitly*'
    }
    It 'refuses a different installed manifest without replacing it' {
        Add-Content (Join-Path $previous 'build-manifest.json') 'changed identity'
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*exact installed manifest*'
        (Get-Content (Join-Path $previous 'build-manifest.json') -Raw)|Should -Match 'changed identity'
    }
    It 'refuses missing registration without a bound product ownership receipt' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;State='Missing'}}
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*matching installed product receipt*'
        Should -Invoke -ModuleName AuthLens.Deploy Get-ALInstallerPackage -Times 0
    }
    It 'refuses a missing database instead of initializing empty storage' {
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*missing database*'
        Test-Path (Join-Path $config.DataDirectory 'authlens.sqlite3')|Should -BeFalse
    }
    It 'allows missing virtual-account registration with exact retained receipt and compatible database' {
        $config|Add-Member ConfigFile (Join-Path $root 'deploy.json')
        $config|Add-Member BackupRoot (Join-Path $root 'backups')
        $config|Add-Member ListenAddress '127.0.0.1'
        $config|Add-Member Port 18795
        $config|Add-Member CertificatePath (Join-Path $root 'server.pfx')
        $config|Add-Member AllowedHosts @()
        $config|Add-Member ProxyHosts @()
        $config|Add-Member TrustedProxies @()
        $resolved|Add-Member ProgramDirectory $previous
        Set-Content (Join-Path $config.DataDirectory 'authlens.sqlite3') 'synthetic database'
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;State='Missing'}}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerServerIdentity {
            [pscustomobject]@{service_account=$config.ServiceAccount;data_directory=$config.DataDirectory;config_file=$config.ConfigFile;config_sha256='reviewed';manifest_sha256=(Get-FileHash (Join-Path $previous 'build-manifest.json')).Hash.ToLowerInvariant()}
        }
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {
            [pscustomobject]@{validated=$true;read_only=$true;source_sha=('a'*40);version='2.0.0-alpha.1';schema=[pscustomobject]@{pending=@()}}
        }
        (Get-ALServerRepairPlan $resolved $package).operation|Should -Be 'offline repair'
        $config.ServiceAccount='LAB\dedicated'
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*default virtual service account*'
    }
    It 'honors a pending repair marker before evaluating service or package ownership' {
        New-Item -ItemType Directory -Path $config.WorkRoot|Out-Null
        Set-Content (Join-Path $config.WorkRoot 'repair-pending.json') 'retained journal reference'
        {Get-ALServerRepairPlan $resolved $package}|Should -Throw '*pending offline repair*'
        Should -Invoke -ModuleName AuthLens.Deploy Get-ALInstallerPackage -Times 0
    }
}
