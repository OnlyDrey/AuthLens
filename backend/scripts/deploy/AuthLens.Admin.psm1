# Restricted development-VM administration. No action occurs on import.
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'
$script:AdminOperations=@('Health','Preflight','Install','Upgrade','Repair','Recover','Start','Stop','Restart')
function Assert-ALAdminJob($Job) {
    $fields=@('schema','product','operation_id','operation','configuration','config_sha256','package','root','timeout_seconds')
    if(@($Job.PSObject.Properties.Name|Where-Object{$_ -notin $fields}).Count -or @($fields|Where-Object{$_ -notin $Job.PSObject.Properties.Name}).Count){throw 'Unexpected administrative job fields.'}
    if($Job.schema -ne 1 -or $Job.product -cne 'AuthLens' -or $Job.operation_id -notmatch '^[a-f0-9]{32}$' -or $Job.operation -cnotin $script:AdminOperations){throw 'Unsupported administrative job identity or operation.'}
    if($Job.config_sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Administrative configuration must have an approved fingerprint.'}
    if($Job.timeout_seconds -isnot [int] -or $Job.timeout_seconds -lt 10 -or $Job.timeout_seconds -gt 1800){throw 'Administrative timeout must be 10..1800 seconds.'}
    foreach($field in 'configuration','package','root'){
        if($Job.$field -isnot [string] -or $Job.$field.IndexOfAny([char[]]"`r`n`0`"") -ge 0 -or -not [IO.Path]::IsPathRooted($Job.$field)){throw 'Administrative paths must be explicit and contain no control/quote characters.'}
    }
}
function Get-ALAdminOperations { $script:AdminOperations }
function Assert-ALAdminProtection([string]$Path) {
    $acl=Get-Acl -LiteralPath $Path
    if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Administrative input owner must be SYSTEM or Administrators.'}
    $write=[long]852310 -bor [long]1073741824 -bor [long]268435456
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -and ([long]$rule.FileSystemRights -band $write)){throw 'Non-administrative mutation of privileged inputs is forbidden.'}
    }
}
function Get-ALAdminAdapterArguments($Job,[string]$Tools,[string]$ResultFile) {
    Assert-ALAdminJob $Job
    $args=@('-NoProfile','-NonInteractive','-File',(Join-Path $Tools 'Install-AuthLens.ps1'),'-Mode','Server','-ConfigFile',$Job.configuration,'-ExpectedConfigSha256',$Job.config_sha256,'-ResultFile',$ResultFile)
    switch -CaseSensitive ($Job.operation) {
        'Preflight' {$args+=@('-PreflightOnly','-Package',$Job.package)}
        'Install' {$args+=@('-Operation','Install','-Package',$Job.package,'-Yes')}
        'Upgrade' {$args+=@('-Operation','Upgrade','-Package',$Job.package,'-Yes')}
        'Repair' {$args+=@('-Operation','Repair','-Package',$Job.package,'-Yes')}
        'Recover' {$args+=@('-Recover','-Yes')}
        default {throw 'This administrative operation is not an installer invocation.'}
    }
    ,$args
}
function ConvertTo-ALAdminCommandLine([string[]]$Arguments) {
    # Windows argv quoting: double backslashes preceding a closing quote. Never pass a command string to a shell evaluator.
    (@($Arguments|ForEach-Object{
        if($_.IndexOfAny([char[]]"`r`n`0`"") -ge 0){throw 'Unexpected command-line delimiter.'}
        '"'+[regex]::Replace($_,'(\\+)$','$1$1')+'"'
    }) -join ' ')
}
function Assert-ALAdminCapsule([string]$Root) {
    Assert-ALAdminProtection $Root
    $manifest=Get-Content -LiteralPath (Join-Path $Root 'capsule.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.schema -ne 1 -or $manifest.product -cne 'AuthLens'){throw 'Invalid administrative capsule.'}
    foreach($entry in $manifest.files){
        if($entry.path -notmatch '^(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$' -or $entry.path -match '(^|/)\.\.(/|$)'){throw 'Invalid administrative capsule path.'}
        $file=Join-Path $Root ($entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
        Assert-ALAdminProtection $file
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.sha256){throw 'Administrative capsule integrity failed.'}
    }
    $manifest
}
function Initialize-ALAdminProcessContainment {
    if('AuthLensAdmin.Child' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AuthLensAdminNative {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateJobObject(IntPtr a,string n);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr j,int c,IntPtr p,uint l);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateJobObject(IntPtr j,uint code);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct Basic { public long a,b;public uint flags; public UIntPtr c,d; public uint e; public UIntPtr f; public uint g,h; }
 [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] public struct Extended { public Basic basic;public Io io;public UIntPtr a,b,c,d; }
}
namespace AuthLensAdmin {
 public sealed class Child : IDisposable {
  private IntPtr job;
  public Child() {
   job=AuthLensAdminNative.CreateJobObject(IntPtr.Zero,null);
   if(job==IntPtr.Zero) throw new InvalidOperationException("Cannot create administrative job containment.");
   var info=new AuthLensAdminNative.Extended(); info.basic.flags=0x2000;
   int size=Marshal.SizeOf(info);IntPtr p=Marshal.AllocHGlobal(size);
   try {Marshal.StructureToPtr(info,p,false); if(!AuthLensAdminNative.SetInformationJobObject(job,9,p,(uint)size)) throw new InvalidOperationException("Cannot configure administrative containment.");}
   catch {Dispose();throw;} finally {Marshal.FreeHGlobal(p);}
  }
  public void Assign(IntPtr process){if(!AuthLensAdminNative.AssignProcessToJobObject(job,process))throw new InvalidOperationException("Cannot contain administrative child.");}
  public void Stop(){if(!AuthLensAdminNative.TerminateJobObject(job,4))throw new InvalidOperationException("Cannot stop administrative job.");}
  public void Dispose(){if(job!=IntPtr.Zero){AuthLensAdminNative.CloseHandle(job);job=IntPtr.Zero;}}
 }
}
'@
}
function Invoke-ALAdminChild([string]$Worker,[string]$Capsule,[string]$JobId,[string]$Run,[int]$TimeoutSeconds) {
    Initialize-ALAdminProcessContainment
    $containment=New-Object AuthLensAdmin.Child
    $process=New-Object Diagnostics.Process
    try {
        $process.StartInfo.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $process.StartInfo.Arguments=ConvertTo-ALAdminCommandLine @('-NoProfile','-NonInteractive','-File',$Worker,'-Capsule',$Capsule,'-JobId',$JobId,'-Run',$Run)
        $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
        $process.StartInfo.EnvironmentVariables['PATH']="$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        $process.StartInfo.EnvironmentVariables['PSModulePath']="$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
        foreach($key in @($process.StartInfo.EnvironmentVariables.Keys)){if($key -like 'AUTHLENS_*'){$process.StartInfo.EnvironmentVariables.Remove($key)}}
        if(-not $process.Start()){throw 'Administrative child could not start.'}
        try{$containment.Assign($process.Handle)}catch{$process.Kill();throw}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        # The worker waits for this gate. No privileged operation can run before job-object assignment succeeds.
        [IO.File]::WriteAllText((Join-Path $Run 'contained'),$JobId)
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){
            $containment.Stop();$process.WaitForExit()
            return [pscustomobject]@{exit_code=4;timed_out=$true}
        }
        $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
        [pscustomobject]@{exit_code=$process.ExitCode;timed_out=$false}
    }finally{$containment.Dispose();$process.Dispose()}
}
Export-ModuleMember -Function *
