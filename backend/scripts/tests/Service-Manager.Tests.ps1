BeforeAll {
    $script:Manager = Join-Path $PSScriptRoot '../Service-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:Ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script:Manager), [ref]$tokens, [ref]$errors)
    if ($errors) { throw 'Service Manager syntax errors' }
    # Load pure functions only. Never execute the menu, a key command, a service query or a host process.
    foreach ($name in 'Get-AuthLensAdminArguments', 'Get-AuthLensFileAcl', 'Set-AuthLensFileAcl', 'Resolve-AuthLensServiceSid', 'Grant-AuthLensKeyRead', 'Test-AuthLensKeyRead', 'Get-AuthLensKeyLocation') {
        $definition = $script:Ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}
Describe 'Packaged local Service Manager' {
    It 'uses packaged maintenance commands with file paths, never secret arguments or SDK projects' {
        @(Get-AuthLensAdminArguments 'ExportKey' 'C:\private\data' 'D:\recovery\copy.key' '') | Should -Be @('--backup-key','export','D:\recovery\copy.key','--data-dir','C:\private\data')
        @(Get-AuthLensAdminArguments 'VerifyKey' 'C:\private\data' 'D:\recovery\copy.key' '') | Should -Be @('--backup-key','verify','D:\recovery\copy.key','--data-dir','C:\private\data')
        @(Get-AuthLensAdminArguments 'RecoveryCode' 'C:\private\data' '' 'admin.synthetic') | Should -Be @('--accounts-code','--recover-administrator','admin.synthetic','--data-dir','C:\private\data')
        { Get-AuthLensAdminArguments 'CreateKey' 'C:\private\data' 'relative.key' '' } | Should -Throw '*absolute*'
        $commands = @($script:Ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        foreach ($name in 'dotnet', 'Stop-Service', 'Start-Service', 'New-Service', 'Remove-Item', 'Get-Content', 'icacls') { $commands | Should -Not -Contain $name }
    }
    It 'ships with release checksums and the server installer' {
        foreach ($name in 'build-release.ps1','build-release.sh') { Get-Content (Join-Path $PSScriptRoot "../$name") -Raw | Should -Match 'Service-Manager.ps1' }
        Get-Content (Join-Path $PSScriptRoot '../../installer/AuthLens-Server.iss') -Raw | Should -Match 'AuthLens Service Manager'
    }
}

Describe 'Recovery-key access for the service identity' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    BeforeEach {
        # A synthetic key-shaped file with a protected ACL (current user only), as Service Manager and BackupKeys create it. No key material.
        $script:Folder = Join-Path ([IO.Path]::GetTempPath()) ('authlens-key-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder | Out-Null
        $script:Key = Join-Path $script:Folder 'synthetic.key'
        [IO.File]::WriteAllText($script:Key, 'synthetic-not-a-key')
        $acl = Get-AuthLensFileAcl $script:Key
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) { $null = $acl.RemoveAccessRule($rule) }
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'Allow'))
        Set-AuthLensFileAcl $script:Key $acl
        $script:LocalService = [Security.Principal.SecurityIdentifier]::new('S-1-5-19')
    }
    AfterEach { [IO.Directory]::Delete($script:Folder, $true) }

    It 'resolves built-in service identities and refuses unknown ones' {
        (Resolve-AuthLensServiceSid 'LocalSystem').Value | Should -Be 'S-1-5-18'
        (Resolve-AuthLensServiceSid 'NT AUTHORITY\LocalService').Value | Should -Be 'S-1-5-19'
        (Resolve-AuthLensServiceSid 'NT AUTHORITY\NetworkService').Value | Should -Be 'S-1-5-20'
        { Resolve-AuthLensServiceSid '' } | Should -Throw '*not installed*'
        { Resolve-AuthLensServiceSid 'AUTHLENS-NO-SUCH-DOMAIN\synthetic-nobody' } | Should -Throw '*could not be resolved*'
    }

    It 'adds exactly one explicit read rule for the service identity on the key file' {
        $before = @((Get-AuthLensFileAcl $script:Key).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Test-AuthLensKeyRead $script:Key $script:LocalService | Should -BeFalse
        Grant-AuthLensKeyRead $script:Key $script:LocalService | Should -Be 'granted'
        $acl = Get-AuthLensFileAcl $script:Key
        $acl.AreAccessRulesProtected | Should -BeTrue
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        $rules.Count | Should -Be ($before.Count + 1)
        $granted = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-19' })
        $granted.Count | Should -Be 1
        $granted[0].IsInherited | Should -BeFalse
        $granted[0].AccessControlType | Should -Be 'Allow'
        ($granted[0].FileSystemRights -band -bnot [Security.AccessControl.FileSystemRights]::Synchronize) | Should -Be ([Security.AccessControl.FileSystemRights]::Read)
        Test-AuthLensKeyRead $script:Key $script:LocalService | Should -BeTrue
        Grant-AuthLensKeyRead $script:Key $script:LocalService | Should -Be 'already_granted'
        @((Get-AuthLensFileAcl $script:Key).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])).Count | Should -Be ($before.Count + 1)
        # The directory itself receives no grant.
        @((Get-Acl -LiteralPath $script:Folder).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-19' }).Count | Should -Be 0
    }

    It 'reports a deny rule as not readable, needs no grant for SYSTEM and refuses directories' {
        $acl = Get-AuthLensFileAcl $script:Key
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($script:LocalService, 'Read', 'Allow'))
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($script:LocalService, 'ReadData', 'Deny'))
        Set-AuthLensFileAcl $script:Key $acl
        Test-AuthLensKeyRead $script:Key $script:LocalService | Should -BeFalse
        Grant-AuthLensKeyRead $script:Key ([Security.Principal.SecurityIdentifier]::new('S-1-5-18')) | Should -Be 'not_required'
        { Grant-AuthLensKeyRead $script:Folder $script:LocalService } | Should -Throw '*regular file*'
    }

    It 'reads the configured key path from the location record only' {
        Get-AuthLensKeyLocation $script:Folder | Should -Be ''
        [IO.File]::WriteAllText((Join-Path $script:Folder 'backup-key-location.json'), (@{ schema = 1; path = $script:Key } | ConvertTo-Json))
        Get-AuthLensKeyLocation $script:Folder | Should -Be $script:Key
    }
}

Describe 'QA-028 recovery bundle and WP34 inventory actions in Service Manager' {
    BeforeAll {
        foreach ($name in 'Invoke-AuthLensRecoveryBundle', 'ConvertFrom-AuthLensPathInput') {
            $definition = $script:Ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
    BeforeEach {
        $script:installed = [pscustomobject]@{ config_file = 'C:\ProgramData\AuthLens\config\deploy.json'; root = 'C:\ProgramData\AuthLens'; data_directory = 'C:\ProgramData\AuthLens\data' }
        function Test-AuthLensAdminElevation { $true }
        function Get-AuthLensInstalledRecoveryTool { 'C:\synthetic\tools\recovery\New-AuthLensRecoveryBundle.ps1' }
        $script:Path = ''; $script:Directory = ''
    }
    It 'requires an explicit destination outside the installation and explicit approval before running anything' {
        { Invoke-AuthLensRecoveryBundle 'CreateRecoveryBundle' $true } | Should -Throw '*Select the recovery root explicitly*'
        $script:Directory = 'C:\ProgramData\AuthLens\recovery'
        { Invoke-AuthLensRecoveryBundle 'CreateRecoveryBundle' $true } | Should -Throw '*outside the installation*'
        $script:Directory = 'D:\AuthLens-Recovery'
        { Invoke-AuthLensRecoveryBundle 'CreateRecoveryBundle' $false } | Should -Throw '*Repeat with -Yes*'
        { Invoke-AuthLensRecoveryBundle 'VerifyRecoveryBundle' $true } | Should -Throw '*Select the recovery bundle folder*'
    }
    It 'reuses the tracked recovery tooling and never deletes, restores or prunes' {
        $source = Get-Content -LiteralPath $script:Manager -Raw
        $source | Should -Match "'recovery\\New-AuthLensRecoveryBundle.ps1'"
        $source | Should -Match "'-VerifyBundle'"
        $source | Should -Match 'not a restore'
        $source | Should -Not -Match "'-Action', 'PruneArtifacts'"
        $source | Should -Match "'-Action', 'ArtifactInventory'"
    }
}
