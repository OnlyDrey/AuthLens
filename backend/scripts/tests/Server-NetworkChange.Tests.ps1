BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
# Post-installation network change (G-001) with the platform layer mocked: no SCM, sc.exe, icacls, firewall, listener or certificate is touched.
# The real configuration parser, access-mode rules, argument builder, drift comparison and transaction run unchanged on a Setup-shaped
# configuration (no RepositoryPath) with synthetic files in TestDrive.
Describe 'Installed Server network configuration change' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $release = Join-Path $script:Root 'releases\AuthLens-2.0.0-synthetic-win-x64'
        foreach ($dir in (Join-Path $script:Root 'config'), (Join-Path $script:Root 'deployment'), (Join-Path $script:Root 'tls\setup-1'), $release) { New-Item -ItemType Directory -Force $dir | Out-Null }
        Set-Content (Join-Path $release 'build-manifest.json') '{"product":"AuthLens","version":"2.0.0","source_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}' -Encoding ASCII
        $cert = Join-Path $script:Root 'tls\setup-1\server.pfx'; $password = Join-Path $script:Root 'tls\setup-1\cert-password'
        foreach ($file in $cert, $password) { Set-Content $file 'synthetic' -Encoding ASCII }
        $script:ConfigFile = Join-Path $script:Root 'config\deploy.json'
        # Exactly the keys Server Setup publishes for a Corporate installation.
        [ordered]@{ Root = $script:Root; AccessMode = 'Corporate'; ListenAddress = '10.20.30.40'; Port = 18795; AllowedHosts = @('lens.example.org', '10.20.30.40')
            ProxyHosts = @(); TrustedProxies = @(); CertificatePath = $cert; CertificatePasswordFile = $password; ReadyTimeoutSeconds = 5 } | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
        $script:OriginalBytes = [IO.File]::ReadAllBytes($script:ConfigFile)
        $script:Config = Read-AuthLensSettings $script:ConfigFile
        $script:Pending = Join-Path $script:Root 'deployment\configuration-pending.json'
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $release }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
        Mock -ModuleName AuthLens.Deploy Assert-ALNoPendingRepair {}
        Mock -ModuleName AuthLens.Deploy Read-ALJournal { $null }
        $script:ServicePath = Get-ALBinaryPath $script:Config
        $servicePath = $script:ServicePath
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; ProcessId = 42; Account = 'NT SERVICE\AuthLens'; PathName = $servicePath } }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
        Mock -ModuleName AuthLens.Deploy Test-ALInstallerListenAddress { $true }
        Mock -ModuleName AuthLens.Deploy Get-ALListener { @() }
        Mock -ModuleName AuthLens.Deploy Get-ALOwnedFirewallReceipts { , @() }
        Mock -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange { @{ changed = $true } }
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $true; read_only = $true } }
        Mock -ModuleName AuthLens.Deploy Grant-ALAccess {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 43; identity = @{ version = '2.0.0' } } }
    }

    It 'returns a consolidated summary for a dry run and changes nothing' {
        $result = Invoke-ALNetworkChange $script:Config @{ Port = 18796; AllowedHosts = @('lens.example.org,lens2.example.org') } -DryRun
        $result.dry_run | Should -BeTrue
        $result.summary.current.port | Should -Be 18795
        $result.summary.proposed.port | Should -Be 18796
        @($result.summary.proposed.allowed_hosts) | Should -Be @('lens.example.org', 'lens2.example.org')
        @($result.summary.changed_settings) | Should -Be @('AllowedHosts', 'Port')
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter { $Arguments[0] -eq '--server-preflight' -and ($Arguments -join ' ') -like '*--port 18796*' }
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        Test-Path $script:Pending | Should -BeFalse
    }

    It 'validates before changing anything' {
        { Invoke-ALNetworkChange $script:Config @{ AccessMode = 'Local' } } | Should -Throw '*Local access requires loopback*'
        { Invoke-ALNetworkChange $script:Config @{ AllowedHosts = @('*.example.org') } } | Should -Throw '*no wildcards*'
        { Invoke-ALNetworkChange $script:Config @{ DataDirectory = 'C:\other' } } | Should -Throw '*cannot be changed by a network configuration change*'
        { Invoke-ALNetworkChange $script:Config @{ Port = 18795 } } | Should -Throw '*equal the current configuration*'
        { Invoke-ALNetworkChange $script:Config @{ AccessMode = 'ReverseProxy' } } | Should -Throw '*Reverse proxy access requires*'
        Mock -ModuleName AuthLens.Deploy Test-ALInstallerListenAddress { $false }
        { Invoke-ALNetworkChange $script:Config @{ ListenAddress = '10.20.30.41' } } | Should -Throw '*not assigned to this machine*'
        Mock -ModuleName AuthLens.Deploy Test-ALInstallerListenAddress { $true }
        Mock -ModuleName AuthLens.Deploy Get-ALListener { 999 }
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } } | Should -Throw '*used by process 999*'
        Mock -ModuleName AuthLens.Deploy Get-ALListener { @() }
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $false; read_only = $true } }
        { Invoke-ALNetworkChange $script:Config @{ AllowedHosts = @('other.example.org') } } | Should -Throw '*did not validate the proposed configuration*'
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
    }

    It 'refuses a moved listener that would orphan an installer-owned firewall rule unless the firewall decision is explicit' {
        Mock -ModuleName AuthLens.Deploy Get-ALOwnedFirewallReceipts { , @([pscustomobject]@{ name = 'AuthLens-Setup-x' }) }
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } } | Should -Throw '*Decide explicitly*'
        $result = Invoke-ALNetworkChange $script:Config @{ Port = 18796 } '10.20.0.0/16' 'Domain' -ApproveFirewall
        $result.changed | Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange -Times 1 -ParameterFilter { $Config.Port -eq 18796 -and $Sources -eq '10.20.0.0/16' -and -not $Remove }
    }

    It 'applies the change, keeps other settings, switches the command line and verifies readiness on the new listener' {
        $result = Invoke-ALNetworkChange $script:Config @{ Port = 18796; AllowedHosts = @('lens.example.org') }
        $result.changed | Should -BeTrue
        $result.firewall_recovery_required | Should -BeFalse
        $saved = Read-AuthLensSettings $script:ConfigFile
        $saved.Port | Should -Be 18796
        @($saved.AllowedHosts) | Should -Be @('lens.example.org')
        $saved.AccessMode | Should -Be 'Corporate'
        $saved.CertificatePath | Should -Be $script:Config.CertificatePath
        $saved.ExecutionContext | Should -Be 'packaged'
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -like '*--port 18796*' }
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter { [int]$Config.Port -eq 18796 -and $Commit -eq ('b' * 40) }
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange -Times 0
        Test-Path $script:Pending | Should -BeFalse
        @(Get-ChildItem (Join-Path $script:Root 'config') -Filter '*.next-*').Count | Should -Be 0
    }

    It 'restores the previous configuration and command line when readiness fails' {
        $calls = [Collections.Generic.List[string]]::new()
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary { param($Name, $BinaryPath) $calls.Add($BinaryPath) }.GetNewClosure()
        $script:Waits = 0
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { $script:Waits++; if ($script:Waits -eq 1) { Stop-AL 'Permanent readiness policy/TLS failure (HTTP 421)' 1 }; [pscustomobject]@{ process_id = 44 } }
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } } | Should -Throw '*previous configuration was restored*HTTP 421*'
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        $calls.Count | Should -Be 2
        $calls[1] | Should -Be $script:ServicePath
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter { [int]$Config.Port -eq 18795 }
        Test-Path $script:Pending | Should -BeFalse
    }

    It 'restores an interrupted change on the next run and through Recover' {
        Mock -ModuleName AuthLens.Deploy Start-ALService { throw 'host interrupted' }
        Mock -ModuleName AuthLens.Deploy Restore-ALConfigurationChange { throw 'interrupted before restoration' }
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } } | Should -Throw '*interrupted before restoration*'
        Test-Path $script:Pending | Should -BeTrue
        (Read-AuthLensSettings $script:ConfigFile).Port | Should -Be 18796
        { Invoke-ALNetworkChange $script:Config @{ Port = 18797 } -DryRun } | Should -Throw '*interrupted configuration change is recorded*'
        # Restoration available again: Recover (the Deploy-AuthLens Recover path) restores the previous bytes and command line.
        Import-TestDeploymentModule
        $release = Join-Path $script:Root 'releases\AuthLens-2.0.0-synthetic-win-x64'
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $release }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 45 } }
        $result = Invoke-ALConfigurationRecover (Read-AuthLensSettings $script:ConfigFile)
        $result.restored_previous | Should -BeTrue
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        Test-Path $script:Pending | Should -BeFalse
        $servicePath = $script:ServicePath
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -eq $servicePath }
        Invoke-ALConfigurationRecover (Read-AuthLensSettings $script:ConfigFile) | Should -BeNullOrEmpty
    }

    It 'refuses configuration drift and reports a failed firewall transition without undoing a ready service' {
        $drifted = $script:ServicePath + ' --trusted-proxies 10.0.0.1'
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; ProcessId = 42; Account = 'NT SERVICE\AuthLens'; PathName = $drifted } }.GetNewClosure()
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } } | Should -Throw '*command line differs*'
        $servicePath = $script:ServicePath
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; ProcessId = 42; Account = 'NT SERVICE\AuthLens'; PathName = $servicePath } }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Invoke-ALInstallerFirewallChange { throw 'firewall transition failed' }
        $result = Invoke-ALNetworkChange $script:Config @{ Port = 18796 } -RemoveFirewall
        $result.changed | Should -BeTrue
        $result.firewall_recovery_required | Should -BeTrue
        (Read-AuthLensSettings $script:ConfigFile).Port | Should -Be 18796
    }

    # WP20 / D-004: a change whose hosts the certificate lacks names the missing identity; a combined change applies the certificate atomically.
    It 'names the identities the certificate lacks and changes nothing' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { throw 'Server preflight refused the TLS certificate' } -ParameterFilter { $Arguments[0] -eq '--server-preflight' }
        Mock -ModuleName AuthLens.Deploy Get-ALCertificateInfo { [pscustomobject]@{ thumbprint_sha256 = ('A' * 64); subject = 'CN=x'; issuer = 'CN=x'; self_signed = $true; missing_identities = @('lens2.example.org'); usable = $false } }
        { Invoke-ALNetworkChange $script:Config @{ AllowedHosts = @('lens.example.org,lens2.example.org') } } | Should -Throw '*does not cover lens2.example.org*'
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
    }

    It 'changes network settings and certificate in one recorded transaction and reports the client-trust impact' {
        $newCert = Join-Path $TestDrive "renewed-$([guid]::NewGuid().ToString('N')).pfx"; $newPassword = "$newCert.password"
        foreach ($file in $newCert, $newPassword) { Set-Content $file 'synthetic' -Encoding ASCII }
        $tlsDir = Join-Path $script:Root 'tls\renew-synthetic'
        Mock -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial { [pscustomobject]@{ certificate = (Join-Path $tlsDir 'server.pfx'); password_file = (Join-Path $tlsDir 'cert-password'); public_certificate = (Join-Path $tlsDir 'server.cer') } }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Get-ALCertificateInfo { [pscustomobject]@{ thumbprint_sha256 = ('1' * 64); self_signed = $true; issuer = 'CN=AuthLens local HTTPS'; missing_identities = @() } }
        Mock -ModuleName AuthLens.Deploy Get-ALCertificateInfo { [pscustomobject]@{ thumbprint_sha256 = ('2' * 64); self_signed = $false; issuer = 'CN=Synthetic Corporate CA'; missing_identities = @() } } -ParameterFilter { "$($Config.CertificatePath)" -like '*renewed-*' }
        $plan = Invoke-ALNetworkChange $script:Config @{ AllowedHosts = @('lens.example.org,lens2.example.org') } -DryRun -CertificateFile $newCert -CertificatePasswordFile $newPassword
        $plan.summary.operation | Should -Be 'network and certificate change'
        $plan.summary.certificate_current.thumbprint_sha256 | Should -Be ('1' * 64)
        $plan.summary.certificate_proposed.thumbprint_sha256 | Should -Be ('2' * 64)
        $plan.summary.client_trust_notice | Should -BeLike '*Synthetic Corporate CA*'
        Should -Invoke -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter { $Arguments[0] -eq '--server-preflight' -and ($Arguments -join ' ') -like "*$newCert*" -and ($Arguments -join ' ') -like '*lens2.example.org*' }
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes

        $result = Invoke-ALNetworkChange $script:Config @{ AllowedHosts = @('lens.example.org,lens2.example.org') } -CertificateFile $newCert -CertificatePasswordFile $newPassword
        $result.changed | Should -BeTrue
        $saved = Read-AuthLensSettings $script:ConfigFile
        @($saved.AllowedHosts) | Should -Be @('lens.example.org', 'lens2.example.org')
        $saved.CertificatePath | Should -Be (Join-Path $tlsDir 'server.pfx')
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -like "*$tlsDir*" -and $BinaryPath -like '*lens2.example.org*' }
        Test-Path $script:Pending | Should -BeFalse
    }

    It 'restores the previous certificate and network settings when the combined change fails readiness' {
        $newCert = Join-Path $TestDrive "renewed-$([guid]::NewGuid().ToString('N')).pfx"; $newPassword = "$newCert.password"
        foreach ($file in $newCert, $newPassword) { Set-Content $file 'synthetic' -Encoding ASCII }
        $tlsDir = Join-Path $script:Root 'tls\renew-failed'
        Mock -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial { [pscustomobject]@{ certificate = (Join-Path $tlsDir 'server.pfx'); password_file = (Join-Path $tlsDir 'cert-password'); public_certificate = '' } }.GetNewClosure()
        $script:Waits = 0
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { $script:Waits++; if ($script:Waits -eq 1) { throw 'synthetic readiness failure on the new certificate' }; [pscustomobject]@{ process_id = 44 } }
        { Invoke-ALNetworkChange $script:Config @{ Port = 18796 } -CertificateFile $newCert -CertificatePasswordFile $newPassword } | Should -Throw '*previous configuration was restored*'
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        $servicePath = $script:ServicePath
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -eq $servicePath }
        Test-Path $script:Pending | Should -BeFalse
    }
}
