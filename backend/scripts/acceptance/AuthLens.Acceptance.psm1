# AuthLens native acceptance harness (WP21). Operator-run, never part of a build or service. Every case states its required execution
# context, expected exit code, expected refusal reason, expected simulation fields and whether the protected installation state must stay
# unchanged; a case passes only when every stated expectation holds. A group stops at the first unexpected state change (QA-012) and at
# the first failed mandatory case (QA-004). Results are machine-readable (results.json) with meaningful exit codes (QA-018):
#   0 every case passed · 1 at least one case failed · 2 precondition or context refused, nothing run · 3 stopped on unexpected mutation.
# Secret files are recorded by length and time only; database rows are never read (fingerprints come from the product's read-only command).
Set-StrictMode -Version 3.0

$script:ExitPassed = 0; $script:ExitFailed = 1; $script:ExitRefused = 2; $script:ExitMutation = 3

class AcceptanceRefusal : System.Exception { AcceptanceRefusal([string]$Message) : base($Message) {} }
function Stop-Acceptance([string]$Message) { throw [AcceptanceRefusal]::new($Message) }

function Test-AcceptanceElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AcceptanceContext {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    [pscustomobject]@{ elevated = [bool](Test-AcceptanceElevated); operator = $identity.Name; computer = $env:COMPUTERNAME; started_utc = [DateTime]::UtcNow.ToString('o') }
}

# QA-011: a case or group declares 'elevated', 'non-elevated' or 'any'; a mismatch refuses before any command runs.
function Assert-AcceptanceContext([ValidateSet('elevated', 'non-elevated', 'any')][string]$Required, [bool]$Elevated, [string]$What) {
    if ($Required -eq 'elevated' -and -not $Elevated) { Stop-Acceptance "$What requires an elevated session; nothing was run." }
    if ($Required -eq 'non-elevated' -and $Elevated) { Stop-Acceptance "$What must run from a NON-elevated session (its cases carry -Yes and would change the installation if the elevation gate were bypassed); nothing was run." }
}

function Get-AcceptanceFileHash([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return 'absent' }
    $stream = [IO.FileStream]::new($Path, 'Open', 'Read', 'ReadWrite, Delete'); $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-AcceptanceFileMeta([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
    $item = Get-Item -LiteralPath $Path -Force; "len=$($item.Length) mtime=$($item.LastWriteTimeUtc.ToString('o'))"
}

# Persistent installation state that a refused or simulated operation must leave unchanged. The live database is recorded by size and time
# only, because the running service writes to it; secrets by length and time only.
function Get-AcceptanceSnapshot([string]$Root = 'C:\ProgramData\AuthLens', [string]$ServiceName = 'AuthLens') {
    $s = [ordered]@{}
    foreach ($f in 'deployment\deployment-journal.json', 'deployment\recovery-audit.jsonl', 'deployment\configuration-pending.json', 'deployment\certificate-pending.json',
                   'config\installed-product.json', 'config\deploy.json', 'tls\server.pfx', 'data\backup-key-location.json', 'data\backup-key-audit.jsonl') { $s["sha256:$f"] = Get-AcceptanceFileHash (Join-Path $Root $f) }
    foreach ($f in 'tls\cert-password', 'keys\host.key', 'data\api-token', 'deployment\deployment.lock', 'data\authlens.sqlite3') { $s["meta:$f"] = Get-AcceptanceFileMeta (Join-Path $Root $f) }
    foreach ($d in 'deployment', 'config', 'releases', 'tls', 'keys', 'backups') {
        $path = Join-Path $Root $d
        $s["files:$d"] = if (Test-Path -LiteralPath $path) { @(Get-ChildItem -LiteralPath $path -Recurse -Force | ForEach-Object { '{0} {1}' -f $_.FullName.Substring($Root.Length), $(if ($_.PSIsContainer) { 'dir' } else { $_.Length }) }) } else { 'absent' }
    }
    $current = Join-Path $Root 'releases\current'
    $s['current_link'] = if (Test-Path -LiteralPath $current) { [string](Get-Item -LiteralPath $current -Force).Target } else { 'absent' }
    foreach ($d in '', 'data', 'config', 'tls', 'keys', 'deployment', 'releases', 'backups') { $p = Join-Path $Root $d; $s["acl:$d"] = if (Test-Path -LiteralPath $p) { (Get-Acl -LiteralPath $p).Sddl } else { 'absent' } }
    $s['source_authority'] = @(Get-ChildItem -LiteralPath $Root -Force -Filter '.authlens-source-policy-*' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) $((Get-Acl -LiteralPath $_.FullName).Sddl)" })
    $service = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    $s['service'] = if ($service) { [ordered]@{ state = $service.State; pid = $service.ProcessId; start = $service.StartMode; account = $service.StartName; path = $service.PathName } } else { 'absent' }
    $s['listener'] = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $service -and $_.OwningProcess -eq $service.ProcessId } | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" } | Sort-Object)
    foreach ($key in @(@('reg:server', 'HKLM:\Software\AuthLens\Server'), @('reg:uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B961C010-9B53-4514-9D2A-73A4641E4AAF}_is1'))) {
        $s[$key[0]] = if (Test-Path -LiteralPath $key[1]) { $p = Get-ItemProperty -LiteralPath $key[1]; $o = [ordered]@{}; foreach ($n in ($p.PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' } | Sort-Object)) { $o[$n] = [string]$p.$n }; $o } else { 'absent' }
    }
    $s['firewall'] = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'AuthLens*' -or $_.DisplayName -like 'AuthLens*' } | ForEach-Object { "$($_.Name) enabled=$($_.Enabled) action=$($_.Action) profile=$($_.Profile)" } | Sort-Object)
    [pscustomobject]$s
}

function Compare-AcceptanceSnapshot($Before, $After) {
    $names = @($Before.PSObject.Properties.Name) + @($After.PSObject.Properties.Name) | Sort-Object -Unique
    foreach ($n in $names) {
        $x = if ($Before.PSObject.Properties[$n]) { $Before.$n | ConvertTo-Json -Depth 6 -Compress } else { '<missing>' }
        $y = if ($After.PSObject.Properties[$n]) { $After.$n | ConvertTo-Json -Depth 6 -Compress } else { '<missing>' }
        if ($x -cne $y) { $n }
    }
}

# The last AUTHLENS-RESULT line of a Deploy-AuthLens.ps1 run, or $null.
function Get-AcceptanceResultLine([string[]]$Output, [string]$Marker = 'AUTHLENS-RESULT:') {
    $line = @($Output | Where-Object { $_ -like "$Marker*" }) | Select-Object -Last 1
    if (-not $line) { return $null }
    try { $line.Substring($Marker.Length).Trim() | ConvertFrom-Json } catch { $null }
}

# QA-006/013/014/015: one case's verdict from its observed exit code, output and state comparison. Pure; unit-tested.
function Get-AcceptanceVerdict($Case, [int]$ExitCode, [string[]]$Output, [string[]]$Changed) {
    $failures = [Collections.Generic.List[string]]::new()
    $expect = $Case.expect
    if (@($expect.exit) -notcontains $ExitCode) { $failures.Add("exit $ExitCode, expected $(@($expect.exit) -join '/')") }
    $parsed = Get-AcceptanceResultLine $Output
    $result = if ($parsed -and $parsed.PSObject.Properties['result']) { $parsed.result } else { $null }
    $text = ($Output -join "`n")
    if ($expect.PSObject.Properties['reason'] -and $expect.reason) {
        if ($text -notmatch $expect.reason) { $failures.Add("expected refusal reason /$($expect.reason)/ not found") }
    }
    if ($expect.PSObject.Properties['forbidden_reason'] -and $expect.forbidden_reason -and $text -match $expect.forbidden_reason) { $failures.Add("output matched the forbidden reason /$($expect.forbidden_reason)/ (the case was refused by an unrelated gate)") }
    foreach ($field in 'simulation', 'changes_applied') {
        if ($expect.PSObject.Properties[$field] -and $null -ne $expect.$field) {
            $actual = if ($result -and $result.PSObject.Properties[$field]) { $result.$field } else { '<absent>' }
            if ("$actual" -ne "$($expect.$field)") { $failures.Add("$field = $actual, expected $($expect.$field)") }
        }
    }
    if ($expect.PSObject.Properties['result_fields'] -and $expect.result_fields) {
        foreach ($p in $expect.result_fields.PSObject.Properties) {
            $actual = if ($result -and $result.PSObject.Properties[$p.Name]) { $result.($p.Name) } else { '<absent>' }
            if ("$actual" -ne "$($p.Value)") { $failures.Add("result.$($p.Name) = $actual, expected $($p.Value)") }
        }
    }
    $unchanged = -not $expect.PSObject.Properties['state_unchanged'] -or $expect.state_unchanged
    if ($unchanged -and @($Changed).Count) { $failures.Add("protected state changed: $(@($Changed) -join ', ')") }
    [pscustomobject]@{ status = $(if ($failures.Count) { 'FAIL' } else { 'PASS' }); failures = @($failures); mutation = [bool]($unchanged -and @($Changed).Count) }
}

function Read-AcceptanceCases([string]$Path) {
    $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in 'scenario', 'context', 'cases') { if (-not $doc.PSObject.Properties[$field]) { Stop-Acceptance "Case file $Path lacks '$field'." } }
    foreach ($case in @($doc.cases)) {
        foreach ($field in 'id', 'args', 'expect') { if (-not $case.PSObject.Properties[$field]) { Stop-Acceptance "A case in $Path lacks '$field'." } }
        if (-not $case.expect.PSObject.Properties['exit']) { Stop-Acceptance "Case $($case.id) has no expected exit code." }
        $hasReason = $case.expect.PSObject.Properties['reason'] -and $case.expect.reason
        $hasSimulation = $case.expect.PSObject.Properties['simulation'] -and $null -ne $case.expect.simulation
        if (-not $hasReason -and -not $hasSimulation) { Stop-Acceptance "Case $($case.id) asserts neither a refusal reason nor simulation fields; an exit code alone is not evidence." }
        $caseContext = if ($case.PSObject.Properties['context']) { $case.context } else { $doc.context }
        if ($doc.context -ne 'any' -and $caseContext -ne $doc.context) { Stop-Acceptance "Case $($case.id) needs '$caseContext' but its group runs '$($doc.context)'; split the group." }
        if ($doc.context -ne 'non-elevated' -and @($case.args) -contains '-Yes' -and @($case.args) -notcontains '-DryRun') { Stop-Acceptance "Case $($case.id) passes -Yes without -DryRun in a group that may run elevated; such cases belong to a non-elevated elevation-refusal group only." }
    }
    $doc
}

function New-AcceptanceDirectory([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Stop-Acceptance "$Path exists; acceptance results are never overwritten. Use a new run name." }
    New-Item -ItemType Directory -Path $Path | Out-Null
}

# Runs one case group against Deploy-AuthLens.ps1 in fresh Windows PowerShell processes. Placeholders in arguments: {release}, {scratch}.
function Invoke-AcceptanceGroup {
    param([Parameter(Mandatory)][string]$CasesFile, [Parameter(Mandatory)][string]$Deploy, [Parameter(Mandatory)][string]$ConfigFile,
        [Parameter(Mandatory)][string]$OutputDirectory, [hashtable]$Values = @{}, [string]$Root = 'C:\ProgramData\AuthLens', [string]$Candidate = '',
        [scriptblock]$Runner = $null)
    $context = Get-AcceptanceContext
    $summary = [ordered]@{ schema = 1; scenario = ''; candidate = $Candidate; context = $context; cases = @(); passed = 0; failed = 0; not_run = 0; status = 'REFUSED'; exit_code = $script:ExitRefused; reason = '' }
    try {
        $doc = Read-AcceptanceCases $CasesFile
        $summary.scenario = $doc.scenario
        Assert-AcceptanceContext $doc.context $context.elevated "Scenario $($doc.scenario)"
        if (-not [IO.File]::Exists($Deploy)) { Stop-Acceptance "Deployment entry point not found: $Deploy" }
        New-AcceptanceDirectory $OutputDirectory
        if (-not $Runner) {
            $Runner = { param([string[]]$Arguments) $o = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1 | ForEach-Object { "$_" }); [pscustomobject]@{ exit = $LASTEXITCODE; output = $o } }
        }
        $cases = @($doc.cases); $stopped = $false
        for ($i = 0; $i -lt $cases.Count; $i++) {
            $case = $cases[$i]
            if ($stopped) { $summary.cases += [pscustomobject]@{ id = $case.id; status = 'NOT RUN'; failures = @('group stopped earlier') }; $summary.not_run++; continue }
            $arguments = @($case.args | ForEach-Object { $a = [string]$_; foreach ($k in $Values.Keys) { $a = $a.Replace("{$k}", [string]$Values[$k]) }; $a })
            $before = Get-AcceptanceSnapshot $Root
            $ErrorActionPreference = 'Continue'
            $run = & $Runner (@('-File', $Deploy) + $arguments + @('-ConfigFile', $ConfigFile))
            $ErrorActionPreference = 'Stop'
            $after = Get-AcceptanceSnapshot $Root
            $changed = @(Compare-AcceptanceSnapshot $before $after)
            $verdict = Get-AcceptanceVerdict $case ([int]$run.exit) @($run.output) $changed
            $tag = '{0:00}-{1}' -f ($i + 1), ($case.id -replace '[^A-Za-z0-9-]', '_')
            @("command: Deploy-AuthLens.ps1 $($arguments -join ' ') -ConfigFile $ConfigFile", "exit: $($run.exit)", "status: $($verdict.status)", "failures: $($verdict.failures -join '; ')", '') + @($run.output) |
                Set-Content -LiteralPath (Join-Path $OutputDirectory "$tag.output.txt") -Encoding UTF8
            if ($changed.Count) { [pscustomobject]@{ before = $before; after = $after; changed = $changed } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory "$tag.state.json") -Encoding UTF8 }
            $summary.cases += [pscustomobject]@{ id = $case.id; status = $verdict.status; exit = $run.exit; failures = $verdict.failures; state_changed = $changed; evidence = "$tag.output.txt" }
            if ($verdict.status -eq 'PASS') { $summary.passed++ } else { $summary.failed++ }
            Write-Host ('{0} {1} exit {2}{3}' -f $verdict.status, $case.id, $run.exit, $(if ($verdict.failures.Count) { ' - ' + ($verdict.failures -join '; ') } else { '' }))
            if ($verdict.mutation) { $stopped = $true; $summary.reason = "Unexpected state change in $($case.id); the group stopped. Review -Action Status before anything else." }
        }
        $summary.status = if ($stopped) { 'STOPPED' } elseif ($summary.failed) { 'FAIL' } else { 'PASS' }
        $summary.exit_code = if ($stopped) { $script:ExitMutation } elseif ($summary.failed) { $script:ExitFailed } else { $script:ExitPassed }
    } catch [AcceptanceRefusal] {
        $summary.reason = $_.Exception.Message
    }
    $summary.completed_utc = [DateTime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $OutputDirectory) { $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'results.json') -Encoding UTF8 }
    [pscustomobject]$summary
}

# QA-002/003/016: controlled mutating acceptance needs an explicitly selected, passed recovery report; a readiness PASS that used that same
# report, is younger than MaxAgeHours and names the candidate; verified escrow; and an operator snapshot attestation (recorded as an
# attestation, never as verification). Returns the facts; refuses with the first missing prerequisite.
function Test-AcceptanceMutationPrerequisites {
    param([Parameter(Mandatory)][string]$RecoveryReport, [Parameter(Mandatory)][string]$ReadinessReport, [Parameter(Mandatory)][string]$ExpectedCandidateSha,
        [Parameter(Mandatory)][string]$ExpectedInstalledSha, [string]$InstalledSha = '', $KeyStatus = $null, [string]$SnapshotAttestation = '', [double]$MaxAgeHours = 24,
        [DateTime]$Now = [DateTime]::UtcNow)
    if (-not $SnapshotAttestation.Trim()) { Stop-Acceptance 'No snapshot attestation: take a Proxmox snapshot, keep it, and pass its name with -SnapshotAttestation. The harness cannot verify it.' }
    if (-not [IO.File]::Exists($RecoveryReport)) { Stop-Acceptance "Recovery report not found: $RecoveryReport (select it explicitly; older reports are never used instead)." }
    $recovery = Get-Content -LiteralPath $RecoveryReport -Raw | ConvertFrom-Json
    foreach ($f in 'status', 'verified', 'bundle', 'archive_sha256') { if (-not $recovery.PSObject.Properties[$f]) { Stop-Acceptance "Recovery report lacks '$f'." } }
    if ($recovery.status -ne 'passed' -or $recovery.verified -ne $true) { Stop-Acceptance 'The selected recovery report did not pass.' }
    if ($recovery.PSObject.Properties['service_changed'] -and $recovery.service_changed) { Stop-Acceptance 'The recovery capture changed the service.' }
    if (-not [IO.File]::Exists($ReadinessReport)) { Stop-Acceptance "Readiness report not found: $ReadinessReport" }
    $readiness = Get-AcceptanceResultLine @(Get-Content -LiteralPath $ReadinessReport) 'AUTHLENS-UPGRADE-READINESS:'
    if (-not $readiness) { Stop-Acceptance 'The readiness report has no AUTHLENS-UPGRADE-READINESS result.' }
    if ($readiness.status -ne 'PASS') { Stop-Acceptance "Upgrade readiness is $($readiness.status) ($($readiness.failure_code))." }
    if ($readiness.source_sha -cne $ExpectedCandidateSha) { Stop-Acceptance "Readiness was checked for $($readiness.source_sha), not the candidate $ExpectedCandidateSha." }
    $completed = [DateTime]::Parse($readiness.completed_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    if (($Now - $completed).TotalHours -gt $MaxAgeHours) { Stop-Acceptance "Readiness is older than $MaxAgeHours hours ($($readiness.completed_utc)); rerun it with the same recovery report." }
    if (-not $readiness.recovery_report_utc) { Stop-Acceptance 'Readiness did not use an explicit recovery report.' }
    if ($InstalledSha -and $InstalledSha -cne $ExpectedInstalledSha) { Stop-Acceptance "The installed release is $InstalledSha, not the expected baseline $ExpectedInstalledSha." }
    if ($null -ne $KeyStatus) {
        if (-not ($KeyStatus.PSObject.Properties['escrow_verified'] -and $KeyStatus.escrow_verified -eq $true)) { Stop-Acceptance 'The recovery key escrow is not verified (Service Manager -Action VerifyKey).' }
        if ($KeyStatus.PSObject.Properties['escrow_pending'] -and $KeyStatus.escrow_pending) { Stop-Acceptance 'Recovery key escrow is still pending.' }
    }
    [pscustomobject]@{ recovery_bundle = $recovery.bundle; archive_sha256 = $recovery.archive_sha256; readiness_operation = $readiness.operation_id; readiness_completed_utc = $readiness.completed_utc
        recovery_report_utc = $readiness.recovery_report_utc; snapshot_attestation = $SnapshotAttestation; snapshot_verification = 'operator_attested_not_verified'; escrow_verified = ($null -ne $KeyStatus) }
}

# Synthetic self-signed PFX for certificate simulations (never a real or trusted certificate): created in memory, written only to the given
# private directory with a random password file. No certificate store is touched.
function New-AcceptanceTestCertificate([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Name, [string[]]$DnsNames = @(), [string[]]$IpAddresses = @()) {
    $pfx = Join-Path $Directory "$Name.pfx"; $passwordFile = Join-Path $Directory "$Name.password"
    if ((Test-Path -LiteralPath $pfx) -or (Test-Path -LiteralPath $passwordFile)) { Stop-Acceptance "Test certificate $Name already exists in $Directory." }
    $rsa = [Security.Cryptography.RSACng]::new(2048)
    try {
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=AuthLens acceptance $Name (synthetic)", $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        foreach ($d in $DnsNames) { $san.AddDnsName($d) }; foreach ($i in $IpAddresses) { $san.AddIpAddress([Net.IPAddress]::Parse($i)) }
        $request.CertificateExtensions.Add($san.Build())
        $usage = [Security.Cryptography.OidCollection]::new(); $null = $usage.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($usage, $false))
        $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddDays(30))
        $bytes = [byte[]]::new(24); [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes); $password = [Convert]::ToBase64String($bytes)
        [IO.File]::WriteAllBytes($pfx, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password))
        [IO.File]::WriteAllText($passwordFile, $password)
        [pscustomobject]@{ pfx = $pfx; password_file = $passwordFile; thumbprint_sha1 = $certificate.Thumbprint }
    } finally { $rsa.Dispose() }
}

# A new private directory (protected ACL: SYSTEM, Administrators, the current user).
function New-AcceptancePrivateDirectory([Parameter(Mandatory)][string]$Path) {
    if (Test-Path -LiteralPath $Path) { Stop-Acceptance "$Path exists; it is never reused." }
    $security = [Security.AccessControl.DirectorySecurity]::new(); $security.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    $null = [IO.Directory]::CreateDirectory($Path, $security)
    $Path
}

Export-ModuleMember -Function New-AcceptanceTestCertificate, New-AcceptancePrivateDirectory, Test-AcceptanceElevated, Get-AcceptanceContext, Assert-AcceptanceContext, Get-AcceptanceFileHash, Get-AcceptanceSnapshot, Compare-AcceptanceSnapshot,
    Get-AcceptanceResultLine, Get-AcceptanceVerdict, Read-AcceptanceCases, New-AcceptanceDirectory, Invoke-AcceptanceGroup, Test-AcceptanceMutationPrerequisites, Stop-Acceptance
