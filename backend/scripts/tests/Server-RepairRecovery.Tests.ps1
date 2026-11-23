BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Interrupted offline repair recovery is bound and fail closed' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $run=Join-Path $root 'deployment/runs/repair-test'
        $old=Join-Path $root 'releases/old';$new=Join-Path $root 'releases/new'
        New-Item -ItemType Directory -Path $run,$old,$new,(Join-Path $root 'data') -Force|Out-Null
        foreach($release in $old,$new){Set-Content (Join-Path $release 'build-manifest.json') 'same installed manifest'}
        $file=Join-Path $root 'deploy.json';Set-Content $file '{}'
        Set-Content (Join-Path $root 'data/authlens.sqlite3') 'synthetic database'
        $config=[pscustomobject]@{Root=$root;ConfigFile=$file;WorkRoot=(Join-Path $root 'deployment');ReleasesRoot=(Join-Path $root 'releases');DataDirectory=(Join-Path $root 'data');ServiceName='AuthLens';ServiceAccount='NT SERVICE\AuthLens';StopTimeoutSeconds=10}
        $journal=[pscustomobject]@{schema=2;operation='offline repair';phase='switching';root=$root;config_file=$file;config_sha256=(Get-FileHash $file).Hash.ToLowerInvariant();service_name='AuthLens';service_account=$config.ServiceAccount;source_sha=('a'*40);version='2.0.0-alpha.1';from_release=$old;to_release=$new;backup=@{file=(Join-Path $root 'backup.slbak');sha256=('b'*64)};run=$run}
        $path=Join-Path $run 'repair-journal.json';Write-ALInstallerJournal $path $journal
        $marker=Join-Path $config.WorkRoot 'repair-pending.json';[IO.File]::WriteAllText($marker,$path)
        Mock -ModuleName AuthLens.Deploy Get-ALCurrentLink {'current'}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$new}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerPackage {[pscustomobject]@{source_sha=('a'*40);version='2.0.0-alpha.1'}}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;Account='NT SERVICE\AuthLens';State='Stopped';PathName='synthetic'}}
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary {$true}
        Mock -ModuleName AuthLens.Deploy Compare-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALServiceArguments {@()}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {
            param($ExePath,$Arguments)
            if($Arguments[0] -eq '--backup-verify'){[pscustomobject]@{verified=$true;sha256=('b'*64)}}
            else{[pscustomobject]@{validated=$true;read_only=$true;source_sha=('a'*40);version='2.0.0-alpha.1';schema=@{pending=@()}}}
        }
        Mock -ModuleName AuthLens.Deploy Set-ALLink {}
        Mock -ModuleName AuthLens.Deploy Grant-ALAccess {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady {}
    }
    It 'completes verified replacement and clears the barrier only after readiness' {
        (Invoke-ALInstallerRepairRecover $config).recovered|Should -BeTrue
        (Get-Content $path -Raw|ConvertFrom-Json).phase|Should -Be 'complete'
        Test-Path $marker|Should -BeFalse
        Test-Path $old|Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1
        Should -Invoke -ModuleName AuthLens.Deploy Get-ALInstallerPackage -Times 1 -ParameterFilter {$PublishedServer}
    }
    It 'refuses changed configuration without stopping the service' {
        Add-Content $file 'changed'
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*bindings*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        Test-Path $marker|Should -BeTrue
    }
    It 'refuses legacy unbound journal evidence without deleting it' {
        $journal.schema=1;Write-ALInstallerJournal $path $journal
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*bindings*'
        Test-Path $marker|Should -BeTrue
    }
    It 'refuses a journal reference outside the protected runs directory' {
        [IO.File]::WriteAllText($marker,$file)
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*approved evidence directory*'
        Should -Invoke -ModuleName AuthLens.Deploy Get-ALInstallerPackage -Times 0
    }
    It 'refuses a backup that no longer verifies before service changes' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{verified=$false;sha256=('c'*64)}}
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*backup no longer verifies*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
    }
    It 'retains the recovery barrier and attempts stop on readiness failure' {
        Mock -ModuleName AuthLens.Deploy Wait-ALReady {throw 'synthetic readiness failure'}
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*failed readiness*'
        (Get-Content $path -Raw|ConvertFrom-Json).phase|Should -Be 'manual_recovery_required'
        Test-Path $marker|Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 2
    }
    It 'refuses an unrelated active release' {
        Mock -ModuleName AuthLens.Deploy Get-ALLink {'unrelated'}
        {Invoke-ALInstallerRepairRecover $config}|Should -Throw '*unrelated active release*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
    }
}
