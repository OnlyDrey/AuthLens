# WP21 acceptance harness (QA-001 to QA-018): verdicts, case-file rules, execution context, stop-on-mutation and mutation prerequisites.
# No installation, service or deployment command is touched: the runner and the snapshot are replaced.
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'acceptance\AuthLens.Acceptance.psm1') -Force
    $script:Cases = Join-Path $root 'acceptance\cases'
    function New-Case([hashtable]$Expect, [string[]]$Arguments = @('-Action', 'Status')) { [pscustomobject]@{ id = 'c'; args = $Arguments; expect = [pscustomobject]$Expect } }
    function New-Output([hashtable]$Result, [string]$Text = '') { @($Text, ('AUTHLENS-RESULT: ' + (@{ exit = 0; result = $Result } | ConvertTo-Json -Compress))) }
}

Describe 'Get-AcceptanceVerdict' {
    It 'passes a simulation only when exit, reason, simulation and changes_applied all match and state is unchanged' {
        $case = New-Case @{ exit = @(0); reason = 'SIMULATION'; simulation = $true; changes_applied = $false; state_unchanged = $true }
        (Get-AcceptanceVerdict $case 0 (New-Output @{ simulation = $true; changes_applied = $false } 'SIMULATION (-DryRun)') @()).status | Should -Be 'PASS'
    }
    It 'fails when simulation fields are absent even with the expected exit code (QA-013/014)' {
        $case = New-Case @{ exit = @(0); reason = 'SIMULATION'; simulation = $true; changes_applied = $false }
        $v = Get-AcceptanceVerdict $case 0 (New-Output @{ recovered = $true } 'SIMULATION') @()
        $v.status | Should -Be 'FAIL'; ($v.failures -join ' ') | Should -Match 'simulation = <absent>'
    }
    It 'fails an exit-2 refusal whose reason is an unrelated gate (QA-006/015)' {
        $case = New-Case @{ exit = @(2); reason = 'repeat with -Yes'; forbidden_reason = 'needs an elevated session' }
        (Get-AcceptanceVerdict $case 2 @('Release C:\x is not a published release folder.') @()).status | Should -Be 'FAIL'
        (Get-AcceptanceVerdict $case 2 @('Deploy changes the service; repeat with -Yes after reviewing', 'Deploy needs an elevated session') @()).status | Should -Be 'FAIL'
        (Get-AcceptanceVerdict $case 2 @('Deploy changes the service or its permissions; repeat with -Yes after reviewing') @()).status | Should -Be 'PASS'
    }
    It 'reports a protected-state change as a mutation (QA-012)' {
        $case = New-Case @{ exit = @(2); reason = 'x' }
        $v = Get-AcceptanceVerdict $case 2 @('x') @('sha256:deployment\deployment-journal.json')
        $v.status | Should -Be 'FAIL'; $v.mutation | Should -BeTrue
    }
}

Describe 'Read-AcceptanceCases' {
    It 'accepts the maintained case files' {
        foreach ($f in 'B13.json', 'B14-approval.json', 'B14-elevation.json') { { Read-AcceptanceCases (Join-Path $script:Cases $f) } | Should -Not -Throw }
    }
    It 'keeps approval and elevation refusals in separately guarded groups (QA-005/011)' {
        $approval = Read-AcceptanceCases (Join-Path $script:Cases 'B14-approval.json'); $elevation = Read-AcceptanceCases (Join-Path $script:Cases 'B14-elevation.json')
        $approval.context | Should -Be 'elevated'; $elevation.context | Should -Be 'non-elevated'
        @($approval.cases | Where-Object { @($_.args) -contains '-Yes' }).Count | Should -Be 0
        @($elevation.cases | Where-Object { @($_.args) -notcontains '-Yes' }).Count | Should -Be 0
        foreach ($c in @($approval.cases) + @($elevation.cases)) { $c.expect.reason | Should -Not -BeNullOrEmpty; $c.expect.forbidden_reason | Should -Not -BeNullOrEmpty }
    }
    It 'refuses a -Yes case without -DryRun in a group that may run elevated' {
        $file = Join-Path $TestDrive 'bad.json'
        @{ scenario = 'x'; context = 'elevated'; cases = @(@{ id = 'a'; args = @('-Action', 'RestartService', '-Yes'); expect = @{ exit = @(2); reason = 'x' } }) } | ConvertTo-Json -Depth 5 | Set-Content $file
        { Read-AcceptanceCases $file } | Should -Throw '*non-elevated elevation-refusal group*'
    }
    It 'refuses a case that asserts only an exit code' {
        $file = Join-Path $TestDrive 'exit-only.json'
        @{ scenario = 'x'; context = 'any'; cases = @(@{ id = 'a'; args = @('-Action', 'Status'); expect = @{ exit = @(0) } }) } | ConvertTo-Json -Depth 5 | Set-Content $file
        { Read-AcceptanceCases $file } | Should -Throw '*exit code alone is not evidence*'
    }
}

Describe 'Assert-AcceptanceContext' {
    It 'refuses an elevated session for a non-elevated group and the reverse' {
        { Assert-AcceptanceContext 'non-elevated' $true 'B14-elevation' } | Should -Throw '*NON-elevated*'
        { Assert-AcceptanceContext 'elevated' $false 'B14-approval' } | Should -Throw '*requires an elevated session*'
        { Assert-AcceptanceContext 'any' $true 'B13' } | Should -Not -Throw
    }
}

Describe 'Invoke-AcceptanceGroup' {
    BeforeEach {
        $script:deploy = Join-Path $TestDrive 'Deploy-AuthLens.ps1'; Set-Content $script:deploy '# placeholder'
        $script:file = Join-Path $TestDrive "cases-$([guid]::NewGuid().ToString('N')).json"
        @{ scenario = 'T'; context = 'any'; cases = @(
            @{ id = 'one'; args = @('-Action', 'Recover', '-DryRun'); expect = @{ exit = @(0); reason = 'SIMULATION'; simulation = $true; changes_applied = $false; state_unchanged = $true } },
            @{ id = 'two'; args = @('-Action', 'Restore', '-DryRun'); expect = @{ exit = @(2); reason = 'not supported'; state_unchanged = $true } }) } | ConvertTo-Json -Depth 6 | Set-Content $script:file
    }
    It 'runs every case, writes results.json and exits 0 when all pass (QA-018)' {
        Mock -ModuleName AuthLens.Acceptance Get-AcceptanceSnapshot { [pscustomobject]@{ journal = 'same' } }
        $runner = { param($a) if ($a -contains 'Recover') { [pscustomobject]@{ exit = 0; output = (New-Output @{ simulation = $true; changes_applied = $false } 'SIMULATION') } } else { [pscustomobject]@{ exit = 2; output = @('-DryRun is not supported for Restore') } } }
        $out = Join-Path $TestDrive "run-$([guid]::NewGuid().ToString('N'))"
        $r = Invoke-AcceptanceGroup -CasesFile $script:file -Deploy $script:deploy -ConfigFile 'c.json' -OutputDirectory $out -Runner $runner
        $r.status | Should -Be 'PASS'; $r.exit_code | Should -Be 0; $r.passed | Should -Be 2
        (Get-Content (Join-Path $out 'results.json') -Raw | ConvertFrom-Json).status | Should -Be 'PASS'
    }
    It 'stops the group at the first unexpected mutation and does not run later cases (QA-012)' {
        $script:n = 0
        Mock -ModuleName AuthLens.Acceptance Get-AcceptanceSnapshot { $script:n++; [pscustomobject]@{ journal = "v$script:n" } }
        $runner = { param($a) [pscustomobject]@{ exit = 0; output = (New-Output @{ simulation = $true; changes_applied = $false } 'SIMULATION') } }
        $r = Invoke-AcceptanceGroup -CasesFile $script:file -Deploy $script:deploy -ConfigFile 'c.json' -OutputDirectory (Join-Path $TestDrive "m-$([guid]::NewGuid().ToString('N'))") -Runner $runner
        $r.status | Should -Be 'STOPPED'; $r.exit_code | Should -Be 3
        @($r.cases)[1].status | Should -Be 'NOT RUN'
    }
    It 'refuses an existing output directory without running anything' {
        $existing = Join-Path $TestDrive 'exists'; New-Item -ItemType Directory $existing | Out-Null
        $runner = { throw 'must not run' }
        $r = Invoke-AcceptanceGroup -CasesFile $script:file -Deploy $script:deploy -ConfigFile 'c.json' -OutputDirectory $existing -Runner $runner
        $r.status | Should -Be 'REFUSED'; $r.exit_code | Should -Be 2
    }
}

Describe 'Test-AcceptanceMutationPrerequisites' {
    BeforeEach {
        $script:recovery = Join-Path $TestDrive 'recovery.json'
        @{ status = 'passed'; verified = $true; bundle = 'C:\AuthLens-Recovery\x'; archive_sha256 = 'ab'; service_changed = $false } | ConvertTo-Json | Set-Content $script:recovery
        $script:readiness = Join-Path $TestDrive 'readiness.txt'
        $script:now = [DateTime]::Parse('2026-11-25T13:00:00Z').ToUniversalTime()
        function Set-Readiness([string]$Status = 'PASS', [string]$Sha = 'abc', [string]$Completed = '2026-11-25T12:20:31Z', [string]$Report = '2026-11-25T12:18:47Z') {
            'PASS: completed', ('AUTHLENS-UPGRADE-READINESS: ' + (@{ status = $Status; source_sha = $Sha; completed_utc = $Completed; recovery_report_utc = $Report; operation_id = 'op'; failure_code = '' } | ConvertTo-Json -Compress)) | Set-Content $script:readiness
        }
        $script:prereq = @{ RecoveryReport = $script:recovery; ReadinessReport = $script:readiness; ExpectedCandidateSha = 'abc'; ExpectedInstalledSha = 'old'; InstalledSha = 'old'; KeyStatus = [pscustomobject]@{ escrow_verified = $true; escrow_pending = $false }; SnapshotAttestation = 'vm130-before-rc4'; Now = $script:now }
    }
    It 'accepts current, matching evidence and records the snapshot as attested, not verified' {
        Set-Readiness; $p = $script:prereq
        $r = Test-AcceptanceMutationPrerequisites @p
        $r.snapshot_verification | Should -Be 'operator_attested_not_verified'
    }
    It 'refuses a failed, stale, foreign or reportless readiness (QA-002/016)' {
        $p = $script:prereq
        Set-Readiness -Status 'FAIL'; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*readiness is FAIL*'
        Set-Readiness -Completed '2026-11-23T12:00:00Z'; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*older than*'
        Set-Readiness -Sha 'other'; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*not the candidate*'
        Set-Readiness -Report ''; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*explicit recovery report*'
    }
    It 'refuses unverified escrow, a missing attestation and an unexpected installed release (QA-003)' {
        Set-Readiness
        $p = $script:prereq.Clone(); $p.KeyStatus = [pscustomobject]@{ escrow_verified = $false; escrow_pending = $true }; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*escrow is not verified*'
        $p = $script:prereq.Clone(); $p.SnapshotAttestation = ' '; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*snapshot attestation*'
        $p = $script:prereq.Clone(); $p.InstalledSha = 'new'; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*expected baseline*'
    }
    It 'refuses a recovery report that did not pass and a missing report (no fallback to older reports)' {
        Set-Readiness
        $p = $script:prereq
        @{ status = 'failed'; verified = $false; bundle = 'x'; archive_sha256 = 'y' } | ConvertTo-Json | Set-Content $script:recovery
        { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*did not pass*'
        $p = $script:prereq.Clone(); $p.RecoveryReport = Join-Path $TestDrive 'missing.json'; { Test-AcceptanceMutationPrerequisites @p } | Should -Throw '*never used instead*'
    }
}
