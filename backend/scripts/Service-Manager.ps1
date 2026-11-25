<#
.SYNOPSIS
  AuthLens local administration: status, network, TLS certificates, backup and recovery keys, administrator accounts, deployment recovery and
  diagnostics for the installed Server. Uses the packaged server executable and the installed, hash-verified deployment tools; no SDK.
.DESCRIPTION
  Without -Action (or -Action Menu) an interactive menu opens with a status overview and grouped menus (B goes back, Q exits); a refused or
  failed operation returns to its menu with an actionable message, and technical details go to <Root>\logs\service-manager (never key material,
  passwords or one-use codes). Every -Action below also runs non-interactively; changing actions need -Yes.

  Read-only: Status (key status), ServiceStatus, NetworkStatus, CertificateStatus, DeploymentStatus (recovery preview through -DryRun).
  Writes a new file only: ExportKey (then verifies the exported copy automatically), ExportCertificate (public .cer), CreateBackup, Diagnostics.
  Changes keys or accounts (no service restart): CreateKey, VerifyKey, GrantKeyAccess, ActivationCode, RecoveryCode.
  Restarts the service (downtime): RestartService, ChangeNetwork, ReplaceCertificate, Recover (Resume starts a stopped service; VerifyCandidate
  only restarts when a replacement certificate is applied).

  Key values never appear in output, logs or process arguments; export never overwrites a file. Administrator codes are shown locally once: do
  not run code actions under a transcript or redirect them to logs.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'CreateKey', 'ExportKey', 'VerifyKey', 'GrantKeyAccess', 'ActivationCode', 'RecoveryCode', 'NetworkStatus', 'ChangeNetwork',
        'ServiceStatus', 'CertificateStatus', 'ExportCertificate', 'ReplaceCertificate', 'DeploymentStatus', 'Recover', 'CreateBackup', 'Diagnostics', 'RestartService')]
    [string]$Action = 'Menu',
    # Empty: resolved from the installation Setup registered (HKLM\Software\AuthLens\Server ConfigFile), so custom roots and data paths are honored.
    [string]$DataDirectory = '',
    [string]$ConfigFile = '',
    # ChangeNetwork: only the settings given are changed.
    [ValidateSet('', 'Local', 'Corporate', 'ReverseProxy')][string]$AccessMode = '',
    [string]$ListenAddress = '',
    [int]$Port = 0,
    [string]$AllowedHosts = '',
    [string]$ProxyHosts = '',
    [string]$TrustedProxies = '',
    [string]$FirewallSources = '',
    [string]$FirewallProfiles = 'Domain',
    [switch]$ApproveFirewall,
    [switch]$RemoveFirewall,
    [string]$Executable = '',
    # Key file (CreateKey, ExportKey, VerifyKey), public certificate (ExportCertificate) or backup folder (CreateBackup).
    [string]$Path = '',
    # Alternative to -Path for CreateKey/ExportKey/ExportCertificate: destination folder and file name (default AuthLens-<computer>-recovery.key or
    # AuthLens-<computer>.cer; the extension is added once).
    [string]$Directory = '',
    [string]$FileName = '',
    # ExportKey/ExportCertificate: create a missing destination folder (protected ACL) instead of refusing.
    [switch]$CreateDirectory,
    [string]$Username = '',
    [string]$ServiceName = 'AuthLens',
    # Recover: VerifyCandidate, Resume, Rollback or Cancel (Auto lets the deployment tools decide). DeploymentStatus previews it.
    [ValidateSet('Auto', 'VerifyCandidate', 'Resume', 'Rollback', 'Cancel')][string]$RecoveryAction = 'Auto',
    # ReplaceCertificate, ChangeNetwork (combined change) and Recover (G-007): replacement PFX and its protected password file.
    [string]$CertificateFile = '',
    [string]$CertificatePasswordFile = '',
    # ExportCertificate from the Server installer's finish page: ask for the destination instead of requiring -Path/-Directory.
    [switch]$Interactive,
    [switch]$Yes
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# The deployment configuration of this machine's installed Server: an explicit -ConfigFile, else the file Setup registered after a verified
# installation, else the default location when it exists. Values are read as data only; nothing here writes the configuration.
function Get-AuthLensInstalledConfiguration([string]$Explicit) {
    $file = $Explicit
    if (-not $file) {
        try { $file = [string](Get-ItemProperty -LiteralPath 'HKLM:\Software\AuthLens\Server' -Name ConfigFile -ErrorAction Stop).ConfigFile } catch { $file = '' }
    }
    if (-not $file -and [IO.File]::Exists('C:\ProgramData\AuthLens\config\deploy.json')) { $file = 'C:\ProgramData\AuthLens\config\deploy.json' }
    if (-not $file) { return $null }
    if (-not [IO.File]::Exists($file)) { throw "The registered deployment configuration $file does not exist; select -ConfigFile or -DataDirectory explicitly." }
    $raw = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $root = if ($raw.PSObject.Properties['Root'] -and $raw.Root) { [string]$raw.Root } else { 'C:\ProgramData\AuthLens' }
    $data = if ($raw.PSObject.Properties['DataDirectory'] -and $raw.DataDirectory) { [string]$raw.DataDirectory } else { Join-Path $root 'data' }
    $service = if ($raw.PSObject.Properties['ServiceName'] -and $raw.ServiceName) { [string]$raw.ServiceName } else { 'AuthLens' }
    $backups = if ($raw.PSObject.Properties['BackupRoot'] -and $raw.BackupRoot) { [string]$raw.BackupRoot } else { Join-Path $root 'backups' }
    [pscustomobject]@{ config_file = $file; root = $root; data_directory = $data; service_name = $service; backup_root = $backups }
}

$installed = $null
$needsInstallation = $Action -in @('NetworkStatus', 'ChangeNetwork', 'ServiceStatus', 'CertificateStatus', 'ExportCertificate', 'ReplaceCertificate', 'DeploymentStatus', 'Recover', 'Diagnostics', 'RestartService')
if (-not $DataDirectory -or $needsInstallation) { $installed = Get-AuthLensInstalledConfiguration $ConfigFile }
elseif ($Action -eq 'Menu') { try { $installed = Get-AuthLensInstalledConfiguration $ConfigFile } catch { $installed = $null } }
if (-not $DataDirectory) {
    if ($installed) { $DataDirectory = $installed.data_directory } else { $DataDirectory = 'C:\ProgramData\AuthLens\data' }
}
if ($installed -and -not $PSBoundParameters.ContainsKey('ServiceName')) { $ServiceName = $installed.service_name }
if (-not $Executable) {
    $Executable = Join-Path $PSScriptRoot 'server\AuthLens.Api.exe'
    # Outside the installed payload: the current release of the registered installation (custom roots honored), else the default root.
    if (-not (Test-Path -LiteralPath $Executable)) { $Executable = Join-Path $(if ($installed) { $installed.root } else { 'C:\ProgramData\AuthLens' }) 'releases\current\server\AuthLens.Api.exe' }
}

function Get-AuthLensAdminArguments([string]$Operation, [string]$Data, [string]$File, [string]$User) {
    if ($Data -notmatch '^([A-Za-z]:[\\/]|\\\\|/)') { throw 'Select an absolute application data directory.' }
    if ($Operation -in @('CreateKey', 'ExportKey', 'VerifyKey') -and $File -notmatch '^([A-Za-z]:[\\/]|\\\\|/)') { throw 'Select an absolute recovery-key file path.' }
    $arguments = switch ($Operation) {
        'Status' { '--backup-key'; 'status' }
        'CreateKey' { '--backup-key'; 'create'; $File }
        'ExportKey' { '--backup-key'; 'export'; $File }
        'VerifyKey' { '--backup-key'; 'verify'; $File }
        'ActivationCode' { '--accounts-code' }
        'RecoveryCode' { if ($User -notmatch '\A[A-Za-z0-9_.@-]{1,100}\z') { throw 'Select the existing administrator username.' }; '--accounts-code'; '--recover-administrator'; $User }
        default { throw 'Unknown local administration action.' }
    }
    @($arguments) + @('--data-dir', $Data)
}

# The identity the installed service runs as, as a SID: LocalSystem, LocalService, NetworkService, the virtual account NT SERVICE\<name>, a local
# or domain account, or a gMSA. $StartName is the service's configured logon name (Win32_Service.StartName). An unknown or unresolvable identity is
# refused: access is never granted to a guessed principal.
function Resolve-AuthLensServiceSid([string]$StartName) {
    if (-not $StartName) { throw 'The AuthLens service is not installed or its logon account is unknown. Run GrantKeyAccess after installation.' }
    $name = $StartName.Trim()
    if ($name -ieq 'LocalSystem' -or $name -ieq 'NT AUTHORITY\SYSTEM') { return [Security.Principal.SecurityIdentifier]::new('S-1-5-18') }
    if ($name -ieq 'NT AUTHORITY\LocalService') { return [Security.Principal.SecurityIdentifier]::new('S-1-5-19') }
    if ($name -ieq 'NT AUTHORITY\NetworkService') { return [Security.Principal.SecurityIdentifier]::new('S-1-5-20') }
    if ($name.StartsWith('.\')) { $name = "$env:COMPUTERNAME\$($name.Substring(2))" }
    try { [Security.Principal.NTAccount]::new($name).Translate([Security.Principal.SecurityIdentifier]) }
    catch { throw "The service logon account '$name' could not be resolved to a security identifier; nothing was changed." }
}

function Get-AuthLensServiceStartName([string]$Name) {
    if ($Name -notmatch '\A[A-Za-z0-9_.-]{1,80}\z') { throw 'Select a valid service name.' }
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($service) { "$($service.StartName)" } else { '' }
}

# The access-control list (DACL) of a file only. Get-Acl/Set-Acl also round-trip the audit list (SACL), which needs SeSecurityPrivilege that an
# elevated token does not enable by default; reading and writing the DACL alone needs only the owner's or WRITE_DAC rights.
function Get-AuthLensFileAcl([string]$File) {
    $info = [IO.FileInfo]::new($File)
    if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::GetAccessControl($info, [Security.AccessControl.AccessControlSections]::Access) }
    else { $info.GetAccessControl([Security.AccessControl.AccessControlSections]::Access) }
}

function Set-AuthLensFileAcl([string]$File, [Security.AccessControl.FileSecurity]$Acl) {
    $info = [IO.FileInfo]::new($File)
    if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::SetAccessControl($info, $Acl) } else { $info.SetAccessControl($Acl) }
}

# Least privilege: one explicit, non-inherited Allow Read rule for the service identity on the key file only. Nothing else in the ACL changes,
# the directory gets no grant (Bypass Traverse Checking covers path traversal), and SYSTEM needs no grant. Reparse points are refused.
function Grant-AuthLensKeyRead([string]$File, [Security.Principal.SecurityIdentifier]$Sid) {
    $item = Get-Item -LiteralPath $File -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The recovery-key path must be a regular file, not a directory or reparse point.' }
    if ($Sid.Value -eq 'S-1-5-18') { return 'not_required' }
    if (Test-AuthLensKeyRead $File $Sid) { return 'already_granted' }
    $acl = Get-AuthLensFileAcl $File
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($Sid, [Security.AccessControl.FileSystemRights]::Read, 'Allow'))
    Set-AuthLensFileAcl $File $acl
    if (-not (Test-AuthLensKeyRead $File $Sid)) { throw 'Read access for the service identity could not be verified after the change.' }
    'granted'
}

# True when the identity has an Allow rule that includes read data on the file and no Deny rule for read data. Group membership is not
# evaluated (provisioning creates an explicit grant); SYSTEM is always true.
function Test-AuthLensKeyRead([string]$File, [Security.Principal.SecurityIdentifier]$Sid) {
    if ($Sid.Value -eq 'S-1-5-18') { return $true }
    $rules = @((Get-AuthLensFileAcl $File).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $Sid.Value })
    $read = [Security.AccessControl.FileSystemRights]::ReadData
    if (@($rules | Where-Object { $_.AccessControlType -eq 'Deny' -and ($_.FileSystemRights -band $read) }).Count) { return $false }
    [bool]@($rules | Where-Object { $_.AccessControlType -eq 'Allow' -and ($_.FileSystemRights -band $read) -eq $read }).Count
}

# The configured key path from the data directory's location record (a path only; the key itself is never read here).
function Get-AuthLensKeyLocation([string]$Data) {
    $pointer = Join-Path $Data 'backup-key-location.json'
    if (-not [IO.File]::Exists($pointer)) { return '' }
    "$(([IO.File]::ReadAllText($pointer) | ConvertFrom-Json).path)"
}

# The installed, hash-verified deployment tools staged by Setup beside this payload (<Root>\app\setup\<package>\tools). Every helper listed in
# installer-tools.json is verified before use; a missing or changed helper is refused, never replaced by a repository copy.
function Get-AuthLensInstalledDeployTool([string]$Payload) {
    $tools = Join-Path (Split-Path (Split-Path $Payload -Parent) -Parent) 'tools'
    $proof = Join-Path $tools 'installer-tools.json'
    if (-not [IO.File]::Exists($proof)) { throw 'The installed deployment tools were not found beside this Service Manager; run the Start-menu AuthLens Service Manager of the installed package.' }
    foreach ($entry in @(([IO.File]::ReadAllText($proof) | ConvertFrom-Json).files)) {
        if ($entry.path -notmatch '\A(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\z' -or $entry.path -match '(^|/)\.\.(/|$)') { throw 'Invalid installed tool path.' }
        $file = Join-Path $tools ($entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not [IO.File]::Exists($file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.sha256) { throw 'Installed deployment tool integrity verification failed; nothing was run.' }
    }
    $deploy = Join-Path $tools 'deploy\Deploy-AuthLens.ps1'
    if (-not [IO.File]::Exists($deploy)) { throw 'Deploy-AuthLens.ps1 is missing from the installed tools.' }
    $deploy
}

# The ChangeNetwork arguments for Deploy-AuthLens.ps1. Lists are comma-separated; an empty value leaves that setting unchanged; '-' clears a list.
function Get-AuthLensNetworkArguments([string]$Config, [hashtable]$Values, [bool]$DryRun) {
    $arguments = @('-Action', 'ChangeNetwork', '-ConfigFile', $Config)
    if ($Values.AccessMode) { $arguments += @('-AccessMode', $Values.AccessMode) }
    if ($Values.ListenAddress) { $arguments += @('-ListenAddress', $Values.ListenAddress) }
    if ([int]$Values.Port) { $arguments += @('-Port', [string][int]$Values.Port) }
    foreach ($name in 'AllowedHosts', 'ProxyHosts', 'TrustedProxies') {
        $value = [string]$Values[$name]
        if ($value -eq '-') { $arguments += @("-$name", '') } elseif ($value) { $arguments += @("-$name", (($value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ',')) }
    }
    if ($Values.ApproveFirewall) { $arguments += @('-ApproveFirewall', '-FirewallSources', [string]$Values.FirewallSources, '-FirewallProfiles', [string]$Values.FirewallProfiles) }
    if ($Values.RemoveFirewall) { $arguments += '-RemoveFirewall' }
    if ($Values.ContainsKey('CertificateFile') -and $Values.CertificateFile) { $arguments += @('-CertificateFile', [string]$Values.CertificateFile, '-CertificatePasswordFile', [string]$Values.CertificatePasswordFile) }
    if ($DryRun) { $arguments += '-DryRun' } else { $arguments += '-Yes' }
    $arguments
}

# Runs the installed deployment entry point and returns its machine-readable result (the AUTHLENS-RESULT line).
function Invoke-AuthLensDeployTool([string]$Deploy, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $output = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Deploy @Arguments 2>&1 | ForEach-Object { "$_" })
    $line = @($output | Where-Object { $_ -like 'AUTHLENS-RESULT: *' }) | Select-Object -Last 1
    if (-not $line) { throw ('The deployment tool returned no result: ' + (($output | Select-Object -Last 3) -join ' ')) }
    ($line.Substring('AUTHLENS-RESULT: '.Length) | ConvertFrom-Json)
}

function Write-AuthLensNetworkSummary($Summary) {
    Write-Host 'Current and proposed network configuration:'
    foreach ($name in 'access_mode', 'listen_address', 'port', 'allowed_hosts', 'proxy_hosts', 'trusted_proxies') {
        Write-Host ('  {0,-16} {1}  ->  {2}' -f $name, (@($Summary.current.$name) -join ','), (@($Summary.proposed.$name) -join ','))
    }
    Write-Host "  certificate      $($Summary.certificate)"
    if ($Summary.PSObject.Properties['certificate_proposed']) { Write-AuthLensCertificate 'certificate for the new settings' $Summary.certificate_proposed }
    if ($Summary.PSObject.Properties['client_trust_notice']) { Write-Host "  client trust     $($Summary.client_trust_notice)" }
    Write-Host "  firewall         $($Summary.firewall)"
    Write-Host '  Downtime: the service restarts; readiness and the release identity are verified on the new listener, and a failure restores the previous configuration.'
}

function Invoke-AuthLensNetworkWorkflow([string]$Operation, [hashtable]$Values, [bool]$Confirmed) {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for this local operation.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    if ($Operation -eq 'NetworkStatus') {
        $status = Invoke-AuthLensDeployTool $deploy @('-Action', 'Status', '-ConfigFile', $installed.config_file)
        $value = $status.result
        Write-Host "Configuration: $($installed.config_file)"
        Write-Host "Access mode: $($value.access_mode)  Listener: $($value.listen_address):$($value.port)  Ready: $($value.ready)"
        Write-Host "Allowed hosts: $(@($value.allowed_hosts) -join ', ')  Proxy hosts: $(@($value.proxy_hosts) -join ', ')  Trusted proxies: $(@($value.trusted_proxies) -join ', ')"
        Write-Host "Certificate: $($value.certificate)  Pending configuration change: $($value.configuration_change_pending)"
        if ($value.PSObject.Properties['certificate_status']) { Write-AuthLensCertificate 'Active certificate' $value.certificate_status }
        return
    }
    $plan = Invoke-AuthLensDeployTool $deploy (Get-AuthLensNetworkArguments $installed.config_file $Values $true)
    if ($plan.exit -ne 0) { throw "The proposed network configuration was refused: $($plan.result.error)" }
    if (-not $plan.result.dry_run) { Write-Host "An interrupted configuration change was restored first (service process $(Get-AuthLensValue $plan.result 'process_id')); review Network status and repeat."; return }
    Write-AuthLensNetworkSummary $plan.result.summary
    if (-not $Confirmed) { throw 'Validated only. Repeat with -Yes (or type YES in the menu) to apply this change.' }
    $applied = Invoke-AuthLensDeployTool $deploy (Get-AuthLensNetworkArguments $installed.config_file $Values $false)
    if ($applied.exit -ne 0) { throw "The network change did not complete: $($applied.result.error)" }
    Write-Host "Network change complete: service process $(Get-AuthLensValue $applied.result 'process_id') is ready on the new configuration."
    if ($applied.result.firewall_recovery_required) { Write-Warning 'The service is ready on the new configuration, but the firewall transition needs recovery (Install-AuthLens.ps1 -Mode Server -Operation Firewall ...).' }
}

function Test-AuthLensAdminElevation {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-AuthLensLocalAdmin([string]$Operation, [string]$File, [string]$User, [bool]$Confirmed) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Packaged AuthLens.Api.exe was not found. Specify -Executable from a verified release.' }
    $target = $null
    if ($Operation -in @('CreateKey', 'ExportKey')) {
        # The whole destination is validated before anything runs (D-005): absolute folder, file name with one .key extension, no directory as
        # file, no reparse point, outside application data, no existing file, write access.
        $target = Resolve-AuthLensKeyTarget $File $Directory $FileName $DataDirectory
        $File = $target.path
    }
    if ($Operation -ne 'Status') {
        if (-not $Confirmed) { throw 'Repeat with -Yes after reviewing the data directory and operation. Key and code actions are never automatic.' }
        if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for this local operation.' }
    }
    if ($target) {
        if (-not $target.directory_exists) {
            # CreateKey keeps its earlier contract (it creates a missing private folder); export creates one only when asked.
            if ($Operation -eq 'ExportKey' -and -not $CreateDirectory) { throw "The folder $($target.directory) does not exist. Create it first, or repeat with -CreateDirectory (a protected folder: SYSTEM, Administrators and you)." }
            New-AuthLensPrivateDirectory $target.directory
        }
        if (-not (Test-AuthLensDirectoryWritable $target.directory)) { throw "This session cannot create files in $($target.directory). Choose a folder you can write to, or run Service Manager as administrator." }
    }
    $arguments = @(Get-AuthLensAdminArguments $Operation $DataDirectory $File $User)
    # The process receives file paths only; it reads key files itself. Never read or echo the key here.
    $result = Invoke-AuthLensHost $arguments
    $result.lines | ForEach-Object { Write-Host "$_" }
    if ($Operation -eq 'ExportKey') {
        # Automatic verification of the new recovery copy (the standalone VerifyKey action remains).
        $verify = Invoke-AuthLensHost @(Get-AuthLensAdminArguments 'VerifyKey' $DataDirectory $File '')
        $verify.lines | ForEach-Object { Write-Host "$_" }
        Write-Host "Recovery copy written and verified: $File"
        Write-AuthLensRecoveryGuidance
    }
    if ($Operation -in @('CreateKey', 'Status')) { Write-AuthLensKeyAccess $Operation }
}

# Runs the packaged host with arguments only (never secret values) and returns its output lines; a refusal becomes an exception without the
# host's internal prefix.
function Invoke-AuthLensHost([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $output = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('AuthLens refused the local operation: ' + (($output | ForEach-Object { $_ -replace '^(backup key refused|maintenance refused|check refused): ', '' }) -join ' ')) }
    [pscustomobject]@{ lines = $output; code = $code }
}

# After CreateKey: grant the service identity read on the new key file. Status: report whether the service can read it (diagnostic only).
function Write-AuthLensKeyAccess([string]$Operation) {
    $key = Get-AuthLensKeyLocation $DataDirectory
    if (-not $key) { return }
    try { $sid = Resolve-AuthLensServiceSid (Get-AuthLensServiceStartName $ServiceName) }
    catch { Write-Warning "$($_.Exception.Message) Until then the service cannot read the key and reports it as inaccessible."; return }
    if ($Operation -eq 'CreateKey') { Write-Host "Service key access: $(Grant-AuthLensKeyRead $key $sid) ($sid)"; return }
    try { Write-Host "Service key access: $(if (Test-AuthLensKeyRead $key $sid) { 'readable' } else { 'not readable; run -Action GrantKeyAccess -Yes as administrator' }) ($sid)" }
    catch { Write-Host 'Service key access: unknown (run Status as administrator to inspect the key ACL)' }
}

# GrantKeyAccess: repairs read access for the configured key of an existing installation. An offered -Path must be the configured key.
function Invoke-AuthLensGrantKeyAccess([bool]$Confirmed) {
    if (-not $Confirmed) { throw 'Repeat with -Yes after reviewing the data directory and operation. Key and code actions are never automatic.' }
    if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for this local operation.' }
    $key = Get-AuthLensKeyLocation $DataDirectory
    if (-not $key) { throw 'No host backup key is configured for this data directory.' }
    if ($Path -and [IO.Path]::GetFullPath($Path) -ine [IO.Path]::GetFullPath($key)) { throw 'The selected file is not the configured host backup key; nothing was changed.' }
    $sid = Resolve-AuthLensServiceSid (Get-AuthLensServiceStartName $ServiceName)
    Write-Host "Service key access: $(Grant-AuthLensKeyRead $key $sid) ($sid)"
}


# ---- destinations (WP19, D-005)

# Removes surrounding quotes and spaces that operators paste with a path ("C:\Recovery keys\").
function ConvertFrom-AuthLensPathInput([string]$Value) { if ($null -eq $Value) { return '' }; $Value.Trim().Trim('"').Trim("'").Trim() }

# A file name for a destination folder: the default when empty, the extension added once (case-insensitive), Windows-invalid names refused.
function ConvertTo-AuthLensFileName([string]$Name, [string]$Default, [string]$Extension) {
    $value = ConvertFrom-AuthLensPathInput $Name
    if (-not $value) { $value = $Default }
    if ($value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'The file name contains a character Windows does not allow (\ / : * ? " < > |). Enter a file name only; the folder is asked separately.' }
    if ($value.EndsWith('.') -or $value.EndsWith(' ')) { throw 'A file name must not end with a dot or a space.' }
    if (-not $value.EndsWith($Extension, [StringComparison]::OrdinalIgnoreCase)) { $value += $Extension }
    if ($value.Length -le $Extension.Length) { throw "Enter a file name before $Extension." }
    if ($value -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw 'That file name is reserved by Windows.' }
    $value
}

function Get-AuthLensDefaultKeyName { "AuthLens-$($env:COMPUTERNAME)-recovery" }

# The complete destination of a new recovery-key file, validated before anything runs. -Path (an existing CLI contract) is taken as the exact
# file; a directory there is refused with the default name suggested. -Directory/-FileName (and the menu) apply the default name and extension.
function Resolve-AuthLensKeyTarget([string]$File, [string]$Folder, [string]$Name, [string]$Data) {
    $File = ConvertFrom-AuthLensPathInput $File; $Folder = ConvertFrom-AuthLensPathInput $Folder
    if ($File -and ($Folder -or $Name)) { throw 'Use either -Path or -Directory with -FileName, not both.' }
    if ($File) {
        if ($File -notmatch '^([A-Za-z]:[\\/]|\\\\)') { throw 'Select an absolute recovery-key file path, for example E:\AuthLens-recovery\' + (Get-AuthLensDefaultKeyName) + '.key.' }
        if ([IO.Directory]::Exists($File)) { throw "$File is a folder. Add a file name, for example $(Join-Path $File ((Get-AuthLensDefaultKeyName) + '.key')), or use -Directory with -FileName." }
        $full = [IO.Path]::GetFullPath($File); $Folder = Split-Path $full -Parent; $leaf = Split-Path $full -Leaf
        if (-not $leaf) { throw 'Select a file name for the recovery key.' }
    } else {
        if (-not $Folder) { throw 'Select the destination folder for the recovery key (-Directory, or -Path with a complete file name).' }
        if ($Folder -notmatch '^([A-Za-z]:[\\/]|\\\\)') { throw 'Select an absolute folder, for example E:\AuthLens-recovery.' }
        $leaf = ConvertTo-AuthLensFileName $Name (Get-AuthLensDefaultKeyName) '.key'
        $Folder = [IO.Path]::GetFullPath($Folder)
        $full = Join-Path $Folder $leaf
    }
    Assert-AuthLensSafeDestination $Folder $full $Data
    [pscustomobject]@{ directory = $Folder; path = $full; directory_exists = [IO.Directory]::Exists($Folder) }
}

# A public certificate destination: folder plus file name (default AuthLens-<computer>.cer), or an exact -Path ending in .cer.
function Resolve-AuthLensCertificateTarget([string]$File, [string]$Folder, [string]$Name, [string]$Data) {
    $File = ConvertFrom-AuthLensPathInput $File; $Folder = ConvertFrom-AuthLensPathInput $Folder
    if ($File) {
        if ([IO.Directory]::Exists($File)) { $Folder = $File; $File = '' }
        else {
            if ($File -notmatch '^([A-Za-z]:[\\/]|\\\\)') { throw 'Select an absolute file path ending in .cer.' }
            $full = [IO.Path]::GetFullPath($File)
            $leaf = ConvertTo-AuthLensFileName (Split-Path $full -Leaf) "AuthLens-$($env:COMPUTERNAME)" '.cer'
            $Folder = Split-Path $full -Parent; $full = Join-Path $Folder $leaf
        }
    }
    if (-not $File) {
        if (-not $Folder -or $Folder -notmatch '^([A-Za-z]:[\\/]|\\\\)') { throw 'Select an absolute destination folder for the public certificate.' }
        $Folder = [IO.Path]::GetFullPath($Folder)
        $full = Join-Path $Folder (ConvertTo-AuthLensFileName $Name "AuthLens-$($env:COMPUTERNAME)" '.cer')
    }
    Assert-AuthLensSafeDestination $Folder $full $Data
    [pscustomobject]@{ directory = $Folder; path = $full; directory_exists = [IO.Directory]::Exists($Folder) }
}

function Assert-AuthLensSafeDestination([string]$Folder, [string]$Full, [string]$Data) {
    if ([IO.File]::Exists($Folder)) { throw "$Folder is a file, not a folder." }
    if ([IO.Directory]::Exists($Full)) { throw "$Full is a folder; choose a file name." }
    if ([IO.File]::Exists($Full)) { throw "$Full already exists. Choose another file name; existing files are never overwritten." }
    if ($Data) {
        $dataRoot = [IO.Path]::GetFullPath($Data).TrimEnd('\') + '\'
        if (($Full + '\').StartsWith($dataRoot, [StringComparison]::OrdinalIgnoreCase) -or $Full.StartsWith($dataRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Recovery copies and exports must be stored outside the application data directory.' }
    }
    $ancestor = $Folder
    while ($ancestor) {
        if ([IO.Directory]::Exists($ancestor) -and ([IO.DirectoryInfo]::new($ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The destination folder must not traverse a junction or symbolic link.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}

# Whether this session can create a file in the folder: a create-only probe file that is removed immediately (no key material).
function Test-AuthLensDirectoryWritable([string]$Folder) {
    $probe = Join-Path $Folder ('.authlens-write-test-' + [guid]::NewGuid().ToString('N'))
    try { $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $stream.Dispose(); [IO.File]::Delete($probe); $true }
    catch [UnauthorizedAccessException] { $false }
    catch [IO.IOException] { $false }
}

# A new private folder: protected ACL with SYSTEM, Administrators and the current user only.
function New-AuthLensPrivateDirectory([string]$Folder) {
    $null = [IO.Directory]::CreateDirectory($Folder)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    $info = [IO.DirectoryInfo]::new($Folder)
    if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::SetAccessControl($info, $acl) } else { $info.SetAccessControl($acl) }
}

function Write-AuthLensRecoveryGuidance {
    Write-Host ''
    Write-Host 'Store the recovery copy off this server:'
    Write-Host '  - Move it to approved offline or vault storage (for example an encrypted removable drive kept in a safe, or your organization''s secrets vault).'
    Write-Host '  - Anyone holding it can decrypt this installation''s backups. Never keep it in the backup share, email it or store it with the backups.'
    Write-Host '  - After moving it, verify that copy again (Backup and recovery keys > Verify recovery copy), then delete any temporary local copy.'
}

# ---- installed tools and results

function Get-AuthLensInstalledInstaller([string]$Payload) {
    $deploy = Get-AuthLensInstalledDeployTool $Payload
    $installer = Join-Path (Split-Path (Split-Path $deploy -Parent) -Parent) 'Install-AuthLens.ps1'
    if (-not [IO.File]::Exists($installer)) { throw 'Install-AuthLens.ps1 is missing from the installed tools.' }
    $installer
}

# Guided preview must never run a real recovery (D-006): the installed deployment module must carry the simulation policy before -DryRun is used.
function Assert-AuthLensSimulationSupport([string]$Deploy) {
    $module = Join-Path (Split-Path $Deploy -Parent) 'AuthLens.Deploy.psm1'
    if (-not [IO.File]::Exists($module) -or -not ([IO.File]::ReadAllText($module)).Contains('function Get-ALActionPolicy')) { throw 'The installed deployment tools predate the simulation safeguard (D-006); guided recovery preview is refused. Use a corrected AuthLens package.' }
}

function Invoke-AuthLensInstallerTool([string]$Installer, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $output = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Installer @Arguments 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $line = @($output | Where-Object { $_ -like 'AUTHLENS-INSTALLER: *' }) | Select-Object -Last 1
    if ($code -ne 0 -or -not $line) {
        $reason = @($output | Where-Object { $_ -like 'Installer refused or failed: *' }) | Select-Object -Last 1
        throw $(if ($reason) { $reason.Substring('Installer refused or failed: '.Length) } else { 'The installer tool returned no result: ' + (($output | Select-Object -Last 3) -join ' ') })
    }
    ($line.Substring('AUTHLENS-INSTALLER: '.Length) | ConvertFrom-Json)
}

function Get-AuthLensValue($Object, [string]$Name) { if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null } }

function Get-AuthLensStatus {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    $status = Invoke-AuthLensDeployTool $deploy @('-Action', 'Status', '-ConfigFile', $installed.config_file)
    if ($status.exit -ne 0) { throw "Status could not be read: $(Get-AuthLensValue $status.result 'error')" }
    $status.result
}

function Write-AuthLensCertificate([string]$Label, $Certificate) {
    if (-not $Certificate) { Write-Host "  $Label`: not available (the installed release cannot describe it, or the certificate cannot be opened)"; return }
    $missing = @(Get-AuthLensValue $Certificate 'missing_identities' | Where-Object { $_ })
    Write-Host "  $Label`: $(Get-AuthLensValue $Certificate 'subject')  issuer $(Get-AuthLensValue $Certificate 'issuer')$(if (Get-AuthLensValue $Certificate 'self_signed') { ' (self-signed)' })"
    Write-Host "    valid until $(Get-AuthLensValue $Certificate 'not_after_utc') ($(Get-AuthLensValue $Certificate 'days_remaining') days)  SHA-256 $(Get-AuthLensValue $Certificate 'thumbprint_sha256')"
    Write-Host "    names: $(@(@(Get-AuthLensValue $Certificate 'dns_names') + @(Get-AuthLensValue $Certificate 'ip_addresses') | Where-Object { $_ }) -join ', ')"
    if ($missing.Count) { Write-Host "    MISSING required identities: $($missing -join ', ')" } else { Write-Host '    covers every required identity' }
}

# The concise overview shown at startup and after each action group.
function Write-AuthLensOverview {
    Write-Host ''
    Write-Host "AuthLens Service Manager - $env:COMPUTERNAME$(if (-not (Test-AuthLensAdminElevation)) { '  (not elevated: changes need Run as administrator)' })"
    if (-not $installed) { Write-Host "  No registered Server installation was found. Data directory: $DataDirectory"; return }
    Write-Host "  Configuration: $($installed.config_file)"
    try { $s = Get-AuthLensStatus } catch { Write-Host "  Status unavailable: $($_.Exception.Message)"; return }
    $svc = Get-AuthLensValue $s 'service'
    Write-Host ("  Service: {0} {1} as {2}, PID {3}; release {4} ({5}); ready: {6}" -f $s.service_name, (Get-AuthLensValue $svc 'State'), (Get-AuthLensValue $svc 'Account'), (Get-AuthLensValue $svc 'ProcessId'), $s.current_version, ("$($s.current_commit)" -replace '^(.{7}).*', '$1'), $s.ready)
    Write-Host ("  Network: {0} {1}:{2}; allowed hosts {3}" -f $s.access_mode, $s.listen_address, $s.port, (@($s.allowed_hosts) -join ', '))
    $cert = Get-AuthLensValue $s 'certificate_status'
    if ($cert) { Write-Host ("  Certificate: expires {0} ({1} days); {2}" -f $cert.not_after_utc, $cert.days_remaining, $(if (@($cert.missing_identities | Where-Object { $_ }).Count) { 'MISSING ' + (@($cert.missing_identities) -join ', ') } else { 'covers required identities' })) }
    try { $key = (Invoke-AuthLensHost @('--backup-key', 'status', '--data-dir', $DataDirectory)).lines -join '' | ConvertFrom-Json; Write-Host "  Backup key: $($key.state); recovery copy verified: $($key.escrow_verified)" } catch { Write-Host '  Backup key: status unavailable' }
    Write-Host ("  Deployment: journal {0}; recovery needed: {1}; configuration change pending: {2}; service key read: {3}" -f $s.journal_phase, $s.recovery_needed, $s.configuration_change_pending, $s.backup_key_service_access)
}

# ---- TLS certificates (WP20)

function Invoke-AuthLensCertificateWorkflow([string]$Operation, [bool]$Confirmed) {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    switch ($Operation) {
        'CertificateStatus' {
            $s = Get-AuthLensStatus
            Write-Host "Certificate file: $($s.certificate)"
            Write-AuthLensCertificate 'Active certificate' (Get-AuthLensValue $s 'certificate_status')
            Write-Host 'Required identities: every allowed host (network access) or the loopback listen address (Local). The listen IP is required only when clients use it as an allowed host.'
        }
        'ExportCertificate' {
            if ($Interactive -and -not $Path -and -not $Directory) {
                Write-Host 'Export the public HTTPS certificate (.cer) of this AuthLens Server. It contains no private key and no password.'
                $script:Directory = Read-AuthLensInput 'Destination folder' ([Environment]::GetFolderPath('MyDocuments'))
                $script:FileName = Read-AuthLensInput 'File name' "AuthLens-$($env:COMPUTERNAME)"
                $preview = Resolve-AuthLensCertificateTarget '' $Directory $FileName $DataDirectory
                if (-not $preview.directory_exists) { if (-not (Read-AuthLensConfirmation "Create the folder $($preview.directory)?")) { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') }; $script:CreateDirectory = $true }
                if (-not (Read-AuthLensConfirmation "Write the public certificate to $($preview.path)? Existing files are never overwritten.")) { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') }
            }
            $target = Resolve-AuthLensCertificateTarget $Path $Directory $FileName $DataDirectory
            if (-not $target.directory_exists) { if (-not $CreateDirectory) { throw "The folder $($target.directory) does not exist; create it or repeat with -CreateDirectory." }; $null = [IO.Directory]::CreateDirectory($target.directory) }
            $result = Invoke-AuthLensDeployTool $deploy @('-Action', 'ExportCertificate', '-ConfigFile', $installed.config_file, '-PublicCertificateFile', $target.path)
            if ($result.exit -ne 0) { throw "The public certificate was not exported: $(Get-AuthLensValue $result.result 'error')" }
            Write-Host "Public certificate (no private key) written to $($target.path); SHA-256 $(Get-AuthLensValue $result.result 'thumbprint_sha256')."
            Write-Host 'Distribute it through an approved channel (for example Group Policy: Trusted People or Trusted Root, per your policy). Never distribute the PFX, its password or recovery keys.'
        }
        'ReplaceCertificate' {
            foreach ($file in $CertificateFile, $CertificatePasswordFile) { if (-not $file) { throw 'Select the replacement PFX (-CertificateFile) and its protected password file (-CertificatePasswordFile).' } }
            $common = @('-Action', 'ReplaceCertificate', '-ConfigFile', $installed.config_file, '-CertificateFile', $CertificateFile, '-CertificatePasswordFile', $CertificatePasswordFile)
            $plan = Invoke-AuthLensDeployTool $deploy ($common + '-DryRun')
            if ($plan.exit -ne 0) { throw "The replacement certificate was refused; nothing was changed: $(Get-AuthLensValue $plan.result 'error')" }
            Write-AuthLensCertificate 'Current certificate' (Get-AuthLensValue $plan.result 'certificate_current')
            Write-AuthLensCertificate 'New certificate' (Get-AuthLensValue $plan.result 'certificate_proposed')
            Write-Host "Client trust: $(Get-AuthLensValue $plan.result 'client_trust_notice')"
            Write-Host 'Applying restarts the service (short downtime); a failure restores the previous certificate automatically. Previous TLS files are kept.'
            if (-not $Confirmed) { throw 'Validated only. Repeat with -Yes (or type YES in the menu) to replace the certificate.' }
            $applied = Invoke-AuthLensDeployTool $deploy ($common + '-Yes')
            if ($applied.exit -ne 0) { throw "The certificate was not replaced: $(Get-AuthLensValue $applied.result 'error')" }
            Write-Host "Certificate replaced; service process $(Get-AuthLensValue $applied.result 'process_id') is ready. New public certificate: $(Get-AuthLensValue $applied.result 'public_certificate')"
        }
    }
}

# ---- service restart (WP19)

function Invoke-AuthLensRestartWorkflow([bool]$Confirmed) {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    Assert-AuthLensSimulationSupport $deploy
    $common = @('-Action', 'RestartService', '-ConfigFile', $installed.config_file)
    # The checks first (a simulation that changes nothing); a pending deployment or configuration recovery refuses here.
    $plan = Invoke-AuthLensDeployTool $deploy ($common + '-DryRun')
    if ($plan.exit -ne 0) { throw "The service cannot be restarted now: $(Get-AuthLensValue $plan.result 'error')" }
    if (-not (Get-AuthLensValue $plan.result 'simulation')) { throw 'The restart check did not identify itself as a simulation; nothing further is run.' }
    Write-Host "Service $(Get-AuthLensValue $plan.result 'service'): $(Get-AuthLensValue $plan.result 'state_before'), process $(Get-AuthLensValue $plan.result 'process_before'); release $(Get-AuthLensValue $plan.result 'version') ($("$(Get-AuthLensValue $plan.result 'commit')" -replace '^(.{7}).*', '$1'))"
    Write-Host "Downtime: $(Get-AuthLensValue $plan.result 'downtime')"
    if (-not $Confirmed) { throw 'Checked only. Repeat with -Yes (or type YES in the menu) to restart the service.' }
    if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator to restart the service.' }
    $applied = Invoke-AuthLensDeployTool $deploy ($common + '-Yes')
    if ($applied.exit -ne 0) { throw "The restart did not complete: $(Get-AuthLensValue $applied.result 'error') Review Service status and Diagnostics." }
    Write-Host "Service restarted: process $(Get-AuthLensValue $applied.result 'process_before') -> $(Get-AuthLensValue $applied.result 'process_after'); it owns the listener and is ready as $((Get-AuthLensValue $applied.result 'identity') | ConvertTo-Json -Compress)."
}

# ---- deployment recovery (G-003): preview through the simulation, then the installed Setup tools with explicit confirmation

function Write-AuthLensRecoveryPreview($Preview) {
    Write-Host "Deployment journal: $(Get-AuthLensValue $Preview 'journal_run') phase $(Get-AuthLensValue $Preview 'journal_phase')"
    Write-Host "  history: $(@(Get-AuthLensValue $Preview 'history') -join ' > ')"
    foreach ($option in @(Get-AuthLensValue $Preview 'options')) { if ($option) { Write-Host ("  {0,-16} {1}{2}" -f $option.action, $(if ($option.available) { 'available' } else { 'not available' }), $(if ($option.reason) { " - $($option.reason)" })) } }
    if (Get-AuthLensValue $Preview 'pending_configuration_change') { Write-Host "  An interrupted $($Preview.pending_configuration_change) is restored first." }
}

function Invoke-AuthLensRecoveryWorkflow([string]$Operation, [string]$Requested, [bool]$Confirmed) {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    Assert-AuthLensSimulationSupport $deploy
    $certificate = @(); if ($CertificateFile -or $CertificatePasswordFile) { $certificate = @('-CertificateFile', $CertificateFile, '-CertificatePasswordFile', $CertificatePasswordFile) }
    # The preview is always a simulation: -DryRun and never -Yes.
    $preview = Invoke-AuthLensDeployTool $deploy (@('-Action', 'Recover', '-ConfigFile', $installed.config_file, '-RecoveryAction', $Requested, '-DryRun') + $certificate)
    $value = $preview.result
    if (-not (Get-AuthLensValue $value 'simulation')) { throw 'The recovery preview did not identify itself as a simulation; nothing further is run.' }
    Write-AuthLensRecoveryPreview $value
    if ($Operation -eq 'DeploymentStatus') {
        if ($Requested -ne 'Auto' -or (Get-AuthLensValue $value 'journal_phase') -in @('stopping', 'switched', 'starting', 'verifying', 'manual_recovery_required')) {
            Write-Host "Preview of $Requested`: $(Get-AuthLensValue $value 'would_action'); would succeed: $(Get-AuthLensValue $value 'would_succeed') $(Get-AuthLensValue $value 'blocking_reason')"
        }
        return
    }
    if ($Requested -eq 'Auto') { throw 'Select an explicit recovery action (VerifyCandidate, Resume, Rollback or Cancel) from the available options.' }
    if (-not (Get-AuthLensValue $value 'would_succeed')) { throw "$Requested would be refused: $(Get-AuthLensValue $value 'blocking_reason') Nothing was changed." }
    Write-Host "$Requested would $(Get-AuthLensValue $value 'would_action') and end in phase $(Get-AuthLensValue $value 'would_phase')."
    if (Get-AuthLensValue $value 'would_replace_certificate') {
        Write-AuthLensCertificate 'Current certificate' (Get-AuthLensValue $value 'certificate_current')
        Write-AuthLensCertificate 'Replacement certificate' (Get-AuthLensValue $value 'certificate_proposed')
        Write-Host "Client trust: $(Get-AuthLensValue $value 'client_trust_notice')"
    }
    $downtime = if ((Get-AuthLensValue $value 'would_replace_certificate') -or $Requested -eq 'Rollback') { 'The service restarts (downtime).' } elseif (Get-AuthLensValue $value 'would_start_service') { 'The stopped service is started.' } else { 'The running service is not restarted.' }
    Write-Host $downtime
    if (-not $Confirmed) { throw "Previewed only. Repeat with -Yes (or type YES in the menu) to run $Requested." }
    if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for deployment recovery.' }
    $installer = Get-AuthLensInstalledInstaller $PSScriptRoot
    $arguments = @('-Mode', 'Server', '-Recover', '-RecoveryAction', $Requested, '-ConfigFile', $installed.config_file, '-Yes')
    if ($CertificateFile) { $arguments += @('-RecoveryCertificateFile', $CertificateFile, '-RecoveryCertificatePasswordFile', $CertificatePasswordFile) }
    $result = Invoke-AuthLensInstallerTool $installer $arguments
    Write-Host "Recovery finished: phase $(Get-AuthLensValue $result 'phase'); $(Get-AuthLensValue $result 'action')"
}

# ---- backups and diagnostics

function Invoke-AuthLensBackup([bool]$Confirmed) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Packaged AuthLens.Api.exe was not found. Specify -Executable from a verified release.' }
    # Default: the installation's pre-deployment backup folder (the archive kind --backup-local writes).
    $folder = if ($Path) { ConvertFrom-AuthLensPathInput $Path } elseif ($installed) { $installed.backup_root } else { throw 'Select the backup folder with -Path.' }
    if ($folder -notmatch '^([A-Za-z]:[\\/]|\\\\)') { throw 'Select an absolute backup folder.' }
    if (-not $Confirmed) { throw "Repeat with -Yes to create an encrypted backup in $folder (online copy; the service keeps running)." }
    if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for this local operation.' }
    $created = (Invoke-AuthLensHost @('--backup-local', $folder, '--data-dir', $DataDirectory)).lines -join "`n" | ConvertFrom-Json
    $verified = (Invoke-AuthLensHost @('--backup-verify', $created.file, '--data-dir', $DataDirectory)).lines -join "`n" | ConvertFrom-Json
    Write-Host "Encrypted backup: $($created.file) ($($created.size) bytes, SHA-256 $($created.sha256)); verified: $(Get-AuthLensValue $verified 'verified')"
}

function Invoke-AuthLensDiagnostics {
    if (-not $installed) { throw 'No installed Server configuration was found; select -ConfigFile.' }
    $deploy = Get-AuthLensInstalledDeployTool $PSScriptRoot
    $status = Invoke-AuthLensDeployTool $deploy @('-Action', 'Status', '-ConfigFile', $installed.config_file)
    $acl = Invoke-AuthLensDeployTool $deploy @('-Action', 'AuditAcl', '-ConfigFile', $installed.config_file)
    $folder = Get-AuthLensLogFolder
    if (-not $folder) { throw 'The installation log folder is not writable from this session; run Service Manager as administrator.' }
    $file = Join-Path $folder ('diagnostics-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
    $report = [ordered]@{ created_utc = [DateTime]::UtcNow.ToString('o'); computer = $env:COMPUTERNAME; status = $status.result; acl_audit = $acl.result; latest_runs = @(Get-ChildItem -LiteralPath (Join-Path $installed.root 'deployment\runs') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 5 | ForEach-Object { $_.FullName }) }
    $stream = [IO.File]::Open($file, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [Text.Encoding]::UTF8.GetBytes(($report | ConvertTo-Json -Depth 8)); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    Write-Host "Diagnostic report (status and ACL audit; no keys, passwords or codes): $file"
    Write-Host "Deployment run logs: $(Join-Path $installed.root 'deployment\runs')"
}

# <Root>\logs\service-manager when it exists or can be created; $null otherwise (diagnostics are then shown on screen only).
function Get-AuthLensLogFolder {
    if (-not $installed) { return $null }
    $folder = Join-Path $installed.root 'logs\service-manager'
    try { $null = [IO.Directory]::CreateDirectory($folder); if (Test-AuthLensDirectoryWritable $folder) { return $folder } } catch { }
    $null
}

# Technical details of a refused or failed operation: action, error type and message only (never output of key or code actions).
function Write-AuthLensDiagnostic([string]$Operation, $ErrorRecord) {
    $folder = Get-AuthLensLogFolder
    if (-not $folder) { return $null }
    $file = Join-Path $folder ('service-manager-' + [DateTime]::UtcNow.ToString('yyyyMMdd') + '.log')
    $message = [regex]::Replace("$($ErrorRecord.Exception.Message)", '(?i)(password|token|secret|passphrase|code)\s*[:=]\s*\S+', '$1=[REDACTED]')
    try { [IO.File]::AppendAllText($file, ("{0} action={1} error={2} message={3}`r`n" -f [DateTime]::UtcNow.ToString('o'), $Operation, $ErrorRecord.Exception.GetType().FullName, $message)); $file } catch { $null }
}

function Get-AuthLensFriendlyError([string]$Message) {
    if ($Message -match 'Access to the path .* is denied|UnauthorizedAccess|access is denied') { return 'Access was denied. Run Service Manager as administrator, or choose a folder this session can write to.' }
    $Message -replace '^AuthLens refused the local operation: ', ''
}

# ---- interactive menu

function Read-AuthLensInput([string]$Prompt, [string]$Default = '') {
    $text = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $value = Read-Host "$text (B = back)"
    if ($value -ieq 'B') { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') }
    if (-not $value) { $Default } else { $value }
}

function Read-AuthLensConfirmation([string]$Summary) {
    Write-Host $Summary
    (Read-Host 'Type YES to continue (anything else cancels)') -ceq 'YES'
}

# Runs one menu action with recoverable error handling: the menu continues after a refusal, a failure or a cancellation.
function Invoke-AuthLensMenuAction([string]$Name, [scriptblock]$Body) {
    try { & $Body }
    catch [OperationCanceledException] { Write-Host $_.Exception.Message }
    catch {
        Write-Host ''
        Write-Host "Not completed: $(Get-AuthLensFriendlyError $_.Exception.Message)" -ForegroundColor Yellow
        $log = Write-AuthLensDiagnostic $Name $_
        if ($log) { Write-Host "Technical details: $log" }
    }
    Write-Host ''
}

function Show-AuthLensMenu([string]$Title, [object[]]$Items) {
    while ($true) {
        Write-Host ''
        Write-Host $Title
        foreach ($item in $Items) { Write-Host ("  {0}  {1}" -f $item[0], $item[1]) }
        Write-Host '  B  Back    Q  Exit'
        $choice = Read-Host 'Choose'
        if ($choice -ieq 'B') { return }
        if ($choice -ieq 'Q') { throw [Management.Automation.HaltCommandException]::new('exit') }
        $selected = @($Items | Where-Object { $_[0] -eq $choice })
        if (-not $selected.Count) { Write-Host 'Choose one of the listed options.'; continue }
        Invoke-AuthLensMenuAction $selected[0][1] $selected[0][2]
    }
}

function Start-AuthLensMenu {
    $keyMenu = @(
        @('1', 'Key status and fingerprint (read-only)', { Invoke-AuthLensLocalAdmin 'Status' '' '' $true }),
        @('2', 'Create the initial host key (new installation only)', {
            $script:Directory = Read-AuthLensInput 'Private key folder' (Join-Path $(if ($installed) { $installed.root } else { 'C:\ProgramData\AuthLens' }) 'keys\host')
            $script:FileName = Read-AuthLensInput 'Key file name' 'host.key'; $script:Path = ''
            $target = Resolve-AuthLensKeyTarget '' $Directory $FileName $DataDirectory
            if (Read-AuthLensConfirmation "Create the host backup key $($target.path)$(if (-not $target.directory_exists) { ' (the folder is created with a protected ACL)' })? Existing keys are never replaced.") { Invoke-AuthLensLocalAdmin 'CreateKey' '' '' $true } else { Write-Host 'Cancelled; nothing was changed.' } }),
        @('3', 'Export a recovery copy (verified automatically)', {
            $script:Directory = Read-AuthLensInput 'Destination folder (for example a removable drive; spaces are fine)'
            $script:FileName = Read-AuthLensInput 'File name' (Get-AuthLensDefaultKeyName); $script:Path = ''
            $target = Resolve-AuthLensKeyTarget '' $Directory $FileName $DataDirectory
            $script:CreateDirectory = $false
            if (-not $target.directory_exists) {
                if (-not (Read-AuthLensConfirmation "The folder $($target.directory) does not exist. Create it with a protected ACL (SYSTEM, Administrators, you)?")) { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') }
                $script:CreateDirectory = $true
            }
            if (Read-AuthLensConfirmation "Export the recovery copy to $($target.path)? It is verified right after export.") { Invoke-AuthLensLocalAdmin 'ExportKey' '' '' $true } else { Write-Host 'Cancelled; nothing was changed.' } }),
        @('4', 'Verify a recovery copy', {
            $file = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Recovery copy file')
            if ([IO.Directory]::Exists($file)) { throw "$file is a folder; select the recovery copy file." }
            Invoke-AuthLensLocalAdmin 'VerifyKey' $file '' $true }),
        @('5', 'Grant the service read access to the configured key', { if (Read-AuthLensConfirmation 'Add one explicit read rule for the service identity on the configured key file?') { $script:Path = ''; Invoke-AuthLensGrantKeyAccess $true } }),
        @('6', 'Create and verify an encrypted backup (service keeps running)', { $script:Path = Read-AuthLensInput 'Backup folder' $(if ($installed) { $installed.backup_root } else { '' }); Invoke-AuthLensBackup (Read-AuthLensConfirmation "Create an encrypted backup in $Path?") })
    )
    while ($true) {
        Write-AuthLensOverview
        Write-Host ''
        Write-Host '1  Service status and management'
        Write-Host '2  Network configuration'
        Write-Host '3  TLS certificates'
        Write-Host '4  Backup and recovery keys'
        Write-Host '5  Administrator accounts'
        Write-Host '6  Deployment and recovery'
        Write-Host '7  Diagnostics and logs'
        Write-Host 'Q  Exit'
        $choice = Read-Host 'Choose'
        try {
            switch ($choice) {
                '1' { Show-AuthLensMenu 'Service status and management (this tool never stops or starts the service outside the actions labelled restart or downtime)' @(
                        @('1', 'Detailed status', { $s = Get-AuthLensStatus; $s | Select-Object service_name, service_model, binary_path_matches, current_release, current_version, current_commit, ready, journal_phase, recovery_needed, execution_context | Format-List | Out-String | Write-Host }),
                        @('2', 'Health check (readiness and running identity)', { $h = Invoke-AuthLensDeployTool (Get-AuthLensInstalledDeployTool $PSScriptRoot) @('-Action', 'Health', '-ConfigFile', $installed.config_file); Write-Host "Ready: $(Get-AuthLensValue $h.result 'ready') (HTTP $(Get-AuthLensValue $h.result 'ready_status')); identity $((Get-AuthLensValue $h.result 'identity') | ConvertTo-Json -Compress)" }),
                        @('3', 'Restart the AuthLens service [downtime]', {
                            try { Invoke-AuthLensRestartWorkflow $false } catch { if ($_.Exception.Message -notlike 'Checked only*') { throw } }
                            if (Read-AuthLensConfirmation 'Restart the AuthLens service now? Clients are disconnected until it is ready again.') { Invoke-AuthLensRestartWorkflow $true } else { Write-Host 'Cancelled; nothing was changed.' } })) }
                '2' { Show-AuthLensMenu 'Network configuration' @(
                        @('1', 'Network status (read-only)', { Invoke-AuthLensNetworkWorkflow 'NetworkStatus' @{} $false }),
                        @('2', 'Change network configuration [restarts the service]', { Invoke-AuthLensNetworkMenu })) }
                '3' { Show-AuthLensMenu 'TLS certificates' @(
                        @('1', 'Certificate status and required identities (read-only)', { Invoke-AuthLensCertificateWorkflow 'CertificateStatus' $false }),
                        @('2', 'Export the public certificate (.cer, no private key)', {
                            $script:Directory = Read-AuthLensInput 'Destination folder'; $script:FileName = Read-AuthLensInput 'File name' "AuthLens-$($env:COMPUTERNAME)"; $script:Path = ''
                            $target = Resolve-AuthLensCertificateTarget '' $Directory $FileName $DataDirectory
                            $script:CreateDirectory = $false
                            if (-not $target.directory_exists) { if (-not (Read-AuthLensConfirmation "Create the folder $($target.directory)?")) { throw [OperationCanceledException]::new('Cancelled; nothing was changed.') }; $script:CreateDirectory = $true }
                            Invoke-AuthLensCertificateWorkflow 'ExportCertificate' $true }),
                        @('3', 'Replace the certificate [restarts the service]', {
                            $script:CertificateFile = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Replacement PFX file'); $script:CertificatePasswordFile = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Protected password file')
                            try { Invoke-AuthLensCertificateWorkflow 'ReplaceCertificate' $false } catch { if ($_.Exception.Message -notlike 'Validated only*') { throw } }
                            if (Read-AuthLensConfirmation 'Replace the certificate and restart the service?') { Invoke-AuthLensCertificateWorkflow 'ReplaceCertificate' $true } else { Write-Host 'Cancelled; nothing was changed.' } })) }
                '4' { Show-AuthLensMenu 'Backup and recovery keys (no service restart)' $keyMenu }
                '5' { Show-AuthLensMenu 'Administrator accounts (one-use codes are shown here once; do not record this session)' @(
                        @('1', 'Initial administrator activation code', { if (Read-AuthLensConfirmation 'Issue a one-use activation code for the first administrator?') { Invoke-AuthLensLocalAdmin 'ActivationCode' '' '' $true } }),
                        @('2', 'Recovery code for an existing administrator (ends their sessions)', { $user = Read-AuthLensInput 'Existing administrator username'; if (Read-AuthLensConfirmation "Issue a recovery code for $user and end all of their sessions?") { Invoke-AuthLensLocalAdmin 'RecoveryCode' '' $user $true } })) }
                '6' { Show-AuthLensMenu 'Deployment and recovery' @(
                        @('1', 'Deployment status and recovery options (read-only preview)', { Invoke-AuthLensRecoveryWorkflow 'DeploymentStatus' 'Auto' $false }),
                        @('2', 'Guided recovery of an interrupted deployment', { Invoke-AuthLensRecoveryMenu })) }
                '7' { Show-AuthLensMenu 'Diagnostics and logs' @(
                        @('1', 'Write a diagnostic report (status and ACL audit, no secrets)', { Invoke-AuthLensDiagnostics }),
                        @('2', 'Show log locations', { Write-Host "Service Manager: $(Get-AuthLensLogFolder)"; if ($installed) { Write-Host "Deployment runs: $(Join-Path $installed.root 'deployment\runs')"; Write-Host "Server logs: $(Join-Path $installed.root 'logs')" } })) }
                { $_ -ieq 'Q' } { return }
                default { Write-Host 'Choose one of the listed options.' }
            }
        } catch [Management.Automation.HaltCommandException] { return }
    }
}

function Invoke-AuthLensNetworkMenu {
    Write-Host 'Leave a value empty to keep it. Lists are comma-separated; type - to clear a list.'
    $values = @{ AccessMode = (Read-AuthLensInput 'Access mode (Local, Corporate, ReverseProxy)'); ListenAddress = (Read-AuthLensInput 'Listening IP address'); Port = 0
        AllowedHosts = (Read-AuthLensInput 'Allowed hosts'); ProxyHosts = (Read-AuthLensInput 'Public reverse-proxy hosts'); TrustedProxies = (Read-AuthLensInput 'Trusted proxy addresses or subnets')
        ApproveFirewall = $false; RemoveFirewall = $false; FirewallSources = ''; FirewallProfiles = $FirewallProfiles; CertificateFile = ''; CertificatePasswordFile = '' }
    $portText = Read-AuthLensInput 'HTTPS port'; if ($portText) { $values.Port = [int]$portText }
    $firewallChoice = Read-AuthLensInput 'Installer-owned firewall rule: K keep, U update to the new listener, R remove' 'K'
    if ($firewallChoice -ieq 'U') { $values.ApproveFirewall = $true; $values.FirewallSources = Read-AuthLensInput 'Allowed source addresses or subnets'; $values.FirewallProfiles = Read-AuthLensInput 'Profiles (Domain, Private)' $FirewallProfiles }
    if ($firewallChoice -ieq 'R') { $values.RemoveFirewall = $true }
    $certificate = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Replacement PFX for the same change (empty keeps the current certificate)')
    if ($certificate) { $values.CertificateFile = $certificate; $values.CertificatePasswordFile = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Protected password file') }
    # Validation and the change summary first; nothing is applied without the confirmation below.
    try { Invoke-AuthLensNetworkWorkflow 'ChangeNetwork' $values $false } catch { if ($_.Exception.Message -notlike 'Validated only*') { throw } }
    if (Read-AuthLensConfirmation 'Apply this change and restart the service?') { Invoke-AuthLensNetworkWorkflow 'ChangeNetwork' $values $true } else { Write-Host 'Cancelled; nothing was changed.' }
}

function Invoke-AuthLensRecoveryMenu {
    $script:CertificateFile = ''; $script:CertificatePasswordFile = ''
    Invoke-AuthLensRecoveryWorkflow 'DeploymentStatus' 'Auto' $false
    $requested = Read-AuthLensInput 'Recovery action to preview (VerifyCandidate, Resume, Rollback, Cancel)'
    if ($requested -notin @('VerifyCandidate', 'Resume', 'Rollback', 'Cancel')) { throw 'Choose VerifyCandidate, Resume, Rollback or Cancel.' }
    if ($requested -in @('VerifyCandidate', 'Resume')) {
        $certificate = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Replacement PFX if the configured certificate blocks recovery (empty: keep it)')
        if ($certificate) { $script:CertificateFile = $certificate; $script:CertificatePasswordFile = ConvertFrom-AuthLensPathInput (Read-AuthLensInput 'Protected password file') }
    }
    try { Invoke-AuthLensRecoveryWorkflow 'Recover' $requested $false } catch { if ($_.Exception.Message -notlike 'Previewed only*') { throw } }
    if (Read-AuthLensConfirmation "Run $requested now?") { Invoke-AuthLensRecoveryWorkflow 'Recover' $requested $true } else { Write-Host 'Cancelled; nothing was changed.' }
}

# ---- dispatch

if ($Action -eq 'Menu') { Start-AuthLensMenu; return }
switch ($Action) {
    { $_ -in @('NetworkStatus', 'ChangeNetwork') } {
        $values = @{ AccessMode = $AccessMode; ListenAddress = $ListenAddress; Port = $Port; AllowedHosts = $AllowedHosts; ProxyHosts = $ProxyHosts; TrustedProxies = $TrustedProxies
            ApproveFirewall = [bool]$ApproveFirewall; RemoveFirewall = [bool]$RemoveFirewall; FirewallSources = $FirewallSources; FirewallProfiles = $FirewallProfiles
            CertificateFile = $CertificateFile; CertificatePasswordFile = $CertificatePasswordFile }
        Invoke-AuthLensNetworkWorkflow $Action $values ([bool]$Yes)
    }
    { $_ -in @('CertificateStatus', 'ExportCertificate', 'ReplaceCertificate') } {
        if ($Interactive) { Invoke-AuthLensMenuAction $Action { Invoke-AuthLensCertificateWorkflow $Action $true } } else { Invoke-AuthLensCertificateWorkflow $Action ([bool]$Yes) }
    }
    'ServiceStatus' { Write-AuthLensOverview }
    'DeploymentStatus' { Invoke-AuthLensRecoveryWorkflow 'DeploymentStatus' $RecoveryAction $false }
    'Recover' { Invoke-AuthLensRecoveryWorkflow 'Recover' $RecoveryAction ([bool]$Yes) }
    'CreateBackup' { Invoke-AuthLensBackup ([bool]$Yes) }
    'Diagnostics' { Invoke-AuthLensDiagnostics }
    'RestartService' { Invoke-AuthLensRestartWorkflow ([bool]$Yes) }
    'GrantKeyAccess' { Invoke-AuthLensGrantKeyAccess ([bool]$Yes) }
    default { Invoke-AuthLensLocalAdmin $Action $Path $Username ([bool]$Yes) }
}
