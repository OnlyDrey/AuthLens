<#
.SYNOPSIS
  AuthLens local administration. Uses the packaged server executable; no SDK, listener or service restart.
.DESCRIPTION
  Key values never appear in output or process arguments. Export writes a new private file only.
  Administrator codes are shown locally once: do not run code actions under a transcript or redirect them to logs.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'CreateKey', 'ExportKey', 'VerifyKey', 'GrantKeyAccess', 'ActivationCode', 'RecoveryCode', 'NetworkStatus', 'ChangeNetwork')]
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
    [string]$Path = '',
    [string]$Username = '',
    [string]$ServiceName = 'AuthLens',
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
    [pscustomobject]@{ config_file = $file; root = $root; data_directory = $data; service_name = $service }
}

$installed = $null
if (-not $DataDirectory -or $Action -in @('NetworkStatus', 'ChangeNetwork')) { $installed = Get-AuthLensInstalledConfiguration $ConfigFile }
if (-not $DataDirectory) {
    if ($installed) { $DataDirectory = $installed.data_directory } else { $DataDirectory = 'C:\ProgramData\AuthLens\data' }
}
if ($installed -and -not $PSBoundParameters.ContainsKey('ServiceName')) { $ServiceName = $installed.service_name }
if (-not $Executable) {
    $Executable = Join-Path $PSScriptRoot 'server\AuthLens.Api.exe'
    if (-not (Test-Path -LiteralPath $Executable)) { $Executable = 'C:\ProgramData\AuthLens\releases\current\server\AuthLens.Api.exe' }
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
    Write-Host "  certificate      $($Summary.certificate) (unchanged; it must cover the new hosts)"
    Write-Host "  firewall         $($Summary.firewall)"
    Write-Host '  The service restarts; readiness and the release identity are verified on the new listener, and a failure restores the previous configuration.'
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
        return
    }
    $plan = Invoke-AuthLensDeployTool $deploy (Get-AuthLensNetworkArguments $installed.config_file $Values $true)
    if ($plan.exit -ne 0) { throw "The proposed network configuration was refused: $($plan.result.error)" }
    if (-not $plan.result.dry_run) { Write-Host 'An interrupted configuration change was restored first; review the result and repeat.'; $plan.result | ConvertTo-Json -Depth 6 | Write-Host; return }
    Write-AuthLensNetworkSummary $plan.result.summary
    if (-not $Confirmed) { throw 'Validated only. Repeat with -Yes (or type YES in the menu) to apply this change.' }
    $applied = Invoke-AuthLensDeployTool $deploy (Get-AuthLensNetworkArguments $installed.config_file $Values $false)
    $applied.result | ConvertTo-Json -Depth 6 | Write-Host
    if ($applied.exit -ne 0) { throw "The network change did not complete: $($applied.result.error)" }
    if ($applied.result.firewall_recovery_required) { Write-Warning 'The service is ready on the new configuration, but the firewall transition needs recovery (Install-AuthLens.ps1 -Mode Server -Operation Firewall ...).' }
}

function Test-AuthLensAdminElevation {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-AuthLensLocalAdmin([string]$Operation, [string]$File, [string]$User, [bool]$Confirmed) {
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Packaged AuthLens.Api.exe was not found. Specify -Executable from a verified release.' }
    if ($Operation -ne 'Status') {
        if (-not $Confirmed) { throw 'Repeat with -Yes after reviewing the data directory and operation. Key and code actions are never automatic.' }
        if (-not (Test-AuthLensAdminElevation)) { throw 'Open PowerShell as administrator for this local operation.' }
    }
    $arguments = @(Get-AuthLensAdminArguments $Operation $DataDirectory $File $User)
    if ($Operation -eq 'CreateKey') {
        $directory = Split-Path $File
        $ancestor = [IO.Path]::GetFullPath($directory)
        while ($ancestor) {
            if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Recovery-key directories must not traverse reparse points.' }
            $ancestor = [IO.Path]::GetDirectoryName($ancestor)
        }
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $acl = [Security.AccessControl.DirectorySecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($sid in 'S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
                $identity = [Security.Principal.SecurityIdentifier]::new($sid)
                $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            }
            Set-Acl -LiteralPath $directory -AclObject $acl
        }
    }
    # The process receives file paths only; it reads key files itself. Never read or echo the key here.
    $ErrorActionPreference = 'Continue'
    $result = & $Executable @arguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw ('AuthLens refused the local operation: ' + (($result | ForEach-Object { "$_" }) -join ' ')) }
    $result | ForEach-Object { Write-Host "$_" }
    if ($Operation -in @('CreateKey', 'Status')) { Write-AuthLensKeyAccess $Operation }
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

if ($Action -eq 'Menu') {
    Write-Host "AuthLens Service Manager`nData: $DataDirectory`nExecutable: $Executable"
    Write-Host 'This tool never stops, starts or migrates services. Key export is local-only.'
    Write-Host "1  Key status and fingerprint`n2  Create initial host key`n3  Export recovery copy`n4  Verify recovery copy`n7  Grant the service read access to the configured key`n5  Initial administrator activation code`n6  Existing administrator recovery code`n8  Network configuration status`n9  Change network configuration`n0  Exit"
    $choice = Read-Host 'Choose action'
    $actions = @{ '1' = 'Status'; '2' = 'CreateKey'; '3' = 'ExportKey'; '4' = 'VerifyKey'; '5' = 'ActivationCode'; '6' = 'RecoveryCode'; '7' = 'GrantKeyAccess'; '8' = 'NetworkStatus'; '9' = 'ChangeNetwork' }
    if (-not $actions.ContainsKey($choice)) { return }
    $Action = $actions[$choice]
    if ($Action -in @('CreateKey', 'ExportKey', 'VerifyKey')) { $Path = Read-Host 'Absolute key file path (create/export never overwrites)' }
    if ($Action -eq 'RecoveryCode') { $Username = Read-Host 'Existing administrator username (all their sessions will end)' }
    if ($Action -eq 'ChangeNetwork') {
        Write-Host 'Leave a value empty to keep it. Lists are comma-separated; type - to clear a list.'
        $AccessMode = Read-Host 'Access mode (Local, Corporate, ReverseProxy)'
        $ListenAddress = Read-Host 'Listening IP address'
        $portText = Read-Host 'HTTPS port'; if ($portText) { $Port = [int]$portText }
        $AllowedHosts = Read-Host 'Allowed hosts'
        $ProxyHosts = Read-Host 'Public reverse-proxy hosts'
        $TrustedProxies = Read-Host 'Trusted proxy addresses or subnets'
        $firewallChoice = Read-Host 'Installer-owned firewall rule: K keep, U update to the new listener, R remove'
        if ($firewallChoice -ieq 'U') { $ApproveFirewall = $true; $FirewallSources = Read-Host 'Allowed source addresses or subnets'; $profilesText = Read-Host 'Profiles (Domain, Private)'; if ($profilesText) { $FirewallProfiles = $profilesText } }
        if ($firewallChoice -ieq 'R') { $RemoveFirewall = $true }
        $values = @{ AccessMode = $AccessMode; ListenAddress = $ListenAddress; Port = $Port; AllowedHosts = $AllowedHosts; ProxyHosts = $ProxyHosts; TrustedProxies = $TrustedProxies
            ApproveFirewall = [bool]$ApproveFirewall; RemoveFirewall = [bool]$RemoveFirewall; FirewallSources = $FirewallSources; FirewallProfiles = $FirewallProfiles }
        # Validation and the change summary first; nothing is applied without the confirmation below.
        try { Invoke-AuthLensNetworkWorkflow 'ChangeNetwork' $values $false } catch { if ($_.Exception.Message -notlike 'Validated only*') { throw } }
        $Yes = (Read-Host 'Apply this network change and restart the service? Type YES') -ceq 'YES'
        Invoke-AuthLensNetworkWorkflow 'ChangeNetwork' $values ([bool]$Yes)
        return
    }
    if ($Action -notin @('Status', 'NetworkStatus')) {
        if ($Action -in @('ActivationCode', 'RecoveryCode')) { Write-Host 'The one-use code will be displayed locally. Do not record this session or save its output.' }
        $Yes = (Read-Host "Confirm $Action for $DataDirectory by typing YES") -ceq 'YES'
    }
}
if ($Action -in @('NetworkStatus', 'ChangeNetwork')) {
    $values = @{ AccessMode = $AccessMode; ListenAddress = $ListenAddress; Port = $Port; AllowedHosts = $AllowedHosts; ProxyHosts = $ProxyHosts; TrustedProxies = $TrustedProxies
        ApproveFirewall = [bool]$ApproveFirewall; RemoveFirewall = [bool]$RemoveFirewall; FirewallSources = $FirewallSources; FirewallProfiles = $FirewallProfiles }
    Invoke-AuthLensNetworkWorkflow $Action $values ([bool]$Yes)
} elseif ($Action -eq 'GrantKeyAccess') { Invoke-AuthLensGrantKeyAccess ([bool]$Yes) } else { Invoke-AuthLensLocalAdmin $Action $Path $Username ([bool]$Yes) }
