<# Fixed Task Scheduler action. Never accepts a command, script, executable or arbitrary argument list. #>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$JobId)
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'
$capsule=$PSScriptRoot
Import-Module (Join-Path $capsule 'AuthLens.Admin.psm1') -Force
$id=[guid]::NewGuid().ToString('N')
$report=[ordered]@{schema=1;operation_id=$id;job_id=$JobId;started_utc=[DateTime]::UtcNow.ToString('o');finished_utc='';exit_code=4;status='refused';diagnostic='Administrative preflight failed.'}
$mutex=$null;$held=$false;$run='';$configLock=$null;$pending=Join-Path (Split-Path (Split-Path $capsule)) 'pending.json'
try {
    $run=Join-Path (Join-Path (Join-Path (Split-Path (Split-Path $capsule)) 'reports') (Split-Path $capsule -Leaf)) $id
    New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
    $manifest=Assert-ALAdminCapsule $capsule
    $jobFile=Join-Path $capsule ('jobs/'+$JobId+'.json')
    $job=Get-Content -LiteralPath $jobFile -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-ALAdminJob $job
    if($job.operation_id -cne $JobId){throw 'Administrative job identity mismatch.'}
    $configLock=[IO.File]::Open($job.configuration,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    if((Get-FileHash -LiteralPath $job.configuration -Algorithm SHA256).Hash -ine $job.config_sha256){throw 'Administrative configuration fingerprint changed.'}
    if([IO.Path]::GetFullPath($manifest.reports).TrimEnd('\') -ine (Split-Path $run)){throw 'Administrative report directory identity mismatch.'}
    $report.operation=$job.operation
    $mutex=[Threading.Mutex]::new($false,'Global\AuthLens.AdministrativeRunner')
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw 'Another administrative operation is running.'}
    $mutating=$job.operation -notin @('Health','Preflight')
    $priorPending=Test-Path -LiteralPath $pending
    if($priorPending){
        $previous=Get-Content -LiteralPath $pending -Raw|ConvertFrom-Json
        if($mutating -and ($job.operation -notin @('Recover','Stop') -or $previous.root -ine $job.root)){throw 'A prior administrative operation requires recovery for its original root.'}
    }
    if($mutating -and -not(Test-Path -LiteralPath $pending)){
        [IO.File]::WriteAllText($pending,(@{schema=1;operation_id=$id;job_id=$JobId;root=$job.root;capsule=$capsule;run=$run}|ConvertTo-Json -Compress))
    }
    $outcome=Invoke-ALAdminChild (Join-Path $capsule 'Invoke-AuthLensAdminWorker.ps1') $capsule $JobId $run $job.timeout_seconds
    $report.exit_code=$outcome.exit_code
    $report.status=if($outcome.timed_out){'timed_out_recovery_required'}elseif($outcome.exit_code -eq 0){'passed'}else{'failed'}
    $report.diagnostic=if($outcome.timed_out){'The contained process tree exceeded its approved timeout. Review retained journals before recovery.'}elseif($outcome.exit_code -eq 0){'Approved operation completed. See its structured adapter result where applicable.'}else{'Approved operation failed. Private journals and structured adapter diagnostics were retained; no raw process output is published.'}
    if($mutating -and $outcome.exit_code -eq 0 -and (-not $priorPending -or $job.operation -eq 'Recover')){Remove-Item -LiteralPath $pending -ErrorAction Stop}
}catch{
    $report.exit_code=4;$report.status='refused_or_failed'
    $report.error_type=$_.Exception.GetType().Name
    # Raw native/parser exceptions may contain private paths/content. Publish only type and stage-independent safe wording.
}finally{
    $report.finished_utc=[DateTime]::UtcNow.ToString('o')
    if($run){[IO.File]::WriteAllText((Join-Path $run 'result.json'),($report|ConvertTo-Json -Depth 4))}
    if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
    if($configLock){$configLock.Dispose()}
}
exit $report.exit_code
