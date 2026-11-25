BeforeAll {
    $script:Manager = Join-Path $PSScriptRoot '../Service-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:Ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script:Manager), [ref]$tokens, [ref]$errors)
    if ($errors) { throw 'Service Manager syntax errors' }
    # Functions only: the menu, the dispatch, the packaged host and the deployment tools never run here (host and tools are replaced below).
    foreach ($node in $script:Ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) { . ([scriptblock]::Create($node.Extent.Text)) }
    $script:DeployModule = (Resolve-Path (Join-Path $PSScriptRoot '../deploy/AuthLens.Deploy.psm1')).ProviderPath
}

# WP19 / D-005: recovery-key destinations are validated completely before anything runs.
Describe 'Service Manager recovery-key destinations' {
    BeforeEach {
        $script:Data = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force $script:Data | Out-Null
        $script:Target = Join-Path $TestDrive ('Recovery keys ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Force $script:Target | Out-Null
    }
    It 'uses the host-based default name and adds the .key extension exactly once' {
        (Resolve-AuthLensKeyTarget '' $script:Target '' $script:Data).path | Should -Be (Join-Path $script:Target "AuthLens-$($env:COMPUTERNAME)-recovery.key")
        (Resolve-AuthLensKeyTarget '' $script:Target 'dash1-copy' $script:Data).path | Should -Be (Join-Path $script:Target 'dash1-copy.key')
        (Resolve-AuthLensKeyTarget '' $script:Target 'dash1-copy.key' $script:Data).path | Should -Be (Join-Path $script:Target 'dash1-copy.key')
        (Resolve-AuthLensKeyTarget '' $script:Target 'DASH1.KEY' $script:Data).path | Should -Be (Join-Path $script:Target 'DASH1.KEY')
        (Resolve-AuthLensKeyTarget '' $script:Target 'archive.key.backup' $script:Data).path | Should -Be (Join-Path $script:Target 'archive.key.backup.key')
    }
    It 'accepts paths with spaces and pasted quotes' {
        $resolved = Resolve-AuthLensKeyTarget '' ('"' + $script:Target + '\"') ' "copy" ' $script:Data
        $resolved.path | Should -Be (Join-Path $script:Target 'copy.key')
        $resolved.directory_exists | Should -BeTrue
    }
    It 'refuses a directory as the file, relative paths, invalid names, the data directory and existing files' {
        { Resolve-AuthLensKeyTarget $script:Target '' '' $script:Data } | Should -Throw '*is a folder. Add a file name, for example*recovery.key*'
        { Resolve-AuthLensKeyTarget 'relative\copy.key' '' '' $script:Data } | Should -Throw '*absolute recovery-key file path*'
        { Resolve-AuthLensKeyTarget '' 'relative' 'copy' $script:Data } | Should -Throw '*absolute folder*'
        { Resolve-AuthLensKeyTarget '' $script:Target 'a:b' $script:Data } | Should -Throw '*does not allow*'
        { Resolve-AuthLensKeyTarget '' $script:Target 'sub\copy' $script:Data } | Should -Throw '*does not allow*'
        { Resolve-AuthLensKeyTarget '' $script:Target 'NUL' $script:Data } | Should -Throw '*reserved*'
        { Resolve-AuthLensKeyTarget '' $script:Data 'copy' $script:Data } | Should -Throw '*outside the application data directory*'
        Set-Content (Join-Path $script:Target 'existing.key') 'synthetic-existing' -Encoding ASCII
        { Resolve-AuthLensKeyTarget '' $script:Target 'existing' $script:Data } | Should -Throw '*already exists*never overwritten*'
        Get-Content (Join-Path $script:Target 'existing.key') | Should -Be 'synthetic-existing'
        { Resolve-AuthLensKeyTarget (Join-Path $script:Target 'x.key') $script:Target 'y' $script:Data } | Should -Throw '*either -Path or -Directory*'
    }
    It 'keeps the exact -Path contract of automation' {
        (Resolve-AuthLensKeyTarget (Join-Path $script:Target 'host-copy') '' '' $script:Data).path | Should -Be (Join-Path $script:Target 'host-copy')
    }
    It 'refuses destinations that traverse a junction' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
        $junction = Join-Path $TestDrive ('junction-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Junction -Path $junction -Target $script:Target | Out-Null
        try { { Resolve-AuthLensKeyTarget '' $junction 'copy' $script:Data } | Should -Throw '*junction or symbolic link*' }
        finally { [IO.Directory]::Delete($junction) }
    }
    It 'detects folders this session cannot write to' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
        Test-AuthLensDirectoryWritable $script:Target | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:Target -Force).Count | Should -Be 0 -Because 'the write probe is removed'
        $info = [IO.DirectoryInfo]::new($script:Target)
        $acl = $info.GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
        $deny = [Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User, 'CreateFiles', 'Deny')
        $acl.AddAccessRule($deny); $info.SetAccessControl($acl)
        try { Test-AuthLensDirectoryWritable $script:Target | Should -BeFalse }
        finally { $acl.RemoveAccessRule($deny) | Out-Null; $info.SetAccessControl($acl) }
    }
}

Describe 'Service Manager recovery-key export workflow' {
    BeforeEach {
        $script:DataDirectory = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force $script:DataDirectory | Out-Null
        $script:Executable = Join-Path $TestDrive 'AuthLens.Api.exe'; Set-Content $script:Executable 'synthetic' -Encoding ASCII
        $script:Directory = ''; $script:FileName = ''; $script:CreateDirectory = $false
        $script:Calls = [Collections.Generic.List[string]]::new()
        Mock Test-AuthLensAdminElevation { $true }
        Mock Write-AuthLensKeyAccess {}
        # The packaged host is replaced: it records its arguments and writes a synthetic file for export; it never sees or prints key material.
        Mock Invoke-AuthLensHost {
            $script:Calls.Add(($Arguments -join ' '))
            if ($Arguments[1] -eq 'export') { Set-Content -LiteralPath $Arguments[2] 'synthetic-not-a-key' -Encoding ASCII; return [pscustomobject]@{ lines = @('{"exported":true,"fingerprint":"0011","escrow_verification_required":true}'); code = 0 } }
            if ($Arguments[1] -eq 'verify') { return [pscustomobject]@{ lines = @('{"escrow_verified":true,"fingerprint":"0011"}'); code = 0 } }
            [pscustomobject]@{ lines = @('{}'); code = 0 }
        }
    }
    It 'validates the destination before -Yes and before the host runs' {
        { Invoke-AuthLensLocalAdmin 'ExportKey' $script:DataDirectory '' $true } | Should -Throw '*is a folder*'
        { Invoke-AuthLensLocalAdmin 'ExportKey' (Join-Path $TestDrive 'x.key') '' $false } | Should -Throw '*Repeat with -Yes*'
        Should -Invoke Invoke-AuthLensHost -Times 0
    }
    It 'exports, then verifies the same copy automatically and prints storage guidance without key material' {
        $folder = Join-Path $TestDrive 'Off host copies'; New-Item -ItemType Directory -Force $folder | Out-Null
        $script:Directory = $folder; $script:FileName = 'dash1'
        $output = Invoke-AuthLensLocalAdmin 'ExportKey' '' '' $true 6>&1 | ForEach-Object { "$_" }
        $file = Join-Path $folder 'dash1.key'
        @($script:Calls) | Should -Be @("--backup-key export $file --data-dir $($script:DataDirectory)", "--backup-key verify $file --data-dir $($script:DataDirectory)")
        ($output -join "`n") | Should -Match 'Recovery copy written and verified'
        ($output -join "`n") | Should -Match 'off this server'
        ($output -join "`n") | Should -Not -Match 'synthetic-not-a-key'
    }
    It 'refuses a missing folder unless creation is confirmed, then creates it with a protected ACL' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
        $folder = Join-Path $TestDrive ('new folder ' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $script:Directory = $folder; $script:FileName = ''
        { Invoke-AuthLensLocalAdmin 'ExportKey' '' '' $true } | Should -Throw '*does not exist*-CreateDirectory*'
        Test-Path $folder | Should -BeFalse
        Should -Invoke Invoke-AuthLensHost -Times 0
        $script:CreateDirectory = $true
        $null = Invoke-AuthLensLocalAdmin 'ExportKey' '' '' $true 6>&1
        ([IO.DirectoryInfo]::new($folder)).GetAccessControl().AreAccessRulesProtected | Should -BeTrue
        Test-Path (Join-Path $folder "AuthLens-$($env:COMPUTERNAME)-recovery.key") | Should -BeTrue
    }
    It 'reports a failed verification instead of claiming success' {
        Mock Invoke-AuthLensHost { if ($Arguments[1] -eq 'verify') { throw 'AuthLens refused the local operation: The recovery copy does not match the host key.' }; Set-Content -LiteralPath $Arguments[2] 'synthetic' -Encoding ASCII; [pscustomobject]@{ lines = @('{}'); code = 0 } }
        $folder = Join-Path $TestDrive 'verify-fails'; New-Item -ItemType Directory -Force $folder | Out-Null
        $script:Directory = $folder; $script:FileName = 'copy'
        { Invoke-AuthLensLocalAdmin 'ExportKey' '' '' $true } | Should -Throw '*does not match the host key*'
    }
}

Describe 'Service Manager menu behaviour' {
    It 'treats B as cancel at every prompt and keeps the default on empty input' {
        Mock Read-Host { 'B' }
        { Read-AuthLensInput 'Destination folder' } | Should -Throw '*Cancelled; nothing was changed*'
        Mock Read-Host { '' }
        Read-AuthLensInput 'File name' 'default-name' | Should -Be 'default-name'
    }
    It 'returns to the menu after a failure with an actionable message' {
        Mock Write-AuthLensDiagnostic { 'C:\synthetic\service-manager.log' }
        $output = Invoke-AuthLensMenuAction 'ExportKey' { throw 'AuthLens refused the local operation: Access to the path ''E:\keys'' is denied.' } 6>&1 | ForEach-Object { "$_" }
        ($output -join "`n") | Should -Match 'Access was denied. Run Service Manager as administrator'
        ($output -join "`n") | Should -Match 'Technical details: C:\\synthetic\\service-manager.log'
        { Invoke-AuthLensMenuAction 'Cancel' { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') } } | Should -Not -Throw
    }
}

# G-003 with the D-006 safeguard: the guided preview is always a simulation; execution needs an explicit action, a successful preview and YES.
Describe 'Service Manager guided deployment recovery' {
    BeforeEach {
        $script:installed = [pscustomobject]@{ config_file = 'C:\synthetic\config\deploy.json'; root = 'C:\synthetic'; data_directory = 'C:\synthetic\data'; service_name = 'AuthLens' }
        $script:CertificateFile = ''; $script:CertificatePasswordFile = ''
        $script:DeployCalls = [Collections.Generic.List[string]]::new()
        Mock Get-AuthLensInstalledDeployTool { 'C:\synthetic\tools\deploy\Deploy-AuthLens.ps1' }
        Mock Get-AuthLensInstalledInstaller { 'C:\synthetic\tools\Install-AuthLens.ps1' }
        Mock Assert-AuthLensSimulationSupport {}
        Mock Test-AuthLensAdminElevation { $true }
        Mock Invoke-AuthLensInstallerTool { [pscustomobject]@{ phase = 'complete'; action = 'candidate revalidated' } }
        Mock Invoke-AuthLensDeployTool {
            $script:DeployCalls.Add(($Arguments -join ' '))
            [pscustomobject]@{ exit = 0; result = [pscustomobject]@{ simulation = $true; changes_applied = $false; journal_run = 'r'; journal_phase = 'manual_recovery_required'; history = @('starting', 'manual_recovery_required')
                options = @([pscustomobject]@{ action = 'VerifyCandidate'; available = $true; reason = '' }); would_succeed = $true; would_phase = 'complete'; would_action = 'revalidate the installed candidate'; would_start_service = $false; would_replace_certificate = $false } }
        }
    }
    It 'previews with -DryRun and never -Yes, and stops without confirmation' {
        { Invoke-AuthLensRecoveryWorkflow 'Recover' 'VerifyCandidate' $false } | Should -Throw '*Previewed only*'
        @($script:DeployCalls).Count | Should -Be 1
        $script:DeployCalls[0] | Should -Match '-Action Recover .*-RecoveryAction VerifyCandidate -DryRun'
        $script:DeployCalls[0] | Should -Not -Match '-Yes'
        Should -Invoke Invoke-AuthLensInstallerTool -Times 0
        $null = Invoke-AuthLensRecoveryWorkflow 'DeploymentStatus' 'Auto' $false 6>&1
        Should -Invoke Invoke-AuthLensInstallerTool -Times 0
    }
    It 'runs the confirmed action through the installed Setup tools only after a successful simulation' {
        $null = Invoke-AuthLensRecoveryWorkflow 'Recover' 'VerifyCandidate' $true 6>&1
        Should -Invoke Invoke-AuthLensInstallerTool -Times 1 -ParameterFilter { ($Arguments -join ' ') -eq '-Mode Server -Recover -RecoveryAction VerifyCandidate -ConfigFile C:\synthetic\config\deploy.json -Yes' }
        { Invoke-AuthLensRecoveryWorkflow 'Recover' 'Auto' $true } | Should -Throw '*explicit recovery action*'
    }
    It 'refuses to continue when the preview would refuse or is not a simulation' {
        Mock Invoke-AuthLensDeployTool { [pscustomobject]@{ exit = 2; result = [pscustomobject]@{ simulation = $true; journal_phase = 'manual_recovery_required'; options = @(); would_succeed = $false; blocking_reason = 'synthetic TLS refusal.' } } }
        { Invoke-AuthLensRecoveryWorkflow 'Recover' 'VerifyCandidate' $true } | Should -Throw '*would be refused: synthetic TLS refusal*'
        Mock Invoke-AuthLensDeployTool { [pscustomobject]@{ exit = 0; result = [pscustomobject]@{ recovered = $true; phase = 'complete' } } }
        { Invoke-AuthLensRecoveryWorkflow 'Recover' 'VerifyCandidate' $true } | Should -Throw '*did not identify itself as a simulation*'
        Should -Invoke Invoke-AuthLensInstallerTool -Times 0
    }
    It 'passes a replacement certificate to preview and execution' {
        $script:CertificateFile = 'D:\tls\replacement.pfx'; $script:CertificatePasswordFile = 'D:\tls\replacement-password'
        $null = Invoke-AuthLensRecoveryWorkflow 'Recover' 'VerifyCandidate' $true 6>&1
        $script:DeployCalls[0] | Should -Match '-CertificateFile D:\\tls\\replacement.pfx -CertificatePasswordFile D:\\tls\\replacement-password'
        Should -Invoke Invoke-AuthLensInstallerTool -Times 1 -ParameterFilter { ($Arguments -join ' ') -like '*-RecoveryCertificateFile D:\tls\replacement.pfx -RecoveryCertificatePasswordFile D:\tls\replacement-password*' }
    }
    It 'requires deployment tools that carry the simulation safeguard' {
        $old = Join-Path $TestDrive 'old-tools\deploy'; New-Item -ItemType Directory -Force $old | Out-Null
        Set-Content (Join-Path $old 'AuthLens.Deploy.psm1') '# deployment module without the action policy' -Encoding ASCII
        { & (Get-Command Assert-AuthLensSimulationSupport -CommandType Function).ScriptBlock (Join-Path $old 'Deploy-AuthLens.ps1') } | Should -Throw '*predate the simulation safeguard*'
        { & (Get-Command Assert-AuthLensSimulationSupport -CommandType Function).ScriptBlock (Join-Path (Split-Path $script:DeployModule) 'Deploy-AuthLens.ps1') } | Should -Not -Throw
    }
}

Describe 'Service Manager public certificate destination' {
    It 'applies the default name and .cer extension and refuses existing files' {
        $folder = Join-Path $TestDrive 'public certs'; New-Item -ItemType Directory -Force $folder | Out-Null
        (Resolve-AuthLensCertificateTarget '' $folder '' '').path | Should -Be (Join-Path $folder "AuthLens-$($env:COMPUTERNAME).cer")
        (Resolve-AuthLensCertificateTarget $folder '' '' '').path | Should -Be (Join-Path $folder "AuthLens-$($env:COMPUTERNAME).cer")
        (Resolve-AuthLensCertificateTarget (Join-Path $folder 'server') '' '' '').path | Should -Be (Join-Path $folder 'server.cer')
        Set-Content (Join-Path $folder 'taken.cer') 'x' -Encoding ASCII
        { Resolve-AuthLensCertificateTarget '' $folder 'taken' '' } | Should -Throw '*already exists*'
    }
}
