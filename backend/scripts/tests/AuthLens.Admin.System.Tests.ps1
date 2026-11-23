BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    Import-Module (Join-Path $PSScriptRoot '../deploy/AuthLens.Admin.psm1') -Force
}
Describe 'Opt-in native SYSTEM execution policy acceptance (no AuthLens operations)' {
    It 'runs the generated task entrypoint and contained worker as SYSTEM with process-only Bypass' {
        if($env:AUTHLENS_TEST_SYSTEM_EXECUTION -cne '1'){
            Set-ItResult -Skipped -Because 'Set AUTHLENS_TEST_SYSTEM_EXECUTION=1 in an elevated Windows PowerShell to register the harmless isolated SYSTEM test.';return
        }
        if([IO.Path]::DirectorySeparatorChar -ne '\' -or -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
            throw 'SYSTEM acceptance requires an elevated Windows context; no UAC attempt was made.'
        }
        $parent=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'AuthLensAdminPolicyTests'
        foreach($directory in @($parent,(Join-Path $parent ([guid]::NewGuid().ToString('N'))))){
            if(-not(Test-Path -LiteralPath $directory)){
                $acl=New-ALProtectedDirectorySecurity
                $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
                New-ALDirectoryWithAcl $directory $acl
            }
            Test-ALPathTree $directory
            Assert-ALAdminProtection $directory
            $root=$directory
        }
        $module=Join-Path $root 'AuthLens.Admin.psm1'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../deploy/AuthLens.Admin.psm1') -Destination $module
        $entry=Join-Path $root 'Invoke-AuthLensAdmin.ps1'
        @'
param($JobId)
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'AuthLens.Admin.psm1') -Force
    $before=@(Get-ExecutionPolicy -List|Where-Object Scope -ne Process|Select-Object Scope,ExecutionPolicy)|ConvertTo-Json -Compress
    $outcome=Invoke-ALAdminChild (Join-Path $PSScriptRoot 'worker.ps1') $PSScriptRoot $JobId $PSScriptRoot 10
    $after=@(Get-ExecutionPolicy -List|Where-Object Scope -ne Process|Select-Object Scope,ExecutionPolicy)|ConvertTo-Json -Compress
    @{sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;process=[string](Get-ExecutionPolicy -Scope Process);persistent_policy_unchanged=($before -ceq $after);worker_exit=$outcome.exit_code;timed_out=$outcome.timed_out}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'task-result.json')
    exit $outcome.exit_code
}catch{exit 4}
'@|Set-Content -LiteralPath $entry
        @'
param($Capsule,$JobId,$Run)
@{sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;process=[string](Get-ExecutionPolicy -Scope Process)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Run 'worker-result.json')
'@|Set-Content -LiteralPath (Join-Path $root 'worker.ps1')
        foreach($file in Get-ChildItem -LiteralPath $root -File){
            $acl=Get-Acl -LiteralPath $file.FullName
            $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));Set-Acl -LiteralPath $file.FullName -AclObject $acl
            Assert-ALAdminProtection $file.FullName
        }
        $moduleHash=(Get-FileHash -LiteralPath $module).Hash
        $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect()
        $folder=$scheduler.GetFolder('\');$name='AuthLens-PolicyTest-'+[guid]::NewGuid().ToString('N')
        $registered=$null
        try{
            $definition=$scheduler.NewTask(0)
            $definition.Principal.UserId='SYSTEM';$definition.Principal.LogonType=5;$definition.Principal.RunLevel=1
            $definition.Settings.ExecutionTimeLimit='PT1M';$definition.Settings.AllowDemandStart=$true
            $action=$definition.Actions.Create(0)
            $action.Path=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $action.Arguments=ConvertTo-ALAdminCommandLine (Get-ALAdminTaskArguments $root ('a'*32))
            $registered=$folder.RegisterTaskDefinition($name,$definition,2,'SYSTEM',$null,5,'O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)')
            $null=$registered.Run($null)
            $resultFile=Join-Path $root 'task-result.json';$deadline=[DateTime]::UtcNow.AddSeconds(30)
            while(-not(Test-Path -LiteralPath $resultFile) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
            Test-Path -LiteralPath $resultFile|Should -BeTrue -Because "SYSTEM reports are retained at $root"
            $result=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
            $result.sid|Should -Be 'S-1-5-18';$result.process|Should -Be 'Bypass'
            $result.persistent_policy_unchanged|Should -BeTrue
            $result.worker_exit|Should -Be 0;$result.timed_out|Should -BeFalse
            $worker=Get-Content -LiteralPath (Join-Path $root 'worker-result.json') -Raw|ConvertFrom-Json
            $worker.sid|Should -Be 'S-1-5-18';$worker.process|Should -Be 'Bypass'
            (Get-FileHash -LiteralPath $module).Hash|Should -Be $moduleHash
            $deadline=[DateTime]::UtcNow.AddSeconds(5)
            while($registered.State -eq 4 -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
            $registered.LastTaskResult|Should -Be 0
        }finally{
            if($registered){if($registered.State -eq 4){$registered.Stop(0)};$folder.DeleteTask($name,0)}
            Write-Host "SYSTEM policy acceptance evidence retained: $root"
        }
    }
}
