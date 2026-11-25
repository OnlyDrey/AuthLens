# AuthLens controlled deployment to a Windows host (build, validate, install service, deploy, verify, roll back, recover).
# Windows PowerShell 5.1 and PowerShell 7. Entry point: Deploy-AuthLens.ps1. Operator guide: docs/deployment/WINDOWS_DEPLOYMENT.md.
#
# Every operating-system action goes through a small function below (git, service control, the release link, HTTP, the server's own maintenance
# commands), so the deployment state machine is tested with mocks (scripts/tests/AuthLens.Deploy.Tests.ps1). Nothing here reads, prints or passes a
# secret: the certificate password stays in its file, which only the service reads.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:Exe = 'AuthLens.Api.exe'
$script:Lock = $null; $script:RunFolder = $null; $script:RunLog = $null; $script:RunId = ''
$script:HostLock = $null
# One service and one installation root. Services of earlier products (SAP Lens: sap-lens, SapLens, SapLens2) are never detected, adopted or
# changed: AuthLens is installed fresh beside them and receives their data by restoring a backup (docs/deployment/WINDOWS_DEPLOYMENT.md).
$script:ServiceName = 'AuthLens'
$script:DefaultRoot = 'C:\ProgramData\AuthLens'
# Configuration lookup when -ConfigFile is not given: $env:AUTHLENS_DEPLOY_CONFIG, then <root>\config\deploy.json. No other location is searched.
$script:ConfigVariables = @('AUTHLENS_DEPLOY_CONFIG')
$script:ConfigDefaults = @('C:\ProgramData\AuthLens\config\deploy.json')
$script:FocusedTests = @('StartupTests', 'ApiTests', 'NetworkTests', 'ReverseProxyTests', 'SessionTests', 'AccountsTests', 'AccountCompatibilityTests',
    'PersistenceTests', 'ApplicationBackupTests', 'LegacyRestoreTests', 'MaintenanceCommandsTests', 'V1CompatibilityTests', 'VersioningTests', 'V1DataMigrationTests')
# Phases after which the running service may already be stopped or switched; an interrupted run in one of them needs recovery.
$script:CriticalPhases = @('stopping', 'switched', 'starting', 'verifying', 'manual_recovery_required')
$script:FinalPhases = @('complete', 'rolled_back', 'aborted')

class DeployException : System.Exception {
    [int]$ExitCode
    DeployException([string]$message, [int]$code) : base($message) { $this.ExitCode = $code }
}

# Path joining without drive resolution (Join-Path needs the drive to exist), identical on Windows.
function Join-AL([string]$Path, [string]$Child) { [System.IO.Path]::Combine($Path, $Child) }

function Stop-AL([string]$Message, [int]$Code = 2) { throw [DeployException]::new($Message, $Code) }

function Assert-ALNoPendingRepair($Config) {
    if(Test-Path -LiteralPath (Join-AL $Config.WorkRoot 'uninstall-pending.json')){Stop-AL 'A pending uninstall requires explicit recovery; application data and evidence remain preserved.' 4}
    if(Test-Path -LiteralPath (Join-AL $Config.WorkRoot 'repair-pending.json')){Stop-AL 'A pending offline repair requires explicit recovery review; its marker and journal were preserved.' 4}
    if(Test-Path -LiteralPath (Join-AL $Config.WorkRoot 'firewall-pending.json')){Stop-AL 'A pending firewall transition requires explicit recovery; its journal was preserved.' 4}
}

function Write-ALLog([string]$Message) {
    $line = '{0:yyyy-MM-ddTHH:mm:ssZ} {1}' -f [DateTime]::UtcNow, $Message
    Write-Host $line
    if ($script:RunLog -and (Test-Path -LiteralPath (Split-Path $script:RunLog))) { Add-Content -LiteralPath $script:RunLog -Value $line -Encoding UTF8 }
}

# ---- configuration

function Find-ALConfigFile {
    foreach ($name in $script:ConfigVariables) { $value = [Environment]::GetEnvironmentVariable($name); if ($value) { return $value } }
    foreach ($file in $script:ConfigDefaults) { if (Test-Path -LiteralPath $file) { return $file } }
    $script:ConfigDefaults[0]
}

# The installation layout under one root (Root setting, default C:\ProgramData\AuthLens). Every path can be set explicitly instead.
function Get-ALInstallLayout([string]$Root) {
    [pscustomobject]@{
        Root = $Root; ReleasesRoot = (Join-AL $Root 'releases'); DataDirectory = (Join-AL $Root 'data'); ConfigRoot = (Join-AL $Root 'config')
        TlsRoot = (Join-AL $Root 'tls'); KeyRoot = (Join-AL $Root 'keys'); BackupRoot = (Join-AL (Join-AL $Root 'backups') 'predeploy'); WorkRoot = (Join-AL $Root 'deployment')
    }
}

function Read-AuthLensSettings([string]$Path, [switch]$Packaged) {
    if (-not $Path) { $Path = Find-ALConfigFile }
    if (-not (Test-Path -LiteralPath $Path)) { Stop-AL "Deployment configuration not found: $Path (copy scripts\deploy\deploy.example.json; looked for `$env:$($script:ConfigVariables -join ', `$env:') and $($script:ConfigDefaults -join ', '))." }
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    # Every application-managed path defaults to the installation layout under Root; an explicit setting replaces exactly that path.
    $root = if ($raw.PSObject.Properties['Root'] -and $raw.Root) { [string]$raw.Root } else { $script:DefaultRoot }
    $layout = Get-ALInstallLayout $root
    $config = [ordered]@{
        Root = $root; RepositoryPath = ''; Remote = 'origin'; Branch = 'experiment/dotnet-backend'; WorkRoot = $layout.WorkRoot; ReleasesRoot = $layout.ReleasesRoot
        BackupRoot = $layout.BackupRoot; ServiceName = $script:ServiceName; ServiceAccount = ''; ListenAddress = ''; Port = 0
        AccessMode = 'Auto'; AllowedHosts = @(); ProxyHosts = @(); TrustedProxies = @(); SourceDirectory = ''; DataDirectory = $layout.DataDirectory; CertificatePath = (Join-AL $layout.TlsRoot 'server.pfx')
        CertificatePasswordFile = (Join-AL $layout.TlsRoot 'cert-password'); ReadyTimeoutSeconds = 120; StopTimeoutSeconds = 90
    }
    foreach ($p in $raw.PSObject.Properties) {
        if (-not $config.Contains($p.Name)) { Stop-AL "Unknown deployment setting '$($p.Name)' in $Path." }
        $config[$p.Name] = $p.Value
    }
    # Execution context. A configuration with RepositoryPath is a repository (source checkout) deployment that may build from Git. Without it,
    # as Server Setup publishes it, the configuration belongs to an installed (packaged) Server: every installed action works, and only actions that
    # build from source refuse (Assert-ALRepositoryContext). No repository path is invented. -Packaged is kept for callers that require that context.
    $config['ExecutionContext'] = if ($config.RepositoryPath) { 'repository' } else { 'packaged' }
    if ($Packaged -and $config.RepositoryPath) { $config['ExecutionContext'] = 'repository' }
    foreach ($required in 'ListenAddress', 'DataDirectory', 'CertificatePath', 'CertificatePasswordFile') {
        if (-not $config[$required]) { Stop-AL "Deployment setting '$required' is required ($Path)." }
    }
    if ([int]$config.Port -lt 1 -or [int]$config.Port -gt 65535) { Stop-AL "Deployment setting 'Port' must be 1..65535." }
    foreach ($pathSetting in 'Root', 'RepositoryPath', 'WorkRoot', 'ReleasesRoot', 'BackupRoot', 'DataDirectory', 'CertificatePath', 'CertificatePasswordFile') {
        if ($pathSetting -eq 'RepositoryPath' -and -not $config[$pathSetting]) { continue }
        if ([string]$config[$pathSetting] -notmatch '^([A-Za-z]:[\\/]|\\\\|/)') { Stop-AL "Deployment setting '$pathSetting' must be an absolute path." }
    }
    $config.AllowedHosts = @($config.AllowedHosts); $config.ProxyHosts = @($config.ProxyHosts); $config.TrustedProxies = @($config.TrustedProxies)
    $config['ConfigFile'] = $Path
    $config['ServiceNameConfigured'] = [bool]($raw.PSObject.Properties['ServiceName'] -and $raw.ServiceName)
    if ($config.ServiceName -notmatch '^[A-Za-z0-9_.-]{1,80}$') { Stop-AL "Deployment setting 'ServiceName' may contain letters, digits, '.', '_' and '-' only." }
    if (-not $config.ServiceAccount) { $config.ServiceAccount = "NT SERVICE\$($config.ServiceName)" }      # the service's own virtual account
    [pscustomobject]$config
}

# The service command line, rebuilt from the configuration. No secret is on it: the server reads the password file itself.
function Get-ALServiceArguments($Config) {
    $access=Get-ALServerAccessPlan $Config
    $arguments = @('--data-dir', $Config.DataDirectory)
    $address=$null
    if(-not [Net.IPAddress]::TryParse($Config.ListenAddress,[ref]$address)){Stop-AL 'ListenAddress must be an explicit IP address.'}
    if($access.network_access){$arguments+='--network'}
    $arguments+=@('--listen', $Config.ListenAddress, '--port', [string]$Config.Port)
    $hosts=($Config.AllowedHosts -join ',').Trim()
    if($hosts){$arguments+=@('--allowed-hosts',$hosts)}
    $arguments+=@('--cert', $Config.CertificatePath, '--cert-password-file', $Config.CertificatePasswordFile)
    if (@($Config.TrustedProxies).Count -gt 0) { $arguments += @('--trusted-proxies', ($Config.TrustedProxies -join ',')) }
    if ($Config.PSObject.Properties['ProxyHosts'] -and @($Config.ProxyHosts).Count -gt 0) { $arguments += @('--proxy-hosts', ($Config.ProxyHosts -join ',')) }
    if ($Config.PSObject.Properties['SourceDirectory'] -and $Config.SourceDirectory) { $arguments += @('--source-dir', [string]$Config.SourceDirectory) }
    $arguments
}

function Test-ALPrivateAddress([Net.IPAddress]$Address) {
    if($Address.IsIPv4MappedToIPv6){$Address=$Address.MapToIPv4()}
    $b=$Address.GetAddressBytes()
    if($b.Length -eq 4){return ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 169 -and $b[1] -eq 254))}
    (($b[0] -band 254) -eq 252 -or $Address.IsIPv6LinkLocal)
}

function Get-ALServerAccessPlan($Config) {
    $mode=if($Config.PSObject.Properties['AccessMode']){[string]$Config.AccessMode}else{'Auto'}
    if($mode -cnotin @('Auto','Local','Corporate','ReverseProxy')){Stop-AL 'AccessMode must be Auto, Local, Corporate or ReverseProxy.'}
    $address=$null
    if(-not [Net.IPAddress]::TryParse($Config.ListenAddress,[ref]$address)){Stop-AL 'ListenAddress must be an explicit IP address.'}
    if($address.Equals([Net.IPAddress]::Any) -or $address.Equals([Net.IPAddress]::IPv6Any)){Stop-AL 'Wildcard binding is not supported by the current runtime; choose one private interface.'}
    $network=-not [Net.IPAddress]::IsLoopback($address)
    $hosts=@();$proxyHosts=@();$proxies=@()
    if($Config.PSObject.Properties['AllowedHosts']){$hosts=@($Config.AllowedHosts)}
    if($Config.PSObject.Properties['ProxyHosts']){$proxyHosts=@($Config.ProxyHosts)}
    if($Config.PSObject.Properties['TrustedProxies']){$proxies=@($Config.TrustedProxies)}
    if($mode -ne 'Auto' -and $network -and -not(Test-ALPrivateAddress $address)){Stop-AL 'Network access requires a specific private LAN address.'}
    if($mode -eq 'Local' -and ($network -or $proxies.Count -or $proxyHosts.Count -or @($hosts|Where-Object{$_ -notin @('localhost','127.0.0.1','::1','[::1]')}).Count)){Stop-AL 'Local access requires loopback binding and loopback hosts without proxy trust.'}
    # D-003: the runtime accepts only loopback names on a loopback listener, so other allowed hosts can never be reached and the readiness probe
    # could not address them. Refused in every mode, including configurations without AccessMode (Auto).
    $unreachable=@($hosts|Where-Object{$_ -and $_ -notin @('localhost','127.0.0.1','::1','[::1]')})
    if(-not $network -and $unreachable.Count){Stop-AL ("A loopback listener accepts loopback host names only; allowed hosts {0} cannot reach it. Listen on a private interface (Corporate access) or remove them." -f ($unreachable -join ', '))}
    if($mode -eq 'Corporate' -and (-not $network -or -not $hosts.Count -or $proxies.Count -or $proxyHosts.Count)){Stop-AL 'Corporate access requires a private interface and explicit allowed hosts without proxy trust.'}
    if($mode -eq 'ReverseProxy' -and (-not $network -or -not $hosts.Count -or -not $proxies.Count -or -not $proxyHosts.Count)){Stop-AL 'Reverse proxy access requires a private backend interface, backend hosts, public proxy hosts and explicit trusted peers.'}
    [pscustomobject]@{access_mode=$mode;network_access=$network;listen_address=$Config.ListenAddress;allowed_hosts=$hosts;wildcard_supported=$false;probe_authority=$(if($network){$hosts|Select-Object -First 1}else{$Config.ListenAddress})}
}

function Get-ALServerNetworkSuggestions {
    $properties=[Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $names=@($properties.HostName)
    if($properties.DomainName){$names+=($properties.HostName+'.'+$properties.DomainName)}
    $addresses=@(@(foreach($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()){
        if($adapter.OperationalStatus -ne 'Up' -or $adapter.NetworkInterfaceType -eq 'Loopback'){continue}
        foreach($entry in $adapter.GetIPProperties().UnicastAddresses){if(Test-ALPrivateAddress $entry.Address){$entry.Address.ToString()}}
    })|Sort-Object -Unique)
    $preferred=@($addresses|Where-Object{$_ -notlike '*:*' -and $_ -notlike '169.254.*'})|Select-Object -First 1
    if(-not $preferred){$preferred=$addresses|Select-Object -First 1}
    [pscustomobject]@{operation='network suggestions';listen_address=[string]$preferred;allowed_hosts=@($names|Where-Object{$_}|Select-Object -Unique);interfaces=$addresses;access_mode='Corporate';wildcard_supported=$false;read_only=$true}
}

# The executable and the arguments of a service command line ("C:\path\AuthLens.Api.exe" --a b "--c" "d e"), quotes removed.
function Split-ALCommandLine([string]$CommandLine) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($CommandLine, '"([^"]*)"|(\S+)')) { $tokens.Add($(if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value })) }
    $tokens.ToArray()          # a plain sequence: callers wrap it in @(...) before indexing (one token would otherwise arrive as a string)
}

# The server options a managed service command line may carry (AuthLens.Api ServerConfiguration): value options and the one flag. Names are
# case-sensitive, as the server parses them.
$script:ServiceValueOptions = @('--data-dir', '--listen', '--port', '--allowed-hosts', '--proxy-hosts', '--trusted-proxies', '--cert', '--cert-password-file')
$script:ServiceFlagOptions = @('--network')

# Parses service arguments (without the executable) into option -> value ('' for the flag). Throws on an unknown option, a stray value, a value
# option without its value, or an option given twice (the server would silently take the last one, so a repeat is a conflict, not a duplicate).
function ConvertTo-ALArgumentMap([string[]]$Arguments) {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $name = $Arguments[$i]
        if ($map.ContainsKey($name)) { throw "option $name is given more than once" }
        if ($script:ServiceFlagOptions -ccontains $name) { $map[$name] = ''; continue }
        if ($script:ServiceValueOptions -cnotcontains $name) { throw "unsupported argument '$name'" }
        if ($i + 1 -ge $Arguments.Count -or $Arguments[$i + 1].StartsWith('--', [StringComparison]::Ordinal)) { throw "option $name has no value" }
        $i++
        $map[$name] = $Arguments[$i]
    }
    $map
}

# A comma-separated list as the server reads it (entries trimmed, empty ones dropped), sorted and de-duplicated for an order-independent comparison.
function Get-ALListSet([string]$Value, [switch]$Address) {
    $items = foreach ($entry in $Value.Split(',')) {
        $item = $entry.Trim()
        if (-not $item) { continue }
        $parsed = $null
        if ($Address -and [System.Net.IPAddress]::TryParse($item, [ref]$parsed)) { $parsed.ToString() } else { $item.ToLowerInvariant() }
    }
    @($items | Sort-Object -Unique)
}

# Semantic comparison of an existing service's arguments with the configured ones. Returns the differences (nothing when equivalent). Order of the
# options and of the entries in --allowed-hosts/--trusted-proxies does not matter; every security-sensitive value must be present and equal:
# paths compare case-insensitively (Windows file system), the listen and proxy addresses as IP addresses, the port as a number, host names
# case-insensitively (DNS). Nothing is ignored: a missing, extra, repeated or unknown option is a difference.
function Compare-ALServiceArguments([string[]]$Existing, [string[]]$Wanted) {
    $differences = New-Object System.Collections.Generic.List[string]
    try { $have = ConvertTo-ALArgumentMap $Existing } catch { return "service: $($_.Exception.Message)" }
    try { $want = ConvertTo-ALArgumentMap $Wanted } catch { return "configuration: $($_.Exception.Message)" }
    foreach ($name in $script:ServiceFlagOptions + $script:ServiceValueOptions) {
        $inHave = $have.ContainsKey($name); $inWant = $want.ContainsKey($name)
        if (-not $inHave -and -not $inWant) { continue }
        if (-not $inHave) { $differences.Add("$name is missing on the service"); continue }
        if (-not $inWant) { $differences.Add("$name is on the service but not in the configuration"); continue }
        $a = $have[$name]; $b = $want[$name]
        $equal = switch ($name) {
            '--network' { $true }
            '--port' { ($a -match '^\d{1,5}$') -and ($b -match '^\d{1,5}$') -and ([int]$a -eq [int]$b) }
            '--listen' {
                $x = $null; $y = $null
                [System.Net.IPAddress]::TryParse($a, [ref]$x) -and [System.Net.IPAddress]::TryParse($b, [ref]$y) -and $x.Equals($y)
            }
            '--allowed-hosts' { ((Get-ALListSet $a) -join ',') -ceq ((Get-ALListSet $b) -join ',') }
            '--proxy-hosts' { ((Get-ALListSet $a) -join ',') -ceq ((Get-ALListSet $b) -join ',') }
            '--trusted-proxies' { ((Get-ALListSet $a -Address) -join ',') -ceq ((Get-ALListSet $b -Address) -join ',') }
            default { [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase) }      # --data-dir, --cert, --cert-password-file
        }
        if (-not $equal) { $differences.Add("$name differs: service '$a', configuration '$b'") }
    }
    $differences.ToArray()          # a plain sequence: callers wrap it in @(...)
}

# An executable path for comparison: surrounding quotes and whitespace removed, separators unified, no trailing separator. Case is compared
# separately (Windows paths are case-insensitive). No drive or file-system lookup, so it behaves the same on Linux test hosts.
function ConvertTo-ALNormalPath([string]$Path) { ($Path.Trim().Trim('"') -replace '[\\/]+', '\').TrimEnd('\') }

# Whether a service command line runs the managed release executable with the configured arguments. The raw command line is not compared:
# Windows and sc.exe store equivalent command lines differently (quotes, option order, list order, case; Windows PowerShell 5.1 can drop the
# quotes around the executable when it passes binPath= to sc.exe), which made a correctly managed service read as unmanaged.
function Test-ALServiceBinary([string]$PathName, $Config) {
    if (-not $PathName) { return $false }
    $tokens = @(Split-ALCommandLine $PathName)
    if ($tokens.Count -eq 0) { return $false }
    $exe = ConvertTo-ALNormalPath $tokens[0]
    if (-not [string]::Equals($exe, (ConvertTo-ALNormalPath (Get-ALServiceExe $Config)), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    @(Compare-ALServiceArguments @($tokens | Select-Object -Skip 1) @(Get-ALServiceArguments $Config)).Count -eq 0
}

function Get-ALCurrentLink($Config) { Join-AL $Config.ReleasesRoot 'current' }
function Get-ALServiceExe($Config) { Join-AL (Join-AL (Get-ALCurrentLink $Config) 'server') $script:Exe }

function Get-ALBinaryPath($Config) {
    $quoted = (Get-ALServiceArguments $Config) | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }
    '"' + (Get-ALServiceExe $Config) + '" ' + ($quoted -join ' ')
}

# ---- platform layer (mocked in tests)

# PowerShell unrolls a one-element array returned from a function into that element; indexing it then yields a [char] (the Windows PowerShell 5.1
# failure "[System.Char] does not contain a method named 'Trim'"). Callers therefore wrap results in @(...), and single values use Get-ALGitValue.
function Get-ALGitValue([string]$Repository, [string[]]$Arguments) {
    $lines = @(Invoke-ALGit $Repository $Arguments | Where-Object { "$_".Trim() })
    if ($lines.Count -ne 1) { Stop-AL ("git {0} returned {1} lines, expected one." -f ($Arguments -join ' '), $lines.Count) }
    ([string]$lines[0]).Trim()
}

# Native commands: Windows PowerShell 5.1 turns every stderr line of a native command redirected with 2>&1 into a terminating error when
# $ErrorActionPreference is 'Stop' (git and the build tools write progress there). These wrappers run with 'Continue' and judge by the exit code.
function Invoke-ALGit([string]$Repository, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-AL ("git {0} failed: {1}" -f ($Arguments -join ' '), (($output | Out-String).Trim())) }
    @($output | ForEach-Object { "$_" })
}

function Get-ALShell {
    $name = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
    $executable = Join-Path $PSHOME $name
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { Stop-AL 'The current PowerShell executable is unavailable; no PATH fallback is allowed.' }
    $executable
}

function Invoke-ALProcess([string]$File, [string[]]$Arguments, [string]$LogFile) {
    $ErrorActionPreference = 'Continue'
    $output = & $File @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($LogFile) { $output | ForEach-Object { "$_" } | Add-Content -LiteralPath $LogFile -Encoding UTF8 }
    [pscustomobject]@{ ExitCode = $code; Output = @($output | ForEach-Object { "$_" }) }
}

# The server's local maintenance commands (--schema-info, --backup-local, --backup-verify): JSON on success, $null when the release does not know
# the command (an older build), otherwise a refusal.
function Invoke-ALMaintenance([string]$ExePath, [string[]]$Arguments, [switch]$AllowUnsupported) {
    $result = Invoke-ALProcess $ExePath $Arguments ''
    if ($result.ExitCode -eq 0) {
        $text = ($result.Output | Where-Object { $_ -notmatch '^maintenance refused' }) -join "`n"
        try { return ($text | ConvertFrom-Json) } catch { if ($AllowUnsupported) { return $null } }
    }
    if ($AllowUnsupported) { return $null }
    Stop-AL ("{0} {1} failed: {2}" -f $ExePath, ($Arguments -join ' '), (($result.Output | Select-Object -Last 3) -join ' '))
}

function Get-ALService([string]$Name) {
    # Windows always has CIM; elsewhere (the Linux test harness) there is no service manager, so the service reads as missing.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ Exists = $false; State = 'Missing'; StartMode = ''; Account = ''; PathName = ''; ProcessId = 0 } }
    $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $service) { return [pscustomobject]@{ Exists = $false; State = 'Missing'; StartMode = ''; Account = ''; PathName = ''; ProcessId = 0 } }
    [pscustomobject]@{ Exists = $true; State = $service.State; StartMode = $service.StartMode; Account = $service.StartName; PathName = $service.PathName; ProcessId = [int]$service.ProcessId }
}

function Get-ALListener([string]$Address, [int]$Port) {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return @() }
    @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in @($Address, '0.0.0.0', '::') } |
        ForEach-Object { [int]$_.OwningProcess } | Sort-Object -Unique)
}

function Test-ALProcessAlive([int]$ProcessId) { [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) }

# Stops only this service, through the Service Control Manager (a graceful stop: running imports are handed back). Never kills any process.
function Stop-ALService([string]$Name, [int]$TimeoutSeconds) {
    $before = Get-ALService $Name
    if ($before.State -eq 'Stopped') { return }
    Stop-Service -Name $Name -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $now = Get-ALService $Name
        if ($now.State -eq 'Stopped' -and ($before.ProcessId -eq 0 -or -not (Test-ALProcessAlive $before.ProcessId))) { return }
        Start-Sleep -Seconds 1
    }
    Stop-AL "Service $Name did not stop within $TimeoutSeconds s (process $($before.ProcessId)). It was not killed; investigate before retrying." 4
}

function Start-ALService([string]$Name) { Start-Service -Name $Name -ErrorAction Stop }

# Changes only the command line of an existing service (sc.exe config binPath=); account, start mode and recovery settings stay as they are.
function Set-ALServiceBinary([string]$Name, [string]$BinaryPath) {
    $result = Invoke-ALProcess 'sc.exe' @('config', $Name, 'binPath=', $BinaryPath) ''
    if ($result.ExitCode -ne 0) { Stop-AL "sc.exe could not update the command line of $Name ($(($result.Output | Select-Object -Last 1)))." 4 }
}

function Get-ALLink([string]$Link) {
    if (-not (Test-Path -LiteralPath $Link)) { return '' }
    $item = Get-Item -LiteralPath $Link -Force
    if ($item.LinkType -ne 'Junction' -and $item.LinkType -ne 'SymbolicLink') { Stop-AL "$Link exists but is not a link; move it aside first." }
    [string]@($item.Target)[0]
}

# Points the 'current' junction at a release folder: a new junction is created beside it and swapped in (remove + rename).
function Set-ALLink([string]$Link, [string]$Target) {
    $staging = "$Link.next"
    if (Get-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue) { Stop-AL "$staging exists from another or interrupted operation; it was preserved for inspection." 4 }
    $parent = Split-Path $Link
    Test-ALPathTree $parent
    if (-not (Test-ALPathWithin $Target $parent) -or [IO.Path]::GetFullPath($Target).TrimEnd('\','/') -ieq [IO.Path]::GetFullPath($parent).TrimEnd('\','/')) { Stop-AL 'Release link target must remain inside its releases directory.' }
    $null = @(Get-ALTreeFiles $Target)
    if (Test-Path -LiteralPath $Link) {
        if ((Get-Item -LiteralPath $Link -Force).LinkType -ne 'Junction') { Stop-AL 'The current release pointer is not an expected junction.' 4 }
    }
    New-Item -ItemType Junction -Path $staging -Target $Target | Out-Null
    if (Test-Path -LiteralPath $Link) { (Get-Item -LiteralPath $Link -Force).Delete() }   # removes the link only, never the release behind it
    Rename-Item -LiteralPath $staging -NewName (Split-Path $Link -Leaf)
}

function Initialize-ALPinnedHttp {
    if('AuthLensDeployment.PinnedHttp' -as [type]){return}
    # A CLR callback avoids running PowerShell on a TLS worker thread. Validation is per request,
    # never a process-wide certificate bypass. The exact configured leaf and validity are required.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
namespace AuthLensDeployment {
 public sealed class ProbeResponse {
  public int Status; public string Body = ""; public string Error = "";
 }
 public static class PinnedHttp {
  public static bool Matches(X509Certificate certificate, byte[] expected, DateTime now) {
   if(certificate == null || expected == null || expected.Length == 0) return false;
   using(var leaf = new X509Certificate2(certificate)) {
    if(now < leaf.NotBefore.ToUniversalTime() || now > leaf.NotAfter.ToUniversalTime()) return false;
    var actual = leaf.RawData;
    if(actual.Length != expected.Length) return false;
    for(int i=0;i<actual.Length;i++) if(actual[i] != expected[i]) return false;
    return true;
   }
  }
  public static ProbeResponse Get(string url, string authority, byte[] expected) {
   var uri = new Uri(url);
   if(uri.Scheme != "https" || expected == null || expected.Length == 0) throw new InvalidOperationException("Pinned HTTPS required.");
   var request = (HttpWebRequest)WebRequest.Create(uri);
   request.Host = authority; request.Proxy = null; request.AllowAutoRedirect = false;
   request.Credentials = null; request.UseDefaultCredentials = false; request.KeepAlive = false;
   request.Timeout = 10000; request.ReadWriteTimeout = 10000;
   request.ServerCertificateValidationCallback = (sender, certificate, chain, errors) => Matches(certificate, expected, DateTime.UtcNow);
   HttpWebResponse response = null;
   try { response = (HttpWebResponse)request.GetResponse(); }
   catch(WebException error) {
    response = error.Response as HttpWebResponse;
    if(response == null) return new ProbeResponse { Error = error.Status.ToString() };
   }
   using(response) using(var reader = new StreamReader(response.GetResponseStream())) {
    var buffer = new char[1048577]; int count=0, next;
    while(count < buffer.Length && (next=reader.Read(buffer,count,buffer.Length-count)) > 0) count+=next;
    if(count == buffer.Length) return new ProbeResponse { Error = "ResponseTooLarge" };
    return new ProbeResponse { Status=(int)response.StatusCode, Body=new string(buffer,0,count) };
   }
  }
 }
}
'@
}

function Invoke-ALHttp([string]$Url, [string]$HostHeader = '',[string]$CertificatePath='',[string]$CertificatePasswordFile='') {
    $ErrorActionPreference = 'Continue'
    if(-not $CertificatePath -or -not $CertificatePasswordFile){Stop-AL 'Readiness requires the configured TLS certificate identity.'}
    Initialize-ALPinnedHttp
    $certificate=$null;$password=$null;$protocol=[Net.ServicePointManager]::SecurityProtocol
    try{
        $password=[IO.File]::ReadAllText($CertificatePasswordFile).TrimEnd("`r","`n")
        $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath,$password,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        [AuthLensDeployment.PinnedHttp]::Get($Url,$HostHeader,$certificate.RawData)
    }catch{Stop-AL 'Pinned HTTPS probe failed; verify the configured certificate, password-file access and local TLS listener.' 1}
    finally{[Net.ServicePointManager]::SecurityProtocol=$protocol;if($certificate){$certificate.Dispose()};$password=$null}
}

function Invoke-ALConfiguredHttp($Config, [string]$Path) {
    # Connect directly to the configured listener with an already allowed host.
    # Never change DNS, host/origin policy or proxy configuration for a probe.
    $listenIp=$null
    if(-not [Net.IPAddress]::TryParse($Config.ListenAddress,[ref]$listenIp)){Stop-AL 'Probe listener must be an IP address.'}
    if($listenIp.Equals([Net.IPAddress]::Any) -or $listenIp.Equals([Net.IPAddress]::IPv6Any)){Stop-AL 'Wildcard listeners are not supported by the current runtime; select a specific private interface.'}
    $hostName=if([Net.IPAddress]::IsLoopback($listenIp)){$Config.ListenAddress}else{@($Config.AllowedHosts|Where-Object{$_ -and $_ -ne '*'})|Select-Object -First 1}
    if (-not $hostName) { Stop-AL 'A configured allowed host is required for health inspection.' }
    $address=$Config.ListenAddress
    if($address.Contains(':')){$address='['+$address+']'}
    if($hostName.Contains(':')){$hostName='['+$hostName+']'}
    Invoke-ALHttp "https://${address}:$($Config.Port)$Path" "$hostName`:$($Config.Port)" $Config.CertificatePath $Config.CertificatePasswordFile
}

# ---- journal and lock

function Get-ALJournalPath($Config) { Join-AL $Config.WorkRoot 'deployment-journal.json' }

function Read-ALJournal($Config) {
    $path = Get-ALJournalPath $Config
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Write-ALJournal($Config, $Journal) {
    $Journal.updated = [DateTime]::UtcNow.ToString('o')
    $path = Get-ALJournalPath $Config
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $temporary = "$path.tmp"
    [System.IO.File]::WriteAllText($temporary, ($Journal | ConvertTo-Json -Depth 8))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    if ($script:RunFolder -and (Test-Path -LiteralPath $script:RunFolder)) { Copy-Item -LiteralPath $path -Destination (Join-AL $script:RunFolder 'journal.json') -Force }
}

function Set-ALPhase($Config, $Journal, [string]$Phase) {
    $Journal.phase = $Phase
    # A journal read back from JSON may hold history as a single object or not at all: rebuild it as an array.
    # (A typed list: an if-expression or a function would unroll a one-entry history into a bare hashtable again.)
    $history = [System.Collections.Generic.List[object]]::new()
    if ($Journal.PSObject.Properties['history'] -and $null -ne $Journal.history) { foreach ($entry in @($Journal.history)) { $history.Add($entry) } }
    $history.Add(@{ phase = $Phase; at = [DateTime]::UtcNow.ToString('o') })
    $Journal | Add-Member -NotePropertyName history -NotePropertyValue $history.ToArray() -Force
    Write-ALJournal $Config $Journal
    Write-ALLog "phase: $Phase"
}

# One deployment operation at a time per host: an exclusive handle, released by Windows when the process ends (also after Ctrl+C or a dropped SSH session).
function Enter-ALLock($Config,[switch]$MutexOnly) {
    # Serialize across source AND target WorkRoot during directory migration.
    $script:HostLock = [Threading.Mutex]::new($false, 'Global\AuthLens.Deployment')
    $acquired = $false
    try { $acquired = $script:HostLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { $script:HostLock.Dispose(); $script:HostLock = $null; Stop-AL 'Another deployment operation is running on this host.' }
    if($MutexOnly){return} # pre-deployment quarantine must not populate the fresh WorkRoot
    New-Item -ItemType Directory -Force $Config.WorkRoot | Out-Null
    $path = Join-AL $Config.WorkRoot 'deployment.lock'
    try { $script:Lock = [System.IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { $script:HostLock.ReleaseMutex(); $script:HostLock.Dispose(); $script:HostLock = $null; Stop-AL 'Another deployment operation is running on this host (deployment.lock is held).' }
}

function Exit-ALLock {
    if ($script:Lock) { $script:Lock.Dispose(); $script:Lock = $null }
    if ($script:HostLock) { $script:HostLock.ReleaseMutex(); $script:HostLock.Dispose(); $script:HostLock = $null }
}

function New-ALRun($Config, [string]$Action) {
    $id = '{0:yyyyMMdd-HHmmss}-{1}-{2}' -f [DateTime]::UtcNow, $Action, [Guid]::NewGuid().ToString('N').Substring(0,8)
    $script:RunId = $id
    $script:RunFolder = Join-AL (Join-AL $Config.WorkRoot 'runs') $id
    New-Item -ItemType Directory -Force $script:RunFolder | Out-Null
    $script:RunLog = Join-AL $script:RunFolder 'deploy.log'
    Write-ALLog "run $id, logs in $script:RunFolder"
    $id
}

# ---- source, build, validation

# The .NET project inside a checkout: backend\ (since the promotion), or experiments\dotnet-backend in commits from before it, which can still be deployed. The Python backend has
# no AuthLens.slnx, so the choice is unambiguous.
function Get-ALProjectRoot([string]$Worktree) {
    foreach ($relative in 'backend', 'experiments/dotnet-backend') {
        $candidate = Join-AL $Worktree $relative
        if (Test-Path -LiteralPath (Join-AL $candidate 'AuthLens.slnx')) { return $candidate }
    }
    Stop-AL "No .NET project (AuthLens.slnx) in $Worktree under experiments\dotnet-backend or backend." 1
}

# Building from Git needs a source checkout; installed (packaged) Servers deploy verified packages (Setup or -Action Deploy -Release).
function Assert-ALRepositoryContext($Config) {
    if (-not $Config.RepositoryPath) { Stop-AL 'This action builds from a source repository, but the configuration has no RepositoryPath (an installed Server). Deploy a verified package with Server Setup or -Action Deploy -Release <published release>.' }
}

function Resolve-ALCommit($Config, [string]$Branch, [string]$Commit) {
    Assert-ALRepositoryContext $Config
    if (-not $Branch) { $Branch = $Config.Branch }
    if ($Branch -in @('main', 'work')) { Stop-AL "Deployments are built from the development branch, not '$Branch'." }
    Invoke-ALGit $Config.RepositoryPath @('fetch', '--quiet', $Config.Remote, "refs/heads/${Branch}:refs/remotes/$($Config.Remote)/$Branch") | Out-Null
    $tip = Get-ALGitValue $Config.RepositoryPath @('rev-parse', "$($Config.Remote)/$Branch^{commit}")
    if (-not $Commit) { return $tip }
    if ($Commit -notmatch '^[0-9a-f]{7,40}$') { Stop-AL "Commit '$Commit' is not a hexadecimal SHA." }
    $full = Get-ALGitValue $Config.RepositoryPath @('rev-parse', "$Commit^{commit}")
    $contained = Invoke-ALProcess 'git' @('-C', $Config.RepositoryPath, 'merge-base', '--is-ancestor', $full, $tip) ''
    if ($contained.ExitCode -ne 0) { Stop-AL "Commit $full is not on $($Config.Remote)/$Branch; only pushed commits of the branch are deployed." }
    $full
}

# An isolated worktree per commit under WorkRoot: the developer's checkout and its working tree are never touched.
function New-ALWorktree($Config, [string]$Commit) {
    Assert-ALRepositoryContext $Config
    $path = Join-AL (Join-AL $Config.WorkRoot 'worktrees') $Commit.Substring(0, 12)
    if (Test-Path -LiteralPath $path) {
        $head = Get-ALGitValue $path @('rev-parse', 'HEAD')
        $dirty = @(Invoke-ALGit $path @('status', '--porcelain'))
        if ($head -ne $Commit -or @($dirty | Where-Object { $_ }).Count -gt 0) {
            Stop-AL "Build worktree $path is not a clean checkout of $Commit. Remove it with: git -C `"$($Config.RepositoryPath)`" worktree remove --force `"$path`""
        }
        return $path
    }
    Invoke-ALGit $Config.RepositoryPath @('worktree', 'add', '--detach', $path, $Commit) | Out-Null
    $path
}

function Get-ALTestFilter([string]$Tests) {
    switch ($Tests) {
        'full' { return '' }
        'focused' { return (($script:FocusedTests | ForEach-Object { "FullyQualifiedName~AuthLens.Tests.$_" }) -join '|') }
        'none' { return $null }
        default { Stop-AL "Unknown test selection '$Tests' (focused, full or none)." }
    }
}

function Invoke-ALBuild($Config, [string]$Worktree, [string]$Commit, [string]$Tests) {
    $builder = Join-AL (Get-ALProjectRoot $Worktree) 'scripts\build-release.ps1'
    $output = Join-AL (Join-AL $Config.WorkRoot 'builds') $Commit.Substring(0, 12)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $builder, '-Output', $output)
    $filter = Get-ALTestFilter $Tests
    if ($null -eq $filter) { $arguments += '-SkipTests' } elseif ($filter) { $arguments += @('-TestFilter', $filter) }
    $log = Join-AL $script:RunFolder 'build.log'
    Write-ALLog "building $Commit with $Tests tests (log: $log)"
    $shell = Get-ALShell
    $result = Invoke-ALProcess $shell $arguments $log
    if ($result.ExitCode -ne 0) { Stop-AL "Build or tests failed (exit $($result.ExitCode)); see $log. Nothing was deployed." 1 }
    $line = $result.Output | Where-Object { $_ -match '^Release build complete: (.+)$' } | Select-Object -Last 1
    if (-not $line) { Stop-AL "The builder did not report a release folder; see $log." 1 }
    ($line -replace '^Release build complete: ', '').Trim()
}

# The release must be the requested commit and version, with every artifact matching its manifest and SHA256SUMS.
function Test-ALRelease([string]$Release, [string]$Commit, [string]$Worktree) {
    $verifier = Join-AL (Get-ALProjectRoot $Worktree) 'scripts\verify-release.ps1'
    $shell = Get-ALShell
    $result = Invoke-ALProcess $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier, '-ReleasePath', $Release) (Join-AL $script:RunFolder 'verify.log')
    if ($result.ExitCode -ne 0) { Stop-AL "Release verification failed for $Release." 1 }
    $manifest = Get-Content -LiteralPath (Join-AL $Release 'build-manifest.json') -Raw | ConvertFrom-Json
    $expected = (Get-Content -LiteralPath (Join-AL (Get-ALProjectRoot $Worktree) 'product-version.json') -Raw | ConvertFrom-Json).version
    if ($manifest.source_sha -ne $Commit) { Stop-AL "Release commit $($manifest.source_sha) is not the locked commit $Commit." 1 }
    if ($manifest.source_dirty) { Stop-AL 'The release was built from a modified working tree.' 1 }
    if ($manifest.version -ne $expected) { Stop-AL "Release version $($manifest.version) is not product-version.json $expected." 1 }
    $manifest
}

# A published release is a server deployment package: every artifact of the verified full build except desktop/ and symbols/, the unchanged
# build-manifest.json and SHA256SUMS (they keep describing the full build), and deployment-package.json, which declares the package and the exact
# omitted paths. verify-release.ps1 -Scope Server checks it. Packages published before the declaration existed verify as undeclared.
function Test-ALPublishedRelease([string]$Folder) {
    $verifier = Join-AL (Split-Path $PSScriptRoot) 'verify-release.ps1'
    $result = Invoke-ALProcess (Get-ALShell) @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier, '-ReleasePath', $Folder, '-Scope', 'Server') ''
    [pscustomobject]@{ Verified = ($result.ExitCode -eq 0); Output = @($result.Output | ForEach-Object { "$_" }) }
}

# The versioned deployment folder <ReleasesRoot>\<release name>. It is assembled in <ReleasesRoot>\.staging\<release name>, verified there and only
# then moved into place, so an interrupted or incomplete copy is never visible as a release. An existing folder is reused only when its manifest
# names the same commit and it verifies as a server package; it is never overwritten or repaired.
function Publish-ALRelease($Config, [string]$Release, $Manifest, [string]$RepairId='') {
    $name = Split-Path $Release -Leaf
    if($RepairId){
        if($RepairId -notmatch '^[a-f0-9]{32}$'){Stop-AL 'Invalid immutable repair publication identity.'}
        $name='repair-'+$RepairId
    }
    $target = Join-AL $Config.ReleasesRoot $name
    if (Test-Path -LiteralPath $target) {
        $existing = Get-Content -LiteralPath (Join-AL $target 'build-manifest.json') -Raw | ConvertFrom-Json
        if ($existing.source_sha -ne $Manifest.source_sha) { Stop-AL "$target exists for another commit." 1 }
        if (-not (Test-ALPublishedRelease $target).Verified) { Stop-AL "$target exists but does not verify as a server package; it was kept as it is. Inspect it with verify-release.ps1 -Scope Server." 1 }
        return $target
    }
    $staging = Join-AL (Join-AL $Config.ReleasesRoot '.staging') $name
    if (Test-Path -LiteralPath $staging) { Stop-AL "$staging remains from an interrupted publication; inspect and remove it, nothing was overwritten." 1 }
    New-Item -ItemType Directory -Force $staging | Out-Null
    $omitted = [System.Collections.Generic.List[string]]::new()
    foreach ($artifact in @($Manifest.artifacts)) {
        $relative = "$($artifact.path)"
        if ($relative -like 'desktop/*' -or $relative -like 'symbols/*') { $omitted.Add($relative); continue }
        $native = $relative -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $destination = Join-AL $staging $native
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-AL $Release $native) -Destination $destination
    }
    foreach ($file in 'build-manifest.json', 'SHA256SUMS') { Copy-Item -LiteralPath (Join-AL $Release $file) -Destination $staging }
    $declaration = [ordered]@{ schema = 1; kind = 'server'; source_release = $name
        build_manifest_sha256 = (Get-FileHash -LiteralPath (Join-AL $staging 'build-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        omitted = @($omitted | Sort-Object); created_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    [System.IO.File]::WriteAllText((Join-AL $staging 'deployment-package.json'), ($declaration | ConvertTo-Json -Depth 4))
    $check = Test-ALPublishedRelease $staging
    if (-not $check.Verified) { Stop-AL "The server package in $staging failed verification and was not published: $(($check.Output | Select-Object -Last 3) -join ' ')" 1 }
    Move-Item -LiteralPath $staging -Destination $target
    $stagingRoot = Split-Path $staging
    if (-not @(Get-ChildItem -LiteralPath $stagingRoot -Force).Count) { Remove-Item -LiteralPath $stagingRoot -Force }
    $target
}

# ---- service installation

# Creates the service (automatic start, its virtual account, restart on failure) or, for an existing one, sets its command line and account.
function Set-ALServiceEntry($Config, [string]$Binary, [bool]$Exists, [string]$StartMode = 'auto') {
    $displayName = if ($Config.ServiceName -ceq $script:ServiceName) { 'AuthLens' } else { $Config.ServiceName }   # isolated test services keep their own name
    if (-not $Exists) {
        New-Service -Name $Config.ServiceName -DisplayName $displayName -BinaryPathName $Binary -StartupType Manual -Description 'AuthLens (.NET) server' | Out-Null
        # Assign identity while the new service is still Manual. A failed identity setup must never leave Auto/LocalSystem behind.
        $identity=Invoke-ALProcess 'sc.exe' @('config',$Config.ServiceName,'obj=',$Config.ServiceAccount) ''
        if($identity.ExitCode -ne 0){Stop-AL 'Service identity preparation failed; the new service remains Manual and was not started.' 1}
    }else{
        $observed=Get-ALService $Config.ServiceName
        if(-not $observed.Exists -or $observed.Account -ine $Config.ServiceAccount){Stop-AL 'Existing service identity differs; a separate validated credential transaction is required.'}
        # Do not reset a stored SCM password when preserving an existing account.
    }
    foreach ($arguments in @(@('config', $Config.ServiceName, 'binPath=', $Binary, 'start=', $StartMode, 'DisplayName=', $displayName),
            @('failure', $Config.ServiceName, 'reset=', '86400', 'actions=', 'restart/60000/restart/60000//'))) {
        $result = Invoke-ALProcess 'sc.exe' $arguments ''     # virtual account: no password
        if ($result.ExitCode -ne 0) { Stop-AL "sc.exe $($arguments[0]) $($Config.ServiceName) failed ($(($result.Output | Select-Object -Last 1)))." 1 }
    }
}

function Install-ALService($Config, [switch]$Reconfigure) {
    $service = Get-ALService $Config.ServiceName
    if ($service.Exists -and -not $Reconfigure) { Stop-AL "Service $($Config.ServiceName) exists; use -Reconfigure to update its command line and permissions." }
    if (-not (Get-ALLink (Get-ALCurrentLink $Config))) { Stop-AL 'No release is linked yet: run the build action and then deploy with -FirstInstall, which installs the service.' }
    $listeners = @(Get-ALListener $Config.ListenAddress ([int]$Config.Port))
    $owned = $service.Exists -and $service.ProcessId -gt 0 -and ($listeners -contains $service.ProcessId)
    if ($listeners.Count -gt 0 -and -not $owned) {
        Stop-AL ("Port {0} on {1} is used by process {2}, not by the service. Stop that server yourself (for example start-server-test.ps1 -Stop); it is never terminated by this script." -f $Config.Port, $Config.ListenAddress, ($listeners -join ','))
    }
    foreach ($file in $Config.CertificatePath, $Config.CertificatePasswordFile) { if (-not (Test-Path -LiteralPath $file)) { Stop-AL "Missing file $file." } }
    $binary = Get-ALBinaryPath $Config
    Set-ALServiceEntry $Config $binary $service.Exists
    Grant-ALAccess $Config
    Write-ALLog "service $($Config.ServiceName) configured: $binary, account $($Config.ServiceAccount)"
}

# Least privilege for the virtual service account: modify the data directory, read the releases, the certificate, its password file and the backup
# key. Grants are added; existing permissions (administrators, the owner) are not removed.
function Grant-ALAccess($Config) {
    $account = $Config.ServiceAccount
    Initialize-ALSourceAuthorityDirectory $Config
    $grants = @(
        @($Config.DataDirectory, "${account}:(OI)(CI)M"), @($Config.ReleasesRoot, "${account}:(OI)(CI)RX"),
        @($Config.CertificatePath, "${account}:R"), @($Config.CertificatePasswordFile, "${account}:R")
    )
    $pointer = Join-AL $Config.DataDirectory 'backup-key-location.json'
    if (Test-Path -LiteralPath $pointer) { $grants += , @(((Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json).path), "${account}:R") }
    foreach ($grant in $grants) {
        $result = Invoke-ALProcess 'icacls' @($grant[0], '/grant', $grant[1]) ''
        if ($result.ExitCode -ne 0) { Stop-AL "icacls could not grant $($grant[1]) on $($grant[0])." }
    }
}

# The web source authority is deliberately outside restorable application data. Same deterministic path as ServerSourceAuthorization.
function Get-ALSourceAuthorityDirectory($Config) {
    $data=[IO.Path]::GetFullPath($Config.DataDirectory).TrimEnd('\','/').ToUpperInvariant()
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $digest=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($data)))).Replace('-','').ToLowerInvariant().Substring(0,16) }
    finally { $sha.Dispose() }
    Join-AL ([IO.Path]::GetDirectoryName($data)) ('.authlens-source-policy-'+$digest)
}

function Initialize-ALSourceAuthorityDirectory($Config) {
    $path=Get-ALSourceAuthorityDirectory $Config
    $sid=([Security.Principal.NTAccount]::new($Config.ServiceAccount)).Translate([Security.Principal.SecurityIdentifier])
    Test-ALPathTree $path
    if(-not(Test-Path -LiteralPath $path)) {
        $security=New-ALProtectedDirectorySecurity
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'Modify','ContainerInherit, ObjectInherit','None','Allow'))
        New-ALDirectoryWithAcl $path $security
    }
    $acl=Get-Acl -LiteralPath $path
    $allowed=@('S-1-5-18','S-1-5-32-544',$sid.Value)
    $owners=$allowed+@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    if(-not $acl.AreAccessRulesProtected -or $owners -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { Stop-AL 'Source authority directory has unrecognized ownership or inheritance; explicit operator review is required.' }
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq 'Allow' -and $allowed -notcontains $rule.IdentityReference.Value) { Stop-AL 'Source authority directory grants access to an unrecognized principal; nothing was changed.' }
    }
    # Existing protected folders may belong to a previously configured service identity: refuse rather than adopt them.
    $required=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $sid.Value -and $_.AccessControlType -eq 'Allow' -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Modify) -eq [Security.AccessControl.FileSystemRights]::Modify })
    if(-not $required.Count) { Stop-AL 'Source authority directory lacks access for the configured service identity; explicit operator review is required.' }
}

# ---- status

function Get-ALStatus($Config) {
    $service = Get-ALService $Config.ServiceName
    $current = Get-ALLink (Get-ALCurrentLink $Config)
    $manifest = $null
    if ($current -and (Test-Path -LiteralPath (Join-AL $current 'build-manifest.json'))) { $manifest = Get-Content -LiteralPath (Join-AL $current 'build-manifest.json') -Raw | ConvertFrom-Json }
    $listeners = @(Get-ALListener $Config.ListenAddress ([int]$Config.Port))
    $model = if ($service.Exists) { 'windows-service' } elseif ($listeners.Count -gt 0) { 'unmanaged-process' } else { 'none' }
    $identity = $null; $ready = $null
    if ($listeners.Count -gt 0) {
        $base = "https://$($Config.ListenAddress):$($Config.Port)"
        $readyResponse = Invoke-ALConfiguredHttp $Config '/health/ready'; $ready = $readyResponse.Status -eq 200
        $identityResponse = Invoke-ALConfiguredHttp $Config '/product-version.json'
        if ($identityResponse.Status -eq 200) { $identity = $identityResponse.Body | ConvertFrom-Json }
    }
    $journal = Read-ALJournal $Config
    [pscustomobject]@{
        service_model = $model; service_name = $Config.ServiceName; service = $service; expected_binary_path = Get-ALBinaryPath $Config
        binary_path_matches = ($service.Exists -and (Test-ALServiceBinary $service.PathName $Config))
        current_release = $current; current_commit = $(if ($manifest) { $manifest.source_sha } else { $null }); current_version = $(if ($manifest) { $manifest.version } else { $null })
        listeners = $listeners; ready = $ready; running_identity = $identity
        journal_phase = $(if ($journal) { $journal.phase } else { $null }); recovery_needed = ($journal -and $journal.phase -in $script:CriticalPhases)
        configuration_change_pending = [bool](Get-ALPendingConfigurationRecord $Config); backup_key_service_access = (Get-ALKeyServiceAccess $Config)
        execution_context = $Config.ExecutionContext; access_mode = $Config.AccessMode; listen_address = $Config.ListenAddress; port = [int]$Config.Port
        allowed_hosts = @($Config.AllowedHosts); proxy_hosts = @($Config.ProxyHosts); trusted_proxies = @($Config.TrustedProxies); certificate = $Config.CertificatePath
        certificate_status = $(try { ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $Config) } catch { $null })
    }
}

# Whether the configured service identity can read the configured host backup key, from the key file's DACL (read-only; the key is never opened):
# not_configured, readable, not_readable (no explicit Allow read or a Deny read), unknown (the DACL is not readable by this session, run elevated),
# identity_unresolved or missing. Group membership is not evaluated; provisioning creates an explicit grant (Grant-ALAccess, Service Manager).
function Get-ALKeyServiceAccess($Config) {
    $pointer = Join-AL $Config.DataDirectory 'backup-key-location.json'
    if (-not [IO.File]::Exists($pointer)) { return 'not_configured' }
    try { $key = [string]([IO.File]::ReadAllText($pointer) | ConvertFrom-Json).path } catch { return 'unknown' }
    if (-not $key -or -not [IO.File]::Exists($key)) { return 'missing' }
    try { $sid = ([Security.Principal.NTAccount]::new($Config.ServiceAccount)).Translate([Security.Principal.SecurityIdentifier]) } catch { return 'identity_unresolved' }
    if ($sid.Value -eq 'S-1-5-18') { return 'readable' }
    try {
        $info = [IO.FileInfo]::new($key)
        $acl = if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::GetAccessControl($info, [Security.AccessControl.AccessControlSections]::Access) } else { $info.GetAccessControl([Security.AccessControl.AccessControlSections]::Access) }
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $sid.Value })
    } catch { return 'unknown' }
    $read = [Security.AccessControl.FileSystemRights]::ReadData
    if (@($rules | Where-Object { $_.AccessControlType -eq 'Deny' -and ($_.FileSystemRights -band $read) }).Count) { return 'not_readable' }
    if (@($rules | Where-Object { $_.AccessControlType -eq 'Allow' -and ($_.FileSystemRights -band $read) -eq $read }).Count) { return 'readable' }
    'not_readable'
}

# ---- deployment state machine

function Wait-ALReady($Config, [string]$Commit, [string]$Version) {
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$Config.ReadyTimeoutSeconds)
    $base = "https://$($Config.ListenAddress):$($Config.Port)"
    $last = 'not started'
    while ([DateTime]::UtcNow -lt $deadline) {
        $service = Get-ALService $Config.ServiceName
        if ($service.State -eq 'Stopped') { Stop-AL 'The service stopped during startup (see <data-dir>\logs\server-*.log).' 1 }
        $listeners = @(Get-ALListener $Config.ListenAddress ([int]$Config.Port))
        if ($service.State -eq 'Running' -and $service.ProcessId -gt 0 -and $listeners -contains $service.ProcessId) {
            $ready = Invoke-ALConfiguredHttp $Config '/health/ready'
            if($ready.Status -in @(400,401,403,404,421) -or ($ready.PSObject.Properties['Error'] -and $ready.Error -in @('TrustFailure','SecureChannelFailure','ResponseTooLarge'))){
                switch($ready.Status){
                    421 {Stop-AL 'Permanent readiness policy/TLS failure (HTTP 421): local authority rejected; review access mode and allowed hosts.' 1}
                    403 {Stop-AL 'Permanent readiness policy/TLS failure (HTTP 403): HTTPS or request policy refused the probe.' 1}
                    404 {Stop-AL 'Permanent readiness policy/TLS failure (HTTP 404): expected readiness endpoint is missing.' 1}
                    401 {Stop-AL 'Permanent readiness policy/TLS failure (HTTP 401): readiness must not require application credentials.' 1}
                    default {Stop-AL 'Permanent readiness policy/TLS failure: verify the configured certificate identity and local request policy.' 1}
                }
            }
            if ($ready.Status -eq 200) {
                $identityResponse = Invoke-ALConfiguredHttp $Config '/product-version.json'
                if ($identityResponse.Status -ne 200) { Stop-AL 'Release identity could not be verified.' 1 }
                $identity = $identityResponse.Body | ConvertFrom-Json
                if ($Commit -and ($identity.source_sha -ne $Commit -or $identity.version -ne $Version)) {
                    Stop-AL "The service answers as $($identity.version) $($identity.source_sha), expected $Version $Commit." 1
                }
                return [pscustomobject]@{ process_id = $service.ProcessId; identity = $identity }
            }
            $last = "health/ready answered $($ready.Status)"
        } elseif ($listeners.Count -gt 0 -and -not ($listeners -contains $service.ProcessId)) {
            Stop-AL "Port $($Config.Port) is held by process $($listeners -join ','), not by the service." 1
        } else { $last = "service $($service.State), not listening yet" }
        Start-Sleep -Seconds 2
    }
    Stop-AL "The service did not become ready within $($Config.ReadyTimeoutSeconds) s ($last)." 1
}

# Whether the release in $ReleaseFolder can open the data as it is now. A release that knows --schema-info answers itself; for an older build the
# proof is that no migration was applied since the deployment started.
function Test-ALRollbackSafe($Config, [string]$ReleaseFolder, $AppliedBefore, [string]$Executable = '') {
    $exe = if ($Executable) { $Executable } else { Join-AL (Join-AL $ReleaseFolder 'server') $script:Exe }
    $info = Invoke-ALMaintenance $exe @('--schema-info', '--data-dir', $Config.DataDirectory) -AllowUnsupported
    if ($info) { return [pscustomobject]@{ Safe = [bool]$info.compatible; Reason = $(if ($info.compatible) { 'the previous release knows every applied migration' } else { 'the database has migrations the previous release does not know: ' + (@($info.unknown_applied) -join ', ') }) } }
    $newExe = Join-AL (Join-AL (Get-ALLink (Get-ALCurrentLink $Config)) 'server') $script:Exe
    $now = Invoke-ALMaintenance $newExe @('--schema-info', '--data-dir', $Config.DataDirectory)
    $added = @($now.applied | Where-Object { @($AppliedBefore) -notcontains $_ })
    if ($added.Count -eq 0) { return [pscustomobject]@{ Safe = $true; Reason = 'no migration was applied during the deployment' } }
    [pscustomobject]@{ Safe = $false; Reason = 'migrations applied during the deployment: ' + ($added -join ', ') }
}

function Write-ALRecoveryInstructions($Config, $Journal, [string]$Reason) {
    $service=Get-ALService $Config.ServiceName
    $backup = if ($Journal.PSObject.Properties['backup'] -and $Journal.backup) { "$($Journal.backup.file) (recorded SHA-256 $($Journal.backup.sha256); revalidation required)" } else { 'none recorded; no rollback/restore prerequisite may be inferred' }
    $rollback=if($Journal.from_release){'Rollback is conditional: the supported recovery action must revalidate the previous package, backup and current schema. No file-copy rollback is authorized.'}else{'Rollback unavailable: this transaction has no previous release. Preserve the newly created data and running service state.'}
    $text = @"
AuthLens deployment $($Journal.run) needs a manual decision. Nothing further was changed automatically.

Reason: $Reason
Observed service: $($Config.ServiceName), state $($service.State). This note does not stop or start it.
Linked release: $(Get-ALLink (Get-ALCurrentLink $Config))
Previous release: $($Journal.from_release)
Pre-deployment backup evidence: $backup

$rollback

Supported choices after correcting the cause and reviewing evidence:
- VerifyCandidate: revalidate an already running owned candidate; success requires package/configuration,
  TLS/read-only preflight, schema, listener PID and exact runtime version/SHA proof.
- Resume: the same validation, with explicit permission to start an existing stopped owned service.
- Rollback: available only with a verified retained previous release and unchanged verified backup evidence.
- Cancel: only before release/service mutation (prepared or backup checkpoint). It never deletes data.
Use Deploy-AuthLens.ps1 -Action Recover -RecoveryAction <choice> -ConfigFile <reviewed configuration> -Yes.
Keep this journal, the run folder, staged tools, databases, keys, certificates and backups. Never mark the
journal complete manually, move a live data directory, erase registration or invent a rollback backup.
"@
    $path = Join-AL $script:RunFolder 'RECOVERY-REQUIRED.txt'
    [System.IO.File]::WriteAllText($path, $text)
    Write-ALLog "manual recovery required: $path"
}

function Invoke-ALRollbackCore($Config, $Journal, [string]$Target) {
    Write-ALLog "rolling back to $Target"
    Stop-ALService $Config.ServiceName ([int]$Config.StopTimeoutSeconds)
    $before = if ($Journal.PSObject.Properties['service_binary_before']) { [string]$Journal.service_binary_before } else { '' }
    $adopted = $before -and -not $Target
    $safety = if ($adopted) { Test-ALRollbackSafe $Config '' $Journal.applied_before @(Split-ALCommandLine $before)[0] } else { Test-ALRollbackSafe $Config $Target $Journal.applied_before }
    if (-not $safety.Safe) {
        Set-ALPhase $Config $Journal 'manual_recovery_required'
        Write-ALRecoveryInstructions $Config $Journal $safety.Reason
        Stop-AL "Rollback is not safe: $($safety.Reason). The service is stopped; see RECOVERY-REQUIRED.txt in $script:RunFolder." 4
    }
    if ($adopted) {
        # The service was adopted in this run: its original command line (and release) comes back unchanged.
        Set-ALServiceBinary $Config.ServiceName $before
        $identity = if ($Journal.PSObject.Properties['identity_before'] -and $Journal.identity_before) { $Journal.identity_before } else { $null }
        $manifest = [pscustomobject]@{ source_sha = $(if ($identity) { $identity.source_sha } else { '' }); version = $(if ($identity) { $identity.version } else { '' }) }
        $Target = @(Split-ALCommandLine $before)[0]
    } else {
        if ($before) { Set-ALServiceBinary $Config.ServiceName (Get-ALBinaryPath $Config) }
        Set-ALLink (Get-ALCurrentLink $Config) $Target
        $manifest = Get-Content -LiteralPath (Join-AL $Target 'build-manifest.json') -Raw | ConvertFrom-Json
    }
    Start-ALService $Config.ServiceName
    try { Wait-ALReady $Config $manifest.source_sha $manifest.version | Out-Null }
    catch {
        Set-ALPhase $Config $Journal 'manual_recovery_required'
        Write-ALRecoveryInstructions $Config $Journal "the previous release did not become ready after the rollback: $($_.Exception.Message)"
        Stop-AL 'The previous release did not become ready after the rollback; see RECOVERY-REQUIRED.txt.' 4
    }
    Set-ALPhase $Config $Journal 'rolled_back'
    Write-ALLog "rolled back to $Target ($($manifest.version) $($manifest.source_sha)); the service is ready"
}

function Invoke-ALDeploy($Config, [string]$ReleaseFolder, [string]$Commit, [switch]$DryRun, [switch]$FirstInstall, [switch]$AdoptService, [switch]$RequireRollback) {
    Assert-ALNoPendingRepair $Config
    $previousJournal = Read-ALJournal $Config
    if ($previousJournal -and $previousJournal.phase -in $script:CriticalPhases) {
        Stop-AL "An earlier deployment ($($previousJournal.run)) was interrupted in phase '$($previousJournal.phase)'. Run -Action Recover first."
    }
    $manifest = Get-Content -LiteralPath (Join-AL $ReleaseFolder 'build-manifest.json') -Raw | ConvertFrom-Json
    $service = Get-ALService $Config.ServiceName
    $link = Get-ALCurrentLink $Config
    $previous = Get-ALLink $link
    if (-not $service.Exists -and -not $FirstInstall) { Stop-AL "Service $($Config.ServiceName) is not installed. Run the first deployment with -FirstInstall (see WINDOWS_DEPLOYMENT.md)." }
    $adopt = $false
    if ($service.Exists -and -not (Test-ALServiceBinary $service.PathName $Config)) {
        # A service installed by hand (or by an earlier procedure) runs another executable path. It is adopted only on request, and only when its
        # arguments are equivalent to the configured ones (data directory, network, TLS, hosts, proxies), so nothing about its runtime changes silently.
        # The comparison is semantic (option order and list order do not matter; every value must match), see Compare-ALServiceArguments.
        $existing = @(Split-ALCommandLine $service.PathName)
        $wanted = @(Get-ALServiceArguments $Config)
        $differences = @(Compare-ALServiceArguments @($existing | Select-Object -Skip 1) $wanted)
        if ($differences.Count -gt 0) {
            Stop-AL ("The service arguments differ from the deployment configuration:`n  - {0}`n  service: {1}`n  config:  {2}`nAlign deploy.local.json with the running service (or apply the configuration with -Action InstallService -Reconfigure -Yes)." -f ($differences -join "`n  - "), (($existing | Select-Object -Skip 1) -join ' '), ($wanted -join ' '))
        }
        if (-not $AdoptService) { Stop-AL "Service $($Config.ServiceName) runs $($existing[0]), not the managed release link. Review -Action Status and deploy once with -AdoptService to bring it under managed releases (its account and arguments are kept)." }
        $adopt = $true
    }
    $newExe = Join-AL (Join-AL $ReleaseFolder 'server') $script:Exe
    $schema = Invoke-ALMaintenance $newExe @('--schema-info', '--data-dir', $Config.DataDirectory)
    if (-not $schema.compatible) { Stop-AL ('The data directory was written by a newer AuthLens build (unknown migrations: {0}); this release would refuse it.' -f (@($schema.unknown_applied) -join ', ')) }
    if ($RequireRollback -and ($service.Exists -or $previous)) {
        if (-not $previous -or -not (Test-ALPathWithin $previous $Config.ReleasesRoot) -or -not (Test-ALPublishedRelease $previous).Verified) { Stop-AL 'The previous managed release must verify before an installer update.' }
        $oldManifest=Get-Content -LiteralPath (Join-AL $previous 'build-manifest.json') -Raw | ConvertFrom-Json
        Assert-ALInstallerUpgradeIdentity $oldManifest $manifest
        $oldSchema = Invoke-ALMaintenance (Join-AL $previous 'server\AuthLens.Api.exe') @('--schema-info', '--data-dir', $Config.DataDirectory)
        if (-not $oldSchema.compatible -or @($schema.pending).Count -gt 0) { Stop-AL 'Installer update cannot prove binary rollback across a schema change. Use a separately approved migration/recovery procedure; nothing was stopped.' }
        if ($service.Exists -and $service.Account -ine $Config.ServiceAccount) { Stop-AL 'The configured service identity differs; installer updates never reconfigure credentials or service accounts.' }
    }
    $journal = [pscustomobject]@{
        run = $script:RunId; commit = $Commit; version = $manifest.version; to_release = $ReleaseFolder; from_release = $previous
        service_state_before = $service.State; applied_before = @($schema.applied); backup = $null; phase = 'prepared'; history = @(); updated = ''
        service_binary_before = $(if ($adopt) { $service.PathName } else { '' }); identity_before = $null
    }
    if ($service.State -eq 'Running') {
        $identity = Invoke-ALConfiguredHttp $Config '/product-version.json'
        if ($identity.Status -eq 200) { $journal.identity_before = $identity.Body | ConvertFrom-Json }
    }
    Write-ALLog ("deploying {0} {1} from {2}; service {3} ({4}); {5} pending migration(s)" -f $manifest.version, $Commit, $(if ($previous) { $previous } else { '(none)' }), $service.State, $service.Account, @($schema.pending).Count)
    if ($DryRun) {
        Write-ALLog 'dry run: no backup, no service change'
        return [pscustomobject]@{ dry_run = $true; plan = $journal }
    }
    Set-ALPhase $Config $journal 'backup'
    if ($schema.database_exists) {
        $backupExe = if ($previous) { Join-AL $previous 'server\AuthLens.Api.exe' } else { $newExe }
        $backup = Invoke-ALMaintenance $backupExe @('--backup-local', $Config.BackupRoot, '--data-dir', $Config.DataDirectory)
        $verified = Invoke-ALMaintenance $backupExe @('--backup-verify', $backup.file, '--data-dir', $Config.DataDirectory)
        if (-not $verified.verified -or $verified.sha256 -ne $backup.sha256) { Stop-AL 'The pre-deployment backup could not be verified; nothing was changed.' 1 }
        $journal.backup = [pscustomobject]@{ file = $backup.file; sha256 = $backup.sha256; size = $backup.size }
        Write-ALLog "pre-deployment backup verified: $($backup.file)"
    }
    $completed = $false
    try {
        if ($service.Exists) {
            Set-ALPhase $Config $journal 'stopping'
            Stop-ALService $Config.ServiceName ([int]$Config.StopTimeoutSeconds)
        }
        Set-ALPhase $Config $journal 'switched'
        Set-ALLink $link $ReleaseFolder
        if ($adopt) { Set-ALServiceBinary $Config.ServiceName (Get-ALBinaryPath $Config) }
        if ($FirstInstall -and -not $service.Exists) { Install-ALService $Config }
        Set-ALPhase $Config $journal 'starting'
        Start-ALService $Config.ServiceName
        Set-ALPhase $Config $journal 'verifying'
        $ready = Wait-ALReady $Config $Commit $manifest.version
        Set-ALPhase $Config $journal 'complete'
        $completed = $true
        Write-ALLog "deployed $($manifest.version) $Commit; service process $($ready.process_id) is ready"
        return [pscustomobject]@{ deployed = $true; release = $ReleaseFolder; identity = $ready.identity; backup = $journal.backup }
    }
    catch [DeployException] {
        Write-ALLog "deployment failed: $($_.Exception.Message)"
        if ($previous -or $adopt) { Invoke-ALRollbackCore $Config $journal $previous; $completed = $true; Stop-AL "Deployment failed and was rolled back: $($_.Exception.Message)" 1 }
        Set-ALPhase $Config $journal 'manual_recovery_required'
        Write-ALRecoveryInstructions $Config $journal "first deployment failed: $($_.Exception.Message)"
        $completed = $true
        throw
    }
    finally {
        # Ctrl+C or a terminating error outside the handled path: return to the previous release if one exists, otherwise leave a recovery note.
        if (-not $completed -and $journal.phase -in $script:CriticalPhases) {
            try { if ($previous -or $adopt) { Invoke-ALRollbackCore $Config $journal $previous } } catch { Write-ALLog "automatic rollback after interruption failed: $($_.Exception.Message)" }
        }
    }
}

# -Preview runs every check of the real recovery but never starts the service or writes the journal (D-006); a stopped service is reported
# as the start Resume would perform, and readiness is then not proven.
# -CertificateFile/-CertificatePasswordFile (G-007): the candidate is proven with the replacement certificate instead of the configured one, and the
# replacement is applied through the recorded configuration transaction (create-only import, service read, configuration and command line,
# restart, pinned readiness; any failure restores the previous certificate) before the journal is completed.
function Confirm-ALCandidateRecovery($Config,$Journal,[switch]$StartStoppedService,[switch]$Preview,[string]$CertificateFile='',[string]$CertificatePasswordFile='') {
    Assert-ALInstallerServerConfiguration $Config
    $fingerprint=(Get-FileHash -LiteralPath $Config.ConfigFile -Algorithm SHA256).Hash
    $stored=Read-AuthLensSettings $Config.ConfigFile -Packaged
    foreach($field in @('Root','DataDirectory','ReleasesRoot','BackupRoot','WorkRoot','ServiceName','ServiceAccount')){if($stored.$field -ine $Config.$field){Stop-AL 'Recovery configuration changed after selection; repeat inspection.' 4}}
    if(@(Compare-ALServiceArguments @(Get-ALServiceArguments $stored) @(Get-ALServiceArguments $Config)).Count){Stop-AL 'Recovery service arguments changed after configuration selection.' 4}
    $null=Assert-ALAclPlan (Get-ALAclPlan $Config) 'Candidate recovery'
    $candidate=[IO.Path]::GetFullPath($Journal.to_release)
    Assert-ALInstallerPath $candidate
    if(-not(Test-ALPathWithin $candidate $Config.ReleasesRoot) -or (Get-ALLink (Get-ALCurrentLink $Config)) -ine $candidate -or -not(Test-ALPublishedRelease $candidate).Verified){Stop-AL 'Candidate recovery requires the unchanged verified owned release pointer.' 4}
    $manifest=Get-Content -LiteralPath (Join-AL $candidate 'build-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($manifest.product -cne 'AuthLens' -or $manifest.source_sha -cne $Journal.commit -or $manifest.version -cne $Journal.version){Stop-AL 'Candidate recovery manifest and original transaction identity disagree.' 4}
    $service=Get-ALService $Config.ServiceName
    if(-not $service.Exists -or $service.Account -ine $Config.ServiceAccount -or -not(Test-ALServiceBinary $service.PathName $Config)){Stop-AL 'Candidate recovery requires the original owned service identity and matching configuration.' 4}
    $instance=''
    if(-not $Journal.from_release){
        $marker=Join-AL $Config.DataDirectory '.authlens-owned-data.json'
        if(-not(Test-Path -LiteralPath $marker -PathType Leaf)){Stop-AL 'Fresh recovery requires retained application-data ownership evidence; data is never adopted.' 4}
        $owned=Get-Content -LiteralPath $marker -Raw -Encoding UTF8|ConvertFrom-Json
        if($owned.schema -ne 1 -or $owned.product -cne 'AuthLens' -or $owned.root -ine $Config.Root -or $owned.data_directory -ine $Config.DataDirectory -or $owned.instance_id -notmatch '^[a-f0-9]{32}$'){Stop-AL 'Fresh recovery data ownership evidence is invalid.' 4}
        $instance=$owned.instance_id
    }else{
        Assert-ALRecoveryBackup $Config $Journal
    }
    $exe=Join-AL $candidate 'server/AuthLens.Api.exe'
    $proven=$Config
    if($CertificateFile){
        Assert-ALCertificateInput $CertificateFile $CertificatePasswordFile
        $proven=Copy-ALConfig $Config @{CertificatePath=$CertificateFile;CertificatePasswordFile=$CertificatePasswordFile}
    }
    $probe=Invoke-ALMaintenance $exe (@('--server-preflight')+@(Get-ALServiceArguments $proven))
    if(-not $probe.validated -or -not $probe.read_only -or $probe.data_modified -ne $false -or $probe.source_sha -cne $Journal.commit -or $probe.version -cne $Journal.version -or -not $probe.schema.compatible -or @($probe.schema.pending).Count){Stop-AL 'Candidate recovery could not prove read-only TLS, key and database/schema compatibility.' 4}
    if($service.State -ne 'Running' -and -not($service.State -eq 'Stopped' -and $StartStoppedService)){Stop-AL 'Candidate is not running; explicit Resume is required to start an existing stopped service.' 4}
    if($Preview){
        $ready=$null
        # With a replacement certificate the current listener still serves the configured one; readiness is proven after the switch.
        if($service.State -eq 'Running' -and -not $CertificateFile){$ready=Wait-ALReady $Config $Journal.commit $Journal.version}
        $plan=[ordered]@{would_succeed=$true;would_phase='complete';would_start_service=($service.State -ne 'Running');readiness_verified=[bool]$ready
            release=$candidate;identity=$(if($ready -and $ready.PSObject.Properties['identity']){$ready.identity}else{$null});instance_id=$instance}
        if($CertificateFile){
            $plan.would_replace_certificate=$true;$plan.would_restart_service=$true
            $plan.certificate_current=ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $Config $exe)
            $plan.certificate_proposed=ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $proven $exe)
            $plan.client_trust_notice=Get-ALCertificateTrustNotice $plan.certificate_current $plan.certificate_proposed
        }
        return [pscustomobject]$plan
    }
    if($CertificateFile){
        $currentCertificate=ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $Config $exe)
        $tls=Copy-ALServerTlsMaterial $proven (Join-AL (Join-AL $Config.Root 'tls') ('renew-'+[guid]::NewGuid().ToString('N')))
        $next=Copy-ALConfig $Config @{CertificatePath=$tls.certificate;CertificatePasswordFile=$tls.password_file}
        $copy=Invoke-ALMaintenance $exe (@('--server-preflight')+@(Get-ALServiceArguments $next))
        if(-not $copy.validated -or -not $copy.read_only){Stop-AL 'The imported certificate copy did not validate; the service was not changed and the copy was retained for review.' 4}
        Write-ALLog "recovery: replacing the certificate of candidate $($Journal.run)"
        $applied=Invoke-ALConfigurationTransaction $Config $next @{CertificatePath=$tls.certificate;CertificatePasswordFile=$tls.password_file} 'recovery certificate replacement' ([pscustomobject]@{service=$service;manifest=$manifest})
        Set-ALPhase $Config $Journal 'complete'
        $proposed=ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $next $exe)
        return [pscustomobject]@{recovered=$true;phase='complete';release=$candidate;identity=$applied.identity;instance_id=$instance;action='candidate revalidated with a replacement certificate';data_restored=$false
            certificate_replaced=$true;certificate=$tls.certificate;public_certificate=$tls.public_certificate;previous_certificate_retained=$Config.CertificatePath;trust_store_modified=$false
            certificate_previous=$currentCertificate;certificate_active=$proposed;client_trust_notice=(Get-ALCertificateTrustNotice $currentCertificate $proposed)}
    }
    if($service.State -eq 'Stopped' -and $StartStoppedService){Start-ALService $Config.ServiceName}
    $ready=Wait-ALReady $Config $Journal.commit $Journal.version
    if((Get-FileHash -LiteralPath $Config.ConfigFile -Algorithm SHA256).Hash -ine $fingerprint){Stop-AL 'Recovery configuration changed during candidate verification; completion was refused.' 4}
    Set-ALPhase $Config $Journal 'complete'
    [pscustomobject]@{recovered=$true;phase='complete';release=$candidate;identity=$ready.identity;instance_id=$instance;action='candidate revalidated';data_restored=$false}
}

function Assert-ALRecoveryBackup($Config,$Journal) {
    if(-not $Journal.backup -or -not(Test-ALPathWithin $Journal.backup.file $Config.BackupRoot) -or $Journal.backup.sha256 -notmatch '^[a-f0-9]{64}$'){Stop-AL 'Recovery requires original verified backup evidence; no backup was inferred.' 4}
    Test-ALPathTree $Journal.backup.file
    if((Get-FileHash -LiteralPath $Journal.backup.file -Algorithm SHA256).Hash -ine $Journal.backup.sha256){Stop-AL 'Recorded recovery backup integrity changed.' 4}
    $current=Get-ALLink (Get-ALCurrentLink $Config)
    $proof=Invoke-ALMaintenance (Join-AL $current 'server/AuthLens.Api.exe') @('--backup-verify',$Journal.backup.file,'--data-dir',$Config.DataDirectory)
    if(-not $proof.verified -or $proof.sha256 -ine $Journal.backup.sha256){Stop-AL 'Recovery backup could not be verified with the retained key.' 4}
}

# The recovery decision for a journal and a requested action, without side effects. Invoke-ALRecover executes it; Get-ALRecoveryPreview evaluates
# it read-only (-DryRun); Get-ALRecoveryOptions lists the actions a journal state allows. A finished journal is never reopened: an explicit action
# on it reports that nothing is to recover instead of re-verifying (and, on a refusal, downgrading) a completed deployment.
function Resolve-ALRecoveryDecision($Config,$Journal,[string]$RecoveryAction='Auto') {
    if (-not $Journal) { return [pscustomobject]@{ kind = 'none'; reason = 'no journal' } }
    $adopted=[bool]($Journal.PSObject.Properties['service_binary_before'] -and $Journal.service_binary_before)
    if ($Journal.phase -in $script:FinalPhases) { return [pscustomobject]@{ kind = 'none'; reason = "the last deployment $($Journal.run) ended in '$($Journal.phase)'"; phase = $Journal.phase } }
    if($RecoveryAction -eq 'Cancel' -and $Journal.phase -notin @('prepared','backup')){return [pscustomobject]@{kind='refuse';reason='Recovery cancellation is unavailable after a release or service may have changed; evidence was preserved.'}}
    if($RecoveryAction -in @('VerifyCandidate','Resume') -or ($RecoveryAction -eq 'Auto' -and -not $Journal.from_release -and -not $adopted -and $Journal.phase -in $script:CriticalPhases)){
        return [pscustomobject]@{kind='candidate';reason='revalidate the installed candidate';start=($RecoveryAction -eq 'Resume')}
    }
    if($Journal.phase -eq 'manual_recovery_required' -and $RecoveryAction -ne 'Rollback'){return [pscustomobject]@{kind='refuse';reason='Manual recovery requires an explicit VerifyCandidate, Resume or verified Rollback decision.'}}
    if($RecoveryAction -eq 'Rollback'){return [pscustomobject]@{kind='rollback';reason='return to the verified previous release'}}
    if ($Journal.phase -in @('prepared', 'backup')) { return [pscustomobject]@{ kind = 'abort'; reason = 'the deployment stopped before any release or service change'; cancel = ($RecoveryAction -eq 'Cancel') } }
    if (-not $Journal.from_release -and -not $adopted) { return [pscustomobject]@{ kind = 'manual'; reason = 'an interrupted first deployment has no previous release to return to' } }
    [pscustomobject]@{ kind = 'auto_rollback'; reason = 'return to the previous release of the interrupted update' }
}

function Assert-ALRecoveryRollback($Config,$Journal) {
    if(-not $Journal.from_release -or -not(Test-ALPathWithin $Journal.from_release $Config.ReleasesRoot) -or -not(Test-ALPublishedRelease $Journal.from_release).Verified){Stop-AL 'Rollback is unavailable without a verified previous release.' 4}
    Assert-ALRecoveryBackup $Config $Journal
}

function Assert-ALRecoveryCancel($Config,$Journal) {
    $adopted=$Journal.PSObject.Properties['service_binary_before'] -and $Journal.service_binary_before
    $observed=Get-ALService $Config.ServiceName
    if((Get-ALLink (Get-ALCurrentLink $Config)) -ine $Journal.from_release -or
        ($observed.Exists -and $Journal.service_state_before -eq 'Missing') -or
        ($observed.Exists -and -not(Test-ALServiceBinary $observed.PathName $Config) -and (-not $adopted -or $observed.PathName -ine $Journal.service_binary_before))){Stop-AL 'Cancellation found changed service or release identity; explicit recovery review is required.' 4}
}

function Invoke-ALRecover($Config,[ValidateSet('Auto','VerifyCandidate','Resume','Rollback','Cancel')][string]$RecoveryAction='Auto',[string]$CertificateFile='',[string]$CertificatePasswordFile='') {
    Assert-ALNoPendingRepair $Config
    # An interrupted configuration change (also a recovery certificate step) is restored before any journal decision.
    $restored = Invoke-ALConfigurationRecover $Config 'an interrupted configuration change was found before recovery'
    if ($restored) { return $restored }
    $journal = Read-ALJournal $Config
    $decision = Resolve-ALRecoveryDecision $Config $journal $RecoveryAction
    if ($CertificateFile -and $decision.kind -ne 'candidate') { Stop-AL 'A replacement certificate applies only to candidate recovery (VerifyCandidate or Resume) of an interrupted deployment.' 4 }
    switch ($decision.kind) {
        'none' {
            Write-ALLog "nothing to recover: $($decision.reason)"
            if (-not $journal) { return [pscustomobject]@{ recovered = $false; reason = 'no journal' } }
            return [pscustomobject]@{ recovered = $false; phase = $journal.phase }
        }
        'refuse' { Stop-AL $decision.reason 4 }
        'candidate' {
            try{return Confirm-ALCandidateRecovery $Config $journal -StartStoppedService:$decision.start -CertificateFile $CertificateFile -CertificatePasswordFile $CertificatePasswordFile}
            catch{Set-ALPhase $Config $journal 'manual_recovery_required';Write-ALRecoveryInstructions $Config $journal 'Candidate verification refused; review the latest sanitized operation result.';throw}
        }
        'rollback' {
            Assert-ALRecoveryRollback $Config $journal
            Invoke-ALRollbackCore $Config $journal $journal.from_release
            return [pscustomobject]@{recovered=$true;phase='rolled_back';release=$journal.from_release}
        }
        'abort' {
            if ($decision.cancel) { Assert-ALRecoveryCancel $Config $journal }
            Set-ALPhase $Config $journal 'aborted'
            $service = Get-ALService $Config.ServiceName
            if ($service.Exists -and $service.State -eq 'Stopped' -and $journal.service_state_before -eq 'Running') { Start-ALService $Config.ServiceName }
            return [pscustomobject]@{ recovered = $true; phase = 'aborted' }
        }
        'manual' {
            Set-ALPhase $Config $journal 'manual_recovery_required'
            Write-ALRecoveryInstructions $Config $journal $decision.reason
            Stop-AL 'Interrupted first deployment: see RECOVERY-REQUIRED.txt.' 4
        }
    }
    Invoke-ALRollbackCore $Config $journal $journal.from_release
    [pscustomobject]@{ recovered = $true; phase = 'rolled_back'; release = $journal.from_release }
}

# The explicit recovery actions a journal state allows, from the same decision as Invoke-ALRecover plus the observable prerequisites (service
# state, previous release, recorded backup). Read-only; the expensive checks run in Get-ALRecoveryPreview for the chosen action.
function Get-ALRecoveryOptions($Config,$Journal) {
    $service = Get-ALService $Config.ServiceName
    foreach ($action in 'VerifyCandidate', 'Resume', 'Rollback', 'Cancel') {
        $decision = Resolve-ALRecoveryDecision $Config $Journal $action
        $available = $decision.kind -notin @('none', 'refuse'); $reason = $decision.reason
        if ($available -and $action -eq 'VerifyCandidate' -and $service.State -ne 'Running') { $available = $false; $reason = 'the service is not running (use Resume)' }
        if ($available -and $action -eq 'Resume' -and $service.State -ne 'Stopped') { $available = $false; $reason = 'the service is not stopped' }
        if ($available -and $action -eq 'Rollback' -and (-not $Journal.from_release -or -not $Journal.backup)) { $available = $false; $reason = 'no previous release with recorded backup evidence' }
        [pscustomobject]@{ action = $action; available = [bool]$available; reason = $reason }
    }
}

# -Action Recover -DryRun: evaluates the recovery Invoke-ALRecover would perform with every read-only check and reports it as a simulation. It
# never writes the journal or recovery notes, restores a configuration, starts, stops or reconfigures the service, or switches releases.
function Get-ALRecoveryPreview($Config,[ValidateSet('Auto','VerifyCandidate','Resume','Rollback','Cancel')][string]$RecoveryAction='Auto',[string]$CertificateFile='',[string]$CertificatePasswordFile='') {
    Assert-ALNoPendingRepair $Config
    $journal = Read-ALJournal $Config
    $base = [ordered]@{ dry_run = $true; requested_action = $RecoveryAction; journal_run = $(if ($journal) { $journal.run } else { $null }); journal_phase = $(if ($journal) { $journal.phase } else { $null })
        history = @(if ($journal -and $journal.PSObject.Properties['history']) { @($journal.history) | ForEach-Object { $_.phase } })
        from_release = $(if ($journal) { $journal.from_release } else { $null }); to_release = $(if ($journal) { $journal.to_release } else { $null })
        options = @(if ($journal) { Get-ALRecoveryOptions $Config $journal }) }
    $pending = Get-ALPendingConfigurationRecord $Config
    if ($pending) {
        $base.would_action = "restore the interrupted $($pending.record.operation) (previous configuration and command line, service restart)"
        $base.would_succeed = $true; $base.pending_configuration_change = $pending.record.operation
        return [pscustomobject]$base
    }
    $decision = Resolve-ALRecoveryDecision $Config $journal $RecoveryAction
    $base.decision = $decision.kind; $base.would_action = $decision.reason
    if ($CertificateFile -and $decision.kind -ne 'candidate') { $base.would_succeed = $false; $base.blocking_reason = 'A replacement certificate applies only to candidate recovery (VerifyCandidate or Resume) of an interrupted deployment.'; return [pscustomobject]$base }
    try {
        switch ($decision.kind) {
            'none' { $base.would_succeed = $true; $base.would_phase = $base.journal_phase }
            'refuse' { $base.would_succeed = $false; $base.blocking_reason = $decision.reason }
            'candidate' { $check = Confirm-ALCandidateRecovery $Config $journal -StartStoppedService:$decision.start -Preview -CertificateFile $CertificateFile -CertificatePasswordFile $CertificatePasswordFile; foreach ($p in $check.PSObject.Properties) { $base[$p.Name] = $p.Value } }
            'rollback' { Assert-ALRecoveryRollback $Config $journal; $base.would_succeed = $true; $base.would_phase = 'rolled_back' }
            'abort' { if ($decision.cancel) { Assert-ALRecoveryCancel $Config $journal }; $base.would_succeed = $true; $base.would_phase = 'aborted' }
            'manual' { $base.would_succeed = $false; $base.would_phase = 'manual_recovery_required'; $base.blocking_reason = $decision.reason }
            default { $base.would_succeed = $true; $base.would_phase = 'rolled_back' }
        }
    } catch {
        # The real run would refuse here (and, for a candidate, record manual_recovery_required); the preview records nothing.
        $base.would_succeed = $false; $base.blocking_reason = $_.Exception.Message
    }
    [pscustomobject]$base
}

# ---- simulation policy (-DryRun, D-006)

# Every Deploy-AuthLens action is classified once. read_only actions never change anything; simulated actions implement -DryRun as a read-only
# evaluation; any other changing action refuses -DryRun instead of running for real. -DryRun never replaces -Yes: without -DryRun an approval
# action needs -Yes, and -DryRun with -Yes is still only a simulation.
$script:ReadOnlyActions = @('Status', 'Health', 'AuditAcl')
$script:SimulatedActions = @('Deploy', 'Recover', 'ReplaceCertificate', 'ChangeNetwork', 'ProtectAcl')
$script:ApprovalActions = @('Deploy', 'InstallService', 'Restore', 'Rollback', 'Recover', 'ReplaceCertificate', 'ChangeNetwork', 'ProtectAcl', 'RestoreAcl')

function Get-ALActionPolicy([string]$Action, [switch]$DryRun, [switch]$Yes) {
    if ($Action -in $script:ReadOnlyActions) { return [pscustomobject]@{ action = $Action; mode = 'read_only'; approval_required = $false } }
    if ($DryRun) {
        if ($Action -notin $script:SimulatedActions) { Stop-AL "-DryRun is not supported for $Action; nothing was run or changed. Review -Action Status (and AuditAcl) instead, then run $Action with -Yes." 2 }
        return [pscustomobject]@{ action = $Action; mode = 'simulate'; approval_required = $false }
    }
    $approval = $Action -in $script:ApprovalActions
    if ($approval -and -not $Yes) { Stop-AL "$Action changes the service or its permissions; repeat with -Yes after reviewing -Action Status or -Action AuditAcl (or -DryRun where supported)." }
    [pscustomobject]@{ action = $Action; mode = 'execute'; approval_required = $approval }
}

function Get-ALFileFingerprint([string]$Path) {
    try { if ([IO.File]::Exists($Path)) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } } catch { return 'unreadable' }
    'missing'
}

# The persistent installation state a simulation must leave unchanged: deployment state files (journal, pending records, firewall receipts,
# recovery notes), configuration, installed-product record, release pointer and release folders, TLS and key folder names, the service
# registration and process, and the Setup registry values. Application data is excluded because the running service writes it.
function Get-ALStateSnapshot($Config) {
    $state = [ordered]@{}
    $state['config'] = Get-ALFileFingerprint $Config.ConfigFile
    $state['installed-product'] = Get-ALFileFingerprint (Join-AL (Join-AL $Config.Root 'config') 'installed-product.json')
    try {
        if (Test-Path -LiteralPath $Config.WorkRoot) {
            foreach ($item in @(Get-ChildItem -LiteralPath $Config.WorkRoot -Force | Sort-Object Name)) {
                if ($item.PSIsContainer) { $state["work:$($item.Name)/"] = @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue).Count }
                elseif ($item.Name -ne 'deployment.lock') { $state["work:$($item.Name)"] = Get-ALFileFingerprint $item.FullName }
            }
        } else { $state['work'] = 'missing' }
    } catch { $state['work'] = 'unreadable' }
    try { $state['current'] = [string](Get-ALLink (Get-ALCurrentLink $Config)) } catch { $state['current'] = 'unreadable' }
    foreach ($folder in @($Config.ReleasesRoot, (Join-AL $Config.Root 'tls'), (Join-AL $Config.Root 'keys'))) {
        try { $state["dir:$folder"] = (@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop | ForEach-Object { $_.Name } | Sort-Object) -join '|') } catch { $state["dir:$folder"] = 'missing' }
    }
    try { $service = Get-ALService $Config.ServiceName; $state['service'] = "$($service.Exists)|$($service.State)|$($service.Account)|$($service.PathName)|$($service.ProcessId)" } catch { $state['service'] = 'unreadable' }
    try {
        $registry = Get-ItemProperty -LiteralPath 'HKLM:\Software\AuthLens\Server' -ErrorAction Stop
        $state['registry'] = (@($registry.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "$($_.Name)=$($_.Value)" } | Sort-Object) -join '|')
    } catch { $state['registry'] = 'missing' }
    $state
}

function Compare-ALStateSnapshot($Before, $After) {
    @(@($Before.Keys) + @($After.Keys) | Select-Object -Unique | Where-Object { "$($Before[$_])" -cne "$($After[$_])" })
}

function Invoke-ALRollback($Config, [string]$ToRelease) {
    Assert-ALNoPendingRepair $Config
    $journal = Read-ALJournal $Config
    if ($journal -and $journal.phase -in $script:CriticalPhases) { Stop-AL 'A deployment is in progress or interrupted; run -Action Recover.' }
    $target = if ($ToRelease) { $ToRelease } elseif ($journal -and $journal.from_release) { $journal.from_release } else { '' }
    if (-not $target -or -not (Test-Path -LiteralPath (Join-AL $target 'build-manifest.json'))) { Stop-AL 'No previous release to roll back to; pass -ToRelease <release folder>.' }
    $current = Get-ALLink (Get-ALCurrentLink $Config)
    $schema = Invoke-ALMaintenance (Join-AL (Join-AL $current 'server') $script:Exe) @('--schema-info', '--data-dir', $Config.DataDirectory)
    $rollback = [pscustomobject]@{ run = $script:RunId; commit = ''; version = ''; to_release = $target; from_release = $target; service_state_before = (Get-ALService $Config.ServiceName).State
        applied_before = @($schema.applied); backup = $null; phase = 'stopping'; history = @(); updated = '' }
    Write-ALJournal $Config $rollback
    Invoke-ALRollbackCore $Config $rollback $target
    [pscustomobject]@{ rolled_back = $true; release = $target }
}

# ---- installation root

# Creates the installation root on first use with a protected DACL (SYSTEM and Administrators only; it does not inherit %ProgramData%'s grants to
# Users) and its subfolders, which inherit it. The service account's grants are added per subfolder by Grant-ALAccess. An existing root is never
# changed here: it must already pass the NTFS audit (-Action AuditAcl; prepare it explicitly with -Action ProtectAcl).
function Initialize-ALInstallation($Config) {
    $root = $Config.Root
    if (Test-ALAclForbidden $root) { Stop-AL "Root $root is a system location; choose a dedicated folder such as C:\ProgramData\AuthLens." }
    $layout = Get-ALInstallLayout $root
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
        $result = Invoke-ALProcess 'icacls.exe' @($root, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F') ''
        if ($result.ExitCode -ne 0) { Stop-AL "icacls could not protect $root; it was left empty for inspection." 1 }
        Write-ALLog "created $root with a protected DACL (SYSTEM, Administrators)"
    } else {
        $report = Get-ALAclReport (Get-ALAclPlan $Config)
        if (-not $report.safe) { Stop-AL "$root grants broad access; review it with -Action AuditAcl and prepare it with -Action ProtectAcl: $(Format-ALAclFindings $report)" }
    }
    foreach ($folder in $layout.ReleasesRoot, $layout.DataDirectory, $layout.ConfigRoot, $layout.TlsRoot, $layout.KeyRoot, $layout.BackupRoot, $layout.WorkRoot) {
        if ((Test-ALPathOverlap $folder $root) -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    }
    foreach($folder in @($Config.DataDirectory,$Config.ReleasesRoot,$Config.BackupRoot,$Config.WorkRoot)|Select-Object -Unique){
        if(Test-Path -LiteralPath $folder){continue}
        # Advanced storage may be outside Root. Never change an existing shared parent's ACL.
        $boundary=$folder
        while(-not(Test-Path -LiteralPath (Split-Path $boundary))){$boundary=Split-Path $boundary}
        Assert-ALInstallerPath $boundary
        New-ALSecureDirectory $folder @($boundary)
    }
}

# ---- installed configuration changes (network settings and certificate replacement)

# One recorded transaction for changes to an installed Server's deployment configuration. configuration-pending.json (deployment state) holds the
# previous configuration bytes, their hash and the previous service command line while a change is in flight; the next change or -Action
# Recover restores it first. An earlier pre-release name (certificate-pending.json) is still recognized.
function Get-ALConfigurationPendingPath($Config) { Join-AL $Config.WorkRoot 'configuration-pending.json' }
function Get-ALCertificatePendingPath($Config) { Join-AL $Config.WorkRoot 'certificate-pending.json' }
function Get-ALPendingConfigurationRecord($Config) {
    foreach ($path in (Get-ALConfigurationPendingPath $Config), (Get-ALCertificatePendingPath $Config)) {
        if (Test-Path -LiteralPath $path) { return [pscustomobject]@{ path = $path; record = ([IO.File]::ReadAllText($path) | ConvertFrom-Json) } }
    }
    $null
}

# A shallow copy of the configuration with selected settings replaced; the original object is never changed.
function Copy-ALConfig($Config, [hashtable]$Changes) {
    $copy = [ordered]@{}
    foreach ($property in $Config.PSObject.Properties) { $copy[$property.Name] = $property.Value }
    foreach ($key in $Changes.Keys) { $copy[$key] = $Changes[$key] }
    [pscustomobject]$copy
}

# Replaces a file's bytes through a temporary file in the same directory (atomic on NTFS); no backup copy is left beside it.
function Write-ALReplaceFile([string]$Path, [byte[]]$Bytes) {
    $temporary = $Path + '.next-' + [guid]::NewGuid().ToString('N')
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Replace($temporary, $Path, [NullString]::Value) # $null would become "" (an invalid backup path)
}

# Preconditions shared by every installed configuration change: no interrupted deployment or change, a managed service with the configured
# identity whose command line equals the configuration (no drift), and the current release manifest.
function Assert-ALConfigurationChangeAllowed($Config) {
    Assert-ALNoPendingRepair $Config
    $journal = Read-ALJournal $Config
    if ($journal -and $journal.phase -in $script:CriticalPhases) { Stop-AL 'An interrupted deployment requires -Action Recover before the configuration can be changed.' 4 }
    $service = Get-ALService $Config.ServiceName
    if (-not $service.Exists) { Stop-AL "Service $($Config.ServiceName) is not installed; nothing was changed." }
    if (-not (Test-ALServiceBinary $service.PathName $Config)) { Stop-AL 'The service runs outside the managed release link; the configuration was not changed.' }
    if ($service.Account -ine $Config.ServiceAccount) { Stop-AL 'The service identity differs from the deployment configuration; nothing was changed.' }
    if (@(Compare-ALServiceArguments @(@(Split-ALCommandLine $service.PathName) | Select-Object -Skip 1) @(Get-ALServiceArguments $Config)).Count) {
        Stop-AL 'The service command line differs from the deployment configuration; review it (-Action Status) before changing the configuration.'
    }
    $manifest = Get-Content -LiteralPath (Join-AL (Get-ALLink (Get-ALCurrentLink $Config)) 'build-manifest.json') -Raw | ConvertFrom-Json
    [pscustomobject]@{ service = $service; manifest = $manifest }
}

# Validates a candidate configuration without changing anything: access-mode rules, an address assigned to this machine, a port that is free or
# held by the service itself, and the packaged host's read-only --server-preflight (TLS names for the hosts, key, validity, host/proxy policy).
function Test-ALCandidateConfiguration($Config, $Candidate, $Service) {
    $access = Get-ALServerAccessPlan $Candidate
    if (-not (Test-ALInstallerListenAddress $Candidate.ListenAddress)) { Stop-AL "The listen address $($Candidate.ListenAddress) is not assigned to this machine; nothing was changed." }
    $listeners = @(Get-ALListener $Candidate.ListenAddress ([int]$Candidate.Port))
    if (@($listeners | Where-Object { $_ -and $_ -ne $Service.ProcessId }).Count) { Stop-AL ("Port {0} on {1} is used by process {2}, not by the service; nothing was changed." -f $Candidate.Port, $Candidate.ListenAddress, ($listeners -join ',')) }
    $probe = Invoke-ALMaintenance (Get-ALServiceExe $Config) (@('--server-preflight') + @(Get-ALServiceArguments $Candidate))
    if (-not $probe.validated -or -not $probe.read_only) { Stop-AL 'The packaged Server did not validate the proposed configuration (TLS names, host or proxy policy); nothing was changed.' }
    $access
}

# Applies a validated candidate: records the previous state, replaces the named settings in the configuration file (other settings and formatting
# of values are kept), grants the service identity its read access, switches the command line, restarts and verifies readiness and the release
# identity against the candidate (pinned to its certificate, using its listener and hosts). Optional firewall work runs after readiness through the
# existing owned-firewall transaction. Any failure before that restores the previous configuration and command line and restarts on them.
function Invoke-ALConfigurationTransaction($Config, $Candidate, [hashtable]$Settings, [string]$Operation, $Context, $Firewall = $null) {
    $pending = Get-ALConfigurationPendingPath $Config
    $previousBytes = [IO.File]::ReadAllBytes($Config.ConfigFile)
    $record = [pscustomobject]@{
        schema = 2; operation = $Operation; config_file = $Config.ConfigFile; previous_config = [Convert]::ToBase64String($previousBytes)
        previous_sha256 = (Get-ALInstallerBytesHash $previousBytes); previous_binary = $Context.service.PathName; settings = @($Settings.Keys | Sort-Object)
        started_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-ALInstallerPrivateBytes $pending ([Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Depth 4)))
    Write-ALLog "$Operation started: $(@($Settings.Keys | Sort-Object) -join ', ')"
    try {
        $raw = [Text.Encoding]::UTF8.GetString($previousBytes).TrimStart([char]0xfeff) | ConvertFrom-Json
        foreach ($key in $Settings.Keys) { $raw | Add-Member -NotePropertyName $key -NotePropertyValue $Settings[$key] -Force }
        Write-ALReplaceFile $Config.ConfigFile ([Text.Encoding]::UTF8.GetBytes(($raw | ConvertTo-Json -Depth 5)))
        Grant-ALAccess $Candidate
        Stop-ALService $Config.ServiceName ([int]$Config.StopTimeoutSeconds)
        Set-ALServiceBinary $Config.ServiceName (Get-ALBinaryPath $Candidate)
        Start-ALService $Config.ServiceName
        $ready = Wait-ALReady $Candidate $Context.manifest.source_sha $Context.manifest.version
    } catch {
        $reason = $_.Exception.Message
        $null = Restore-ALConfigurationChange $Config $record $reason $pending
        Stop-AL "$Operation failed and the previous configuration was restored: $reason" 1
    }
    [IO.File]::Delete($pending)
    $firewallResult = $null
    if ($Firewall) {
        try { $firewallResult = Invoke-ALInstallerFirewallChange $Candidate $Firewall.sources $Firewall.profiles -Remove:$Firewall.remove -Approved -LockHeld }
        catch { $firewallResult = @{ changed = $false; recovery_required = $true; error = $_.Exception.Message } }
    }
    Write-ALLog "$Operation complete; service process $($ready.process_id) is ready"
    [pscustomobject]@{ changed = $true; operation = $Operation; process_id = $ready.process_id; identity = $(if ($ready.PSObject.Properties['identity']) { $ready.identity } else { $null }); firewall = $firewallResult
        firewall_recovery_required = [bool]($firewallResult -is [hashtable] -and $firewallResult['recovery_required']) }
}

# Restores the configuration bytes and service command line recorded before a configuration change and restarts on them. The record must belong
# to this configuration and its previous bytes must match their hash; otherwise it is retained for manual recovery.
function Restore-ALConfigurationChange($Config, $Record, [string]$Reason, [string]$PendingPath) {
    if ($Record.schema -notin 1, 2 -or [IO.Path]::GetFullPath([string]$Record.config_file) -ine [IO.Path]::GetFullPath($Config.ConfigFile)) { Stop-AL 'The pending configuration record does not belong to this configuration; it was retained for manual recovery.' 4 }
    $bytes = [Convert]::FromBase64String([string]$Record.previous_config)
    if ((Get-ALInstallerBytesHash $bytes) -ine $Record.previous_sha256) { Stop-AL 'The recorded previous configuration is damaged; the pending record was retained for manual recovery.' 4 }
    Write-ALLog "restoring the previous configuration: $Reason"
    Write-ALReplaceFile $Config.ConfigFile $bytes
    $previous = Read-AuthLensSettings $Config.ConfigFile
    $manifest = Get-Content -LiteralPath (Join-AL (Get-ALLink (Get-ALCurrentLink $previous)) 'build-manifest.json') -Raw | ConvertFrom-Json
    Stop-ALService $previous.ServiceName ([int]$previous.StopTimeoutSeconds)
    Set-ALServiceBinary $previous.ServiceName ([string]$Record.previous_binary)
    Start-ALService $previous.ServiceName
    $ready = Wait-ALReady $previous $manifest.source_sha $manifest.version
    [IO.File]::Delete($PendingPath)
    Write-ALLog 'previous configuration restored and ready'
    [pscustomobject]@{ changed = $false; restored_previous = $true; certificate = $previous.CertificatePath; listen_address = $previous.ListenAddress
        port = $previous.Port; process_id = $ready.process_id; reason = $Reason }
}

# Restores an interrupted configuration change, if one is recorded. Returns $null when nothing is pending.
function Invoke-ALConfigurationRecover($Config, [string]$Reason = 'an interrupted configuration change was found') {
    $pending = Get-ALPendingConfigurationRecord $Config
    if (-not $pending) { return $null }
    Restore-ALConfigurationChange $Config $pending.record $Reason $pending.path
}

# Replaces the TLS certificate of the installed Server. The new PFX is validated by the packaged host against the unchanged listener and hosts
# before anything changes, imported create-only into a new protected Root\tls\renew-<id> directory and validated again, then applied through the
# configuration transaction. Previous TLS files are retained; no trusted root is added.
function Invoke-ALReplaceCertificate($Config, [string]$CertificateFile, [string]$PasswordFile, [switch]$DryRun) {
    if (Get-ALPendingConfigurationRecord $Config) {
        if ($DryRun) { Stop-AL 'An interrupted configuration change is recorded; run without -DryRun (or -Action Recover) to restore the previous configuration first.' 4 }
        return Invoke-ALConfigurationRecover $Config
    }
    Assert-ALCertificateInput $CertificateFile $PasswordFile
    $context = Assert-ALConfigurationChangeAllowed $Config
    $candidate = Copy-ALConfig $Config @{ CertificatePath = $CertificateFile; CertificatePasswordFile = $PasswordFile }
    $probe = Invoke-ALMaintenance (Get-ALServiceExe $Config) (@('--server-preflight') + @(Get-ALServiceArguments $candidate))
    if (-not $probe.validated -or -not $probe.read_only) { Stop-AL 'The packaged Server did not validate the new certificate for the configured hosts; nothing was changed.' }
    $currentCertificate = ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $Config)
    $proposedCertificate = ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $candidate)
    $notice = Get-ALCertificateTrustNotice $currentCertificate $proposedCertificate
    if ($DryRun) { return [pscustomobject]@{ dry_run = $true; certificate_validated = $true; service = $Config.ServiceName; restart_required = $true; network_changed = $false
        certificate_current = $currentCertificate; certificate_proposed = $proposedCertificate; client_trust_notice = $notice } }
    $tls = Copy-ALServerTlsMaterial $candidate (Join-AL (Join-AL $Config.Root 'tls') ('renew-' + [guid]::NewGuid().ToString('N')))
    $next = Copy-ALConfig $Config @{ CertificatePath = $tls.certificate; CertificatePasswordFile = $tls.password_file }
    $probe = Invoke-ALMaintenance (Get-ALServiceExe $Config) (@('--server-preflight') + @(Get-ALServiceArguments $next))
    if (-not $probe.validated -or -not $probe.read_only) { Stop-AL 'The imported certificate copy did not validate; the service was not changed and the copy was retained for review.' 4 }
    $result = Invoke-ALConfigurationTransaction $Config $next @{ CertificatePath = $tls.certificate; CertificatePasswordFile = $tls.password_file } 'certificate replacement' $context
    $result | Add-Member -NotePropertyName replaced -NotePropertyValue $true
    $result | Add-Member -NotePropertyName certificate -NotePropertyValue $tls.certificate
    $result | Add-Member -NotePropertyName public_certificate -NotePropertyValue $tls.public_certificate
    $result | Add-Member -NotePropertyName previous_certificate_retained -NotePropertyValue $Config.CertificatePath
    $result | Add-Member -NotePropertyName trust_store_modified -NotePropertyValue $false
    $result | Add-Member -NotePropertyName network_changed -NotePropertyValue $false
    $result | Add-Member -NotePropertyName certificate_previous -NotePropertyValue $currentCertificate
    $result | Add-Member -NotePropertyName certificate_active -NotePropertyValue $proposedCertificate
    $result | Add-Member -NotePropertyName client_trust_notice -NotePropertyValue $notice
    $result
}

# ---- TLS certificate lifecycle (WP20)

function Assert-ALCertificateInput([string]$CertificateFile, [string]$PasswordFile) {
    foreach ($file in $CertificateFile, $PasswordFile) {
        if (-not $file -or -not [IO.Path]::IsPathRooted($file) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-AL 'A certificate change needs -CertificateFile <absolute .pfx file> and -CertificatePasswordFile <absolute protected password file>.' }
        if ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { Stop-AL 'Certificate files must not be reparse points; nothing was changed.' }
    }
    if ([IO.Path]::GetExtension($CertificateFile) -notin @('.pfx', '.p12')) { Stop-AL 'Certificate replacement requires a PFX/PKCS12 file; nothing was changed.' }
}

# The packaged host's read-only description of the configured (or proposed) certificate against the shared endpoint-identity rule; $null when the
# release predates --certificate-info or the certificate cannot be opened.
function Get-ALCertificateInfo($Config, [string]$Exe = '') {
    if (-not $Exe) { $Exe = Get-ALServiceExe $Config }
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $null }
    Invoke-ALMaintenance $Exe (@('--certificate-info') + @(Get-ALServiceArguments $Config)) -AllowUnsupported
}

function ConvertTo-ALCertificateSummary($Info) {
    if (-not $Info -or -not $Info.PSObject.Properties['thumbprint_sha256']) { return $null }
    $value = { param($Name) if ($Info.PSObject.Properties[$Name]) { $Info.$Name } else { $null } }
    [pscustomobject]@{ subject = (& $value 'subject'); issuer = (& $value 'issuer'); self_signed = [bool](& $value 'self_signed'); not_after_utc = (& $value 'not_after_utc'); days_remaining = (& $value 'days_remaining')
        thumbprint_sha256 = $Info.thumbprint_sha256; dns_names = @(& $value 'dns_names' | Where-Object { $_ }); ip_addresses = @(& $value 'ip_addresses' | Where-Object { $_ }); missing_identities = @(& $value 'missing_identities' | Where-Object { $_ })
        usable = [bool](& $value 'usable'); warnings = @(& $value 'warnings' | Where-Object { $_ }) }
}

# What a certificate change means for clients. Trust stores are never changed; distribution is an administrator decision.
function Get-ALCertificateTrustNotice($Current, $Proposed) {
    if (-not $Proposed) { return 'The new certificate could not be described; review it before applying.' }
    if ($Current -and $Current.thumbprint_sha256 -eq $Proposed.thumbprint_sha256) { return 'The certificate is unchanged; client trust is not affected.' }
    $old = if ($Current) { $Current.thumbprint_sha256 } else { 'unknown' }
    $text = "The server certificate changes from SHA-256 $old to $($Proposed.thumbprint_sha256). Clients that trusted the previous certificate by its fingerprint will ask for trust again."
    if ($Proposed.self_signed) { $text + ' The new certificate is self-signed: distribute its public .cer (never the PFX or its password) through an approved channel such as Group Policy (Trusted People or Trusted Root, per your policy), or replace it with a certificate from your internal CA. AuthLens does not change any trust store.' }
    else { $text + " It is issued by '$($Proposed.issuer)': clients that already trust that CA need no change. AuthLens does not change any trust store." }
}

# Writes the public certificate of the installed Server (DER .cer) to a new file for client trust distribution; the PFX, its password and keys are
# never exported. Create-only, outside the installation's private folders.
function Export-ALPublicCertificate($Config, [string]$Destination) {
    if (-not $Destination -or -not [IO.Path]::IsPathRooted($Destination)) { Stop-AL 'Select an absolute destination file ending in .cer (-PublicCertificateFile).' }
    $full = [IO.Path]::GetFullPath($Destination)
    foreach ($private in @($Config.DataDirectory, $Config.WorkRoot, (Join-AL $Config.Root 'keys'), (Join-AL $Config.Root 'tls'), $Config.BackupRoot)) {
        if ($private -and (Test-ALPathWithin $full $private)) { Stop-AL 'Export the public certificate outside the installation''s private folders.' }
    }
    $exe = Get-ALServiceExe $Config
    $result = Invoke-ALMaintenance $exe (@('--certificate-export-public', $full) + @(Get-ALServiceArguments $Config))
    if (-not $result.exported -or $result.private_key_included) { Stop-AL 'The public certificate export was refused.' }
    $result
}

# The network settings a supported post-installation change may set, and how each is normalized. Anything else (data directory, identity, paths,
# certificate) is refused here; certificates use Invoke-ALReplaceCertificate.
$script:NetworkSettings = @('AccessMode', 'ListenAddress', 'Port', 'AllowedHosts', 'ProxyHosts', 'TrustedProxies')

function ConvertTo-ALNetworkSettings([hashtable]$Requested, $Config) {
    $changes = @{}
    foreach ($key in @($Requested.Keys)) {
        if ($script:NetworkSettings -notcontains $key) { Stop-AL "Setting '$key' cannot be changed by a network configuration change." }
        $value = $Requested[$key]
        if ($key -in 'AllowedHosts', 'ProxyHosts', 'TrustedProxies') {
            $items = @(@($value) | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            foreach ($item in $items) { if ($item -match '[\s"*/\\]' -and $key -ne 'TrustedProxies') { Stop-AL "Invalid host '$item': host names and IP addresses only, no wildcards, URLs or paths." } }
            if ($key -eq 'TrustedProxies') { foreach ($item in $items) { if ($item -match '\*|^0\.0\.0\.0|^::/0') { Stop-AL 'Trusted proxies must be explicit addresses or restricted subnets.' } } }
            $value = [string[]]@($items | Select-Object -Unique)
        } elseif ($key -eq 'Port') {
            $port = 0; if (-not [int]::TryParse("$value", [ref]$port) -or $port -lt 1 -or $port -gt 65535) { Stop-AL 'Port must be 1..65535.' }
            $value = $port
        } else { $value = "$value".Trim() }
        $changes[$key] = $value
    }
    if (-not $changes.Count) { Stop-AL 'No network setting was given; nothing was changed.' }
    $effective = @{}
    foreach ($key in $changes.Keys) {
        $current = $Config.$key
        if (($current -is [array]) -or ($changes[$key] -is [array])) { if ((@($current) -join ',') -cne (@($changes[$key]) -join ',')) { $effective[$key] = $changes[$key] } }
        elseif ("$current" -cne "$($changes[$key])") { $effective[$key] = $changes[$key] }
    }
    if (-not $effective.Count) { Stop-AL 'The proposed network settings equal the current configuration; nothing was changed.' }
    $effective
}

# Changes the network settings of the installed Server (access mode, listener, port, allowed hosts, proxy hosts, trusted proxies) as one recorded
# transaction with validation first, a consolidated summary (-DryRun returns it without changing anything), readiness on the new listener with the
# existing certificate, automatic restoration on failure and interrupted-run recovery. An installer-owned firewall rule is updated or removed only
# with an explicit firewall decision; a change that would leave an owned rule pointing at the old listener is refused without one.
function Invoke-ALNetworkChange($Config, [hashtable]$Requested, [string]$FirewallSources = '', [string]$FirewallProfiles = 'Domain', [switch]$ApproveFirewall, [switch]$RemoveFirewall, [switch]$DryRun, [string]$CertificateFile = '', [string]$CertificatePasswordFile = '') {
    if (Get-ALPendingConfigurationRecord $Config) {
        if ($DryRun) { Stop-AL 'An interrupted configuration change is recorded; run without -DryRun (or -Action Recover) to restore the previous configuration first.' 4 }
        return Invoke-ALConfigurationRecover $Config
    }
    $context = Assert-ALConfigurationChangeAllowed $Config
    $changes = ConvertTo-ALNetworkSettings $Requested $Config
    $candidate = Copy-ALConfig $Config $changes
    # Combined change: the replacement certificate is validated against the proposed network settings and applied in the same transaction.
    if ($CertificateFile) { Assert-ALCertificateInput $CertificateFile $CertificatePasswordFile; $candidate = Copy-ALConfig $candidate @{ CertificatePath = $CertificateFile; CertificatePasswordFile = $CertificatePasswordFile } }
    try { $access = Test-ALCandidateConfiguration $Config $candidate $context.service }
    catch {
        $missing = ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $candidate)
        if ($missing -and @($missing.missing_identities).Count) { Stop-AL ("The certificate does not cover {0} required by the proposed settings; nothing was changed. Add -CertificateFile with a certificate that covers every allowed host (and the listener IP only if clients use it), or change the hosts." -f (@($missing.missing_identities) -join ', ')) }
        throw
    }
    $currentCertificate = ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $Config)
    $proposedCertificate = ConvertTo-ALCertificateSummary (Get-ALCertificateInfo $candidate)
    # The receipts come back as one array object (",$records"); unroll it so an empty result counts as no owned rule.
    $owned = @((Get-ALOwnedFirewallReceipts $Config) | Where-Object { $_ })
    $listenerMoved = $candidate.ListenAddress -ne $Config.ListenAddress -or [int]$candidate.Port -ne [int]$Config.Port
    $firewall = $null
    if ($ApproveFirewall -and $RemoveFirewall) { Stop-AL 'Choose either -ApproveFirewall with sources or -RemoveFirewall.' }
    if ($RemoveFirewall) { $firewall = @{ sources = ''; profiles = $FirewallProfiles; remove = $true } }
    elseif ($ApproveFirewall) {
        $plan = Get-ALInstallerFirewallPlan $candidate $FirewallSources $FirewallProfiles -AllowOwnedUpdate
        if (-not $plan.required) { Stop-AL 'A loopback listener needs no firewall rule; use -RemoveFirewall to remove an owned rule.' }
        $firewall = @{ sources = $FirewallSources; profiles = $FirewallProfiles; remove = $false }
    } elseif ($owned.Count -and $listenerMoved) {
        Stop-AL 'An installer-owned firewall rule allows the current listener only. Decide explicitly: -ApproveFirewall -FirewallSources <addresses> [-FirewallProfiles Domain] or -RemoveFirewall.'
    }
    $summary = [ordered]@{
        operation = $(if ($CertificateFile) { 'network and certificate change' } else { 'network change' }); service = $Config.ServiceName; restart_required = $true
        certificate = $(if ($CertificateFile) { "replaced by $CertificateFile (imported create-only into Root\tls\renew-<id>)" } else { $Config.CertificatePath })
        certificate_current = $currentCertificate; certificate_proposed = $proposedCertificate
        client_trust_notice = $(if ($CertificateFile) { Get-ALCertificateTrustNotice $currentCertificate $proposedCertificate } else { 'The certificate is unchanged; client trust is not affected.' })
        current = [ordered]@{ access_mode = $Config.AccessMode; listen_address = $Config.ListenAddress; port = [int]$Config.Port; allowed_hosts = @($Config.AllowedHosts); proxy_hosts = @($Config.ProxyHosts); trusted_proxies = @($Config.TrustedProxies) }
        proposed = [ordered]@{ access_mode = $candidate.AccessMode; listen_address = $candidate.ListenAddress; port = [int]$candidate.Port; allowed_hosts = @($candidate.AllowedHosts); proxy_hosts = @($candidate.ProxyHosts); trusted_proxies = @($candidate.TrustedProxies) }
        changed_settings = @($changes.Keys | Sort-Object); network_access = $access.network_access
        firewall = $(if ($firewall) { if ($firewall.remove) { 'remove the installer-owned rule' } else { "allow TCP $($candidate.ListenAddress):$($candidate.Port) from $FirewallSources ($FirewallProfiles)" } } elseif ($owned.Count) { 'installer-owned rule unchanged' } else { 'no change' })
    }
    if ($DryRun) { return [pscustomobject]@{ dry_run = $true; validated = $true; summary = $summary } }
    $settings = $changes
    if ($CertificateFile) {
        $tls = Copy-ALServerTlsMaterial $candidate (Join-AL (Join-AL $Config.Root 'tls') ('renew-' + [guid]::NewGuid().ToString('N')))
        $candidate = Copy-ALConfig $candidate @{ CertificatePath = $tls.certificate; CertificatePasswordFile = $tls.password_file }
        $copy = Invoke-ALMaintenance (Get-ALServiceExe $Config) (@('--server-preflight') + @(Get-ALServiceArguments $candidate))
        if (-not $copy.validated -or -not $copy.read_only) { Stop-AL 'The imported certificate copy did not validate; the service was not changed and the copy was retained for review.' 4 }
        $settings = @{} + $changes; $settings.CertificatePath = $tls.certificate; $settings.CertificatePasswordFile = $tls.password_file
    }
    $result = Invoke-ALConfigurationTransaction $Config $candidate $settings $summary.operation $context $firewall
    $result | Add-Member -NotePropertyName summary -NotePropertyValue $summary
    $result
}

# ---- restore (fresh installation + restore of an AuthLens or SAP Lens backup)

# Restores a verified .slbak backup into this installation: the host key that sealed it is copied into <root>\keys (never overwritten) and
# selected, the server stages and validates the archive (AuthLens.Api --restore), the service restarts, and the restore is applied before the
# database opens; a failure is rolled back by the server and reported here. The source installation is never touched.
function Invoke-ALRestore($Config, [string]$Backup, [string]$KeyFile) {
    if (-not [IO.Path]::IsPathRooted($Backup) -or -not (Test-Path -LiteralPath $Backup -PathType Leaf)) { Stop-AL 'Restore needs -Backup <absolute path of a .slbak file>.' }
    $service = Get-ALService $Config.ServiceName
    if (-not $service.Exists) { Stop-AL "Service $($Config.ServiceName) is not installed. Install AuthLens first (Deploy -FirstInstall), then restore." }
    $exe = Get-ALServiceExe $Config
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Stop-AL "No current release ($exe); install AuthLens first." }
    $pointer = Join-AL $Config.DataDirectory 'backup-key-location.json'
    if ($KeyFile) {
        if (Test-Path -LiteralPath $pointer) { Stop-AL 'A host backup key is already configured for this installation; restore uses it. Omit -KeyFile.' }
        if (-not (Test-Path -LiteralPath $KeyFile -PathType Leaf)) { Stop-AL "Key file $KeyFile does not exist." }
        $keyRoot = (Get-ALInstallLayout $Config.Root).KeyRoot
        $copy = Join-AL $keyRoot (Split-Path $KeyFile -Leaf)
        if (Test-Path -LiteralPath $copy) { Stop-AL "$copy exists; it is never overwritten. Choose the key file by another name." }
        New-Item -ItemType Directory -Force -Path $keyRoot | Out-Null
        Copy-Item -LiteralPath $KeyFile -Destination $copy
        $null = Invoke-ALMaintenance $exe @('--backup-key', 'use', $copy, '--data-dir', $Config.DataDirectory)
        Write-ALLog "host backup key copied to $copy and selected"
    } elseif (-not (Test-Path -LiteralPath $pointer) -and -not $env:AUTHLENS_BACKUP_PASSPHRASE) {
        Stop-AL 'Restore needs the key that sealed the backup: -KeyFile <recovery key file> (or AUTHLENS_BACKUP_PASSPHRASE for a passphrase backup).'
    }
    $staged = Invoke-ALMaintenance $exe @('--restore', $Backup, '--replace-all-data', '--data-dir', $Config.DataDirectory)
    Write-ALLog "restore $($staged.staged.id) staged from $($staged.staged.preview.source_product) $($staged.staged.preview.source_version) ($($staged.staged.preview.created_at)); restarting $($Config.ServiceName)"
    Grant-ALAccess $Config
    $manifest = Get-Content -LiteralPath (Join-AL (Get-ALLink (Get-ALCurrentLink $Config)) 'build-manifest.json') -Raw | ConvertFrom-Json
    Stop-ALService $Config.ServiceName ([int]$Config.StopTimeoutSeconds)
    Start-ALService $Config.ServiceName
    $null = Wait-ALReady $Config $manifest.source_sha $manifest.version
    $operation = Get-Content -LiteralPath (Join-AL (Join-AL $Config.DataDirectory 'backups') 'operation.json') -Raw | ConvertFrom-Json
    if ($operation.id -ne $staged.staged.id -or $operation.status -ne 'completed') {
        Stop-AL "The restore was not applied and the previous data is unchanged: $($operation.message)" 1
    }
    Write-ALLog $operation.message
    [pscustomobject]@{ restored = $true; id = $operation.id; source_product = $staged.staged.preview.source_product; source_version = $staged.staged.preview.source_version
        created_at = $staged.staged.preview.created_at; message = $operation.message; status = (Get-ALStatus $Config) }
}

. (Join-Path $PSScriptRoot 'AuthLens.Paths.ps1')
. (Join-Path $PSScriptRoot 'AuthLens.Acl.ps1')
. (Join-Path $PSScriptRoot 'AuthLens.Installer.ps1')
Export-ModuleMember -Function * -Variable FocusedTests
