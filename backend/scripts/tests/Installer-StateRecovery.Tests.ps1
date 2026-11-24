BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'State classification and explicit program-only quarantine' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config')|Out-Null
        $file=Join-Path $root 'config/deploy.json'
        @{Root=$root;ListenAddress='127.0.0.1';Port=18795}|ConvertTo-Json|Set-Content $file
        $config=Read-AuthLensSettings $file -Packaged
        $resolved=[pscustomobject]@{Config=$config;ConfigSha256=(Get-FileHash $file).Hash.ToLowerInvariant();ProgramDirectory=(Join-Path $root 'app')}
        $evidence=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;State='Missing'}}
        Mock -ModuleName AuthLens.Deploy Get-ALListener {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerLegacyPresence {[pscustomobject]@{present=@();unknown=@()}}
        Mock -ModuleName AuthLens.Deploy Enter-ALLock {}
        Mock -ModuleName AuthLens.Deploy Exit-ALLock {}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Assert-ALFailedPreflightOwner {}
        Mock -ModuleName AuthLens.Deploy New-ALProtectedDirectorySecurity {$null}
        Mock -ModuleName AuthLens.Deploy New-ALDirectoryWithAcl {param($Path) New-Item -ItemType Directory -Path $Path|Out-Null}
        # Ownership/package proof is supplied by the separately tested full Setup planner. Never
        # invoke a real server or service here; verify this boundary is called with the receipt.
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupPlan {[pscustomobject]@{read_only=$true}}
    }
    It 'does not treat an expected journal path as an interrupted transaction' {
        $state=Get-ALServerInstallationState $resolved
        $state.state|Should -Be 'clean_program_target'
        $state.deployment_journal_exists|Should -BeFalse
        Test-Path (Get-ALJournalPath $config)|Should -BeFalse
    }
    It 'protects retained data and classifies actual interrupted journal state separately' {
        New-Item -ItemType Directory -Force $config.DataDirectory,$config.WorkRoot|Out-Null
        Set-Content (Join-Path $config.DataDirectory 'authlens.sqlite3') 'synthetic data sentinel'
        (Get-ALServerInstallationState $resolved).state|Should -Be 'protected_application_data'
        @{phase='manual_recovery_required'}|ConvertTo-Json|Set-Content (Get-ALJournalPath $config)
        (Get-ALServerInstallationState $resolved).state|Should -Be 'interrupted_deployment'
        Get-Content (Join-Path $config.DataDirectory 'authlens.sqlite3')|Should -Be 'synthetic data sentinel'
    }
    It 'quarantines only a verified program directory and is idempotent after the atomic move' {
        $app=Join-Path $root 'app'
        New-Item -ItemType Directory -Force (Join-Path $app 'setup/pkg')|Out-Null
        Set-Content (Join-Path $app 'setup/pkg/transaction-diagnostic.txt') 'diagnostic sentinel'
        $before=(Get-FileHash $file).Hash
        $result=Move-ALFailedSetupProgramToEvidence $resolved 'synthetic-package' 'synthetic-metadata' 'verified-failure-receipt' $evidence -Approved
        $result.quarantined|Should -BeTrue
        $result.data_deleted|Should -BeFalse
        Test-Path $app|Should -BeFalse
        Get-Content (Join-Path $evidence 'app/setup/pkg/transaction-diagnostic.txt')|Should -Be 'diagnostic sentinel'
        (Get-FileHash $file).Hash|Should -Be $before
        $journalHash=(Get-FileHash (Join-Path $evidence 'program-quarantine.json')).Hash
        (Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $evidence -Approved).phase|Should -Be 'complete'
        (Get-FileHash (Join-Path $evidence 'program-quarantine.json')).Hash|Should -Be $journalHash
        Should -Invoke -ModuleName AuthLens.Deploy Get-ALServerSetupPlan -Times 1 -ParameterFilter {$FailedPreflightReceipt -eq 'verified-failure-receipt' -and $Operation -eq 'Install'}
    }
    It 'requires explicit approval and refuses existing data before a move' {
        {Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $evidence}|Should -Throw '*explicit approval*'
        New-Item -ItemType Directory $config.DataDirectory|Out-Null
        Set-Content (Join-Path $config.DataDirectory 'sentinel') 'protected'
        {Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $evidence -Approved}|Should -Throw '*Retained data*'
        Test-Path $evidence|Should -BeFalse
    }
    It 'refuses a service, ambiguous ownership or tampered retained evidence' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;State='Running'}}
        {Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $evidence -Approved}|Should -Throw '*service, listener or deployment journal*'
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;State='Missing'}}
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupPlan {throw 'unverified ownership'}
        {Move-ALFailedSetupProgramToEvidence $resolved 'pkg' 'metadata' 'receipt' $evidence -Approved}|Should -Throw '*unverified ownership*'
        Test-Path $evidence|Should -BeFalse
    }
    It 'refuses hash changes in quarantined artifacts and unknown evidence directories' {
        New-Item -ItemType Directory (Join-Path $root 'app')|Out-Null
        Set-Content (Join-Path $root 'app/sentinel') 'owned bytes'
        $null=Move-ALFailedSetupProgramToEvidence $resolved 'pkg' 'metadata' 'receipt' $evidence -Approved
        Set-Content (Join-Path $evidence 'app/sentinel') 'changed'
        {Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $evidence -Approved}|Should -Throw '*quarantine integrity changed*'
        $foreign=Join-Path $TestDrive 'foreign-evidence';New-Item -ItemType Directory $foreign|Out-Null
        {Move-ALFailedSetupProgramToEvidence $resolved '' '' '' $foreign -Approved}|Should -Throw
    }
}
