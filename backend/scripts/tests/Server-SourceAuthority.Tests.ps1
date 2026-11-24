BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Protected server source authority provisioning' {
    It 'uses a deterministic sibling outside data without modifying existing data' {
        $config=[pscustomobject]@{DataDirectory=(Join-Path $TestDrive 'data')}
        $one=Get-ALSourceAuthorityDirectory $config
        $one|Should -Be (Get-ALSourceAuthorityDirectory $config)
        (Split-Path $one)|Should -Be $TestDrive.ToUpperInvariant()
        (Split-Path $one -Leaf)|Should -Match '^\.authlens-source-policy-[a-f0-9]{16}$'
        Test-Path -LiteralPath $one|Should -BeFalse
    }
    It 'provisions only a private test folder and refuses unrelated principals' -Skip:([IO.Path]::DirectorySeparatorChar -ne '\') {
        $root=Join-Path $TestDrive 'private-fixture'
        New-Item -ItemType Directory -Path $root|Out-Null
        $config=[pscustomobject]@{DataDirectory=(Join-Path $root 'data');ServiceAccount=[Security.Principal.WindowsIdentity]::GetCurrent().Name}
        # Replace only the native parent policy in this disposable fixture; no application installation is used.
        Mock -ModuleName AuthLens.Deploy Test-ALProvisioningAncestor {$true}
        Initialize-ALSourceAuthorityDirectory $config
        $path=Get-ALSourceAuthorityDirectory $config
        (Get-Acl -LiteralPath $path).AreAccessRulesProtected|Should -BeTrue
        Initialize-ALSourceAuthorityDirectory $config
        $acl=Get-Acl -LiteralPath $path
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'))
        $accessOnly=[Security.AccessControl.DirectorySecurity]::new()
        $accessOnly.SetSecurityDescriptorSddlForm($acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),[Security.AccessControl.AccessControlSections]::Access)
        [IO.Directory]::SetAccessControl($path,$accessOnly)
        {Initialize-ALSourceAuthorityDirectory $config}|Should -Throw '*unrecognized principal*'
    }
}
