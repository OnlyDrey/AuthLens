BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}

# G-004: every recovery attempt that acts leaves a durable audit record; history keeps the original entries; simulations never write it.
Describe 'Recovery audit metadata (G-004)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config'), (Join-Path $root 'data'), (Join-Path $root 'deployment'), (Join-Path $root 'releases/candidate') | Out-Null
        $file = Join-Path $root 'config/deploy.json'
        @{ Root = $root; ListenAddress = '127.0.0.1'; Port = 18795 } | ConvertTo-Json | Set-Content $file
        $config = Read-AuthLensSettings $file -Packaged
        $candidate = Join-Path $root 'releases/candidate'
        $sha = 'b' * 40
        @{ product = 'AuthLens'; version = '2.0.0'; source_sha = $sha } | ConvertTo-Json | Set-Content (Join-Path $candidate 'build-manifest.json')
        @{ schema = 1; product = 'AuthLens'; root = $root; data_directory = $config.DataDirectory; instance_id = ('a' * 32) } | ConvertTo-Json | Set-Content (Join-Path $config.DataDirectory '.authlens-owned-data.json')
        Write-ALJournal $config ([pscustomobject]@{ phase = 'manual_recovery_required'; run = 'original-run'; from_release = ''; to_release = $candidate; commit = $sha; version = '2.0.0'; backup = $null; service_binary_before = ''; service_state_before = 'Missing'
            history = @(@{ phase = 'starting'; at = 'a' }, @{ phase = 'manual_recovery_required'; at = 'b' }); updated = '' })
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; Account = $config.ServiceAccount; PathName = 'owned'; ProcessId = 4944 } }
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $candidate }
        Mock -ModuleName AuthLens.Deploy Test-ALPublishedRelease { [pscustomobject]@{ Verified = $true } }
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $true; read_only = $true; data_modified = $false; source_sha = $sha; version = '2.0.0'; schema = [pscustomobject]@{ compatible = $true; pending = @() } } }
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 4944; identity = [pscustomobject]@{ version = '2.0.0'; source_sha = $sha } } }
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions {}
    }
    It 'records action, operator, runs, version, commit, manifest and configuration hashes and the outcome; history is preserved' {
        $null = Get-ALRecoveryPreview $config -RecoveryAction VerifyCandidate
        Test-Path (Get-ALRecoveryAuditPath $config) | Should -BeFalse -Because 'a simulation never writes recovery audit metadata'
        $result = Invoke-ALRecover $config -RecoveryAction VerifyCandidate
        $result.phase | Should -Be 'complete'
        $audit = @(Read-ALRecoveryAudit $config)
        $audit.Count | Should -Be 1
        $record = $audit[0]
        $record.requested_action | Should -Be 'VerifyCandidate'
        $record.decision | Should -Be 'candidate'
        $record.outcome | Should -Be 'succeeded'
        $record.original_run | Should -Be 'original-run'
        $record.phase_before | Should -Be 'manual_recovery_required'
        $record.phase_after | Should -Be 'complete'
        $record.version | Should -Be '2.0.0'
        $record.source_commit | Should -Be $sha
        $record.release | Should -Be 'candidate'
        $record.manifest_sha256 | Should -Be ((Get-FileHash (Join-Path $candidate 'build-manifest.json')).Hash.ToLowerInvariant())
        $record.config_sha256 | Should -Be ((Get-FileHash $file).Hash.ToLowerInvariant())
        $record.operator | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        $record.operator_source | Should -Be 'windows_process_token'
        $record.recorded_utc | Should -Match '^\d{4}-\d{2}-\d{2}T'
        $history = @((Read-ALJournal $config).history)
        @($history | ForEach-Object { $_.phase }) | Should -Be @('starting', 'manual_recovery_required', 'complete')
        $history[0].PSObject.Properties['recovery_action'] | Should -BeNullOrEmpty -Because 'original entries are unchanged'
        $history[2].recovery_action | Should -Be 'VerifyCandidate'
        $history[2].operator | Should -Be $record.operator
        (Get-Content (Get-ALRecoveryAuditPath $config) -Raw) | Should -Not -Match 'cert-password|CertificatePasswordFile'
    }
    It 'records refusals without changing a finished journal, and nothing for "nothing to recover"' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { throw 'synthetic preflight refusal' }
        { Invoke-ALRecover $config -RecoveryAction VerifyCandidate } | Should -Throw '*synthetic preflight refusal*'
        $audit = @(Read-ALRecoveryAudit $config)
        $audit.Count | Should -Be 1
        $audit[0].outcome | Should -BeIn @('refused', 'failed')
        $audit[0].reason | Should -BeLike '*synthetic preflight refusal*'
        $journal = Read-ALJournal $config; Set-ALPhase $config $journal 'complete'
        $null = Invoke-ALRecover $config -RecoveryAction Auto
        @(Read-ALRecoveryAudit $config).Count | Should -Be 1
    }
    It 'records the operator as unknown instead of guessing when no process identity is available' {
        Mock -ModuleName AuthLens.Deploy Get-ALOperatorIdentity { [pscustomobject]@{ name = $null; sid = $null; source = 'unavailable' } }
        $null = Invoke-ALRecover $config -RecoveryAction VerifyCandidate
        $record = @(Read-ALRecoveryAudit $config)[0]
        $record.operator | Should -BeNullOrEmpty
        $record.operator_source | Should -Be 'unavailable'
    }
}

# G-005: Setup registration reconciliation with proven ownership, exercised on disposable HKCU keys (never the machine's HKLM registration).
Describe 'Setup registration reconciliation after recovery (G-005)' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    BeforeEach {
        $base = "Registry::HKEY_CURRENT_USER\Software\AuthLensTests\$([guid]::NewGuid().ToString('N'))"
        $serverKey = "$base\Server"; $uninstallKey = "$base\Uninstall"
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $package = 'AuthLens-2.0.0-synthetic-win-x64'
        $release = Join-Path $root "releases\$package"
        $app = Join-Path $root 'app'
        $staged = Join-Path $app "setup\$package\payload\$package"
        foreach ($dir in $release, $staged, (Join-Path $root 'config')) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $manifestText = '{"product":"AuthLens","version":"2.0.0","source_sha":"cccccccccccccccccccccccccccccccccccccccc","file_version":[2,0,0,0]}'
        foreach ($dir in $release, $staged) { [IO.File]::WriteAllText((Join-Path $dir 'build-manifest.json'), $manifestText) }
        $manifest = $manifestText | ConvertFrom-Json
        $config = [pscustomobject]@{ Root = $root; ConfigFile = (Join-Path $root 'config\deploy.json') }
        New-Item -Path $serverKey -Force | Out-Null
        New-ItemProperty -LiteralPath $serverKey -Name SetupState -Value 'pending-verification' -PropertyType String | Out-Null
        New-Item -Path $uninstallKey -Force | Out-Null
        New-ItemProperty -LiteralPath $uninstallKey -Name 'Inno Setup: App Path' -Value $app -PropertyType String | Out-Null
        New-ItemProperty -LiteralPath $uninstallKey -Name 'DisplayName' -Value 'AuthLens Server (pending verification; recovery required)' -PropertyType String | Out-Null
        New-ItemProperty -LiteralPath $uninstallKey -Name 'UninstallString' -Value '"C:\synthetic\unins000.exe"' -PropertyType String | Out-Null
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
    }
    AfterEach { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
    It 'writes the values Setup writes after verified success, only with proven ownership, and keeps the uninstall entry' {
        $result = Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey
        $result.state | Should -Be 'reconciled'
        $server = Get-ItemProperty -LiteralPath $serverKey
        ($server.SetupState, $server.Root, $server.ConfigFile, $server.ProgramDirectory, $server.FileVersion) | Should -Be @('verified', $root, $config.ConfigFile, $app, '2.0.0.0')
        $uninstall = Get-ItemProperty -LiteralPath $uninstallKey
        $uninstall.DisplayName | Should -Be 'AuthLens Server'
        $uninstall.UninstallString | Should -Be '"C:\synthetic\unins000.exe"'
        @((Get-Item -LiteralPath $base).GetSubKeyNames()).Count | Should -Be 2 -Because 'no duplicate or additional registration is created'
        (Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey).state | Should -Be 'already_verified'
    }
    It 'refuses without proof and changes nothing' {
        Remove-Item -LiteralPath $uninstallKey -Recurse -Force
        (Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey).state | Should -Be 'not_reconciled'
        (Get-ItemProperty -LiteralPath $serverKey).SetupState | Should -Be 'pending-verification'
        Test-Path -LiteralPath $uninstallKey | Should -BeFalse -Because 'a missing uninstall entry is never invented'
        New-Item -Path $uninstallKey -Force | Out-Null
        New-ItemProperty -LiteralPath $uninstallKey -Name 'Inno Setup: App Path' -Value $app -PropertyType String | Out-Null
        [IO.File]::WriteAllText((Join-Path $staged 'build-manifest.json'), '{"product":"AuthLens","version":"2.0.0","source_sha":"dddddddddddddddddddddddddddddddddddddddd","file_version":[2,0,0,0]}')
        $result = Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey
        $result.state | Should -Be 'not_reconciled'
        $result.reason | Should -BeLike '*not the recovered release*'
        $server = Get-ItemProperty -LiteralPath $serverKey
        $server.SetupState | Should -Be 'pending-verification'
        $server.PSObject.Properties['ConfigFile'] | Should -BeNullOrEmpty
    }
    It 'reports a missing registration, a conflicting verified registration and an unknown state without writing' {
        $absent = Update-ALInstallerRegistrationAfterRecovery $config $release $manifest "$base\Missing" $uninstallKey
        $absent.state | Should -Be 'not_present'
        Test-Path -LiteralPath "$base\Missing" | Should -BeFalse
        Set-ItemProperty -LiteralPath $serverKey -Name SetupState -Value 'verified'
        Set-ItemProperty -LiteralPath $serverKey -Name ConfigFile -Value 'D:\other\deploy.json'
        (Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey).state | Should -Be 'conflict'
        (Get-ItemProperty -LiteralPath $serverKey).ConfigFile | Should -Be 'D:\other\deploy.json'
        Set-ItemProperty -LiteralPath $serverKey -Name SetupState -Value 'something-else'
        (Update-ALInstallerRegistrationAfterRecovery $config $release $manifest $serverKey $uninstallKey).state | Should -Be 'not_reconciled'
    }
}

# WP19: restart of the installed service on its unchanged configuration.
Describe 'Service restart (WP19)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config'), (Join-Path $root 'deployment') | Out-Null
        $file = Join-Path $root 'config/deploy.json'
        @{ Root = $root; ListenAddress = '127.0.0.1'; Port = 18795 } | ConvertTo-Json | Set-Content $file
        $config = Read-AuthLensSettings $file -Packaged
        Mock -ModuleName AuthLens.Deploy Assert-ALConfigurationChangeAllowed { [pscustomobject]@{ service = [pscustomobject]@{ State = 'Running'; ProcessId = 10 }; manifest = [pscustomobject]@{ version = '2.0.0'; source_sha = ('e' * 40) } } }
        Mock -ModuleName AuthLens.Deploy Get-ALLink { 'C:\synthetic\releases\current-target' }
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 11; identity = [pscustomobject]@{ version = '2.0.0'; source_sha = ('e' * 40) } } }
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
    }
    It 'checks only with -DryRun and restarts with verification otherwise' {
        $plan = Invoke-ALServiceRestart $config -DryRun
        $plan.dry_run | Should -BeTrue
        $plan.downtime | Should -BeLike '*clients are disconnected*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        $done = Invoke-ALServiceRestart $config
        $done.restarted | Should -BeTrue
        ($done.process_before, $done.process_after) | Should -Be @(10, 11)
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter { $Commit -eq ('e' * 40) -and $Version -eq '2.0.0' }
    }
    It 'refuses while a deployment or configuration change awaits recovery and reports a failed start' {
        Mock -ModuleName AuthLens.Deploy Assert-ALConfigurationChangeAllowed { throw 'An interrupted deployment requires -Action Recover before the configuration can be changed.' }
        { Invoke-ALServiceRestart $config } | Should -Throw '*requires -Action Recover*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        [IO.File]::WriteAllText((Get-ALConfigurationPendingPath $config), '{"schema":2}')
        { Invoke-ALServiceRestart $config -DryRun } | Should -Throw '*interrupted configuration change*'
        Remove-Item (Get-ALConfigurationPendingPath $config)
        Mock -ModuleName AuthLens.Deploy Assert-ALConfigurationChangeAllowed { [pscustomobject]@{ service = [pscustomobject]@{ State = 'Running'; ProcessId = 10 }; manifest = [pscustomobject]@{ version = '2.0.0'; source_sha = ('e' * 40) } } }
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { throw 'The service did not become ready on its listener.' }
        { Invoke-ALServiceRestart $config } | Should -Throw '*did not become ready*'
    }
    It 'is a simulated, approval-gated action' {
        (Get-ALActionPolicy 'RestartService' -DryRun).mode | Should -Be 'simulate'
        (Get-ALActionPolicy 'RestartService' -DryRun -Yes).mode | Should -Be 'simulate'
        { Get-ALActionPolicy 'RestartService' } | Should -Throw '*repeat with -Yes*'
        (Get-ALActionPolicy 'RestartService' -Yes).approval_required | Should -BeTrue
    }
}

# T-001: current tools recover a journal written by an older build (8ec7f77 era: one history object instead of an array, no adoption fields,
# configuration without AccessMode or RepositoryPath) after a manual correction; inconsistent states are refused and the journal is kept.
Describe 'Recovery of an older-build journal (T-001)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config'), (Join-Path $root 'data'), (Join-Path $root 'deployment'), (Join-Path $root 'releases/old-candidate') | Out-Null
        $file = Join-Path $root 'config/deploy.json'
        @{ Root = $root; ListenAddress = '10.26.1.55'; Port = 18795; AllowedHosts = @('lens.example.test') } | ConvertTo-Json | Set-Content $file
        $config = Read-AuthLensSettings $file -Packaged
        $candidate = Join-Path $root 'releases/old-candidate'
        $sha = '8ec7f77b35b23d8c295e119bc6e4128b0681f67d'
        @{ product = 'AuthLens'; version = '2.0.0'; source_sha = $sha } | ConvertTo-Json | Set-Content (Join-Path $candidate 'build-manifest.json')
        @{ schema = 1; product = 'AuthLens'; root = $root; data_directory = $config.DataDirectory; instance_id = ('f' * 32) } | ConvertTo-Json | Set-Content (Join-Path $config.DataDirectory '.authlens-owned-data.json')
        $journalPath = Get-ALJournalPath $config
        # Written as the older build wrote it: history as a single object, no service_binary_before or identity_before.
        [IO.File]::WriteAllText($journalPath, (@{ run = '20261124-101158-installer-840e61e7'; commit = $sha; version = '2.0.0'; to_release = $candidate; from_release = $null
            service_state_before = 'Missing'; applied_before = @(); backup = $null; phase = 'manual_recovery_required'; history = @{ phase = 'manual_recovery_required'; at = '2026-11-24T10:20:00Z' }; updated = '2026-11-24T10:20:00Z' } | ConvertTo-Json -Depth 5))
        $before = (Get-FileHash $journalPath).Hash
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; Account = $config.ServiceAccount; PathName = 'owned'; ProcessId = 4944 } }
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $candidate }
        Mock -ModuleName AuthLens.Deploy Test-ALPublishedRelease { [pscustomobject]@{ Verified = $true } }
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $true; read_only = $true; data_modified = $false; source_sha = $sha; version = '2.0.0'; schema = [pscustomobject]@{ compatible = $true; pending = @() } } }
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 4944; identity = [pscustomobject]@{ version = '2.0.0'; source_sha = $sha } } }
        Mock -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions {}
    }
    It 'completes a consistent manual correction and keeps the older history entry' {
        $config.AccessMode | Should -Be 'Auto'
        $config.ExecutionContext | Should -Be 'packaged'
        (Get-ALRecoveryPreview $config -RecoveryAction VerifyCandidate).would_succeed | Should -BeTrue
        (Get-FileHash $journalPath).Hash | Should -Be $before
        (Invoke-ALRecover $config -RecoveryAction VerifyCandidate).phase | Should -Be 'complete'
        @((Read-ALJournal $config).history | ForEach-Object { $_.phase }) | Should -Be @('manual_recovery_required', 'complete')
    }
    It 'refuses a mismatched command line, a changed pointer, a manifest mismatch, a pending operation and a missing ownership marker' {
        $cases = @(
            @{ Name = 'command line'; Setup = { Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $false } }; Expect = '*original owned service identity and matching configuration*' },
            @{ Name = 'pointer'; Setup = { Mock -ModuleName AuthLens.Deploy Get-ALLink { 'C:\synthetic\elsewhere' } }; Expect = '*unchanged verified owned release pointer*' },
            @{ Name = 'manifest'; Setup = { @{ product = 'AuthLens'; version = '2.0.0'; source_sha = ('0' * 40) } | ConvertTo-Json | Set-Content (Join-Path $candidate 'build-manifest.json') }; Expect = '*manifest and original transaction identity disagree*' },
            @{ Name = 'pending'; Setup = { Set-Content (Join-Path $config.WorkRoot 'repair-pending.json') '{}' }; Expect = '*pending offline repair*' },
            @{ Name = 'marker'; Setup = { Remove-Item (Join-Path $config.DataDirectory '.authlens-owned-data.json') }; Expect = '*data is never adopted*' })
        foreach ($case in $cases) {
            & $case.Setup
            { Invoke-ALRecover $config -RecoveryAction VerifyCandidate } | Should -Throw $case.Expect -Because $case.Name
            (Read-ALJournal $config).phase | Should -Be 'manual_recovery_required' -Because $case.Name
            # Restore the fixture for the next case.
            Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
            Mock -ModuleName AuthLens.Deploy Get-ALLink { $candidate }
            @{ product = 'AuthLens'; version = '2.0.0'; source_sha = $sha } | ConvertTo-Json | Set-Content (Join-Path $candidate 'build-manifest.json')
            Remove-Item (Join-Path $config.WorkRoot 'repair-pending.json') -ErrorAction SilentlyContinue
            if (-not (Test-Path (Join-Path $config.DataDirectory '.authlens-owned-data.json'))) { @{ schema = 1; product = 'AuthLens'; root = $root; data_directory = $config.DataDirectory; instance_id = ('f' * 32) } | ConvertTo-Json | Set-Content (Join-Path $config.DataDirectory '.authlens-owned-data.json') }
        }
    }
}
