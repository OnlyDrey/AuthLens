# Installer adapters for the existing release verifier, deployment journal and application backup engine.
# No service or file operations occur on import. Setup payloads and failed runs are never reused or overwritten.
$script:InstallerTools = @('Install-AuthLens.ps1','verify-release.ps1','deploy/AuthLens.Deploy.psm1','deploy/Deploy-AuthLens.ps1','deploy/AuthLens.Paths.ps1','deploy/AuthLens.Acl.ps1','deploy/AuthLens.Installer.ps1')
function Save-ALInstallerRecoveryTools([string]$Run) {
    $tools = Join-AL $Run 'recovery-tools'
    $entries = foreach ($relative in $script:InstallerTools) {
        $source = Join-AL (Split-Path $PSScriptRoot) ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        $target = Join-AL $tools ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
        [ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    [IO.File]::WriteAllText((Join-AL $tools 'installer-tools.json'),(@{schema=1;files=@($entries)} | ConvertTo-Json -Depth 5))
}
function Assert-ALInstallerPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path.StartsWith('//')) { Stop-AL 'Installer paths must be absolute local paths.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if (Test-ALAclForbidden $full) { Stop-AL 'Global Windows directories are not installer targets.' }
    if ($env:SystemRoot -and (Test-ALPathWithin $full $env:SystemRoot)) { Stop-AL 'Windows system directories are protected.' }
    if ($full.Length -lt 4 -or $full -match '^(?i)C:\\saplens2($|\\)|^(?i)C:\\sap-lens($|\\)') { Stop-AL 'Protected legacy installations and drive roots are never installer targets.' }
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    foreach ($old in 'SAP Lens','SAP Lens Desktop','SAP Lens 2 Prototype','Programs\SAP Lens','Programs\SAP Lens Desktop') {
        if ($local -and (Test-ALPathWithin $full (Join-AL $local $old))) { Stop-AL 'Earlier product profiles are protected.' }
    }
    Test-ALPathTree $full
}

function Get-ALInstallerPackage([string]$Package) {
    Assert-ALInstallerPath $Package
    $null = @(Get-ALTreeFiles $Package)
    $verifier = Join-AL (Split-Path $PSScriptRoot) 'verify-release.ps1'
    $result = Invoke-ALProcess (Get-ALShell) @('-NoProfile','-NonInteractive','-File',$verifier,'-ReleasePath',$Package) ''
    if ($result.ExitCode -ne 0) { Stop-AL 'Installer package integrity verification failed; no installed files were replaced.' }
    $manifest = Get-Content -LiteralPath (Join-AL $Package 'build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.product -cne 'AuthLens' -or $manifest.target_platform -ne 'win-x64' -or $manifest.source_dirty) { Stop-AL 'Only a clean AuthLens Windows package may be installed.' }
    $manifest
}

function Invoke-ALInstallerServer($Config, [string]$Package, [switch]$Recover) {
    # All SCM calls remain in the existing state machine. Explicit configuration is required, even on first install.
    if ($Recover) {
        Assert-ALInstallerServerConfiguration $Config
        $null=Assert-ALAclPlan (Get-ALAclPlan $Config) 'Server installer recovery'
        Enter-ALLock $Config
        try {
            $null=New-ALRun $Config 'installer-recover'
            Save-ALInstallerRecoveryTools $script:RunFolder
            return Invoke-ALRecover $Config
        } finally { Exit-ALLock }
    }
    $manifest = Get-ALInstallerPackage $Package
    Initialize-ALInstallerServerRoot $Config
    Enter-ALLock $Config
    try {
        $null = New-ALRun $Config 'installer'
        Save-ALInstallerRecoveryTools $script:RunFolder
        $published = Publish-ALRelease $Config $Package $manifest
        Invoke-ALDeploy $Config $published $manifest.source_sha -FirstInstall -RequireRollback
    } finally { Exit-ALLock }
}

function Assert-ALInstallerServerConfiguration($Config) {
    if ($Config.ServiceName -in @('SapLens2','sap-lens','SapLens')) { Stop-AL 'Legacy services are protected.' }
    foreach ($path in $Config.Root,$Config.DataDirectory,$Config.WorkRoot,$Config.ReleasesRoot,$Config.BackupRoot,$Config.ConfigFile,$Config.CertificatePath,$Config.CertificatePasswordFile) {
        if($path.IndexOfAny([char[]]"`r`n`0`"") -ge 0){Stop-AL 'Server paths contain unsupported delimiters.'}
        Assert-ALInstallerPath $path
        if([IO.Path]::GetFullPath($path).TrimEnd('\','/') -ine $path.Replace([IO.Path]::AltDirectorySeparatorChar,[IO.Path]::DirectorySeparatorChar).TrimEnd('\','/')){Stop-AL 'Server paths must be normalized absolute paths without dot segments.'}
        $local=[Environment]::GetFolderPath('LocalApplicationData')
        if($local -and ((Test-ALPathWithin $path (Join-AL $local 'AuthLens')) -or (Test-ALPathWithin $path (Join-AL $local 'Programs\AuthLens Desktop')))){Stop-AL 'Server Setup cannot use the current Desktop application or data profile.'}
    }
}
function Assert-ALInstallerUpgradeIdentity($Previous, $Next) {
    foreach ($manifest in $Previous,$Next) {
        if ($manifest.product -cne 'AuthLens' -or $manifest.source_sha -notmatch '^[a-f0-9]{40}$' -or
            (@($manifest.file_version) -join '.') -notmatch '^\d+\.\d+\.\d+\.\d+$') { Stop-AL 'Upgrade identity is incomplete; retain the installed release and recovery evidence.' }
    }
    $comparison=if ($Previous.PSObject.Properties['version'] -and $Next.PSObject.Properties['version']) { Compare-ALProductVersion $Next.version $Previous.version } else { ([version](@($Next.file_version) -join '.')).CompareTo([version](@($Previous.file_version) -join '.')) }
    if ($comparison -lt 0) { Stop-AL 'Installer downgrades are not supported; use a separately authorized compatible rollback/recovery plan.' }
    if ($comparison -eq 0 -and $Previous.source_sha -ne $Next.source_sha) {
        if (-not $Previous.PSObject.Properties['build_timestamp_utc'] -or -not $Next.PSObject.Properties['build_timestamp_utc'] -or
            [datetime]::Parse($Next.build_timestamp_utc).ToUniversalTime() -le [datetime]::Parse($Previous.build_timestamp_utc).ToUniversalTime()) { Stop-AL 'Same-version update requires a newer verified build identity; silent replacement is refused.' }
    }
}

# Product channel ordering is separate from Windows' four numeric version fields.
function Compare-ALProductVersion([string]$Left, [string]$Right) {
    $values=@()
    foreach ($value in $Left,$Right) {
        if ($value -notmatch '^(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})\.(0|[1-9]\d{0,4})(?:-(alpha|beta|rc)\.([1-9]\d{0,4}))?$') { Stop-AL 'Invalid AuthLens product version; verified release metadata is required.' }
        $rank=if(-not $Matches[4]){3}elseif($Matches[4]-eq 'alpha'){0}elseif($Matches[4]-eq 'beta'){1}else{2}
        $sequence=if($Matches[5]){[int]$Matches[5]}else{0}
        $values+=,@([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],$rank,$sequence)
    }
    for($i=0;$i -lt 5;$i++){if($values[0][$i] -lt $values[1][$i]){return -1};if($values[0][$i] -gt $values[1][$i]){return 1}}
    0
}

function Get-ALServerSetupRegistration {
    $key='Registry::HKEY_LOCAL_MACHINE\Software\AuthLens\Server'
    if(Test-Path -LiteralPath $key){
        $record=Get-ItemProperty -LiteralPath $key
        if($record.PSObject.Properties['Root'] -or $record.PSObject.Properties['ConfigFile'] -or $record.PSObject.Properties['ProgramDirectory']){
            foreach($field in 'Root','ConfigFile','ProgramDirectory'){if(-not $record.PSObject.Properties[$field] -or -not $record.$field){Stop-AL 'Server installer registration is incomplete; review its deployment history before continuing.'}}
        }
        if($record.PSObject.Properties['ConfigFile'] -and $record.ConfigFile){
            return [pscustomobject]@{ConfigFile=[string]$record.ConfigFile;Root=[string]$record.Root;ProgramDirectory=[string]$record.ProgramDirectory}
        }
    }
    $null
}

function Resolve-ALServerSetupConfiguration([string]$ConfigFile='',[string]$InstallRoot='') {
    $registration=Get-ALServerSetupRegistration
    $discoveredRoot=''
    if(-not $ConfigFile){
        if($registration){$ConfigFile=$registration.ConfigFile}
        else{
            $service=Get-ALService 'AuthLens'
            if($service.Exists){
                $parts=@(Split-ALCommandLine $service.PathName)
                if(-not $parts.Count -or $parts[0] -notmatch '^(?<root>[A-Za-z]:[\\/].+)[\\/]releases[\\/]current[\\/]server[\\/]AuthLens\.Api\.exe$'){Stop-AL 'Existing service is not a discoverable managed Server; supply its reviewed configuration explicitly. No service is adopted.'}
                $discoveredRoot=$Matches.root
                $ConfigFile=Join-AL (Join-AL $discoveredRoot 'config') 'deploy.json'
            }else{$ConfigFile=Join-AL (Join-AL $script:DefaultRoot 'config') 'deploy.json'}
        }
    }
    Assert-ALInstallerPath $ConfigFile
    $before=(Get-FileHash -LiteralPath $ConfigFile -Algorithm SHA256).Hash
    $config=Read-AuthLensSettings $ConfigFile -Packaged
    $after=(Get-FileHash -LiteralPath $ConfigFile -Algorithm SHA256).Hash
    if($before -ine $after){Stop-AL 'Deployment configuration changed while loading; repeat detection before continuing.'}
    if($config.ServiceName -cne 'AuthLens'){Stop-AL 'Server Setup supports one canonical AuthLens service per machine. Custom test services use the separate deployment acceptance tooling.'}
    Assert-ALInstallerServerConfiguration $config
    if([IO.Path]::GetFullPath($config.ReleasesRoot).TrimEnd('\','/') -ine [IO.Path]::GetFullPath((Join-AL $config.Root 'releases')) -or
        [IO.Path]::GetFullPath($config.WorkRoot).TrimEnd('\','/') -ine [IO.Path]::GetFullPath((Join-AL $config.Root 'deployment'))){Stop-AL 'Setup requires releases/deployment beneath the selected root. Existing nonstandard layouts need a separately reviewed procedure; no relocation was attempted.'}
    $observed=Get-ALService 'AuthLens'
    if($observed.Exists -and -not(Test-ALServiceBinary $observed.PathName $config)){Stop-AL 'Existing AuthLens service and selected configuration/root disagree. Setup never adopts an unrelated service or relocates its installation.'}
    if($discoveredRoot -and [IO.Path]::GetFullPath($discoveredRoot).TrimEnd('\','/') -ine [IO.Path]::GetFullPath($config.Root).TrimEnd('\','/')){Stop-AL 'Managed service root and discovered configuration disagree; relocation is refused.'}
    $program=[IO.Path]::GetFullPath((Join-AL $config.Root 'app')).TrimEnd('\','/')
    Assert-ALInstallerPath $program
    if($InstallRoot -and [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/') -ine $program){Stop-AL 'Explicit program directory conflicts with configuration Root\app. Remove /DIR or select the matching deployment configuration; no path validation was bypassed.'}
    if($registration -and ([IO.Path]::GetFullPath($registration.Root).TrimEnd('\','/') -ine [IO.Path]::GetFullPath($config.Root).TrimEnd('\','/') -or
        [IO.Path]::GetFullPath($registration.ConfigFile) -ine [IO.Path]::GetFullPath($ConfigFile) -or
        [IO.Path]::GetFullPath($registration.ProgramDirectory).TrimEnd('\','/') -ine $program)){Stop-AL 'Registered Server identity and deployment configuration disagree. Relocation is not an upgrade; retain the current installation and review its registration.'}
    [pscustomobject]@{Config=$config;ProgramDirectory=$program;ConfigSha256=$after.ToLowerInvariant();Registered=[bool]$registration}
}

function Get-ALServerSetupPlan($Resolved,[string]$Package='',[ValidateSet('Auto','Install','Upgrade','Repair')][string]$Operation='Auto') {
    $config=$Resolved.Config
    Assert-ALServerSetupFingerprint $Resolved $Resolved.ConfigSha256
    # Nothing here initializes paths, locks, journals, databases, keys or services.
    $kind=Assert-ALInstallerServerPreflight $config
    if($Operation -eq 'Install' -and $kind -ne 'fresh installation'){Stop-AL 'Install was requested but an existing Server was found.'}
    if($Operation -in @('Upgrade','Repair') -and $kind -eq 'fresh installation'){Stop-AL 'The requested operation requires a verified existing Server.'}
    foreach($path in $config.DataDirectory,$config.BackupRoot){
        foreach($protected in (Join-AL $config.Root 'app'),$config.ReleasesRoot,$config.WorkRoot,(Split-Path $config.ConfigFile),(Split-Path $config.CertificatePath),(Join-AL $config.Root 'keys')){
            if(Test-ALPathOverlap $path $protected){Stop-AL 'Data/backup storage overlaps program, deployment, configuration, TLS or key storage.'}
        }
    }
    if(Test-ALPathOverlap $config.DataDirectory $config.BackupRoot){Stop-AL 'Data and pre-deployment backup directories must be separate.'}
    $null=Assert-ALAclPlan @([pscustomobject]@{Path=$config.Root;Class='private';Role='installation root';Recurse=$false}) 'Server installation root'
    $null=Assert-ALAclPlan (Get-ALAclPlan $config) 'Server preflight'
    foreach($file in $config.CertificatePath,$config.CertificatePasswordFile){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){Stop-AL 'TLS certificate/password file is missing; Setup never invents or replaces TLS secrets.'}}
    if(-not (Test-ALInstallerListenAddress $config.ListenAddress)){Stop-AL 'The configured listen address is not assigned to this machine; no listener or interface was changed.'}
    $service=Get-ALService $config.ServiceName
    $listeners=@(Get-ALListener $config.ListenAddress ([int]$config.Port))
    if(@($listeners|Where-Object{-not $service.Exists -or $_ -ne $service.ProcessId}).Count){Stop-AL 'Configured port is owned by another process; it will never be terminated by Setup.'}
    if($kind -eq 'fresh installation' -and (Test-Path -LiteralPath (Join-AL $config.DataDirectory 'authlens.sqlite3'))){Stop-AL 'Existing database without a verified Server identity requires recovery or an explicit isolated restore; empty initialization/adoption is refused.'}
    if($kind -eq 'fresh installation'){
        foreach($directory in $config.DataDirectory,$config.ReleasesRoot,$config.WorkRoot){
            if((Test-Path -LiteralPath $directory) -and @(Get-ChildItem -LiteralPath $directory -Force).Count){Stop-AL 'Fresh installation found retained or unrelated data/program/deployment files. Review recovery; Setup never treats an unregistered populated directory as empty.'}
        }
        $app=Join-AL $config.Root 'app'
        if((Test-Path -LiteralPath $app) -and @(Get-ChildItem -LiteralPath $app -Force).Count){
            $name=if($Package){Split-Path $Package -Leaf}else{''}
            $expected=Join-AL (Join-AL (Join-AL (Join-AL $app 'setup') $name) 'payload') $name
            if(-not $Package -or [IO.Path]::GetFullPath($Package).TrimEnd('\','/') -ine [IO.Path]::GetFullPath($expected) -or
                @(Get-ChildItem -LiteralPath $app -Force|Where-Object Name -ne 'setup').Count -or
                @(Get-ChildItem -LiteralPath (Join-AL $app 'setup') -Force|Where-Object Name -ne $name).Count){Stop-AL 'Fresh program directory is populated beyond this verified Setup payload; explicit recovery is required.'}
        }
        if(Test-Path -LiteralPath $config.Root){
            foreach($entry in Get-ChildItem -LiteralPath $config.Root -Force){if($entry.Name -notin @('app','releases','config','tls','keys','deployment','data','backups')){Stop-AL 'Selected fresh root contains unrelated entries. Choose a dedicated installation root; no cleanup is automatic.'}}
        }
    }
    if($kind -eq 'fresh installation' -and $config.ServiceAccount -ine ('NT SERVICE\'+$config.ServiceName)){Stop-AL 'Fresh Setup supports the virtual service account only. Password-bearing and gMSA provisioning require a separate validated service-logon procedure.'}
    $manifest=$null
    if($Package){
        $manifest=Get-ALInstallerPackage $Package
        $network=Invoke-ALMaintenance (Join-AL $Package 'server/AuthLens.Api.exe') (@('--server-preflight')+@(Get-ALServiceArguments $config))
        if(-not $network.validated -or -not $network.read_only){Stop-AL 'The packaged Server did not prove read-only network/TLS configuration validation.'}
        if($network.version -cne $manifest.version -or $network.source_sha -cne $manifest.source_sha){Stop-AL 'Verified manifest and Server preflight runtime identity disagree; no installation was provisioned.'}
        $previous=Get-ALLink (Get-ALCurrentLink $config)
        if($previous){
            $old=Get-Content -LiteralPath (Join-AL $previous 'build-manifest.json') -Raw | ConvertFrom-Json
            if($Operation -eq 'Repair' -and ($old.source_sha -ne $manifest.source_sha -or (Compare-ALProductVersion $manifest.version $old.version) -ne 0)){Stop-AL 'Repair requires the identical verified product/build; use Upgrade for a different build.'}
            Assert-ALInstallerUpgradeIdentity $old $manifest
            if(@($network.schema.pending).Count){Stop-AL 'Installer preflight cannot prove binary rollback across pending schema changes; use a separately approved migration/recovery procedure.'}
            $oldSchema=Invoke-ALMaintenance (Join-AL $previous 'server/AuthLens.Api.exe') @('--schema-info','--data-dir',$config.DataDirectory)
            if(-not $oldSchema.compatible){Stop-AL 'The previous release cannot open the current schema; repair/upgrade rollback is not safe.'}
        }
        $payloadFiles=@(Get-ALTreeFiles $Package)
        $staging=Join-AL (Join-AL (Join-AL (Join-AL (Join-AL $config.Root 'app') 'setup') (Split-Path $Package -Leaf)) 'payload') (Split-Path $Package -Leaf)
        $packagePath=[IO.Path]::GetFullPath($Package).TrimEnd('\','/')
        foreach($file in $payloadFiles){if((Join-AL $staging $file.FullName.Substring($packagePath.Length+1)).Length -ge 248){Stop-AL 'Staged payload exceeds the supported Windows PowerShell path length. Choose a shorter dedicated root; no file was moved.'}}
        $bytes=($payloadFiles|Measure-Object Length -Sum).Sum
        $dataBytes=if(Test-Path -LiteralPath $config.DataDirectory){(@(Get-ALTreeFiles $config.DataDirectory)|Measure-Object Length -Sum).Sum}else{0}
        $needed=@{}
        foreach($entry in @(@($config.Root,([long]$bytes*2+64MB)),@($config.BackupRoot,([long]$dataBytes*2+64MB)),@([IO.Path]::GetTempPath(),([long]$dataBytes*2+64MB)))){
            $drive=[IO.Path]::GetPathRoot($entry[0]).ToUpperInvariant()
            if(-not $needed.ContainsKey($drive)){$needed[$drive]=[long]0}
            $needed[$drive]+=[long]$entry[1]
        }
        foreach($drive in $needed.Keys){if((Get-ALInstallerFreeBytes $drive) -lt $needed[$drive]){Stop-AL 'Insufficient free storage for immutable staging/publication and a verified backup; nothing was provisioned.'}}
    }
    [pscustomobject]@{schema=1;operation_id=[guid]::NewGuid().ToString('N');operation=$(if($Operation-eq 'Repair'){'repair'}else{$kind});read_only=$true;package_network_database_verified=[bool]$Package;root=$config.Root;program_directory=$Resolved.ProgramDirectory;config_file=$config.ConfigFile;config_sha256=$Resolved.ConfigSha256;data_directory=$config.DataDirectory;backup_directory=$config.BackupRoot;listen_address=$config.ListenAddress;port=$config.Port;service_name=$config.ServiceName;service_account=$config.ServiceAccount;certificate=$config.CertificatePath;allowed_hosts=@($config.AllowedHosts);proxy_hosts=@($config.ProxyHosts);trusted_proxies=@($config.TrustedProxies);firewall='unchanged; no automatic rule creation';version=$(if($manifest){$manifest.version}else{''});source_sha=$(if($manifest){$manifest.source_sha}else{''});limitations=@('Service-identity key access, encrypted backup verification and final Windows TLS/readiness are mandatory transaction checks.','Custom-account provisioning, automatic firewall changes, destructive uninstall and legacy restore remain separate explicit operations.')}
}

function Get-ALInstallerFreeBytes([string]$Drive){([IO.DriveInfo]::new($Drive)).AvailableFreeSpace}

function Assert-ALServerSetupFingerprint($Resolved,[string]$Expected){
    if($Expected -and (Get-FileHash -LiteralPath $Resolved.Config.ConfigFile -Algorithm SHA256).Hash -ine $Expected){Stop-AL 'Deployment configuration changed after review; repeat detection and preflight before installation.'}
}

function Test-ALInstallerListenAddress([string]$Address){
    $ip=$null
    if(-not [Net.IPAddress]::TryParse($Address,[ref]$ip)){return $false}
    if([Net.IPAddress]::IsLoopback($ip)){return $true}
    foreach($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()){
        foreach($unicast in $adapter.GetIPProperties().UnicastAddresses){if($unicast.Address.Equals($ip)){return $true}}
    }
    $false
}

function Get-ALInstallerLegacyPresence([switch]$ServicesOnly){
    $present=@();$unknown=@()
    foreach($name in 'sap-lens','SapLens','SapLens2'){
        try{if((Get-ALService $name).Exists){$present+=('service:'+ $name)}}catch{$unknown+=('service:'+ $name)}
    }
    if(-not $ServicesOnly){foreach($path in 'C:\sap-lens','C:\saplens2'){try{if(Test-Path -LiteralPath $path){$present+=('protected path:'+ $path)}}catch{$unknown+=('protected path:'+ $path)}}}
    [pscustomobject]@{present=$present;unknown=$unknown;policy='read-only presence only; never adopted, modified or deleted'}
}

function Write-ALServerSetupPlan([string]$Path,$Plan) {
    # GUI uses a private INI bridge; automation consumes the same JSON plan on stdout.
    $lines=@('[AuthLens]')
    foreach($name in @('operation_id','operation','root','program_directory','config_file','config_sha256','data_directory','backup_directory','listen_address','port','service_name','service_account','certificate','allowed_hosts','proxy_hosts','trusted_proxies')){
        $value=@($Plan.$name) -join ', '
        if($value.IndexOfAny([char[]]"`r`n`0") -ge 0){Stop-AL 'Setup plan contains invalid line delimiters.'}
        $lines+=($name+'='+$value)
    }
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer=[IO.StreamWriter]::new($stream,[Text.Encoding]::Unicode)
    try{$writer.Write($lines -join "`r`n")}finally{$writer.Dispose()}
}
function Initialize-ALInstallerServerRoot($Config) {
    Assert-ALInstallerServerConfiguration $Config
    if (-not (Test-Path -LiteralPath $Config.Root)) { New-ALDirectoryWithAcl $Config.Root (New-ALProtectedDirectorySecurity) }
    $null=Assert-ALAclPlan @([pscustomobject]@{Path=$Config.Root;Class='private';Role='installation root';Recurse=$false}) 'Server installation root'
    Initialize-ALInstallation $Config
}
function Assert-ALInstallerServerPreflight($Config) {
    Assert-ALInstallerServerConfiguration $Config
    $journal=Read-ALJournal $Config
    if ($journal -and $journal.phase -in $script:CriticalPhases) { Stop-AL 'An interrupted Server deployment requires explicit recovery before Setup can continue.' 4 }
    $service=Get-ALService $Config.ServiceName
    $previous=Get-ALLink (Get-ALCurrentLink $Config)
    if ($service.Exists) {
        if (-not (Test-ALServiceBinary $service.PathName $Config)) { Stop-AL 'Existing service is outside the managed release link; Setup will not adopt or replace it.' }
        if ($service.Account -ine $Config.ServiceAccount) { Stop-AL 'Existing service identity differs; Setup will not reconfigure it.' }
        $arguments=@(Split-ALCommandLine $service.PathName)
        if (@(Compare-ALServiceArguments @($arguments | Select-Object -Skip 1) @(Get-ALServiceArguments $Config)).Count) { Stop-AL 'Existing service configuration differs; review explicit deployment settings before Setup.' }
        if (-not $previous -or -not (Test-ALPathWithin $previous $Config.ReleasesRoot) -or -not (Test-ALPublishedRelease $previous).Verified) { Stop-AL 'Existing Server release cannot prove rollback; nothing was changed.' }
        return 'upgrade'
    }
    if ($previous) { Stop-AL 'A release pointer exists without its service; explicit recovery is required.' }
    'fresh installation'
}

function New-ALInstallerPrivateDirectory([string]$Path) {
    Assert-ALInstallerPath $Path
    if (Test-Path -LiteralPath $Path) { Stop-AL 'Installer recovery directory already exists; it was preserved.' }
    $security = New-ALProtectedDirectorySecurity
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User,'FullControl','ContainerInherit, ObjectInherit','None','Allow'))
    New-ALDirectoryWithAcl $Path $security
}

function Assert-ALDesktopIdle([string]$Data) {
    $normal = Join-AL ([Environment]::GetFolderPath('LocalApplicationData')) 'AuthLens\data'
    $name = 'Local\AuthLensDesktop'
    if ([IO.Path]::GetFullPath($Data).TrimEnd('\') -ine [IO.Path]::GetFullPath($normal)) {
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $suffix = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Data).TrimEnd('\').ToUpperInvariant())))).Replace('-','').Substring(0,16) } finally { $hash.Dispose() }
        $name += '-' + $suffix
    }
    try { $mutex = [Threading.Mutex]::OpenExisting($name) } catch [Threading.WaitHandleCannotBeOpenedException] { return }
    $mutex.Dispose()
    Stop-AL 'Close the selected AuthLens Desktop before installing or recovering. It is never terminated.'
}

function Invoke-ALDesktopProbe([string]$Exe, [string]$Data) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$Exe; $info.Arguments='--data-dir "'+[IO.Path]::GetFullPath($Data).TrimEnd('\','/')+'" --self-check'
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    try {
        $output=$process.StandardOutput.ReadToEndAsync(); $errorOutput=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { Stop-AL "Owned Desktop readiness probe $($process.Id) did not exit; it was not terminated. Review its data-directory log before recovery." 4 }
        if ($process.ExitCode -ne 0) { Stop-AL 'Desktop readiness failed; see its isolated data-directory log.' 1 }
        $null=$output.GetAwaiter().GetResult(); $null=$errorOutput.GetAwaiter().GetResult()
    } finally { $process.Dispose() }
}

function Write-ALInstallerJournal([string]$Path, $Journal) {
    # Atomic checkpoints; the run's immutable previous files and encrypted backup are separate from this replaceable status.
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.part'
    [IO.File]::WriteAllText($temporary,($Journal | ConvertTo-Json -Depth 8))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,($Path+'.previous-'+[Guid]::NewGuid().ToString('N'))) } else { [IO.File]::Move($temporary,$Path) }
}

function Assert-ALInstalledDesktop([string]$Root) {
    $manifest = Get-Content -LiteralPath (Join-AL $Root 'build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = @($manifest.artifacts | Where-Object path -CEQ 'desktop/AuthLens.exe')
    if ($manifest.product -cne 'AuthLens' -or $entry.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-AL $Root 'AuthLens.exe') -Algorithm SHA256).Hash -ine $entry[0].sha256) { Stop-AL 'The previous Desktop executable does not match its manifest; no update is allowed.' }
    $manifest
}

function Restore-ALInstallerDesktop([string]$Root, [string]$Data, [string]$JournalPath, $Journal, [string]$MaintenanceExe) {
    Assert-ALDesktopIdle $Data
    $schema = Invoke-ALMaintenance $MaintenanceExe @('--schema-info','--data-dir',$Data)
    if ((@($Journal.applied_before) -join '|') -cne (@($schema.applied) -join '|')) { Stop-AL 'Data schema changed; automatic binary rollback is refused. Recovery evidence was preserved.' 4 }
    $old = Join-AL $Journal.run 'previous.exe'
    if (-not (Test-Path -LiteralPath $old) -or (Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash -ine $Journal.previous_sha256) { Stop-AL 'Previous executable recovery proof is missing or changed.' 4 }
    if ((Get-FileHash -LiteralPath (Join-AL $Journal.run 'previous-manifest.json') -Algorithm SHA256).Hash -ine $Journal.previous_manifest_sha256) { Stop-AL 'Previous manifest recovery proof changed.' 4 }
    $next = Join-AL $Root ('restore-' + [Guid]::NewGuid().ToString('N') + '.exe')
    Copy-Item -LiteralPath $old -Destination $next
    $installed = Join-AL $Root 'AuthLens.exe'
    if (Test-Path -LiteralPath $installed) { [IO.File]::Replace($next,$installed,(Join-AL $Journal.run ('rollback-candidate-'+[Guid]::NewGuid().ToString('N')+'.exe'))) } else { [IO.File]::Move($next,$installed) }
    Copy-Item -LiteralPath (Join-AL $Journal.run 'previous-manifest.json') -Destination (Join-AL $Root 'build-manifest.json') -Force
    Invoke-ALDesktopProbe $installed $Data
    $Journal.phase = 'rolled_back'; Write-ALInstallerJournal $JournalPath $Journal
}

function Invoke-ALInstallerDesktop([string]$Root, [string]$Data, [string]$Package, [switch]$Recover) {
    foreach ($path in $Root,$Data) { Assert-ALInstallerPath $path }
    if (Test-ALPathOverlap $Root $Data) { Stop-AL 'Desktop data must be outside its program directory.' }
    if (Test-Path -LiteralPath $Root) { $null = @(Get-ALTreeFiles $Root) }
    $manifest = Get-ALInstallerPackage $Package
    $maintenance = Join-AL $Package 'server\AuthLens.Api.exe'
    Assert-ALDesktopIdle $Data
    $state = Join-AL $Root '.setup-state'
    $journalPath = Join-AL $state 'journal.json'
    if (-not (Test-Path -LiteralPath $Root)) { New-ALInstallerPrivateDirectory $Root }
    if (-not (Test-Path -LiteralPath $state)) { New-ALInstallerPrivateDirectory $state }
    if (-not (Test-Path -LiteralPath $Data)) {
        $parent = Split-Path $Data
        if (-not (Test-Path -LiteralPath $parent)) { New-ALInstallerPrivateDirectory $parent }
        New-ALInstallerPrivateDirectory $Data
    }
    $null = Assert-ALAclPlan @(
        [pscustomobject]@{Path=$Root;Class='binaries';Role='Desktop programs';Recurse=$true},
        [pscustomobject]@{Path=$state;Class='private';Role='installer recovery';Recurse=$true},
        [pscustomobject]@{Path=$Data;Class='private';Role='Desktop data';Recurse=$true}
    ) 'Desktop installer state'
    $lock = [IO.File]::Open((Join-AL $state 'installer.lock'),'OpenOrCreate','ReadWrite','None')
    try {
        if (Test-Path -LiteralPath $journalPath) {
            $prior = Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($prior.install_root -ine [IO.Path]::GetFullPath($Root) -or $prior.data_directory -ine [IO.Path]::GetFullPath($Data)) { Stop-AL 'Installer paths differ from the recorded installation; configuration is never silently replaced.' 4 }
            if ($prior.phase -notin @('complete','rolled_back','aborted')) {
                if (-not $Recover) { Stop-AL 'An interrupted installer operation needs explicit recovery; existing artifacts were preserved.' 4 }
                if (-not (Test-ALPathWithin $prior.run $state)) { Stop-AL 'Invalid recovery run path.' 4 }
                if ($prior.install_root -ine [IO.Path]::GetFullPath($Root) -or $prior.data_directory -ine [IO.Path]::GetFullPath($Data)) { Stop-AL 'Recovery paths differ from the recorded operation.' 4 }
                Restore-ALInstallerDesktop $Root $Data $journalPath $prior $maintenance
                return [pscustomobject]@{ recovered=$true; phase='rolled_back' }
            }
        }
        if ($Recover) { return [pscustomobject]@{ recovered=$false; reason='no incomplete operation' } }
        $schema = Invoke-ALMaintenance $maintenance @('--schema-info','--data-dir',$Data)
        if (-not $schema.compatible) { Stop-AL 'The selected data is incompatible with this package.' }
        $installed = Join-AL $Root 'AuthLens.exe'
        $updating = Test-Path -LiteralPath $installed
        if (-not $schema.database_exists -and (Test-Path -LiteralPath $Data) -and @(Get-ChildItem -LiteralPath $Data -Force).Count) { Stop-AL 'Data exists without its canonical database; inspect it instead of initializing a replacement.' }
        if ($updating -and @($schema.pending).Count) { Stop-AL 'Installer update cannot prove binary rollback across pending schema migrations; nothing was replaced.' }
        if ($updating) {
            $oldManifest = Assert-ALInstalledDesktop $Root
            if ($oldManifest.PSObject.Properties['file_version'] -and $manifest.PSObject.Properties['file_version'] -and
                [version](@($manifest.file_version) -join '.') -lt [version](@($oldManifest.file_version) -join '.')) { Stop-AL 'Installer downgrades are not supported.' }
            if ($oldManifest.PSObject.Properties['file_version'] -and $manifest.PSObject.Properties['file_version']) { Assert-ALInstallerUpgradeIdentity $oldManifest $manifest }
        } elseif (Test-Path -LiteralPath (Join-AL $Root 'build-manifest.json')) { Stop-AL 'A manifest exists without its installed Desktop; inspect the incomplete installation before proceeding.' }
        $run = Join-AL $state ([Guid]::NewGuid().ToString('N')); New-ALInstallerPrivateDirectory $run
        Save-ALInstallerRecoveryTools $run
        $journal = [pscustomobject]@{ phase='prepared'; run=$run; install_root=[IO.Path]::GetFullPath($Root); data_directory=[IO.Path]::GetFullPath($Data); package_sha=$manifest.source_sha; applied_before=@($schema.applied); previous_sha256=''; previous_manifest_sha256=''; backup=$null; had_previous=[bool]$updating }
        if ($updating) {
            Copy-Item -LiteralPath $installed -Destination (Join-AL $run 'previous.exe')
            Copy-Item -LiteralPath (Join-AL $Root 'build-manifest.json') -Destination (Join-AL $run 'previous-manifest.json')
            $journal.previous_sha256 = (Get-FileHash -LiteralPath (Join-AL $run 'previous.exe') -Algorithm SHA256).Hash
            $journal.previous_manifest_sha256 = (Get-FileHash -LiteralPath (Join-AL $run 'previous-manifest.json') -Algorithm SHA256).Hash
            $journal.phase='backup'; Write-ALInstallerJournal $journalPath $journal
            if ($schema.database_exists) {
                $backup = Invoke-ALMaintenance $maintenance @('--backup-local',$run,'--data-dir',$Data)
                $verified = Invoke-ALMaintenance $maintenance @('--backup-verify',$backup.file,'--data-dir',$Data)
                if (-not $verified.verified -or $verified.sha256 -ne $backup.sha256) { Stop-AL 'Protective backup verification failed; nothing was replaced.' }
                $journal.backup = $backup
            }
            Invoke-ALDesktopProbe $installed $Data # prove the previous version worked before replacement
        }
        Write-ALInstallerJournal $journalPath $journal
        try {
            Assert-ALDesktopIdle $Data
            $journal.phase='replacing'; Write-ALInstallerJournal $journalPath $journal
            $next = Join-AL $Root ('candidate-' + [Guid]::NewGuid().ToString('N') + '.exe')
            Copy-Item -LiteralPath (Join-AL $Package 'desktop\AuthLens.exe') -Destination $next
            if ((Get-FileHash -LiteralPath $next -Algorithm SHA256).Hash -ine (@($manifest.artifacts | Where-Object path -CEQ 'desktop/AuthLens.exe')[0].sha256)) { Stop-AL 'Staged executable changed before replacement.' }
            if ($updating) { [IO.File]::Replace($next,$installed,(Join-AL $run 'replaced.exe')) } else { [IO.File]::Move($next,$installed) }
            Copy-Item -LiteralPath (Join-AL $Package 'build-manifest.json') -Destination (Join-AL $Root 'build-manifest.json') -Force
            $journal.phase='verifying'; Write-ALInstallerJournal $journalPath $journal
            Invoke-ALDesktopProbe $installed $Data
            $journal.phase='complete'; Write-ALInstallerJournal $journalPath $journal
            [pscustomobject]@{ installed=$true; updated=[bool]$updating; backup=$journal.backup; run=$run }
        } catch {
            $failure=$_.Exception.Message
            if ($updating) {
                try { Restore-ALInstallerDesktop $Root $Data $journalPath $journal $maintenance }
                catch { $journal.phase='manual_recovery_required'; Write-ALInstallerJournal $journalPath $journal; Stop-AL 'Installer rollback could not be verified; close Desktop and use explicit recovery. All evidence was preserved.' 4 }
                Stop-AL "Update failed and the previous Desktop was restored and verified: $failure" 1
            }
            $journal.phase='manual_recovery_required'; Write-ALInstallerJournal $journalPath $journal
            Stop-AL 'Fresh Desktop installation did not become ready; files and diagnostics were preserved for review.' 4
        }
    } finally { $lock.Dispose() }
}
