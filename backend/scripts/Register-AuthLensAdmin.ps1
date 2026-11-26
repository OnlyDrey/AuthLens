<#
.SYNOPSIS
  One-time elevated bootstrap of fixed AuthLens development-VM operations. No UAC attempts, passwords, triggers or arbitrary-command interface.
.DESCRIPTION
  Administrator approval pins this exact tools/package/configuration revision. A later payload/configuration revision requires a new explicit
  elevated bootstrap; an unprivileged build cannot replace SYSTEM's executable inputs. Existing capsules/tasks and recovery material are retained.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$ToolsDirectory,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$RecoveryBundle,
    [string]$OperatorSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
    [ValidateSet('Health','Preflight','Install','Upgrade','Repair','Recover','Uninstall','Start','Stop','Restart')][string[]]$Operations=@('Health','Preflight'),
    [ValidateRange(10,1800)][int]$TimeoutSeconds=1200,
    [switch]$Approve
)
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'
if(-not $Approve){throw 'Review the exact payload/configuration and approved operations, then supply -Approve from an elevated administrator session.'}
if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Initial elevation is unavailable. Run this bootstrap once in an administrator terminal. No UAC attempt was made.'}
Import-Module (Join-Path $PSScriptRoot 'deploy/AuthLens.Deploy.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'deploy/AuthLens.Admin.psm1') -Force
$operator=New-Object Security.Principal.SecurityIdentifier($OperatorSid)
$account=@(Get-CimInstance Win32_UserAccount -Filter "SID='$($operator.Value)'" -ErrorAction Stop)
if($account.Count -ne 1 -or -not $account[0].LocalAccount -or $account[0].Disabled){throw 'The development operator must be one enabled local user SID, never a group or broad principal.'}
foreach($path in $Package,$ToolsDirectory,$ConfigFile,$RecoveryBundle){Assert-ALInstallerPath $path}
$config=Read-AuthLensSettings $ConfigFile -Packaged
Assert-ALInstallerServerConfiguration $config
if($config.ServiceName -cne 'AuthLens'){throw 'Administrative bootstrap supports only the canonical AuthLens service.'}
# No administration profile may target developer tools, a repository, a drive root or independent recovery storage.
$allowedRoots=@('C:\ProgramData\AuthLens','C:\AuthLens-Lifecycle\Server')
if([IO.Path]::GetFullPath($config.Root).TrimEnd('\') -notin $allowedRoots){throw 'Choose the canonical development installation or the dedicated AuthLens lifecycle Server root.'}
foreach($path in $config.DataDirectory,$config.BackupRoot,$config.WorkRoot,$config.ReleasesRoot,$config.CertificatePath,$config.CertificatePasswordFile){
    if(-not(Test-ALPathWithin $path $config.Root)){throw 'Administrative jobs require all mutable/TLS paths beneath their approved installation root.'}
}
if(-not(Test-ALPathWithin $RecoveryBundle 'C:\AuthLens-Recovery') -or (Test-ALPathOverlap $RecoveryBundle $config.Root)){throw 'Independent recovery must remain outside all administrative target roots.'}
$private=Get-Content -LiteralPath (Join-Path $RecoveryBundle 'private-inventory.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($file in $private.files){
    if(-not(Test-ALPathWithin $file.copy $RecoveryBundle) -or (Get-FileHash -LiteralPath $file.copy -Algorithm SHA256).Hash -ine $file.sha256){throw 'Independent recovery inventory verification failed.'}
}
if(-not(Test-ALPathWithin $private.backup.file $RecoveryBundle) -or (Get-FileHash -LiteralPath $private.backup.file -Algorithm SHA256).Hash -ine $private.backup.sha256){throw 'Independent recovery archive hash failed.'}
$helperFiles=@('Install-AuthLens.ps1','verify-release.ps1','deploy/AuthLens.Deploy.psm1','deploy/Deploy-AuthLens.ps1','deploy/AuthLens.Paths.ps1','deploy/AuthLens.Acl.ps1','deploy/AuthLens.Installer.ps1')
$helperProof=Get-Content -LiteralPath (Join-Path $ToolsDirectory 'installer-tools.json') -Raw -Encoding UTF8|ConvertFrom-Json
# QA-028: packages built since then also carry the recovery scripts and the acceptance module the restore rehearsal imports.
$recoveryHelpers=@('recovery/New-AuthLensRecoveryBundle.ps1','recovery/Test-AuthLensRestoreRehearsal.ps1','acceptance/AuthLens.Acceptance.psm1')
if((@($helperProof.files.path|Sort-Object)-join '|') -ceq (@(@($helperFiles)+@($recoveryHelpers)|Sort-Object)-join '|')){$helperFiles=@($helperFiles)+@($recoveryHelpers)}
if((@($helperProof.files.path|Sort-Object)-join '|') -cne (@($helperFiles|Sort-Object)-join '|')){throw 'Reviewed helper inventory mismatch.'}
foreach($file in $helperProof.files){if((Get-FileHash -LiteralPath (Join-Path $ToolsDirectory $file.path) -Algorithm SHA256).Hash -ine $file.sha256){throw 'Reviewed helper integrity failed.'}}
$id=[guid]::NewGuid().ToString('N')
$root='C:\ProgramData\AuthLensAdmin'
function New-AdminPrivateDirectory([string]$Path,[switch]$Traverse,[switch]$ReadReports) {
    $security=New-ALProtectedDirectorySecurity
    $security.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    if($Traverse){$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($operator,'Traverse','None','None','Allow'))}
    if($ReadReports){$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($operator,'ReadAndExecute','ContainerInherit, ObjectInherit','None','Allow'))}
    New-ALDirectoryWithAcl $Path $security
}
if(Test-Path -LiteralPath $root){
    Test-ALPathTree $root
    Assert-ALAdminProtection $root
}else{New-AdminPrivateDirectory $root -Traverse}
foreach($name in 'capsules','reports'){
    $path=Join-Path $root $name
    if(-not(Test-Path -LiteralPath $path)){New-AdminPrivateDirectory $path -Traverse}
    Assert-ALAdminProtection $path
}
$capsule=Join-Path (Join-Path $root 'capsules') $id
$reports=Join-Path (Join-Path $root 'reports') $id
New-AdminPrivateDirectory $capsule
New-AdminPrivateDirectory $reports -ReadReports
function Copy-ApprovedFile([string]$Source,[string]$Target) {
    $hash=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    New-Item -ItemType Directory -Path (Split-Path $Target) -Force|Out-Null
    [IO.File]::Copy($Source,$Target,$false)
    # Set the owner explicitly: inheritance/CREATOR OWNER must not give the medium-integrity operator mutation rights.
    $acl=Get-Acl -LiteralPath $Target;$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));Set-Acl -LiteralPath $Target -AclObject $acl
    if((Get-FileHash -LiteralPath $Target).Hash -ine $hash -or (Get-FileHash -LiteralPath $Source).Hash -ine $hash){throw 'Approved input changed during protected capture.'}
}
Copy-ApprovedFile (Join-Path $PSScriptRoot 'deploy/AuthLens.Admin.psm1') (Join-Path $capsule 'AuthLens.Admin.psm1')
foreach($name in 'Invoke-AuthLensAdmin.ps1','Invoke-AuthLensAdminWorker.ps1'){Copy-ApprovedFile (Join-Path $PSScriptRoot $name) (Join-Path $capsule $name)}
foreach($name in @($helperFiles)+@('installer-tools.json')){Copy-ApprovedFile (Join-Path $ToolsDirectory $name) (Join-Path (Join-Path $capsule 'tools') $name)}
$source=[IO.Path]::GetFullPath($Package).TrimEnd('\')
$protectedPackage=Join-Path $capsule ('package/'+(Split-Path $source -Leaf))
foreach($file in @(Get-ALTreeFiles $source)){
    $relative=$file.FullName.Substring($source.Length).TrimStart('\','/')
    Copy-ApprovedFile $file.FullName (Join-Path $protectedPackage $relative)
}
# Execute only the protected, snapshotted verifier; no subsequent privileged job executes code from the working tree.
Import-Module (Join-Path $capsule 'tools/deploy/AuthLens.Deploy.psm1') -Force
$release=Get-ALInstallerPackage $protectedPackage
Copy-ApprovedFile $ConfigFile (Join-Path $capsule 'approved-config.json')
$configHash=(Get-FileHash -LiteralPath (Join-Path $capsule 'approved-config.json')).Hash.ToLowerInvariant()
$jobs=@()
New-Item -ItemType Directory -Path (Join-Path $capsule 'jobs')|Out-Null
foreach($operation in @($Operations|Sort-Object -Unique)){
    $job=[pscustomobject]@{schema=1;product='AuthLens';operation_id=[guid]::NewGuid().ToString('N');operation=$operation;configuration=$ConfigFile;config_sha256=$configHash;package=$protectedPackage;root=$config.Root;timeout_seconds=$TimeoutSeconds}
    Assert-ALAdminJob $job
    [IO.File]::WriteAllText((Join-Path $capsule ('jobs/'+$job.operation_id+'.json')),($job|ConvertTo-Json -Depth 4))
    $jobs+=@{operation=$operation;task_name=$job.operation_id}
}
$files=@(Get-ALTreeFiles $capsule|ForEach-Object{@{path=$_.FullName.Substring($capsule.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
[IO.File]::WriteAllText((Join-Path $capsule 'capsule.json'),(@{schema=1;product='AuthLens';id=$id;reports=$reports;source_sha=$release.source_sha;files=$files}|ConvertTo-Json -Depth 6))
foreach($item in @((Get-Item -LiteralPath $capsule))+@(Get-ChildItem -LiteralPath $capsule -Recurse -Force)){
    $acl=Get-Acl -LiteralPath $item.FullName;$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));Set-Acl -LiteralPath $item.FullName -AclObject $acl
    Assert-ALAdminProtection $item.FullName
}
$null=Assert-ALAdminCapsule $capsule
# Prove the copied key can decrypt and validate the archive using the approved protected application.
$probe=Join-Path $root ('recovery-check-'+$id)
New-AdminPrivateDirectory $probe
$env:AUTHLENS_BACKUP_KEY_FILE=$null;$env:AUTHLENS_BACKUP_PASSPHRASE=$null
$exe=Join-Path $protectedPackage 'server/AuthLens.Api.exe'
$null=Invoke-ALMaintenance $exe @('--backup-key','use',(Join-Path $RecoveryBundle 'selected/host-recovery.key'),'--data-dir',$probe)
$verification=Invoke-ALMaintenance $exe @('--backup-verify',$private.backup.file,'--data-dir',$probe)
if(-not $verification.verified -or $verification.sha256 -ine $private.backup.sha256){throw 'Independent archive verification failed; no task was registered.'}
$scheduler=New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$sddl='O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGX;;;'+$operator.Value+')'
$folderName='AuthLens-Development-'+$id
$folder=$scheduler.GetFolder('\').CreateFolder($folderName,$sddl)
$registered=@()
try {
    foreach($job in $jobs){
        $definition=$scheduler.NewTask(0)
        $definition.RegistrationInfo.Author='AuthLens development administration'
        $definition.RegistrationInfo.Description='Pinned AuthLens '+$job.operation+'; capsule '+$id+'; no arbitrary arguments.'
        $definition.Principal.UserId='SYSTEM';$definition.Principal.LogonType=5;$definition.Principal.RunLevel=1
        $definition.Settings.Enabled=$true;$definition.Settings.AllowDemandStart=$true;$definition.Settings.MultipleInstances=2
        $definition.Settings.DisallowStartIfOnBatteries=$false;$definition.Settings.StopIfGoingOnBatteries=$false
        $definition.Settings.AllowHardTerminate=$false;$definition.Settings.ExecutionTimeLimit='PT35M'
        $action=$definition.Actions.Create(0)
        $action.Path=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $action.Arguments=ConvertTo-ALAdminCommandLine (Get-ALAdminTaskArguments $capsule $job.task_name)
        $action.WorkingDirectory=$capsule
        $null=$folder.RegisterTaskDefinition($job.task_name,$definition,2,'SYSTEM',$null,5,$sddl)
        $registered+=$job.task_name
    }
}catch{
    foreach($name in $registered){$folder.DeleteTask($name,0)}
    throw 'Task registration failed; registered tasks from this bootstrap were removed. Protected evidence was retained.'
}
$summary=@{schema=1;capsule_id=$id;task_path=('\'+$folderName+'\');jobs=$jobs;reports=$reports;source_sha=$release.source_sha;recovery_verified=$true;credentials_stored=$false;automatic_triggers=$false}
[IO.File]::WriteAllText((Join-Path $reports 'bootstrap.json'),($summary|ConvertTo-Json -Depth 5))
$summary|ConvertTo-Json -Depth 5
