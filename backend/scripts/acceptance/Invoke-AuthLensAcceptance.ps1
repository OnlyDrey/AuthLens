<#
.SYNOPSIS
  AuthLens native acceptance runner (WP21, replaces the ad-hoc OP1/OP2/b13 evidence scripts; those stay in their evidence folders as history).
.DESCRIPTION
  -Operation B13            Simulation cases (any context) against the packaged or installed deployment tools.
  -Operation B14Approval    Missing -Yes refusals. ELEVATED only, so the elevation gate cannot be the reason.
  -Operation B14Elevation   -Yes refusals on the elevation gate. NON-ELEVATED only; refused from an elevated session.
  -Operation Lifecycle      B17 upgrade -> C12 -> C14 -> B15 -> B17 repair on the installation (STATE-CHANGING). Requires -AuthorizeMutation,
                            an explicit -RecoveryReport and -ReadinessReport, verified escrow and -SnapshotAttestation. Every mandatory step is
                            checked; the first failure stops the run (no later step runs) and no completion marker is printed.
  Results: <EvidenceRoot>\<RunName>\results.json (machine-readable) and per-case output. Exit codes: 0 passed, 1 failed, 2 refused before
  running (context or prerequisites), 3 stopped on unexpected mutation.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File backend\scripts\acceptance\Invoke-AuthLensAcceptance.ps1 -Operation B14Elevation -Candidate C:\AuthLens\AuthLens-2.0.0-2026-11-25_0807-37eadd5 -RunName B14-elevation-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('B13', 'B14Approval', 'B14Elevation', 'Lifecycle')][string]$Operation,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$RunName,
    [string]$EvidenceRoot = '',
    [ValidateSet('Packaged', 'Installed')][string]$Tools = 'Packaged',
    [string]$ConfigFile = 'C:\ProgramData\AuthLens\config\deploy.json',
    [string]$Root = 'C:\ProgramData\AuthLens',
    [string]$RecoveryReport = '',
    [string]$ReadinessReport = '',
    [string]$SnapshotAttestation = '',
    [string]$ExpectedInstalledSha = '',
    [string]$VerifierExecutable = '',
    [switch]$AuthorizeMutation
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuthLens.Acceptance.psm1') -Force

$candidateRoot = [IO.Path]::GetFullPath($Candidate)
if (-not $EvidenceRoot) { $EvidenceRoot = Join-Path 'C:\AuthLens\acceptance' (Split-Path $candidateRoot -Leaf) }
$summaryFile = Join-Path $candidateRoot 'build-summary.json'
if (-not (Test-Path -LiteralPath $summaryFile)) { Write-Host "REFUSED: $summaryFile not found (a canonical build.ps1 run directory is required)."; exit 2 }
$identity = (Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json).identity
$release = @(Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'build') -Directory | Where-Object Name -Like 'AuthLens-*-win-x64')[0].FullName
$package = Split-Path $release -Leaf
$packagedTools = @(Get-ChildItem -LiteralPath (Join-Path $candidateRoot 'installer') -Directory -Filter 'installer-tools-*')[0].FullName
$staged = Join-Path $Root "app\setup\$package"
# QA-007: installed-runtime tests use the installed, hash-verified tools Setup staged for this package, never a build copy.
$deploy = if ($Tools -eq 'Installed') { Join-Path $staged 'tools\deploy\Deploy-AuthLens.ps1' } else { Join-Path $packagedTools 'deploy\Deploy-AuthLens.ps1' }
$output = Join-Path $EvidenceRoot $RunName
$cases = Join-Path $PSScriptRoot 'cases'

function Get-SyntheticCertificates {
    $directory = New-AcceptancePrivateDirectory (Join-Path ([IO.Path]::GetTempPath()) ('authlens-acceptance-' + [guid]::NewGuid().ToString('N')))
    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    $hosts = @($config.AllowedHosts); $ips = @($hosts | Where-Object { $_ -as [Net.IPAddress] }); $names = @($hosts | Where-Object { -not ($_ -as [Net.IPAddress]) })
    $full = New-AcceptanceTestCertificate $directory 'full' $names $ips
    $missing = New-AcceptanceTestCertificate $directory 'missing' @('acceptance-missing.invalid') @()
    @{ scratch = $directory; cert_full = $full.pfx; cert_full_password = $full.password_file; cert_missing = $missing.pfx; cert_missing_password = $missing.password_file; release = $release }
}

if ($Operation -ne 'Lifecycle') {
    $file = Join-Path $cases @{ B13 = 'B13.json'; B14Approval = 'B14-approval.json'; B14Elevation = 'B14-elevation.json' }[$Operation]
    $values = Get-SyntheticCertificates
    try {
        $result = Invoke-AcceptanceGroup -CasesFile $file -Deploy $deploy -ConfigFile $ConfigFile -OutputDirectory $output -Values $values -Root $Root -Candidate $identity.source_sha
    } finally { [IO.Directory]::Delete($values.scratch, $true) }
    Write-Host "$($result.scenario): $($result.status) (passed $($result.passed), failed $($result.failed), not run $($result.not_run)) $($result.reason)"
    Write-Host "Results: $(Join-Path $output 'results.json')"
    exit $result.exit_code
}

# ---------------- Lifecycle (state-changing) ----------------
$steps = [Collections.Generic.List[object]]::new()
$state = [ordered]@{ schema = 1; operation = 'Lifecycle'; candidate = $identity.source_sha; context = (Get-AcceptanceContext); prerequisites = $null; steps = $steps; status = 'REFUSED'; exit_code = 2; reason = '' }
function Save-Lifecycle { if (Test-Path -LiteralPath $output) { $state.completed_utc = [DateTime]::UtcNow.ToString('o'); $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding UTF8 } }
function Invoke-Tool([string]$Name, [string]$Script, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $o = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | ForEach-Object { "$_" }); $c = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    @("command: $Script $($Arguments -join ' ')", "exit: $c", '') + $o | Set-Content -LiteralPath (Join-Path $output "$Name.txt") -Encoding UTF8
    [pscustomobject]@{ exit = $c; output = $o; result = (Get-AcceptanceResultLine $o) }
}
# QA-004/010: a mandatory step records PASS or FAIL; FAIL throws and nothing later runs.
function Assert-Step([string]$Id, [bool]$Passed, [string]$Detail) {
    $steps.Add([pscustomobject]@{ id = $Id; status = $(if ($Passed) { 'PASS' } else { 'FAIL' }); detail = $Detail; utc = [DateTime]::UtcNow.ToString('o') })
    Write-Host ('{0} {1}: {2}' -f $(if ($Passed) { 'PASS' } else { 'FAIL' }), $Id, $Detail)
    if (-not $Passed) { throw "Mandatory step $Id failed: $Detail" }
}
function Get-ServiceFacts { $s = Get-CimInstance Win32_Service -Filter "Name='AuthLens'"; [pscustomobject]@{ state = $s.State; pid = $s.ProcessId; account = $s.StartName; start = $s.StartMode; path = $s.PathName } }
function Get-CertificateThumbprint([string]$Exe) {
    $parts = @((Get-ServiceFacts).path.Trim() -split '\s+' | Select-Object -Skip 1)
    if (@($parts | Where-Object { $_ -match '"' }).Count) { throw 'Quoted service arguments; read the certificate manually.' }
    $o = & $Exe '--certificate-info' @parts; if ($LASTEXITCODE -ne 0) { throw 'certificate-info failed.' }
    ($o | Out-String | ConvertFrom-Json).thumbprint_sha256
}
function Get-DataFingerprint([string]$Tag) {
    if (-not $VerifierExecutable) { return $null }
    $copy = New-AcceptancePrivateDirectory (Join-Path ([IO.Path]::GetTempPath()) ('authlens-acceptance-fp-' + [guid]::NewGuid().ToString('N')))
    try {
        $data = Join-Path $Root 'data'
        foreach ($relative in 'authlens.sqlite3', 'authlens.sqlite3-wal', 'security\accounts.sqlite3', 'security\accounts.sqlite3-wal') {
            $source = Join-Path $data $relative; if (-not [IO.File]::Exists($source)) { continue }
            $target = Join-Path $copy $relative; $null = [IO.Directory]::CreateDirectory((Split-Path $target))
            $before = Get-AcceptanceFileHash $source
            $in = [IO.FileStream]::new($source, 'Open', 'Read', 'ReadWrite, Delete'); $out = [IO.File]::Create($target)
            try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
            if ((Get-AcceptanceFileHash $source) -ne $before -or (Get-AcceptanceFileHash $target) -ne $before) { throw "Database $relative changed during the copy; repeat in a quiet period." }
        }
        $o = & $VerifierExecutable '--fingerprint-data' '--data-dir' $copy; if ($LASTEXITCODE -ne 0) { throw 'fingerprint-data failed.' }
        ($o -join "`n") | Set-Content -LiteralPath (Join-Path $output "fingerprint-$Tag.json") -Encoding UTF8
        ($o -join "`n") | ConvertFrom-Json
    } finally { [IO.Directory]::Delete($copy, $true) }
}
function Compare-Fingerprint($A, $B) {
    if (-not $A -or -not $B) { return 'not_compared (no -VerifierExecutable)' }
    $diff = @(); foreach ($store in $A.stores.PSObject.Properties.Name) { foreach ($t in $A.stores.$store.tables.PSObject.Properties.Name) {
        $x = $A.stores.$store.tables.$t; $y = if ($B.stores.$store -and $B.stores.$store.tables.PSObject.Properties[$t]) { $B.stores.$store.tables.$t } else { $null }
        if (-not $y -or $x.count -ne $y.count -or $x.sha256 -cne $y.sha256) { $diff += "$store/$t" } } }
    if ($diff.Count) { 'changed: ' + ($diff -join ', ') } else { 'identical' }
}
try {
    if (-not $AuthorizeMutation) { throw [System.Management.Automation.RuntimeException]::new('REFUSED: Lifecycle changes the installation; pass -AuthorizeMutation after reviewing the prerequisites.') }
    Assert-AcceptanceContext 'elevated' (Test-AcceptanceElevated) 'Lifecycle'
    if (-not $ExpectedInstalledSha) { throw 'REFUSED: -ExpectedInstalledSha (the installed baseline commit) is required.' }
    $installed = Get-Content -LiteralPath (Join-Path $Root 'config\installed-product.json') -Raw | ConvertFrom-Json
    $installedSha = (Get-Content -LiteralPath (Join-Path $installed.release 'build-manifest.json') -Raw | ConvertFrom-Json).source_sha
    $keyStatus = (& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $release 'Service-Manager.ps1') -Action Status 2>$null | Where-Object { $_ -like '{*' } | Select-Object -First 1) | ConvertFrom-Json
    $state.prerequisites = Test-AcceptanceMutationPrerequisites -RecoveryReport $RecoveryReport -ReadinessReport $ReadinessReport -ExpectedCandidateSha $identity.source_sha `
        -ExpectedInstalledSha $ExpectedInstalledSha -InstalledSha $installedSha -KeyStatus $keyStatus -SnapshotAttestation $SnapshotAttestation
    $journal = Get-Content -LiteralPath (Join-Path $Root 'deployment\deployment-journal.json') -Raw | ConvertFrom-Json
    if ($journal.phase -notin 'complete', 'rolled_back') { throw "REFUSED: the deployment journal is '$($journal.phase)', not terminal." }
    $server = Join-Path $candidateRoot "installer\AuthLens-Server-$($identity.version)-Setup.exe"
    $expectedSetup = @((Get-Content -LiteralPath $summaryFile -Raw | ConvertFrom-Json).artifacts | Where-Object { $_.path -eq "installer/$(Split-Path $server -Leaf)" })[0].sha256
    if (-not $expectedSetup -or (Get-AcceptanceFileHash $server) -ne $expectedSetup.ToLowerInvariant()) { throw 'REFUSED: Server Setup hash differs from build-summary.json.' }
    New-AcceptanceDirectory $output
    $state.status = 'RUNNING'; $state.exit_code = 1
    $exe = Join-Path $release 'server\AuthLens.Api.exe'
    # Baseline (QA-008/009).
    $snap0 = Get-AcceptanceSnapshot $Root; $svc0 = Get-ServiceFacts; $thumb0 = Get-CertificateThumbprint $exe; $cfg0 = Get-AcceptanceFileHash $ConfigFile
    $key0 = $keyStatus.fingerprint; $fp0 = Get-DataFingerprint '0-before'
    $snap0 | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'snapshot-0-before.json') -Encoding UTF8
    Assert-Step 'baseline' ($svc0.state -eq 'Running' -and $thumb0 -and $cfg0 -ne 'absent') "service $($svc0.state) pid $($svc0.pid), certificate $thumb0, key $key0"
    # B17 upgrade.
    $setup = Start-Process -FilePath $server -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/CONFIGFILE=`"$ConfigFile`"", '/OPERATION=Upgrade', "/LOG=`"$output\B17-upgrade-setup.log`"") -Wait -PassThru
    Assert-Step 'B17-upgrade-setup' ($setup.ExitCode -eq 0) "Setup exit $($setup.ExitCode)"
    $deployInstalled = Join-Path $staged 'tools\deploy\Deploy-AuthLens.ps1'; $manager = Join-Path $staged "payload\$package\Service-Manager.ps1"
    Assert-Step 'B17-installed-tools' ((Test-Path -LiteralPath $deployInstalled) -and (Test-Path -LiteralPath $manager)) $staged
    $status = Invoke-Tool 'B17-status-after-upgrade' $deployInstalled @('-Action', 'Status', '-ConfigFile', $ConfigFile)
    $r = $status.result.result
    Assert-Step 'B17-identity' ($status.exit -eq 0 -and $r.current_commit -ceq $identity.source_sha -and $r.ready -and $r.running_identity.source_sha -ceq $identity.source_sha -and -not $r.recovery_needed) "commit $($r.current_commit), ready $($r.ready), journal $($r.journal_phase)"
    $svc1 = Get-ServiceFacts; $thumb1 = Get-CertificateThumbprint $exe; $cfg1 = Get-AcceptanceFileHash $ConfigFile; $fp1 = Get-DataFingerprint '1-after-upgrade'
    Assert-Step 'B17-upgrade-preserved' ($thumb1 -eq $thumb0 -and $svc1.account -eq $svc0.account -and $svc1.start -eq $svc0.start) "certificate same $($thumb1 -eq $thumb0); configuration $(if ($cfg1 -eq $cfg0) { 'unchanged' } else { 'rewritten (review B17-status)' }); data $(Compare-Fingerprint $fp0 $fp1)"
    if ($fp0) { Assert-Step 'B17-upgrade-data' ((Compare-Fingerprint $fp0 $fp1) -eq 'identical') (Compare-Fingerprint $fp0 $fp1) }
    # C12 with the installed Service Manager.
    $c12 = Invoke-Tool 'C12-certificate-status' $manager @('-Action', 'CertificateStatus')
    Assert-Step 'C12-status' ($c12.exit -eq 0) 'installed Service Manager certificate status'
    $e1 = Invoke-Tool 'C12-export-1' $manager @('-Action', 'ExportCertificate', '-Directory', $output, '-FileName', 'installed-public')
    $cer = Join-Path $output 'installed-public.cer'
    $x = if (Test-Path -LiteralPath $cer) { [Security.Cryptography.X509Certificates.X509Certificate2]::new($cer) } else { $null }
    Assert-Step 'C12-export' ($e1.exit -eq 0 -and $x -and -not $x.HasPrivateKey) 'public certificate only'
    $h = Get-AcceptanceFileHash $cer
    $e2 = Invoke-Tool 'C12-export-2' $manager @('-Action', 'ExportCertificate', '-Directory', $output, '-FileName', 'installed-public')
    Assert-Step 'C12-no-overwrite' ($e2.exit -ne 0 -and (Get-AcceptanceFileHash $cer) -eq $h) "second export exit $($e2.exit), file unchanged"
    # C14 restart.
    $auditFile = Join-Path $Root 'deployment\recovery-audit.jsonl'
    $auditLines0 = if (Test-Path -LiteralPath $auditFile) { @(Get-Content -LiteralPath $auditFile).Count } else { 0 }
    $pidA = (Get-ServiceFacts).pid
    $sim = Invoke-Tool 'C14-restart-dryrun' $deployInstalled @('-Action', 'RestartService', '-ConfigFile', $ConfigFile, '-DryRun')
    Assert-Step 'C14-simulation' ($sim.exit -eq 0 -and $sim.result.result.simulation -eq $true -and $sim.result.result.changes_applied -eq $false -and (Get-ServiceFacts).pid -eq $pidA) 'simulation changed nothing'
    $restart = Invoke-Tool 'C14-restart' $deployInstalled @('-Action', 'RestartService', '-ConfigFile', $ConfigFile, '-Yes')
    $pidB = (Get-ServiceFacts).pid
    $health = Invoke-Tool 'C14-health' $deployInstalled @('-Action', 'Health', '-ConfigFile', $ConfigFile)
    Assert-Step 'C14-restart' ($restart.exit -eq 0 -and $pidB -ne $pidA -and $health.exit -eq 0 -and $health.result.result.identity.source_sha -ceq $identity.source_sha) "pid $pidA -> $pidB, ready $($health.result.result.ready)"
    # B15 semantics: a simulation adds no audit line; any existing line carries the required fields and no secrets.
    $rec = Invoke-Tool 'B15-recover-dryrun' $deployInstalled @('-Action', 'Recover', '-ConfigFile', $ConfigFile, '-DryRun')
    $auditLines1 = if (Test-Path -LiteralPath $auditFile) { @(Get-Content -LiteralPath $auditFile).Count } else { 0 }
    Assert-Step 'B15-simulation-no-audit' ($rec.result.result.simulation -eq $true -and $auditLines1 -eq $auditLines0) "audit lines $auditLines0 -> $auditLines1"
    # B17 repair: validate read-only first (exact manifest, read-only preflight), then stop (authorized by -AuthorizeMutation), plan, repair.
    $manifestSame = (Get-AcceptanceFileHash (Join-Path (Get-Item (Join-Path $Root 'releases\current')).Target 'build-manifest.json')) -eq (Get-AcceptanceFileHash (Join-Path $release 'build-manifest.json'))
    Assert-Step 'B17-repair-prevalidation' $manifestSame 'installed manifest equals the repair package'
    Stop-Service -Name AuthLens
    $plan = Invoke-Tool 'B17-repair-plan' (Join-Path $packagedTools 'Install-AuthLens.ps1') @('-Mode', 'Server', '-PreflightOnly', '-Operation', 'Repair', '-Package', $release, '-ConfigFile', $ConfigFile, '-ResultFile', (Join-Path $output 'B17-repair-plan.json'))
    if ($plan.exit -ne 0) { Start-Service -Name AuthLens; Assert-Step 'B17-repair-plan' $false "plan exit $($plan.exit); the service was started again unchanged" }
    Assert-Step 'B17-repair-plan' $true 'plan validated'
    $repair = Invoke-Tool 'B17-repair' (Join-Path $packagedTools 'Install-AuthLens.ps1') @('-Mode', 'Server', '-Operation', 'Repair', '-Package', $release, '-ConfigFile', $ConfigFile, '-ResultFile', (Join-Path $output 'B17-repair-result.json'), '-Yes')
    $health2 = Invoke-Tool 'B17-health-after-repair' $deployInstalled @('-Action', 'Health', '-ConfigFile', $ConfigFile)
    Assert-Step 'B17-repair' ($repair.exit -eq 0 -and $health2.exit -eq 0 -and $health2.result.result.identity.source_sha -ceq $identity.source_sha) "repair exit $($repair.exit), ready $($health2.result.result.ready)"
    $svc2 = Get-ServiceFacts; $thumb2 = Get-CertificateThumbprint $exe; $cfg2 = Get-AcceptanceFileHash $ConfigFile; $fp2 = Get-DataFingerprint '2-after-repair'
    Assert-Step 'B17-repair-preserved' ($thumb2 -eq $thumb0 -and $cfg2 -eq $cfg1 -and $svc2.account -eq $svc0.account -and $svc2.path -eq $svc1.path) "certificate same $($thumb2 -eq $thumb0); configuration same $($cfg2 -eq $cfg1); data $(Compare-Fingerprint $fp1 $fp2)"
    if ($fp1) { Assert-Step 'B17-repair-data' ((Compare-Fingerprint $fp1 $fp2) -eq 'identical') (Compare-Fingerprint $fp1 $fp2) }
    $state.status = 'PASS'; $state.exit_code = 0
} catch {
    $state.reason = $_.Exception.Message
    if ($state.status -eq 'RUNNING') { $state.status = 'FAIL'; $state.exit_code = 1 }
    Write-Host "STOPPED: $($state.reason)"
} finally { Save-Lifecycle; Write-Host ('AUTHLENS-ACCEPTANCE: ' + ([pscustomobject]@{ operation = 'Lifecycle'; status = $state.status; exit_code = $state.exit_code; reason = $state.reason; steps = @($steps | ForEach-Object { "$($_.id)=$($_.status)" }) } | ConvertTo-Json -Compress -Depth 4)) }
if ($state.status -eq 'PASS') { Write-Host "Lifecycle PASS. Results: $(Join-Path $output 'results.json')" } else { Write-Host "Lifecycle $($state.status). Results: $(Join-Path $output 'results.json')" }
exit $state.exit_code
