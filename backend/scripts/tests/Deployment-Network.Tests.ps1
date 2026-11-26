BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Deployment probes follow the runtime access boundary' {
    BeforeEach {
        $config=[pscustomobject]@{ListenAddress='127.0.0.1';Port=18795;AllowedHosts=@('server.example.invalid','server');CertificatePath='synthetic.pfx';CertificatePasswordFile='synthetic-password-file';ServiceName='AuthLens';ReadyTimeoutSeconds=3}
        Mock -ModuleName AuthLens.Deploy Invoke-ALHttp {[pscustomobject]@{Status=200;Body='{}'}}
    }
    It 'uses loopback authority for a loopback listener and refuses unreachable corporate hosts (D-003)' {
        # D-003 (6fbfd48): the probe always uses the loopback authority; non-loopback hosts can never reach a loopback listener, so the service configuration refuses them.
        Invoke-ALConfiguredHttp $config '/health/ready'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 1 -ParameterFilter {$Url -eq 'https://127.0.0.1:18795/health/ready' -and $HostHeader -eq '127.0.0.1:18795' -and $CertificatePath -eq 'synthetic.pfx'}
        {Get-ALServiceArguments ([pscustomobject]@{ListenAddress=$config.ListenAddress;Port=$config.Port;DataDirectory='synthetic';AllowedHosts=$config.AllowedHosts;CertificatePath=$config.CertificatePath;CertificatePasswordFile=$config.CertificatePasswordFile;TrustedProxies=@()})}|Should -Throw '*loopback host names only*'
        @(Get-ALServiceArguments ([pscustomobject]@{ListenAddress=$config.ListenAddress;Port=$config.Port;DataDirectory='synthetic';AllowedHosts=@('localhost');CertificatePath=$config.CertificatePath;CertificatePasswordFile=$config.CertificatePasswordFile;TrustedProxies=@()}))|Should -Not -Contain '--network'
    }
    It 'uses a configured authority for a specific LAN listener' {
        $config.ListenAddress='192.168.10.20'
        Invoke-ALConfiguredHttp $config '/health/ready'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 1 -ParameterFilter {$Url -eq 'https://192.168.10.20:18795/health/ready' -and $HostHeader -eq 'server.example.invalid:18795'}
    }
    It 'formats IPv6 loopback correctly' {
        $config.ListenAddress='::1'
        Invoke-ALConfiguredHttp $config '/health/ready'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 1 -ParameterFilter {$Url -eq 'https://[::1]:18795/health/ready' -and $HostHeader -eq '[::1]:18795'}
    }
    It 'refuses wildcard destinations before any request' -ForEach @(@{Address='0.0.0.0'},@{Address='::'}) {
        $config.ListenAddress=$Address
        {Invoke-ALConfiguredHttp $config '/health/ready'}|Should -Throw '*Wildcard listeners*'
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALHttp -Times 0
    }
    It 'fails immediately on deterministic HTTP policy failure' -ForEach @(@{Status=421},@{Status=403},@{Status=404}) {
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{State='Running';ProcessId=123}}
        Mock -ModuleName AuthLens.Deploy Get-ALListener {123}
        Mock -ModuleName AuthLens.Deploy Invoke-ALConfiguredHttp {[pscustomobject]@{Status=$Status;Body='private error text never printed'}}
        Mock -ModuleName AuthLens.Deploy Start-Sleep {throw 'Permanent failure must not sleep'}
        {Wait-ALReady $config ('a'*40) '2.0.0'}|Should -Throw '*Permanent readiness policy/TLS failure*'
        Should -Invoke -ModuleName AuthLens.Deploy Start-Sleep -Times 0
    }
}
Describe 'Exact certificate identity is required for local readiness' {
    It 'accepts only the configured unexpired leaf and rejects missing, changed or expired identity' {
        Initialize-ALPinnedHttp
        $key=[Security.Cryptography.RSA]::Create(2048)
        $certificate=$null;$other=$null
        try{
            $request=[Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=synthetic.example.invalid',$key,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $certificate=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1),[DateTimeOffset]::UtcNow.AddDays(1))
            $other=$request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1),[DateTimeOffset]::UtcNow.AddDays(1))
            [AuthLensDeployment.PinnedHttp]::Matches($certificate,$certificate.RawData,[DateTime]::UtcNow)|Should -BeTrue
            [AuthLensDeployment.PinnedHttp]::Matches($other,$certificate.RawData,[DateTime]::UtcNow)|Should -BeFalse
            [AuthLensDeployment.PinnedHttp]::Matches($certificate,$certificate.RawData,[DateTime]::UtcNow.AddDays(2))|Should -BeFalse
            [AuthLensDeployment.PinnedHttp]::Matches($null,$certificate.RawData,[DateTime]::UtcNow)|Should -BeFalse
        }finally{if($certificate){$certificate.Dispose()};if($other){$other.Dispose()};$key.Dispose()}
    }
}
Describe 'Explicit Server access modes preserve the runtime contract' {
    BeforeEach {
        $config=[pscustomobject]@{AccessMode='Local';ListenAddress='127.0.0.1';AllowedHosts=@('localhost');ProxyHosts=@();TrustedProxies=@();Port=18795;DataDirectory='synthetic';CertificatePath='synthetic.pfx';CertificatePasswordFile='synthetic-password-file'}
    }
    It 'keeps local access loopback-only without network service arguments' {
        Set-StrictMode -Version Latest
        (Get-ALServerAccessPlan $config).network_access|Should -BeFalse
        @(Get-ALServiceArguments $config)|Should -Not -Contain '--network'
        $config.AllowedHosts=@('server.example.invalid')
        {Get-ALServerAccessPlan $config}|Should -Throw '*Local access requires*'
    }
    It 'passes only an explicitly configured operator source directory to the service' {
        $config | Add-Member NoteProperty SourceDirectory '\\files.example.invalid\exports\AuthLens'
        $arguments=@(Get-ALServiceArguments $config)
        $arguments[$arguments.IndexOf('--source-dir')+1]|Should -Be '\\files.example.invalid\exports\AuthLens'
    }
    It 'enables corporate mode only for an explicit private interface and host policy' {
        $config.AccessMode='Corporate';$config.ListenAddress='10.0.7.50';$config.AllowedHosts=@('server.example.invalid')
        @(Get-ALServiceArguments $config)|Should -Contain '--network'
        $config.TrustedProxies=@('10.0.7.1')
        {Get-ALServerAccessPlan $config}|Should -Throw '*Corporate access requires*'
    }
    It 'requires complete reverse-proxy policy on a private backend interface' {
        $config.AccessMode='ReverseProxy'
        {Get-ALServerAccessPlan $config}|Should -Throw '*Reverse proxy access requires*'
        $config.ListenAddress='10.0.7.50';$config.AllowedHosts=@('backend.example.invalid');$config.TrustedProxies=@('10.0.7.10');$config.ProxyHosts=@('public.example.invalid')
        (Get-ALServerAccessPlan $config).network_access|Should -BeTrue
        @(Get-ALServiceArguments $config)|Should -Contain '--proxy-hosts'
    }
    It 'preserves old loopback configurations without an explicit mode and refuses unreachable hosts in them (D-003)' {
        $config.PSObject.Properties.Remove('AccessMode');$config.AllowedHosts=@('localhost')
        (Get-ALServerAccessPlan $config).access_mode|Should -Be 'Auto'
        @(Get-ALServiceArguments $config)|Should -Not -Contain '--network'
        $config.AllowedHosts=@('server.example.invalid')
        {Get-ALServerAccessPlan $config}|Should -Throw '*loopback host names only*'
    }
    It 'refuses unsafe listener <Address> before service configuration' -ForEach @(@{Address='0.0.0.0'},@{Address='::'},@{Address='8.8.8.8'}) {
        $config.ListenAddress=$Address
        {Get-ALServiceArguments $config}|Should -Throw
    }
}
