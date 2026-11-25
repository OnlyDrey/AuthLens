<#
.SYNOPSIS
  Isolated restore rehearsal of an AuthLens recovery bundle (WP22, QA-020/025/027/029/031). Never touches the installed service or its data.
.DESCRIPTION
  In a new private folder (default %LOCALAPPDATA%\AuthLens-Lifecycle\restore-<id>) the bundle's archive is verified with the bundle's COPIED
  recovery key, staged with the supported --restore command and activated by starting an owned, isolated process of the bundle's program:
  loopback only (127.0.0.1, an OS-assigned free port), synthetic TLS generated for this run, --no-worker (no import worker, no refresh
  scheduler), no authority folder (server sources stay unauthorized) and no backup-key or passphrase environment. Then:
    HTTPS readiness and runtime identity (= the bundle's program manifest), the frontend, integrity and foreign keys, business, evidence and
    account fingerprints of the restored data against the archive's staged copy, persistence after a restart of the owned process, and that
    the active service (state, PID, command line, account), its configuration, certificate, recovery key and the bundle archive are unchanged.
  Fingerprints come from a read-only verifier executable with --fingerprint-data (a release after RC4, or a development build); no Python.
  Only the owned process is stopped. One machine-readable report is written into the rehearsal folder; exit 0 only when every check passed.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File backend\scripts\recovery\Test-AuthLensRestoreRehearsal.ps1 -Bundle C:\AuthLens-Recovery\<bundle> -Verifier <new AuthLens.Api.exe>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Bundle,
    [Parameter(Mandatory)][string]$Verifier,
    [string]$Program = '',
    [string]$WorkRoot = '',
    [string]$ConfigFile = 'C:\ProgramData\AuthLens\config\deploy.json',
    [string]$ServiceName = 'AuthLens',
    [int]$ReadyTimeoutSeconds = 90
)
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'acceptance\AuthLens.Acceptance.psm1') -Force
if (-not $Program) { $Program = Join-Path $Bundle 'program' }
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:LOCALAPPDATA 'AuthLens-Lifecycle' }
if (-not (Test-Path -LiteralPath $WorkRoot)) { $null = New-AcceptancePrivateDirectory $WorkRoot }
$root = New-AcceptancePrivateDirectory (Join-Path $WorkRoot ('restore-' + [guid]::NewGuid().ToString('N')))
$data = Join-Path $root 'data'
$script:process = $null; $script:stdout = $null; $script:stderr = $null; $script:port = 0
$business = @('DatasetRecords', 'Datasets', 'RefreshReports', 'ReviewDecisions', 'ReviewInvalidations', 'SavedFilters', 'SodDocuments', 'SodDecisionEvents', 'SodEvidenceSnapshots', '__EFMigrationsHistory')
$result = [ordered]@{ schema = 1; tool = 'Test-AuthLensRestoreRehearsal'; status = 'failed'; phase = 'prerequisites'; root = $root; bundle = $Bundle; actual_restore = $false
    https_verified = $false; frontend_loaded = $false; restart_verified = $false; active_installation_unchanged = $false; stop_method = 'termination of the owned isolated process only' }

function Invoke-Exe([string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'  # Windows PowerShell 5.1 turns redirected native stderr into errors
    $o = & $Exe @Arguments 2>$null; if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $Exe -Leaf) $($Arguments[0]) failed (exit $LASTEXITCODE)." }
    ($o -join "`n") | ConvertFrom-Json
}
function Save-Fingerprint([string]$Directory, [string]$Name) {
    $fp = Invoke-Exe $Verifier @('--fingerprint-data', '--data-dir', $Directory)
    $fp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root $Name) -Encoding UTF8
    foreach ($store in $fp.stores.PSObject.Properties) { if ($store.Value -and ($store.Value.integrity -ne 'ok' -or $store.Value.foreign_key_violations -ne 0)) { throw "Integrity or foreign-key check failed for $($store.Name) ($Name)." } }
    $fp
}
function Get-ActiveFacts {
    $s = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    $pointer = Join-Path $config.DataDirectory 'backup-key-location.json'
    [ordered]@{ state = $s.State; pid = $s.ProcessId; account = $s.StartName; path = $s.PathName; config = (Get-AcceptanceFileHash $ConfigFile); certificate = (Get-AcceptanceFileHash $config.CertificatePath)
        key = $(if (Test-Path -LiteralPath $pointer) { Get-AcceptanceFileHash ((Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json).path) } else { 'absent' }) }
}
function Stop-OwnedProcess {
    if ($script:process -and -not $script:process.HasExited) { $script:process.Kill(); $script:process.WaitForExit() }
    if ($script:stdout) { $null = $script:stdout.GetAwaiter().GetResult(); $script:stdout = $null }
    if ($script:stderr) { $null = $script:stderr.GetAwaiter().GetResult(); $script:stderr = $null }
    if ($script:process) { $script:process.Dispose(); $script:process = $null }
}
function Invoke-Https([string]$Path) {
    $ErrorActionPreference = 'Continue'
    $o = & (Join-Path $env:SystemRoot 'System32\curl.exe') --noproxy '*' --silent --show-error --fail --max-time 5 --cacert (Join-Path $root 'tls\trust.pem') "https://127.0.0.1:$($script:port)$Path" 2>$null
    [pscustomobject]@{ ok = ($LASTEXITCODE -eq 0); body = ($o -join "`n") }
}
function Start-OwnedProcess([string]$Exe) {
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $probe.Start(); $script:port = $probe.LocalEndpoint.Port; $probe.Stop()
    $script:process = [Diagnostics.Process]::new()
    $script:process.StartInfo.FileName = $Exe
    $arguments = @('--data-dir', $data, '--listen', '127.0.0.1', '--port', [string]$script:port, '--cert', (Join-Path $root 'tls\server.pfx'), '--cert-password-file', (Join-Path $root 'tls\cert-password'), '--no-worker')
    $script:process.StartInfo.Arguments = (@($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $script:process.StartInfo.UseShellExecute = $false; $script:process.StartInfo.CreateNoWindow = $true
    $script:process.StartInfo.RedirectStandardOutput = $true; $script:process.StartInfo.RedirectStandardError = $true
    foreach ($name in 'AUTHLENS_BACKUP_KEY_FILE', 'AUTHLENS_BACKUP_PASSPHRASE', 'AUTHLENS_DATA_DIR', 'AUTHLENS_SOURCE_DIR') { $script:process.StartInfo.EnvironmentVariables.Remove($name) }
    $null = $script:process.Start(); $script:stdout = $script:process.StandardOutput.ReadToEndAsync(); $script:stderr = $script:process.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    do {
        if ($script:process.HasExited) { throw 'The isolated process stopped before readiness.' }
        if ((Invoke-Https '/health/ready').ok) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Isolated HTTPS readiness timed out.'
}
try {
    $active0 = Get-ActiveFacts
    $inventory = Get-Content -LiteralPath (Join-Path $Bundle 'private-inventory.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $archive = $inventory.backup.file
    $archiveHash = Get-AcceptanceFileHash $archive
    if ($archiveHash -ne ([string]$inventory.backup.sha256).ToLowerInvariant()) { throw 'Bundle archive hash mismatch.' }
    $keyEntry = @($inventory.files | Where-Object { $_.copy -like '*\selected\host-recovery.key' })[0]
    if (-not $keyEntry -or (Get-AcceptanceFileHash $keyEntry.copy) -ne ([string]$keyEntry.sha256).ToLowerInvariant()) { throw 'Bundle recovery key copy does not match its inventory.' }
    $exe = Join-Path $Program 'server\AuthLens.Api.exe'
    $programManifest = Get-Content -LiteralPath (Join-Path $Program 'build-manifest.json') -Raw | ConvertFrom-Json
    $result.program = [ordered]@{ version = $programManifest.version; source_sha = $programManifest.source_sha }
    $activeRelease = (Get-Item -LiteralPath (Join-Path (Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json).Root 'releases\current') -Force).Target
    $result.active_program = [ordered]@{ source_sha = (Get-Content -LiteralPath (Join-Path $activeRelease 'build-manifest.json') -Raw | ConvertFrom-Json).source_sha }
    $result.program_matches_active = ($result.program.source_sha -ceq $result.active_program.source_sha)
    $result.archive_sha256 = $archiveHash
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'keys'), (Join-Path $root 'tls')
    [IO.File]::Copy($keyEntry.copy, (Join-Path $root 'keys\host.key'), $false)
    $tls = New-AcceptanceTestCertificate (Join-Path $root 'tls') 'server' @('localhost') @('127.0.0.1')
    Move-Item -LiteralPath $tls.password_file -Destination (Join-Path $root 'tls\cert-password')
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($tls.pfx, [IO.File]::ReadAllText((Join-Path $root 'tls\cert-password')), [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
    try { [IO.File]::WriteAllText((Join-Path $root 'tls\trust.pem'), "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert), [Base64FormattingOptions]::InsertLineBreaks) + "`n-----END CERTIFICATE-----`n") } finally { $certificate.Dispose() }
    $env:AUTHLENS_BACKUP_KEY_FILE = $null; $env:AUTHLENS_BACKUP_PASSPHRASE = $null
    $result.phase = 'verify and stage supported restore'
    $null = Invoke-Exe $exe @('--backup-key', 'use', (Join-Path $root 'keys\host.key'), '--data-dir', $data)
    $verified = Invoke-Exe $exe @('--backup-verify', $archive, '--data-dir', $data)
    if (-not $verified.verified -or ([string]$verified.sha256).ToLowerInvariant() -ne $archiveHash) { throw 'Archive validation with the copied key failed.' }
    $restore = Invoke-Exe $exe @('--restore', $archive, '--replace-all-data', '--data-dir', $data)
    $stage = Join-Path (Join-Path (Join-Path $data 'restore') $restore.staged.id) 'staged'
    $baseline = Save-Fingerprint $stage 'archive-fingerprints.json'
    $result.phase = 'activate the restore in the owned isolated process'
    Start-OwnedProcess $exe
    $identity = Invoke-Https '/product-version.json'
    if (-not $identity.ok -or ($identity.body | ConvertFrom-Json).source_sha -cne $programManifest.source_sha) { throw 'Restored runtime identity mismatch.' }
    $result.https_verified = $true
    $frontend = Invoke-Https '/'
    if (-not $frontend.ok -or $frontend.body -notmatch 'AuthLens') { throw 'The restored frontend did not load.' }
    $result.frontend_loaded = $true
    Stop-OwnedProcess
    $first = Save-Fingerprint $data 'restored-fingerprints.json'
    $result.actual_restore = $true
    $result.phase = 'restart persistence'
    Start-OwnedProcess $exe; Stop-OwnedProcess
    $second = Save-Fingerprint $data 'restarted-fingerprints.json'
    $comparisons = @()
    $app = 'authlens.sqlite3'
    foreach ($table in $business) {
        $s = $baseline.stores.$app.tables.$table; $a = $first.stores.$app.tables.$table; $b = $second.stores.$app.tables.$table
        if (-not $s) { $comparisons += [pscustomobject]@{ table = $table; present = $false }; continue }
        $same = $a -and $b -and $s.count -eq $a.count -and $s.sha256 -ceq $a.sha256 -and $a.sha256 -ceq $b.sha256
        $comparisons += [pscustomobject]@{ table = $table; present = $true; source_count = $s.count; restored_count = $a.count; restart_count = $b.count; fingerprints_match = [bool]$same }
        if (-not $same) { throw "Restored business/evidence fingerprint mismatch: $table." }
    }
    $acct = 'security/accounts.sqlite3'
    if ($baseline.stores.$acct) {
        $s = $baseline.stores.$acct; $b = $second.stores.$acct
        if (-not $b -or $s.tables.users.sha256 -cne $b.tables.users.sha256 -or $s.users -ne $b.users) { throw 'Restored account/credential fingerprint mismatch.' }
        if ($s.PSObject.Properties['enabled_administrators'] -and ($s.enabled_administrators -lt 1 -or $s.enabled_administrators -ne $b.enabled_administrators)) { throw 'Restored enabled-administrator count differs or is zero.' }
        $result.accounts = [ordered]@{ users = $b.users; enabled_administrators = $(if ($b.PSObject.Properties['enabled_administrators']) { $b.enabled_administrators } else { $null }); credentials_fingerprint_match = $true }
    } else { $result.accounts = 'not in archive' }
    $result.comparison = $comparisons; $result.restart_verified = $true; $result.integrity = 'ok'; $result.foreign_keys = 'ok'
    $result.scheduler = 'disabled by --no-worker'; $result.runtime_sha = $programManifest.source_sha
    $active1 = Get-ActiveFacts
    $changed = @($active0.Keys | Where-Object { $active0[$_] -ne $active1[$_] })
    if ($changed.Count -or (Get-AcceptanceFileHash $archive) -ne $archiveHash) { throw "Active installation or archive changed: $($changed -join ', ')." }
    $result.active_installation_unchanged = $true
    $result.status = 'passed'; $result.phase = 'complete'
} catch {
    $result.error = $_.Exception.Message -replace '[A-Za-z]:\\[^\s]*', '<path>'
    $result.error_line = $_.InvocationInfo.ScriptLineNumber
} finally {
    Stop-OwnedProcess
    $result.completed_utc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $root 'restore-result.json'), ($result | ConvertTo-Json -Depth 6))
    Write-Host ('Restore rehearsal: ' + $result.status + ' (' + $result.phase + '). Report: ' + (Join-Path $root 'restore-result.json'))
    Write-Host ('AUTHLENS-RESTORE-REHEARSAL: ' + ([pscustomobject]@{ status = $result.status; phase = $result.phase; report = (Join-Path $root 'restore-result.json') } | ConvertTo-Json -Compress))
}
if ($result.status -ne 'passed') { exit 1 }
