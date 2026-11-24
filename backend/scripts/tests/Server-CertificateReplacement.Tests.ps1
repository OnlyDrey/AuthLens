BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
# Installed-certificate replacement transaction with the platform layer mocked (no SCM, sc.exe, icacls, listener or real certificate).
# Synthetic files only; the real configuration parser, service-argument builder and comparison run unchanged.
Describe 'Installed Server certificate replacement' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $release = Join-Path $script:Root 'releases\AuthLens-2.0.0-synthetic-win-x64'
        foreach ($dir in (Join-Path $script:Root 'config'), (Join-Path $script:Root 'deployment'), (Join-Path $script:Root 'tls\setup-1'), $release, (Join-Path $script:Root 'source')) { New-Item -ItemType Directory -Force $dir | Out-Null }
        Set-Content (Join-Path $release 'build-manifest.json') '{"product":"AuthLens","version":"2.0.0","source_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' -Encoding ASCII
        $script:OldCert = Join-Path $script:Root 'tls\setup-1\server.pfx'; $script:OldPassword = Join-Path $script:Root 'tls\setup-1\cert-password'
        $script:NewCert = Join-Path $script:Root 'source\renewed.pfx'; $script:NewPassword = Join-Path $script:Root 'source\renewed-password'
        foreach ($file in $script:OldCert, $script:OldPassword, $script:NewCert, $script:NewPassword) { Set-Content $file 'synthetic' -Encoding ASCII }
        $script:ConfigFile = Join-Path $script:Root 'config\deploy.json'
        @{ Root = $script:Root; RepositoryPath = $script:Root; ListenAddress = '127.0.0.1'; Port = 18795; AccessMode = 'Local'; AllowedHosts = @('localhost')
           CertificatePath = $script:OldCert; CertificatePasswordFile = $script:OldPassword; ReadyTimeoutSeconds = 5 } | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
        $script:OriginalBytes = [IO.File]::ReadAllBytes($script:ConfigFile)
        $script:Config = Read-AuthLensSettings $script:ConfigFile
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $release }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
        Mock -ModuleName AuthLens.Deploy Assert-ALNoPendingRepair {}
        Mock -ModuleName AuthLens.Deploy Read-ALJournal { $null }
        $script:ServicePath = Get-ALBinaryPath $script:Config
        $servicePath = $script:ServicePath
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; ProcessId = 42; Account = 'NT SERVICE\AuthLens'; PathName = $servicePath } }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Test-ALServiceBinary { $true }
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $true; read_only = $true } }
        $root = $script:Root
        Mock -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial {
            param($Config, $Directory)
            if (Test-Path -LiteralPath $Directory) { throw 'exists' }
            New-Item -ItemType Directory $Directory | Out-Null
            foreach ($name in 'server.pfx', 'cert-password', 'server.cer') { Set-Content (Join-Path $Directory $name) 'imported' -Encoding ASCII }
            [pscustomobject]@{ certificate = (Join-Path $Directory 'server.pfx'); password_file = (Join-Path $Directory 'cert-password'); public_certificate = (Join-Path $Directory 'server.cer') }
        }
        Mock -ModuleName AuthLens.Deploy Grant-ALAccess {}
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 43 } }
        $script:Pending = Join-Path $script:Root 'deployment\certificate-pending.json'
    }

    It 'validates a dry run with the packaged host and changes nothing' {
        $result = Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword -DryRun
        $result.dry_run | Should -BeTrue
        $result.certificate_validated | Should -BeTrue
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter { $Arguments[0] -eq '--server-preflight' -and ($Arguments -join ' ') -like "*--cert $($script:NewCert)*" }
        Should -Invoke -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial -Times 0
        Should -Invoke -ModuleName AuthLens.Deploy Stop-ALService -Times 0
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        Test-Path $script:Pending | Should -BeFalse
    }

    It 'refuses a certificate the packaged host does not validate before anything changes' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ validated = $false; read_only = $true } }
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*did not validate the new certificate*'
        Should -Invoke -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial -Times 0
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
    }

    It 'refuses relative paths, PEM files and a service command line that differs from the configuration' {
        { Invoke-ALReplaceCertificate $script:Config 'renewed.pfx' $script:NewPassword } | Should -Throw '*absolute*'
        $pem = Join-Path $script:Root 'source\renewed.pem'; Set-Content $pem 'synthetic'
        { Invoke-ALReplaceCertificate $script:Config $pem $script:NewPassword } | Should -Throw '*PFX/PKCS12*'
        $drifted = $script:ServicePath + ' --trusted-proxies 10.0.0.1'
        Mock -ModuleName AuthLens.Deploy Get-ALService { [pscustomobject]@{ Exists = $true; State = 'Running'; ProcessId = 42; Account = 'NT SERVICE\AuthLens'; PathName = $drifted } }.GetNewClosure()
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*command line differs*'
        Should -Invoke -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial -Times 0
    }

    It 'imports into a new TLS version, switches configuration and command line, and pins readiness to the new certificate' {
        $result = Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword
        $result.replaced | Should -BeTrue
        $result.certificate | Should -BeLike (Join-Path $script:Root 'tls\renew-*\server.pfx')
        $result.previous_certificate_retained | Should -Be $script:OldCert
        Test-Path $script:OldCert | Should -BeTrue
        $saved = Read-AuthLensSettings $script:ConfigFile
        $saved.CertificatePath | Should -Be $result.certificate
        $saved.ListenAddress | Should -Be '127.0.0.1'
        @($saved.AllowedHosts) | Should -Be @('localhost')
        $newCertificate = $result.certificate
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -like "*$newCertificate*" }
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter { $Config.CertificatePath -eq $newCertificate -and $Commit -eq ('a' * 40) }
        Should -Invoke -ModuleName AuthLens.Deploy Grant-ALAccess -Times 1 -ParameterFilter { $Config.CertificatePath -eq $newCertificate }
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 2
        Test-Path $script:Pending | Should -BeFalse
        @(Get-ChildItem (Join-Path $script:Root 'config') -Filter '*.next-*').Count | Should -Be 0
    }

    It 'restores the previous configuration and command line when readiness fails' {
        $calls = [Collections.Generic.List[string]]::new()
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary { param($Name, $BinaryPath) $calls.Add($BinaryPath) }.GetNewClosure()
        $script:WaitCount = 0
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { $script:WaitCount++; if ($script:WaitCount -eq 1) { Stop-AL 'Permanent readiness policy/TLS failure (HTTP 421)' 1 }; [pscustomobject]@{ process_id = 44 } }
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*previous certificate was restored*HTTP 421*'
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        $calls.Count | Should -Be 2
        $calls[1] | Should -Be $script:ServicePath
        Should -Invoke -ModuleName AuthLens.Deploy Wait-ALReady -Times 1 -ParameterFilter { $Config.CertificatePath -eq $script:OldCert }
        Test-Path $script:Pending | Should -BeFalse
    }

    It 'restores an interrupted replacement first and does not import again' {
        Mock -ModuleName AuthLens.Deploy Stop-ALService { throw [System.Management.Automation.PipelineStoppedException]::new() } -ParameterFilter { $false }
        # Simulate an interruption after the configuration switched: the pending record and the new configuration remain.
        $first = $null
        Mock -ModuleName AuthLens.Deploy Start-ALService { throw 'host interrupted' }
        Mock -ModuleName AuthLens.Deploy Restore-ALCertificateReplacement { throw 'interrupted before restoration' }
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*interrupted before restoration*'
        Test-Path $script:Pending | Should -BeTrue
        (Read-AuthLensSettings $script:ConfigFile).CertificatePath | Should -BeLike '*renew-*'
        # The next run (with restoration available again) restores the previous certificate before anything else.
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Remove-Variable first
        Import-TestDeploymentModule
        Mock -ModuleName AuthLens.Deploy Write-ALLog {}
        Mock -ModuleName AuthLens.Deploy Assert-ALNoPendingRepair {}
        Mock -ModuleName AuthLens.Deploy Read-ALJournal { $null }
        $release = Join-Path $script:Root 'releases\AuthLens-2.0.0-synthetic-win-x64'
        Mock -ModuleName AuthLens.Deploy Get-ALLink { $release }.GetNewClosure()
        Mock -ModuleName AuthLens.Deploy Copy-ALServerTlsMaterial { throw 'must not import again' }
        Mock -ModuleName AuthLens.Deploy Stop-ALService {}
        Mock -ModuleName AuthLens.Deploy Start-ALService {}
        Mock -ModuleName AuthLens.Deploy Set-ALServiceBinary {}
        Mock -ModuleName AuthLens.Deploy Wait-ALReady { [pscustomobject]@{ process_id = 45 } }
        $current = Read-AuthLensSettings $script:ConfigFile
        $result = Invoke-ALReplaceCertificate $current $script:NewCert $script:NewPassword
        $result.restored_previous | Should -BeTrue
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
        Test-Path $script:Pending | Should -BeFalse
        $servicePath = $script:ServicePath
        Should -Invoke -ModuleName AuthLens.Deploy Set-ALServiceBinary -Times 1 -ParameterFilter { $BinaryPath -eq $servicePath }
    }

    It 'keeps a pending record that belongs to another configuration or is damaged' {
        $record = @{ schema = 1; config_file = 'C:\other\deploy.json'; previous_config = [Convert]::ToBase64String($script:OriginalBytes); previous_sha256 = 'x'; previous_binary = 'x' }
        Set-Content $script:Pending ($record | ConvertTo-Json) -Encoding UTF8
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*does not belong to this configuration*'
        $record.config_file = $script:ConfigFile
        Set-Content $script:Pending ($record | ConvertTo-Json) -Encoding UTF8
        { Invoke-ALReplaceCertificate $script:Config $script:NewCert $script:NewPassword } | Should -Throw '*damaged*'
        Test-Path $script:Pending | Should -BeTrue
        [IO.File]::ReadAllBytes($script:ConfigFile) | Should -Be $script:OriginalBytes
    }
}
