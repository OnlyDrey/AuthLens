BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
# Read-only status diagnostics on synthetic files. The key file holds no key material; its DACL is changed only in TestDrive.
Describe 'Backup-key service access diagnostic' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    BeforeEach {
        $script:Data = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:Data | Out-Null
        $script:Key = Join-Path $script:Data 'synthetic.key'
        [IO.File]::WriteAllText($script:Key, 'synthetic-not-a-key')
        $script:Config = [pscustomobject]@{ DataDirectory = $script:Data; ServiceAccount = 'NT AUTHORITY\LocalService' }
    }
    BeforeAll {
    function script:Set-SyntheticRule([string]$Rights, [string]$Type) {
        $info = [IO.FileInfo]::new($script:Key)
        $acl = if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::GetAccessControl($info, [Security.AccessControl.AccessControlSections]::Access) } else { $info.GetAccessControl([Security.AccessControl.AccessControlSections]::Access) }
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-19'), $Rights, $Type))
        if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::SetAccessControl($info, $acl) } else { $info.SetAccessControl($acl) }
    }
    }

    It 'distinguishes unconfigured, missing, unreadable and readable keys without opening the key' {
        Get-ALKeyServiceAccess $script:Config | Should -Be 'not_configured'
        [IO.File]::WriteAllText((Join-Path $script:Data 'backup-key-location.json'), (@{ schema = 1; path = (Join-Path $script:Data 'absent.key') } | ConvertTo-Json))
        Get-ALKeyServiceAccess $script:Config | Should -Be 'missing'
        [IO.File]::WriteAllText((Join-Path $script:Data 'backup-key-location.json'), (@{ schema = 1; path = $script:Key } | ConvertTo-Json))
        Get-ALKeyServiceAccess $script:Config | Should -Be 'not_readable'
        Set-SyntheticRule 'Read' 'Allow'
        Get-ALKeyServiceAccess $script:Config | Should -Be 'readable'
        Set-SyntheticRule 'ReadData' 'Deny'
        Get-ALKeyServiceAccess $script:Config | Should -Be 'not_readable'
    }

    It 'treats LocalSystem as readable and an unknown identity as unresolved' {
        [IO.File]::WriteAllText((Join-Path $script:Data 'backup-key-location.json'), (@{ schema = 1; path = $script:Key } | ConvertTo-Json))
        Get-ALKeyServiceAccess ([pscustomobject]@{ DataDirectory = $script:Data; ServiceAccount = 'NT AUTHORITY\SYSTEM' }) | Should -Be 'readable'
        Get-ALKeyServiceAccess ([pscustomobject]@{ DataDirectory = $script:Data; ServiceAccount = 'AUTHLENS-NO-SUCH-DOMAIN\synthetic' }) | Should -Be 'identity_unresolved'
    }
}
