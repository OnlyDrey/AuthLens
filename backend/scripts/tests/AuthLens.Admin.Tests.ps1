BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../deploy/AuthLens.Admin.psm1') -Force
}
Describe 'Pinned administrative jobs have no arbitrary-command interface' {
    BeforeEach {
        $job=[pscustomobject]@{schema=1;product='AuthLens';operation_id=('a'*32);operation='Preflight';configuration=(Join-Path $TestDrive 'deploy.json');config_sha256=('b'*64);package=(Join-Path $TestDrive 'package');root=(Join-Path $TestDrive 'server');timeout_seconds=120}
    }
    It 'accepts only the supported exact operation names' {
        foreach($operation in Get-ALAdminOperations){$job.operation=$operation;{Assert-ALAdminJob $job}|Should -Not -Throw}
    }
    It 'refuses unrestricted operation <Operation>' -ForEach @(@{Operation='Execute'},@{Operation='PowerShell'},@{Operation='cmd.exe'},@{Operation='Install;whoami'},@{Operation='install'},@{Operation='DeleteFiles'}) {
        $job.operation=$Operation
        {Assert-ALAdminJob $job}|Should -Throw '*Unsupported*'
    }
    It 'refuses additional arguments or executable fields' {
        $job|Add-Member executable 'cmd.exe'
        {Assert-ALAdminJob $job}|Should -Throw '*fields*'
    }
    It 'requires a pinned configuration hash and bounded integral timeout' {
        $job.config_sha256='unapproved';{Assert-ALAdminJob $job}|Should -Throw '*fingerprint*'
        $job.config_sha256='b'*64
        $job.timeout_seconds=1801;{Assert-ALAdminJob $job}|Should -Throw '*timeout*'
        $job.timeout_seconds='120';{Assert-ALAdminJob $job}|Should -Throw '*timeout*'
    }
    It 'refuses command-line injection in approved paths' {
        $job.configuration+='" -Command whoami'
        {Assert-ALAdminJob $job}|Should -Throw '*paths*'
    }
    It 'maps fixed adapter verbs and forwards configuration fingerprints' {
        $args=Get-ALAdminAdapterArguments $job $TestDrive (Join-Path $TestDrive 'result.json')
        $args|Should -Contain '-PreflightOnly'
        $args|Should -Contain '-ExpectedConfigSha256'
        $args|Should -Contain ('b'*64)
        ($args[0..4] -join '|')|Should -Be '-NoProfile|-NonInteractive|-ExecutionPolicy|Bypass|-File'
        $args|Should -Not -Contain '-Command'
        $args|Should -Not -Contain '-Yes'
        $job.operation='Upgrade'
        $args=Get-ALAdminAdapterArguments $job $TestDrive (Join-Path $TestDrive 'result.json')
        $args|Should -Contain '-Yes'
        $args|Should -Contain 'Upgrade'
    }
    It 'never maps service verbs to arbitrary installer operations' {
        $job.operation='Start'
        {Get-ALAdminAdapterArguments $job $TestDrive (Join-Path $TestDrive 'result.json')}|Should -Throw '*not an installer invocation*'
    }
    It 'pins uninstall to preservation without arbitrary paths or deletion flags' {
        $job.operation='Uninstall'
        $args=Get-ALAdminAdapterArguments $job $TestDrive (Join-Path $TestDrive 'result.json')
        $args|Should -Contain 'Uninstall'
        $args|Should -Contain '-Yes'
        $args|Should -Not -Contain '-Package'
        $args|Should -Not -Contain '-RemoveData'
    }
    It 'quotes paths including trailing backslashes without shell evaluation' {
        (ConvertTo-ALAdminCommandLine @('C:\a b\','-File','C:\a.ps1'))|Should -Be '"C:\a b\\" "-File" "C:\a.ps1"'
        {ConvertTo-ALAdminCommandLine @("x`r`nwhoami")}|Should -Throw '*delimiter*'
    }
}
Describe 'Administrative capsule integrity' {
    BeforeEach {
        Mock -ModuleName AuthLens.Admin Assert-ALAdminProtection {}
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root|Out-Null
        $file=Join-Path $root 'worker.ps1';Set-Content -LiteralPath $file 'approved bytes'
        $manifest=@{schema=1;product='AuthLens';files=@(@{path='worker.ps1';sha256=(Get-FileHash -LiteralPath $file).Hash})}
        $path=Join-Path $root 'capsule.json';$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $path
    }
    It 'accepts unchanged approved bytes' {
        (Assert-ALAdminCapsule $root).product|Should -Be 'AuthLens'
        Should -Invoke -ModuleName AuthLens.Admin Assert-ALAdminProtection -Times 2
    }
    It 'refuses a modified executable payload' {
        Add-Content -LiteralPath $file 'changed'
        {Assert-ALAdminCapsule $root}|Should -Throw '*integrity failed*'
    }
    It 'refuses traversal in manifest paths' {
        $manifest.files[0].path='../outside.ps1';$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $path
        {Assert-ALAdminCapsule $root}|Should -Throw '*capsule path*'
    }
    It 'refuses inputs whose DACL permits non-administrative mutation' {
        Mock -ModuleName AuthLens.Admin Assert-ALAdminProtection {throw 'Non-administrative mutation of privileged inputs is forbidden.'}
        {Assert-ALAdminCapsule $root}|Should -Throw '*Non-administrative mutation*'
    }
}
Describe 'Privileged inputs reject operator ownership and mutation rights' {
    BeforeEach {
        $acl=[pscustomobject]@{owner='S-1-5-32-544';rules=@()}
        $acl|Add-Member ScriptMethod GetOwner {param($Type) [Security.Principal.SecurityIdentifier]::new($this.owner)}
        $acl|Add-Member ScriptMethod GetAccessRules {param($Explicit,$Inherited,$Type) $this.rules}
        Mock -ModuleName AuthLens.Admin Get-Acl {$acl}
    }
    It 'accepts only administrative ownership and read-only operator access' {
        $acl.rules=@([Security.AccessControl.FileSystemAccessRule]::new('S-1-5-21-123-456-789-1001','ReadAndExecute','Allow'))
        {Assert-ALAdminProtection 'synthetic'}|Should -Not -Throw
    }
    It 'refuses implicit owner rights for a non-elevated operator' {
        $acl.owner='S-1-5-21-123-456-789-1001'
        {Assert-ALAdminProtection 'synthetic'}|Should -Throw '*owner must be SYSTEM or Administrators*'
    }
    It 'refuses operator rights <Right>' -ForEach @(@{Right='WriteData'},@{Right='DeleteSubdirectoriesAndFiles'},@{Right='ChangePermissions'},@{Right='TakeOwnership'},@{Right='FullControl'}) {
        $acl.rules=@([Security.AccessControl.FileSystemAccessRule]::new('S-1-5-21-123-456-789-1001',$Right,'Allow'))
        {Assert-ALAdminProtection 'synthetic'}|Should -Throw '*mutation*'
    }
}
Describe 'Administrative bootstrap and worker isolation contracts' {
    It 'uses SYSTEM highest privileges with no credentials, triggers or runtime command input' {
        $bootstrap=Get-Content (Join-Path $PSScriptRoot '../Register-AuthLensAdmin.ps1') -Raw
        $bootstrap|Should -Match "Principal.UserId='SYSTEM'"
        $bootstrap|Should -Match 'Principal.RunLevel=1'
        $bootstrap|Should -Match 'O:BAG:BAD:P'
        $bootstrap|Should -Not -Match 'Start-Process|RunAs|Triggers.Create|Set-ExecutionPolicy'
        $bootstrap|Should -Match 'Get-ALAdminTaskArguments \$capsule \$job.task_name'
        $bootstrap|Should -Match 'RegisterTaskDefinition\(\$job.task_name,\$definition,2'
    }
    It 'generates the fixed scheduler entrypoint with process-scoped execution policy' {
        $args=Get-ALAdminTaskArguments 'C:\Protected capsule' ('a'*32)
        (ConvertTo-ALAdminCommandLine $args)|Should -Be ('"-NoProfile" "-NonInteractive" "-ExecutionPolicy" "Bypass" "-File" "C:\Protected capsule\Invoke-AuthLensAdmin.ps1" "-JobId" "'+('a'*32)+'"')
        $args|Should -Not -Contain '-Command'
        {Get-ALAdminTaskArguments 'C:\Protected capsule' 'unapproved'}|Should -Throw
    }
    It 'contains a worker before enabling its operation and preserves interrupted-operation barriers' {
        $module=Get-Content (Join-Path $PSScriptRoot '../deploy/AuthLens.Admin.psm1') -Raw
        $runner=Get-Content (Join-Path $PSScriptRoot '../Invoke-AuthLensAdmin.ps1') -Raw
        $worker=Get-Content (Join-Path $PSScriptRoot '../Invoke-AuthLensAdminWorker.ps1') -Raw
        $module.IndexOf('Assign($process.Handle)')|Should -BeLessThan $module.IndexOf("WriteAllText((Join-Path `$Run 'contained')")
        $module|Should -Match 'TerminateJobObject'
        $module|Should -Match 'WaitForExit\(\$TimeoutSeconds\*1000\)'
        $runner|Should -Match 'pending.json'
        $runner|Should -Match 'timed_out_recovery_required'
        $worker|Should -Match 'containment was not established'
        $worker|Should -Match 'refuses empty database initialization'
    }
}
Describe 'Native Windows administrative process containment (no elevation or service change)' {
    It 'starts the contained worker with Bypass even when the calling process is Restricted' {
        if([IO.Path]::DirectorySeparatorChar -ne '\'){Set-ItResult -Skipped -Because 'Windows PowerShell process policy requires native Windows.';return}
        $run=Join-Path $TestDrive 'native-policy';New-Item -ItemType Directory $run|Out-Null
        $worker=Join-Path $run 'worker.ps1'
        @'
param($Capsule,$JobId,$Run)
[IO.File]::WriteAllText((Join-Path $Run 'worker-policy.json'),(@{process=[string](Get-ExecutionPolicy -Scope Process);sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json))
'@|Set-Content -LiteralPath $worker
        $before=$env:PSExecutionPolicyPreference
        try{
            $env:PSExecutionPolicyPreference='Restricted'
            $outcome=Invoke-ALAdminChild $worker $TestDrive ('a'*32) $run 10
            $outcome.exit_code|Should -Be 0
            $outcome.timed_out|Should -BeFalse
            (Get-Content (Join-Path $run 'worker-policy.json') -Raw|ConvertFrom-Json).process|Should -Be 'Bypass'
            Get-ExecutionPolicy -Scope Process|Should -Be 'Restricted'
        }finally{$env:PSExecutionPolicyPreference=$before}
    }
    It 'terminates a timed-out worker and its descendant while retaining its work directory' {
        if([IO.Path]::DirectorySeparatorChar -ne '\'){Set-ItResult -Skipped -Because 'Windows Job Objects require native Windows.';return}
        $run=Join-Path $TestDrive 'native-contained'
        New-Item -ItemType Directory -Path $run|Out-Null
        $worker=Join-Path $TestDrive 'native-worker.ps1'
        @'
param($Capsule,$JobId,$Run)
$deadline=[DateTime]::UtcNow.AddSeconds(10)
while(-not(Test-Path -LiteralPath (Join-Path $Run 'contained'))){if([DateTime]::UtcNow -gt $deadline){exit 3};Start-Sleep -Milliseconds 50}
$child=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
[IO.File]::WriteAllText((Join-Path $Run 'descendant.pid'),[string]$child.Id)
Start-Sleep -Seconds 60
'@|Set-Content -LiteralPath $worker
        $outcome=Invoke-ALAdminChild $worker $TestDrive ('a'*32) $run 5
        $outcome.timed_out|Should -BeTrue
        $outcome.exit_code|Should -Be 4
        $pidFile=Join-Path $run 'descendant.pid'
        Test-Path -LiteralPath $pidFile|Should -BeTrue
        $descendant=Get-Process -Id ([int](Get-Content -LiteralPath $pidFile)) -ErrorAction SilentlyContinue
        if($descendant){$descendant.WaitForExit(3000)|Should -BeTrue}
        Test-Path -LiteralPath $run|Should -BeTrue
    }
}
