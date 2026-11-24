BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Fresh deployment recovery revalidates candidate invariants' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config'),(Join-Path $root 'data'),(Join-Path $root 'deployment'),(Join-Path $root 'releases/candidate')|Out-Null
        $file=Join-Path $root 'config/deploy.json'
        @{Root=$root;ListenAddress='127.0.0.1';Port=18795}|ConvertTo-Json|Set-Content $file
        $config=Read-AuthLensSettings $file -Packaged
        $candidate=Join-Path $root 'releases/candidate'
        $sha='b'*40
        @{product='AuthLens';version='2.0.0';source_sha=$sha}|ConvertTo-Json|Set-Content (Join-Path $candidate 'build-manifest.json')
        @{schema=1;product='AuthLens';root=$root;data_directory=$config.DataDirectory;instance_id=('a'*32)}|ConvertTo-Json|Set-Content (Join-Path $config.DataDirectory '.authlens-owned-data.json')
        Set-Content (Join-Path $config.DataDirectory 'authlens.sqlite3') 'synthetic database sentinel'
        Write-ALJournal $config ([pscustomobject]@{phase='manual_recovery_required';run='synthetic';from_release='';to_release=$candidate;commit=$sha;version='2.0.0';backup=$null;service_binary_before='';service_state_before='Missing';history=@();updated=''})
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Running';Account=$config.ServiceAccount;PathName='owned synthetic service'}}
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary {$true}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$candidate}
        Mock -ModuleName AuthLens.Deploy Test-ALPublishedRelease {[pscustomobject]@{Verified=$true}}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{validated=$true;read_only=$true;data_modified=$false;source_sha=$sha;version='2.0.0';schema=[pscustomobject]@{compatible=$true;pending=@()}}}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady {[pscustomobject]@{process_id=123;identity=[pscustomobject]@{version='2.0.0';source_sha=$sha}}}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Invoke-ALRollbackCore {throw 'No previous release; rollback must never run'}
        Mock -ModuleName AuthLens.Deploy Write-ALRecoveryInstructions {}
    }
    It 'fixes forward a running owned fresh candidate without a previous release or backup' {
        $before=(Get-FileHash (Join-Path $config.DataDirectory 'authlens.sqlite3')).Hash
        $result=Invoke-ALRecover $config -RecoveryAction VerifyCandidate
        $result.phase|Should -Be 'complete'
        $result.data_restored|Should -BeFalse
        (Read-ALJournal $config).phase|Should -Be 'complete'
        (Get-FileHash (Join-Path $config.DataDirectory 'authlens.sqlite3')).Hash|Should -Be $before
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALRollbackCore -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter {$Commit -eq $sha -and $Version -eq '2.0.0'}
    }
    It 'does not mark the journal complete when read-only preflight refuses' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {throw 'synthetic preflight refusal'}
        {Invoke-ALRecover $config -RecoveryAction VerifyCandidate}|Should -Throw '*synthetic preflight refusal*'
        (Read-ALJournal $config).phase|Should -Be 'manual_recovery_required'
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 0
    }
    It 'refuses data adoption and missing rollback prerequisites' {
        Remove-Item -LiteralPath (Join-Path $config.DataDirectory '.authlens-owned-data.json')
        {Invoke-ALRecover $config -RecoveryAction VerifyCandidate}|Should -Throw '*ownership evidence*'
        {Invoke-ALRecover $config -RecoveryAction Rollback}|Should -Throw '*verified previous release*'
        (Read-ALJournal $config).phase|Should -Be 'manual_recovery_required'
    }
    It 'starts a stopped owned candidate only with explicit Resume' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Stopped';Account=$config.ServiceAccount;PathName='owned'}}
        {Invoke-ALRecover $config -RecoveryAction VerifyCandidate}|Should -Throw '*explicit Resume*'
        Should -Invoke -ModuleName AuthLens.Deploy Start-ALService -Times 0
        (Invoke-ALRecover $config -RecoveryAction Resume).phase|Should -Be 'complete'
        Should -Invoke -ModuleName AuthLens.Deploy Start-ALService -Times 1
    }
    It 'refuses cancellation after startup and blocks normal Setup while manual recovery is pending' {
        {Invoke-ALRecover $config -RecoveryAction Cancel}|Should -Throw '*cancellation is unavailable*'
        {Assert-ALInstallerServerPreflight $config}|Should -Throw '*explicit recovery*'
    }
}
