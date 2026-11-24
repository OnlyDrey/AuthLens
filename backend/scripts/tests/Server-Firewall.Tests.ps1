BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    function New-TestFirewallState($Record) {
        [pscustomobject]@{name=$Record.name;group='AuthLens Setup';direction='Inbound';action='Allow';enabled=$true;profiles=($Record.plan.profiles -join ', ');edge='Block';protocol='TCP';local_ports=@([string]$Record.plan.port);remote_ports=@('Any');local_addresses=@($Record.plan.local_address);remote_addresses=@($Record.plan.remote_addresses);service='AuthLens';program='Any';authentication='NotRequired';encryption='NotRequired';override_block=$false;local_user='Any';remote_user='Any';remote_machine='Any';interfaces=@('Any');interface_type='Any'}
    }
}
Describe 'Firewall ownership and transactional lifecycle' {
    BeforeEach {
        $work=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work|Out-Null
        $config=[pscustomobject]@{Root=$work;WorkRoot=$work;ListenAddress='10.1.2.3';Port=18795;ServiceName='AuthLens'}
        $old=[pscustomobject]@{schema=1;owner='AuthLens Setup';name=('AuthLens-Setup-'+('a'*32));root=$work;phase='applied';plan=[pscustomobject]@{required=$true;local_address='10.1.2.3';port=18795;profiles=@('Private');remote_addresses=@('10.1.2.10')}}
        $old|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $work ('firewall-'+('a'*32)+'.json')) -Encoding UTF8
        $states=@{};$states[$old.name]=New-TestFirewallState $old
        $states['administrator-rule']=[pscustomobject]@{name='administrator-rule';enabled=$true}
        $events=[Collections.Generic.List[string]]::new()
        Mock -ModuleName AuthLens.Deploy Enter-ALLock {}
        Mock -ModuleName AuthLens.Deploy Exit-ALLock {}
        Mock -ModuleName AuthLens.Deploy Get-ALNativeFirewallState {param($Name) if($states.ContainsKey($Name)){$states[$Name]}}
        Mock -ModuleName AuthLens.Deploy Disable-NetFirewallRule {param($Name) $events.Add('disable');$states[@($Name)[0]].enabled=$false}
        Mock -ModuleName AuthLens.Deploy Enable-NetFirewallRule {param($Name) $events.Add('enable');$states[@($Name)[0]].enabled=$true}
        Mock -ModuleName AuthLens.Deploy Remove-NetFirewallRule {param($Name) $events.Add('remove');$states.Remove(@($Name)[0])}
        Mock -ModuleName AuthLens.Deploy New-ALNativeOwnedFirewallRule {param($Config,$Record) $events.Add('create');$states[$Record.name]=New-TestFirewallState $Record}
    }
    It 'disables the old scope before creating a replacement and preserves administrator rules' {
        $result=Invoke-ALInstallerFirewallChange $config '10.1.2.20' 'Private' -Approved
        $result.changed|Should -BeTrue
        $states.ContainsKey($old.name)|Should -BeFalse
        $states[$result.rule].remote_addresses|Should -Contain '10.1.2.20'
        ($events -join ',')|Should -Be 'disable,create,remove'
        $states.ContainsKey('administrator-rule')|Should -BeTrue
        Test-Path -LiteralPath (Join-Path $work 'firewall-pending.json')|Should -BeFalse
        @(Get-ALOwnedFirewallReceipts $config)[0].Count|Should -Be 1
    }
    It 'removes only verified owned rules and retains receipts' {
        $result=Invoke-ALInstallerFirewallChange $config '' -Remove -Approved
        $result.removed|Should -BeTrue
        $states.ContainsKey($old.name)|Should -BeFalse
        $states.ContainsKey('administrator-rule')|Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $work ('firewall-'+('a'*32)+'.json')) -Raw|ConvertFrom-Json).phase|Should -Be 'removed'
    }
    It 'preserves a rule whose addresses were changed by an administrator' {
        $states[$old.name].remote_addresses=@('10.1.2.99')
        {Invoke-ALInstallerFirewallChange $config '10.1.2.20' -Approved}|Should -Throw '*addresses differ*'
        $events.Count|Should -Be 0
        $states[$old.name].remote_addresses|Should -Contain '10.1.2.99'
    }
    It 'preserves administrator changes to service binding, security and interface filters' {
        $states[$old.name].authentication='Required'
        {Invoke-ALInstallerFirewallChange $config '' -Remove -Approved}|Should -Throw '*administrator changes were preserved*'
        $events.Count|Should -Be 0
    }
    It 'requires explicit security approval before disabling anything' {
        {Invoke-ALInstallerFirewallChange $config '10.1.2.20'}|Should -Throw '*security approval*'
        $events.Count|Should -Be 0
    }
    It 'retains a fail-closed interrupted transition then completes the latest approved scope' {
        Mock -ModuleName AuthLens.Deploy New-ALNativeOwnedFirewallRule {throw 'synthetic creation failure'}
        {Invoke-ALInstallerFirewallChange $config '10.1.2.20' -Approved}|Should -Throw '*transition did not complete*'
        $states[$old.name].enabled|Should -BeFalse
        Test-Path -LiteralPath (Join-Path $work 'firewall-pending.json')|Should -BeTrue
        {Assert-ALNoPendingRepair $config}|Should -Throw '*pending firewall transition*'
        Mock -ModuleName AuthLens.Deploy New-ALNativeOwnedFirewallRule {param($Config,$Record) $events.Add('create');$states[$Record.name]=New-TestFirewallState $Record}
        $recovery=Invoke-ALInstallerFirewallRecover $config
        $recovery.firewall_transition_verified|Should -BeTrue
        $recovery.firewall_rollback_verified|Should -BeFalse
        $states.ContainsKey($old.name)|Should -BeFalse
        @($states.Values|Where-Object{$_.name -like 'AuthLens-Setup-*'})[0].remote_addresses|Should -Contain '10.1.2.20'
    }
    It 'verifies actual previous scope restoration when rollback is explicitly requested' {
        Mock -ModuleName AuthLens.Deploy New-ALNativeOwnedFirewallRule {throw 'synthetic creation failure'}
        {Invoke-ALInstallerFirewallChange $config '10.1.2.20' -Approved}|Should -Throw '*transition did not complete*'
        $states[$old.name].enabled|Should -BeFalse
        $result=Invoke-ALInstallerFirewallRecover $config -Rollback
        $result.firewall_rollback_verified|Should -BeTrue
        $states[$old.name].enabled|Should -BeTrue
        $states[$old.name].remote_addresses|Should -Contain '10.1.2.10'
        Test-Path -LiteralPath (Join-Path $work 'firewall-pending.json')|Should -BeFalse
    }
    It 'refuses forged ownership roots before native changes' {
        $recordPath=Join-Path $work ('firewall-'+('a'*32)+'.json')
        $old.root=Join-Path $TestDrive 'unrelated'
        $old|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $recordPath -Encoding UTF8
        {Invoke-ALInstallerFirewallChange $config '' -Remove -Approved}|Should -Throw '*ownership receipt is invalid*'
        $events.Count|Should -Be 0
    }
}
Describe 'Canonical firewall address comparison' {
    It 'compares CIDR, netmask and host forms without broadening scope' {
        (Get-ALFirewallAddressIdentity '10.1.2.10/24')|Should -Be (Get-ALFirewallAddressIdentity '10.1.2.0/255.255.255.0')
        (Get-ALFirewallAddressIdentity '10.1.2.10')|Should -Be (Get-ALFirewallAddressIdentity '10.1.2.10/32')
        (Get-ALFirewallAddressIdentity 'fd00::123/64')|Should -Be (Get-ALFirewallAddressIdentity 'fd00::/64')
        {Get-ALFirewallAddressIdentity 'Any'}|Should -Throw '*identity*'
        {Get-ALFirewallAddressIdentity '10.0.0.0/0'}|Should -Throw '*Unrestricted*'
        {Get-ALFirewallAddressIdentity '10.0.0.0/255.0.255.0'}|Should -Throw '*not contiguous*'
    }
}
