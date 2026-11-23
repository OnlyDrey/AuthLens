BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Server Setup configuration ownership and directory resolution' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
        @{Root=$root;ListenAddress='127.0.0.1';Port=18799;AllowedHosts=@('localhost')}|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupRegistration {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false}}
    }
    It 'derives app from the explicit custom root without requiring a DIR workaround or creating paths' {
        $result=Resolve-ALServerSetupConfiguration $file
        $result.ProgramDirectory | Should -Be (Join-Path $root 'app')
        Test-Path -LiteralPath $root | Should -BeFalse
    }
    It 'keeps strict path validation for a conflicting explicit DIR' {
        {Resolve-ALServerSetupConfiguration $file (Join-Path $TestDrive 'wrong/app')}|Should -Throw '*Explicit program directory conflicts*'
        Test-Path -LiteralPath $root | Should -BeFalse
    }
    It 'accepts a matching explicit DIR and fingerprints the reviewed configuration' {
        $result=Resolve-ALServerSetupConfiguration $file (Join-Path $root 'app')
        $result.ConfigSha256 | Should -Be ((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant())
    }
    It 'discovers registered configuration but rejects registration/configuration disagreement' {
        $script:registration=[pscustomobject]@{Root=$root;ConfigFile=$file;ProgramDirectory=(Join-Path $root 'app')}
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupRegistration {$script:registration}
        (Resolve-ALServerSetupConfiguration).Registered | Should -BeTrue
        $script:registration.ProgramDirectory=Join-Path $TestDrive 'wrong/app'
        {Resolve-ALServerSetupConfiguration $file}|Should -Throw '*Registered Server identity*disagree*'
    }
    It 'refuses a second custom service through normal Setup' {
        $json=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
        $json|Add-Member ServiceName 'AuthLens-Other'
        $json|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
        {Resolve-ALServerSetupConfiguration $file}|Should -Throw '*one canonical AuthLens service*'
    }
    It 'retains external data and backup directories without normalizing them into the root' {
        $json=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
        $json|Add-Member DataDirectory (Join-Path $TestDrive 'external-data')
        $json|Add-Member BackupRoot (Join-Path $TestDrive 'external-backups')
        $json|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
        $config=(Resolve-ALServerSetupConfiguration $file).Config
        $config.DataDirectory|Should -Be $json.DataDirectory
        $config.BackupRoot|Should -Be $json.BackupRoot
    }
    It 'refuses the current Desktop profile as a Server root' {
        $json=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
        $json.Root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AuthLens'
        $json|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
        {Resolve-ALServerSetupConfiguration $file}|Should -Throw '*current Desktop*profile*'
    }
    It 'refuses a configuration changed after review without creating installation paths' {
        $resolved=Resolve-ALServerSetupConfiguration $file
        Add-Content -LiteralPath $file ' '
        {Assert-ALServerSetupFingerprint $resolved $resolved.ConfigSha256}|Should -Throw '*changed after review*'
        Test-Path -LiteralPath $root|Should -BeFalse
    }
    It 'discovers a custom managed root when old Setup has no configuration registration' -Skip:($env:OS -ne 'Windows_NT') {
        New-Item -ItemType Directory -Force (Join-Path $root 'config')|Out-Null
        Copy-Item -LiteralPath $file -Destination (Join-Path $root 'config/deploy.json')
        $script:managedExe=Get-ALBinaryPath (Read-AuthLensSettings (Join-Path $root 'config/deploy.json') -Packaged)
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$true;PathName=$script:managedExe}}
        (Resolve-ALServerSetupConfiguration).ProgramDirectory|Should -Be (Join-Path $root 'app')
    }
    It 'refuses a junction at the derived program directory before Setup can stage files through it' -Skip:($env:OS -ne 'Windows_NT') {
        New-Item -ItemType Directory -Force $root|Out-Null
        $target=Join-Path $TestDrive ('outside-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory $target|Out-Null
        Set-Content (Join-Path $target 'sentinel.txt') 'untouched'
        New-Item -ItemType Junction -Path (Join-Path $root 'app') -Target $target|Out-Null
        {Resolve-ALServerSetupConfiguration $file}|Should -Throw '*reparse points*'
        Get-Content (Join-Path $target 'sentinel.txt')|Should -Be 'untouched'
        @(Get-ChildItem $target).Count|Should -Be 1
    }
}
Describe 'Product version semantics independent of Windows file version' {
    It 'orders <Before> before <After>' -ForEach @(
        @{Before='2.0.0-alpha.9';After='2.0.0-alpha.10'},
        @{Before='2.0.0-alpha.99';After='2.0.0-beta.1'},
        @{Before='2.0.0-beta.99';After='2.0.0-rc.1'},
        @{Before='2.0.0-rc.99';After='2.0.0'},
        @{Before='2.0.0';After='2.0.1-alpha.1'}) {
        Compare-ALProductVersion $Before $After|Should -Be -1
        Compare-ALProductVersion $After $Before|Should -Be 1
    }
    It 'accepts stable after alpha despite its lower Windows revision' {
        $old=[pscustomobject]@{product='AuthLens';version='2.0.0-alpha.1';file_version=@(2,0,0,1);source_sha=('a'*40)}
        $next=[pscustomobject]@{product='AuthLens';version='2.0.0';file_version=@(2,0,0,0);source_sha=('b'*40)}
        {Assert-ALInstallerUpgradeIdentity $old $next}|Should -Not -Throw
        {Assert-ALInstallerUpgradeIdentity $next $old}|Should -Throw '*downgrades*'
    }
    It 'refuses unsupported version strings' {
        {Compare-ALProductVersion '2.0.0-preview.1' '2.0.0'}|Should -Throw '*Invalid*version*'
    }
}

Describe 'Read-only Setup planning and guarded lifecycle operations' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config'),(Join-Path $root 'tls')|Out-Null
        $file=Join-Path $root 'config/deploy.json'
        @{Root=$root;ListenAddress='127.0.0.1';Port=18799;AllowedHosts=@('localhost')}|ConvertTo-Json|Set-Content -LiteralPath $file -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'tls/server.pfx') 'synthetic-not-a-certificate; validator is mocked'
        Set-Content -LiteralPath (Join-Path $root 'tls/cert-password') 'synthetic-password-marker'
        $script:Kind='fresh installation';$script:Previous=$null
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupRegistration {$null}
        Mock -ModuleName AuthLens.Deploy Assert-ALInstallerServerPreflight {$script:Kind}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {[pscustomobject]@{safe=$true}}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false;ProcessId=0}}
        Mock -ModuleName AuthLens.Deploy Get-ALListener {@()}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$script:Previous}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerFreeBytes {1TB}
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{validated=$true;read_only=$true;version=$script:PackageManifest.version;source_sha=$script:PackageManifest.source_sha;compatible=$true;schema=[pscustomobject]@{compatible=$true;pending=@()}}}
        Mock -ModuleName AuthLens.Deploy Initialize-ALInstallation {throw 'Planning must never provision directories'}
        Mock -ModuleName AuthLens.Deploy New-ALDirectoryWithAcl {throw 'Planning must never create directories'}
        $resolved=Resolve-ALServerSetupConfiguration $file
        $package=Join-Path $TestDrive ('pkg-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Force (Join-Path $package 'server')|Out-Null
        Set-Content -LiteralPath (Join-Path $package 'server/AuthLens.Api.exe') 'synthetic package'
        $script:PackageManifest=[pscustomobject]@{product='AuthLens';version='2.0.0-alpha.1';file_version=@(2,0,0,1);source_sha=('b'*40);build_timestamp_utc='2026-11-22T10:00:00Z'}
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerPackage {$script:PackageManifest}
    }
    It 'plans without a data directory, token, lock, journal, service or configuration write' {
        $before=(Get-FileHash -LiteralPath $file).Hash
        $plan=Get-ALServerSetupPlan $resolved $package Install
        $plan.read_only|Should -BeTrue
        $plan.program_directory|Should -Be (Join-Path $root 'app')
        $plan.firewall|Should -Be 'unchanged; no automatic rule creation'
        ($plan|ConvertTo-Json -Depth 8)|Should -Not -Match 'synthetic-password-marker'
        (Get-FileHash -LiteralPath $file).Hash|Should -Be $before
        foreach($directory in 'app','data','deployment','releases'){Test-Path (Join-Path $root $directory)|Should -BeFalse}
        Should -Invoke -ModuleName AuthLens.Deploy Initialize-ALInstallation -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter {$Arguments[0] -eq '--server-preflight'}
    }
    It 'does not add the network exposure flag for local HTTPS' {
        @(Get-ALServiceArguments $resolved.Config)|Should -Not -Contain '--network'
    }
    It 'omits an empty extra-host list in local HTTPS instead of emitting a valueless command option' {
        $resolved.Config.AllowedHosts=@()
        @(Get-ALServiceArguments $resolved.Config)|Should -Not -Contain '--allowed-hosts'
    }
    It 'rejects a busy port rather than stopping an unrelated process' {
        Mock -ModuleName AuthLens.Deploy Get-ALListener {9999}
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*owned by another process*'
        Test-Path (Join-Path $root 'app')|Should -BeFalse
    }
    It 'refuses an unassigned address before provisioning or binding a listener' {
        Mock -ModuleName AuthLens.Deploy Test-ALInstallerListenAddress {$false}
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*not assigned to this machine*'
        Test-Path (Join-Path $root 'app')|Should -BeFalse
    }
    It 'refuses existing unregistered data and leaves its sentinel unchanged' {
        $data=Join-Path $root 'data';New-Item -ItemType Directory $data|Out-Null
        Set-Content (Join-Path $data 'unrelated.csv') 'synthetic sentinel'
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*retained or unrelated*'
        Get-Content (Join-Path $data 'unrelated.csv')|Should -Be 'synthetic sentinel'
    }
    It 'rejects data nested inside the program directory' {
        $resolved.Config.DataDirectory=Join-Path $root 'app/data'
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*overlaps program*'
    }
    It 'rejects insufficient disk space before provisioning' {
        Mock -ModuleName AuthLens.Deploy Get-ALInstallerFreeBytes {0}
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*Insufficient free storage*'
        Test-Path (Join-Path $root 'app')|Should -BeFalse
    }
    It 'refuses manifest/runtime identity disagreement before installation provisioning' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance {[pscustomobject]@{validated=$true;read_only=$true;version='2.0.0-alpha.1';source_sha=('c'*40)}}
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*runtime identity disagree*'
        Test-Path (Join-Path $root 'app')|Should -BeFalse
    }
    It 'requires a declared Upgrade to target an existing identity' {
        {Get-ALServerSetupPlan $resolved $package Upgrade}|Should -Throw '*requires a verified existing Server*'
    }
    It 'rejects custom-account provisioning rather than silently falling back' {
        $resolved.Config.ServiceAccount='EXAMPLE\service-account'
        {Get-ALServerSetupPlan $resolved $package}|Should -Throw '*virtual service account only*'
    }
    It 'exports an immutable Unicode wizard plan without exposing certificate credentials' {
        $plan=Get-ALServerSetupPlan $resolved $package
        $path=Join-Path $TestDrive 'wizard-plan.ini'
        Write-ALServerSetupPlan $path $plan
        $text=Get-Content -LiteralPath $path -Raw
        $text|Should -Match '\[AuthLens\]'
        $text|Should -Not -Match 'synthetic-password-marker'
        {Write-ALServerSetupPlan $path $plan}|Should -Throw
    }
    It 'verifies same-build repair without program or data replacement and refuses a different build' {
        $script:Kind='upgrade';$script:Previous=Join-Path $TestDrive 'previous'
        New-Item -ItemType Directory -Force $script:Previous|Out-Null
        $script:PackageManifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $script:Previous 'build-manifest.json') -Encoding UTF8
        (Get-ALServerSetupPlan $resolved $package Repair).operation|Should -Be 'repair'
        $script:PackageManifest.source_sha=('c'*40)
        {Get-ALServerSetupPlan $resolved $package Repair}|Should -Throw '*identical verified product/build*'
        Should -Invoke -ModuleName AuthLens.Deploy Initialize-ALInstallation -Times 0
    }
    It 'permits only this verified staged Setup payload inside a fresh app directory' {
        $name=Split-Path $package -Leaf
        $staged=Join-Path $root ('app/setup/'+$name+'/payload/'+$name)
        New-Item -ItemType Directory -Force (Join-Path $staged 'server')|Out-Null
        Set-Content -LiteralPath (Join-Path $staged 'server/AuthLens.Api.exe') 'synthetic package'
        (Get-ALServerSetupPlan $resolved $staged Install).read_only|Should -BeTrue
        Set-Content -LiteralPath (Join-Path $root 'app/unrelated.txt') 'sentinel'
        {Get-ALServerSetupPlan $resolved $staged Install}|Should -Throw '*populated beyond*'
    }
    It 'accepts only hash-bound fresh Inno metadata and preserves every byte' {
        $name=Split-Path $package -Leaf
        $app=Join-Path $root 'app';$stage=Join-Path $app ('setup/'+$name)
        $staged=Join-Path $stage ('payload/'+$name)
        New-Item -ItemType Directory -Force (Join-Path $staged 'server')|Out-Null
        Set-Content (Join-Path $staged 'server/AuthLens.Api.exe') 'synthetic package'
        $script:PackageManifest|ConvertTo-Json|Set-Content (Join-Path $staged 'build-manifest.json')
        foreach($file in 'unins000.exe','unins000.dat'){Set-Content (Join-Path $app $file) ('synthetic '+$file)}
        {Get-ALServerSetupPlan $resolved $staged Install}|Should -Throw '*populated beyond*'
        $receipt=Join-Path $stage 'setup-metadata.ini'
        $lines=@('[AuthLensSetup]','schema=1',('manifest_sha256='+(Get-FileHash (Join-Path $staged 'build-manifest.json')).Hash.ToLowerInvariant()))
        foreach($file in 'unins000.exe','unins000.dat'){$lines+=($file+'='+(Get-FileHash (Join-Path $app $file)).Hash.ToLowerInvariant())}
        $lines|Set-Content $receipt -Encoding ASCII
        $before=@(Get-ChildItem $app -Recurse -File|ForEach-Object{(Get-FileHash $_.FullName).Hash})
        (Get-ALServerSetupPlan $resolved $staged Install $receipt).operation|Should -Be 'fresh installation'
        (Get-ALServerSetupPlan $resolved $staged Install $receipt).read_only|Should -BeTrue
        @(Get-ChildItem $app -Recurse -File|ForEach-Object{(Get-FileHash $_.FullName).Hash})|Should -Be $before
        Set-Content (Join-Path $app 'unins000.dat') 'changed'
        {Get-ALServerSetupPlan $resolved $staged Install $receipt}|Should -Throw '*metadata integrity changed*'
        Get-Content (Join-Path $app 'unins000.dat')|Should -Be 'changed'
        $lines[4]='unins000.dat='+(Get-FileHash (Join-Path $app 'unins000.dat')).Hash.ToLowerInvariant()
        $lines|Set-Content $receipt -Encoding ASCII
        Set-Content (Join-Path $stage 'operation-result.json') 'interrupted operation sentinel'
        {Get-ALServerSetupPlan $resolved $staged Install $receipt}|Should -Throw '*populated beyond*'
        Get-Content (Join-Path $stage 'operation-result.json')|Should -Be 'interrupted operation sentinel'
    }
    It 'does not trust a metadata receipt from another staging directory' {
        {Assert-ALFreshSetupMetadata (Join-Path $root 'app') (Join-Path $root 'app/setup/current') $package (Join-Path $TestDrive 'foreign.ini')}|Should -Throw '*outside this payload*'
    }
    It 'detects known legacy services by name without adopting or changing them' {
        Mock -ModuleName AuthLens.Deploy Get-ALService {param($Name) [pscustomobject]@{Exists=($Name-eq 'SapLens')}}
        $presence=Get-ALInstallerLegacyPresence -ServicesOnly
        $presence.present|Should -Be @('service:SapLens')
        $presence.policy|Should -Match 'never adopted, modified or deleted'
    }
    It 'returns a structured refusal for unsupported silent operations before any helper or system change' {
        $result=Invoke-TestPowerShell @('-File',(Join-Path $PSScriptRoot '../Install-AuthLens.ps1'),'-Mode','Server','-Operation','Downgrade')
        $result.Code|Should -Be 2
        $result.Output|Should -Match 'AUTHLENS-INSTALLER-RESULT:'
        $result.Output|Should -Match 'Unknown installer operation'
    }
}
