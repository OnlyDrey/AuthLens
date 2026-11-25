BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    function script:New-PlanConfig([hashtable]$Values) {
        $base = [ordered]@{ ListenAddress = '127.0.0.1'; AllowedHosts = @(); ProxyHosts = @(); TrustedProxies = @() }
        foreach ($key in $Values.Keys) { $base[$key] = $Values[$key] }
        [pscustomobject]$base
    }
}

# WP20: TLS certificate lifecycle helpers (D-003 address rule, client-trust notice, public certificate export, action policy).
Describe 'Loopback listener host rule (D-003)' {
    It 'refuses non-loopback allowed hosts on a loopback listener in every mode, including Auto' {
        { Get-ALServerAccessPlan (New-PlanConfig @{ AllowedHosts = @('enp-emea-dash1.example.test', 'enp-emea-dash1') }) } | Should -Throw '*loopback listener accepts loopback host names only*enp-emea-dash1.example.test*'
        { Get-ALServerAccessPlan (New-PlanConfig @{ AccessMode = 'Local'; AllowedHosts = @('lens.example.test') }) } | Should -Throw '*Local access requires loopback*'
        $local = Get-ALServerAccessPlan (New-PlanConfig @{ AllowedHosts = @('localhost', '127.0.0.1') })
        $local.network_access | Should -BeFalse
        $local.probe_authority | Should -Be '127.0.0.1'
    }
    It 'probes a network listener with the first allowed host and accepts a DNS-only host list' {
        $plan = Get-ALServerAccessPlan (New-PlanConfig @{ AccessMode = 'Corporate'; ListenAddress = '10.26.1.55'; AllowedHosts = @('enp-emea-dash1.example.test', 'enp-emea-dash1') })
        $plan.network_access | Should -BeTrue
        $plan.probe_authority | Should -Be 'enp-emea-dash1.example.test'
    }
}

Describe 'Client trust notice' {
    It 'explains self-signed, CA-issued and unchanged certificates without changing trust stores' {
        $old = [pscustomobject]@{ thumbprint_sha256 = ('1' * 64); self_signed = $true; issuer = 'CN=AuthLens local HTTPS' }
        $selfSigned = Get-ALCertificateTrustNotice $old ([pscustomobject]@{ thumbprint_sha256 = ('2' * 64); self_signed = $true; issuer = 'CN=AuthLens local HTTPS' })
        $selfSigned | Should -BeLike "*$('1' * 64)*$('2' * 64)*"
        $selfSigned | Should -BeLike '*Group Policy*'
        $selfSigned | Should -BeLike '*never the PFX or its password*'
        $selfSigned | Should -BeLike '*does not change any trust store*'
        Get-ALCertificateTrustNotice $old ([pscustomobject]@{ thumbprint_sha256 = ('3' * 64); self_signed = $false; issuer = 'CN=Synthetic Corporate CA' }) | Should -BeLike '*already trust that CA need no change*'
        Get-ALCertificateTrustNotice $old $old | Should -BeLike '*unchanged*'
    }
    It 'summarizes the packaged host description and tolerates releases without it' {
        ConvertTo-ALCertificateSummary $null | Should -BeNullOrEmpty
        ConvertTo-ALCertificateSummary ([pscustomobject]@{ validated = $true }) | Should -BeNullOrEmpty
        $summary = ConvertTo-ALCertificateSummary ([pscustomobject]@{ subject = 'CN=s'; issuer = 'CN=i'; self_signed = $false; not_after_utc = '2027-01-01T00:00:00Z'; days_remaining = 400
            thumbprint_sha256 = ('A' * 64); dns_names = @('lens.example.test'); ip_addresses = @(); missing_identities = @('10.26.1.55'); usable = $false; warnings = @() })
        @($summary.missing_identities) | Should -Be @('10.26.1.55')
        $summary.usable | Should -BeFalse
    }
}

Describe 'Public certificate export' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force (Join-Path $root 'config') | Out-Null
        $file = Join-Path $root 'config\deploy.json'
        @{ Root = $root; ListenAddress = '127.0.0.1'; Port = 18795 } | ConvertTo-Json | Set-Content $file
        $config = Read-AuthLensSettings $file -Packaged
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ exported = $true; path = $Arguments[1]; format = 'DER'; private_key_included = $false } }
    }
    It 'exports through the packaged host outside private folders only' {
        $target = Join-Path $TestDrive 'AuthLens-server.cer'
        (Export-ALPublicCertificate $config $target).private_key_included | Should -BeFalse
        Should -Invoke -ModuleName AuthLens.Deploy Invoke-ALMaintenance -Times 1 -ParameterFilter { $Arguments[0] -eq '--certificate-export-public' -and $Arguments[1] -eq $target }
        foreach ($private in (Join-Path $config.DataDirectory 'x.cer'), (Join-Path $root 'tls\x.cer'), (Join-Path $root 'keys\x.cer'), (Join-Path $config.WorkRoot 'x.cer')) {
            { Export-ALPublicCertificate $config $private } | Should -Throw '*outside the installation*'
        }
        { Export-ALPublicCertificate $config 'relative.cer' } | Should -Throw '*absolute destination*'
    }
    It 'refuses a result that claims private key material' {
        Mock -ModuleName AuthLens.Deploy Invoke-ALMaintenance { [pscustomobject]@{ exported = $true; private_key_included = $true } }
        { Export-ALPublicCertificate $config (Join-Path $TestDrive 'other.cer') } | Should -Throw '*refused*'
    }
    It 'is neither simulated nor approval-gated: -DryRun is refused, the export runs without -Yes' {
        { Get-ALActionPolicy 'ExportCertificate' -DryRun } | Should -Throw '*-DryRun is not supported for ExportCertificate*'
        $policy = Get-ALActionPolicy 'ExportCertificate'
        $policy.mode | Should -Be 'execute'
        $policy.approval_required | Should -BeFalse
    }
}
