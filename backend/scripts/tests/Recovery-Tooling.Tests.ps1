# WP22 recovery tooling: parse, fail-closed prerequisites and machine-readable reports. The native capture and the isolated restore
# rehearsal are acceptance steps (they need an installation and a real bundle) and are not run here.
BeforeAll {
    $script:Recovery = Join-Path (Split-Path $PSScriptRoot -Parent) 'recovery'
    $script:Ps = Join-Path $PSHOME 'powershell.exe'
}

Describe 'Recovery tooling scripts' {
    It 'parse without errors and carry no hard-coded release, bundle, account or Python path' {
        foreach ($file in Get-ChildItem $script:Recovery -Filter *.ps1) {
            $errors = $null; $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
            @($errors).Count | Should -Be 0
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match 'python\.exe|\.py\b|Python3\d+'
            $text | Should -Not -Match 'alpha\.1|8c6ea68|arkasa|acceptance-admin|tls-prototype'
        }
    }
    It 'refuses bundle creation without elevation and still writes a failed report' -Skip:(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $reports = Join-Path $TestDrive 'reports'; New-Item -ItemType Directory $reports | Out-Null
        $out = & $script:Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:Recovery 'New-AuthLensRecoveryBundle.ps1') -RecoveryRoot (Join-Path $TestDrive 'root') -ReportDirectory $reports 2>&1
        $LASTEXITCODE | Should -Be 1
        $report = Get-Content (Get-ChildItem $reports -Filter 'backup-result-*.json')[0].FullName -Raw | ConvertFrom-Json
        $report.status | Should -Be 'failed'; $report.failure_stage | Should -Be 'elevation'; $report.verified | Should -BeFalse
        Test-Path (Join-Path $TestDrive 'root') | Should -BeFalse
        ($out -join "`n") | Should -Match 'AUTHLENS-RECOVERY-BUNDLE:'
    }
    It 'fails a rehearsal of a missing bundle closed, with a report and without starting anything' {
        $work = Join-Path $TestDrive 'work'
        $out = & $script:Ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:Recovery 'Test-AuthLensRestoreRehearsal.ps1') -Bundle (Join-Path $TestDrive 'no-bundle') -Verifier (Join-Path $TestDrive 'none.exe') -WorkRoot $work 2>&1
        $LASTEXITCODE | Should -Be 1
        $result = Get-Content (Get-ChildItem $work -Recurse -Filter 'restore-result.json')[0].FullName -Raw | ConvertFrom-Json
        $result.status | Should -Be 'failed'; $result.actual_restore | Should -BeFalse; $result.active_installation_unchanged | Should -BeFalse
        ($out -join "`n") | Should -Match 'AUTHLENS-RESTORE-REHEARSAL:'
    }
}
