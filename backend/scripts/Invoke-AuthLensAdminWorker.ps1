[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Capsule,[Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$JobId,[Parameter(Mandatory=$true)][string]$Run)
Set-StrictMode -Version 3
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $Capsule 'AuthLens.Admin.psm1') -Force
    $manifest=Assert-ALAdminCapsule $Capsule
    $job=Get-Content -LiteralPath (Join-Path $Capsule ('jobs/'+$JobId+'.json')) -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-ALAdminJob $job
    $gate=Join-Path $Run 'contained'
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    while(-not(Test-Path -LiteralPath $gate)){
        if([DateTime]::UtcNow -gt $deadline){throw 'Administrative containment was not established.'}
        Start-Sleep -Milliseconds 100
    }
    if((Get-Content -LiteralPath $gate -Raw) -cne $JobId){throw 'Administrative containment identity mismatch.'}
    Import-Module (Join-Path $Capsule 'tools/deploy/AuthLens.Deploy.psm1') -Force
    $config=Read-AuthLensSettings $job.configuration -Packaged
    if($config.Root -ine $job.root -or $config.ServiceName -cne 'AuthLens'){throw 'Administrative target mismatch.'}
    Assert-ALInstallerServerConfiguration $config
    if($job.operation -in @('Start','Stop','Restart','Health')){
        $service=Get-ALService 'AuthLens'
        if(-not $service.Exists -or $service.Account -ine $config.ServiceAccount -or -not(Test-ALServiceBinary $service.PathName $config) -or
            @(Compare-ALServiceArguments @((Split-ALCommandLine $service.PathName)|Select-Object -Skip 1) @(Get-ALServiceArguments $config)).Count){throw 'Administrative service ownership mismatch.'}
        if($job.operation -ne 'Stop' -and -not(Test-Path -LiteralPath (Join-Path $config.DataDirectory 'authlens.sqlite3') -PathType Leaf)){throw 'Administrative operation refuses empty database initialization.'}
        if($job.operation -in @('Start','Restart')){
            Assert-ALNoPendingRepair $config
            $journal=Read-ALJournal $config
            if($journal -and $journal.phase -in @('stopping','switched','starting','verifying')){throw 'Administrative start requires transaction recovery first.'}
        }
        if($job.operation -in @('Stop','Restart')){Stop-ALService 'AuthLens' $config.StopTimeoutSeconds}
        if($job.operation -in @('Start','Restart')){Start-ALService 'AuthLens'}
        if($job.operation -ne 'Stop'){
            $identity=Get-Content -LiteralPath (Join-Path (Get-ALLink (Get-ALCurrentLink $config)) 'build-manifest.json') -Raw|ConvertFrom-Json
            $null=Wait-ALReady $config $identity.source_sha $identity.version
        }
        exit 0
    }
    $arguments=Get-ALAdminAdapterArguments $job (Join-Path $Capsule 'tools') (Join-Path $Run 'adapter-result.json')
    $outcome=Invoke-ALProcess (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') $arguments ''
    if($outcome.ExitCode -ne 0){exit $outcome.ExitCode}
    $adapter=Get-Content -LiteralPath (Join-Path $Run 'adapter-result.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($adapter.status -cne 'completed' -or $adapter.exit_code -ne 0){throw 'Administrative adapter did not report verified completion.'}
    if($adapter.result.PSObject.Properties['uninstalled'] -and $adapter.result.uninstalled){
        if($job.operation -notin @('Uninstall','Recover') -or (Get-ALService 'AuthLens').Exists){throw 'Administrative uninstall did not verify service absence.'}
        Assert-ALNoPendingRepair $config
        exit 0
    }
    if($job.operation -eq 'Recover'){
        Assert-ALNoPendingRepair $config
        $journal=Read-ALJournal $config
        if($journal -and $journal.phase -in @('stopping','switched','starting','verifying')){throw 'Recovery left an interrupted transaction.'}
        $identity=Get-Content -LiteralPath (Join-Path (Get-ALLink (Get-ALCurrentLink $config)) 'build-manifest.json') -Raw|ConvertFrom-Json
        $null=Wait-ALReady $config $identity.source_sha $identity.version
    }
    exit 0
}catch{exit 4}
