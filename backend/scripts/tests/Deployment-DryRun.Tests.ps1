BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    $script:Entry = (Resolve-Path (Join-Path $PSScriptRoot '..\deploy\Deploy-AuthLens.ps1')).ProviderPath
    # A synthetic packaged installation in TestDrive whose service does not exist: the real entry point runs read-only service queries only.
    function script:New-DryRunInstallation {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 12))
        foreach ($dir in 'config', 'data', 'deployment', 'releases\candidate') { New-Item -ItemType Directory -Force (Join-Path $root $dir) | Out-Null }
        $file = Join-Path $root 'config\deploy.json'
        [ordered]@{ Root = $root; ServiceName = 'AuthLensDryRunSynthetic'; AccessMode = 'Local'; ListenAddress = '127.0.0.1'; Port = 18799; AllowedHosts = @('localhost', '127.0.0.1')
            CertificatePath = (Join-Path $root 'tls\setup-1\server.pfx'); CertificatePasswordFile = (Join-Path $root 'tls\setup-1\cert-password') } | ConvertTo-Json | Set-Content $file -Encoding UTF8
        $config = Read-AuthLensSettings $file
        Write-ALJournal $config ([pscustomobject]@{ phase = 'manual_recovery_required'; run = 'synthetic-run'; from_release = ''; to_release = (Join-Path $root 'releases\candidate'); commit = ('c' * 40); version = '2.0.0'
            backup = $null; service_binary_before = ''; service_state_before = 'Missing'; history = @(@{ phase = 'starting'; at = 'x' }, @{ phase = 'manual_recovery_required'; at = 'y' }); updated = '' })
        [pscustomobject]@{ Root = $root; File = $file; Config = $config; Journal = (Get-ALJournalPath $config) }
    }
    function script:Invoke-Entry([string[]]$Arguments) {
        $run = Invoke-TestPowerShell (@('-ExecutionPolicy', 'Bypass', '-File', $script:Entry) + $Arguments)
        $line = @($run.Output -split "`n" | Where-Object { $_ -like 'AUTHLENS-RESULT: *' }) | Select-Object -Last 1
        [pscustomobject]@{ Code = $run.Code; Output = $run.Output; Result = $(if ($line) { ($line.Substring(17) | ConvertFrom-Json) } else { $null }) }
    }
}

# D-006 (P0): -DryRun on Recover performed the real recovery without -Yes. Approval and simulation are now one policy.
Describe 'Deploy-AuthLens action policy (D-006)' {
    It 'classifies every action: read-only, simulated with -DryRun, refused -DryRun, approval without it' {
        foreach ($action in 'Status', 'Health', 'AuditAcl') {
            foreach ($dry in $false, $true) { foreach ($yes in $false, $true) { (Get-ALActionPolicy $action -DryRun:$dry -Yes:$yes).mode | Should -Be 'read_only' } }
        }
        foreach ($action in 'Deploy', 'Recover', 'ReplaceCertificate', 'ChangeNetwork', 'ProtectAcl', 'RestartService') {
            (Get-ALActionPolicy $action -DryRun).mode | Should -Be 'simulate'
            (Get-ALActionPolicy $action -DryRun -Yes).mode | Should -Be 'simulate' -Because '-DryRun with -Yes is still only a simulation'
            (Get-ALActionPolicy $action -Yes).mode | Should -Be 'execute'
            { Get-ALActionPolicy $action } | Should -Throw '*repeat with -Yes*'
        }
        foreach ($action in 'InstallService', 'Restore', 'Rollback', 'RestoreAcl') {
            { Get-ALActionPolicy $action -DryRun } | Should -Throw "*-DryRun is not supported for $action*"
            { Get-ALActionPolicy $action -DryRun -Yes } | Should -Throw '*-DryRun is not supported*'
            { Get-ALActionPolicy $action } | Should -Throw '*repeat with -Yes*'
            (Get-ALActionPolicy $action -Yes).approval_required | Should -BeTrue
        }
        { Get-ALActionPolicy 'Build' -DryRun } | Should -Throw '*-DryRun is not supported for Build*'
        (Get-ALActionPolicy 'Build').mode | Should -Be 'execute'
    }
    It 'detects any persistent state difference in a snapshot' {
        $site = New-DryRunInstallation
        $before = Get-ALStateSnapshot $site.Config
        @(Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config)).Count | Should -Be 0
        $journal = Read-ALJournal $site.Config; Set-ALPhase $site.Config $journal 'complete'
        Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config) | Should -Contain 'work:deployment-journal.json'
        Set-Content (Join-Path $site.Root 'config\installed-product.json') '{}'
        Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config) | Should -Contain 'installed-product'
    }
}

Describe 'Recovery preview is read-only (D-006)' {
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
        Write-ALJournal $config ([pscustomobject]@{ phase = 'manual_recovery_required'; run = 'synthetic'; from_release = ''; to_release = $candidate; commit = $sha; version = '2.0.0'; backup = $null; service_binary_before = ''; service_state_before = 'Missing'; history = @(); updated = '' })
        $journalHash = (Get-FileHash (Get-ALJournalPath $config)).Hash
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; Account = $config.ServiceAccount; PathName = 'owned synthetic service'; ProcessId = 4944 } }
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $candidate }
        Mock -ModuleName AuthLens.Deploy Test-ALPublishedRelease { [pscustomobject]@{ Verified = $true } }
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $true; read_only = $true; data_modified = $false; source_sha = $sha; version = '2.0.0'; schema = [pscustomobject]@{ compatible = $true; pending = @() } } }
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 4944; identity = [pscustomobject]@{ version = '2.0.0'; source_sha = $sha } } }
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALRollbackCore { throw 'rollback must never run in a preview' }
        Mock -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions {}
    }
    It 'evaluates VerifyCandidate with every check and changes nothing' {
        $preview = Get-ALRecoveryPreview $config -RecoveryAction VerifyCandidate
        $preview.blocking_reason | Should -BeNullOrEmpty
        $preview.would_succeed | Should -BeTrue
        $preview.would_phase | Should -Be 'complete'
        $preview.readiness_verified | Should -BeTrue
        $preview.PSObject.Properties['recovered'] | Should -BeNullOrEmpty
        $preview.journal_phase | Should -Be 'manual_recovery_required'
        (Get-FileHash (Get-ALJournalPath $config)).Hash | Should -Be $journalHash
        (Read-ALJournal $config).phase | Should -Be 'manual_recovery_required'
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1
        Should -Invoke -ModuleName AuthLens.Deploy Start-ALService -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions -Times 0
        # The decision matches the real run, which completes the same journal.
        (Invoke-ALRecover $config -RecoveryAction VerifyCandidate).phase | Should -Be 'complete'
    }
    It 'reports a refusal without recording manual_recovery_required or recovery notes' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { throw 'synthetic TLS refusal: SAN lacks 10.26.1.55' }
        $preview = Get-ALRecoveryPreview $config -RecoveryAction Auto
        $preview.decision | Should -Be 'candidate'
        $preview.would_succeed | Should -BeFalse
        $preview.blocking_reason | Should -BeLike '*SAN lacks*'
        (Get-FileHash (Get-ALJournalPath $config)).Hash | Should -Be $journalHash
        Should -Invoke -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions -Times 0
    }
    It 'previews Resume of a stopped service without starting it' {
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Stopped'; Account = $config.ServiceAccount; PathName = 'owned'; ProcessId = 0 } }
        $preview = Get-ALRecoveryPreview $config -RecoveryAction Resume
        $preview.would_succeed | Should -BeTrue
        $preview.would_start_service | Should -BeTrue
        $preview.readiness_verified | Should -BeFalse
        Should -Invoke -ModuleName AuthLens.Deploy Start-ALService -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 0
        (@($preview.options) | Where-Object action -eq 'Resume').available | Should -BeTrue
        (@($preview.options) | Where-Object action -eq 'VerifyCandidate').available | Should -BeFalse
    }
    It 'offers only the actions the state allows and previews unavailable ones as refusals' {
        $options = @(Get-ALRecoveryOptions $config (Read-ALJournal $config))
        ($options | Where-Object available).action | Should -Be @('VerifyCandidate')
        $rollback = Get-ALRecoveryPreview $config -RecoveryAction Rollback
        $rollback.would_succeed | Should -BeFalse
        $rollback.blocking_reason | Should -BeLike '*verified previous release*'
        (Get-ALRecoveryPreview $config -RecoveryAction Cancel).would_succeed | Should -BeFalse
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALRollbackCore -Times 0
        (Get-FileHash (Get-ALJournalPath $config)).Hash | Should -Be $journalHash
    }
    It 'reports a pending configuration change as the restoration it would perform, without restoring' {
        Mock -ModuleName AuthLens.Deploy Restore-ALConfigurationChange { throw 'restoration must never run in a preview' }
        [IO.File]::WriteAllText((Get-ALConfigurationPendingPath $config), (@{ schema = 2; operation = 'certificate replacement' } | ConvertTo-Json))
        $preview = Get-ALRecoveryPreview $config
        $preview.pending_configuration_change | Should -Be 'certificate replacement'
        $preview.would_action | Should -BeLike 'restore the interrupted certificate replacement*'
        Should -Invoke -ModuleName AuthLens.Deploy Restore-ALConfigurationChange -Times 0
        Test-Path (Get-ALConfigurationPendingPath $config) | Should -BeTrue
    }
    It 'never reopens a completed journal, even for an explicit action whose checks would fail' {
        $journal = Read-ALJournal $config; Set-ALPhase $config $journal 'complete'
        $completed = (Get-FileHash (Get-ALJournalPath $config)).Hash
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { throw 'synthetic refusal' }
        (Invoke-ALRecover $config -RecoveryAction VerifyCandidate).recovered | Should -BeFalse
        (Get-ALRecoveryPreview $config -RecoveryAction VerifyCandidate).decision | Should -Be 'none'
        (Get-FileHash (Get-ALJournalPath $config)).Hash | Should -Be $completed
        (Read-ALJournal $config).phase | Should -Be 'complete'
    }
}

Describe 'Deploy-AuthLens -DryRun entry point leaves the installation unchanged (D-006)' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    It 'refuses Recover without -Yes and simulates Recover -DryRun (also with -Yes) without changing persistent state' {
        $site = New-DryRunInstallation
        $before = Get-ALStateSnapshot $site.Config
        $journal = (Get-FileHash $site.Journal).Hash

        $refused = Invoke-Entry @('-Action', 'Recover', '-ConfigFile', $site.File, '-RecoveryAction', 'VerifyCandidate')
        $refused.Code | Should -Be 2
        $refused.Result.result.error | Should -BeLike '*repeat with -Yes*'

        foreach ($extra in @(@(), @('-Yes'))) {
            $run = Invoke-Entry (@('-Action', 'Recover', '-ConfigFile', $site.File, '-RecoveryAction', 'VerifyCandidate', '-DryRun') + $extra)
            $run.Output | Should -Match 'SIMULATION \(-DryRun\): no change was made'
            $run.Result.result.simulation | Should -BeTrue
            $run.Result.result.changes_applied | Should -BeFalse
            $run.Result.result.PSObject.Properties['recovered'] | Should -BeNullOrEmpty
            $run.Result.result.journal_phase | Should -Be 'manual_recovery_required'
            # The synthetic service does not exist, so the candidate would be refused: reported, not recorded.
            $run.Result.result.would_succeed | Should -BeFalse
            $run.Code | Should -Be 2
        }
        (Get-FileHash $site.Journal).Hash | Should -Be $journal
        @(Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config)).Count | Should -Be 0
        Test-Path (Join-Path $site.Config.WorkRoot 'runs') | Should -BeFalse -Because 'a simulation writes no run folder'
        Test-Path (Join-Path $site.Config.WorkRoot 'deployment.lock') | Should -BeFalse -Because 'a simulation takes the host mutex only'
        Test-Path (Join-Path $site.Config.WorkRoot 'RECOVERY-REQUIRED.txt') | Should -BeFalse
        Test-Path (Join-Path $site.Config.WorkRoot 'recovery-audit.jsonl') | Should -BeFalse -Because 'a simulation never writes recovery audit metadata (G-004)'
    }
    It 'refuses -DryRun for actions without a simulation before anything runs' {
        $site = New-DryRunInstallation
        $before = Get-ALStateSnapshot $site.Config
        foreach ($action in 'InstallService', 'Restore', 'Rollback', 'RestoreAcl', 'Build') {
            foreach ($extra in @(@(), @('-Yes'))) {
                $run = Invoke-Entry (@('-Action', $action, '-ConfigFile', $site.File, '-DryRun') + $extra)
                $run.Code | Should -Be 2 -Because "$action -DryRun $extra"
                $run.Result.result.error | Should -BeLike "*-DryRun is not supported for $action*"
            }
        }
        @(Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config)).Count | Should -Be 0
        Test-Path (Join-Path $site.Config.WorkRoot 'runs') | Should -BeFalse
    }
    It 'marks the network and certificate simulations and their refusals as simulations' {
        $site = New-DryRunInstallation
        $before = Get-ALStateSnapshot $site.Config
        $network = Invoke-Entry @('-Action', 'ChangeNetwork', '-ConfigFile', $site.File, '-Port', '18800', '-DryRun')
        $network.Output | Should -Match 'SIMULATION'
        $network.Result.result.simulation | Should -BeTrue
        $network.Code | Should -Not -Be 0 -Because 'an interrupted deployment blocks configuration changes'
        $certificate = Invoke-Entry @('-Action', 'ReplaceCertificate', '-ConfigFile', $site.File, '-CertificateFile', (Join-Path $TestDrive 'missing.pfx'), '-CertificatePasswordFile', (Join-Path $TestDrive 'missing'), '-DryRun', '-Yes')
        $certificate.Result.result.simulation | Should -BeTrue
        $restart = Invoke-Entry @('-Action', 'RestartService', '-ConfigFile', $site.File, '-DryRun')
        $restart.Result.result.simulation | Should -BeTrue
        $restart.Code | Should -Not -Be 0 -Because 'an interrupted deployment blocks a restart'
        $certificate.Code | Should -Be 2
        @(Compare-ALStateSnapshot $before (Get-ALStateSnapshot $site.Config)).Count | Should -Be 0
    }
}
