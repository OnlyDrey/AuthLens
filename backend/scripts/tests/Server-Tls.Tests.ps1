BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
}
Describe 'Local TLS generation and import (synthetic private test material)' {
    BeforeEach {
        $directory=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        # Exercise actual Windows crypto/file I/O; production administrative ACL creation is a separate elevated acceptance check.
        Mock -ModuleName AuthLens.Deploy New-ALInstallerTlsDirectory {
            param($Path)
            if(Test-Path -LiteralPath $Path){throw 'TLS destination already exists'}
            New-Item -ItemType Directory -Path $Path|Out-Null
        }
    }
    It 'creates encrypted PFX, a separate random password and public certificate without returning secrets' {
        $result=New-ALServerTlsMaterial $directory '127.0.0.1' @('localhost')
        $result.trust_store_modified|Should -BeFalse
        $result.self_signed|Should -BeTrue
        $password=[IO.File]::ReadAllText($result.password_file)
        [Convert]::FromBase64String($password).Length|Should -Be 32
        $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($result.certificate,$password,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
        try{
            $certificate.HasPrivateKey|Should -BeTrue
            $certificate.PublicKey.Key.KeySize|Should -Be 3072
            ($certificate.NotAfter-$certificate.NotBefore).TotalDays|Should -BeGreaterThan 364
            $certificate.Subject|Should -Be $certificate.Issuer
            @($certificate.Extensions|Where-Object{$_.Oid.Value -eq '2.5.29.17'}).Count|Should -Be 1
            ($result|ConvertTo-Json -Compress).Contains($password)|Should -BeFalse
        }finally{$certificate.Dispose();$password=$null}
        Test-Path -LiteralPath $result.public_certificate|Should -BeTrue
    }
    It 'refuses wildcard and URL names before writing material' {
        {New-ALServerTlsMaterial $directory '127.0.0.1' @('*.example.org')}|Should -Throw '*wildcards*'
        {New-ALServerTlsMaterial $directory '127.0.0.1' @('https://example.org')}|Should -Throw '*URLs*'
        Test-Path -LiteralPath $directory|Should -BeFalse
    }
    It 'refuses wildcard listening addresses' {
        {New-ALServerTlsMaterial $directory '0.0.0.0' @()}|Should -Throw '*explicit listening IP*'
        {New-ALServerTlsMaterial $directory '::' @()}|Should -Throw '*explicit listening IP*'
    }
    It 'never replaces a previously generated key or certificate' {
        $result=New-ALServerTlsMaterial $directory '127.0.0.1' @()
        $hash=(Get-FileHash -LiteralPath $result.certificate).Hash
        {New-ALServerTlsMaterial $directory '127.0.0.1' @()}|Should -Throw '*already exists*'
        (Get-FileHash -LiteralPath $result.certificate).Hash|Should -Be $hash
    }
    It 'imports exact bytes into a new version while preserving original TLS' {
        $source=New-ALServerTlsMaterial $directory '127.0.0.1' @()
        $config=[pscustomobject]@{CertificatePath=$source.certificate;CertificatePasswordFile=$source.password_file}
        $destination=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $copy=Copy-ALServerTlsMaterial $config $destination
        (Get-FileHash -LiteralPath $copy.certificate).Hash|Should -Be (Get-FileHash -LiteralPath $source.certificate).Hash
        (Get-FileHash -LiteralPath $copy.password_file).Hash|Should -Be (Get-FileHash -LiteralPath $source.password_file).Hash
        $public=[Security.Cryptography.X509Certificates.X509Certificate2]::new($copy.public_certificate)
        try{$public.HasPrivateKey|Should -BeFalse}finally{$public.Dispose()}
        {Copy-ALServerTlsMaterial $config $destination}|Should -Throw '*already exists*'
    }
    It 'never silently relabels PEM as PKCS12' {
        $config=[pscustomobject]@{CertificatePath=(Join-Path $TestDrive 'combined.pem');CertificatePasswordFile=(Join-Path $TestDrive 'password')}
        {Copy-ALServerTlsMaterial $config $directory}|Should -Throw '*requires a PFX*'
        Test-Path -LiteralPath $directory|Should -BeFalse
    }
}
Describe 'Fresh configuration publication with imported TLS' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach($name in 'config','tls'){New-Item -ItemType Directory -Path (Join-Path $root $name) -Force|Out-Null}
        $source=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $source|Out-Null
        Set-Content -LiteralPath (Join-Path $source 'original.pfx') 'synthetic PFX bytes; validation occurs before publication'
        Set-Content -LiteralPath (Join-Path $source 'password') 'synthetic test-only password'
        $draft=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
        @{Root=$root;ListenAddress='127.0.0.1';Port=18799;CertificatePath=(Join-Path $source 'original.pfx');CertificatePasswordFile=(Join-Path $source 'password')}|ConvertTo-Json|Set-Content -LiteralPath $draft -Encoding UTF8
        Mock -ModuleName AuthLens.Deploy New-ALInstallerTlsDirectory {param($Path) New-Item -ItemType Directory -Path $Path -ErrorAction Stop|Out-Null}
        Mock -ModuleName AuthLens.Deploy Get-ALService {[pscustomobject]@{Exists=$false}}
        Mock -ModuleName AuthLens.Deploy Get-ALLink {$null}
        Mock -ModuleName AuthLens.Deploy Get-ALServerSetupRegistration {$null}
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Export-ALServerPublicCertificate {param($Config,$Destination) Set-Content -LiteralPath $Destination 'synthetic public certificate'}
        $resolved=Resolve-ALServerSetupConfiguration $draft
    }
    It 'publishes private versioned paths and proves an idempotent retry without replacing keys' {
        $result=Publish-ALServerSetupConfiguration $resolved -ImportTls
        $result.Config.CertificatePath|Should -BeLike (Join-Path $root 'tls/setup-*/server.pfx')
        $result.ConfigSha256|Should -Not -Be $resolved.ConfigSha256
        Test-Path -LiteralPath (Join-Path $source 'original.pfx')|Should -BeTrue
        (Publish-ALServerSetupConfiguration $resolved -ImportTls).ConfigSha256|Should -Be $result.ConfigSha256
        @(Get-ChildItem -LiteralPath (Join-Path $root 'tls') -Directory).Count|Should -Be 1
    }
    It 'refuses retry after published key material is changed' {
        $result=Publish-ALServerSetupConfiguration $resolved -ImportTls
        Add-Content -LiteralPath $result.Config.CertificatePasswordFile 'changed'
        {Publish-ALServerSetupConfiguration $resolved -ImportTls}|Should -Throw '*TLS material changed*'
    }
}
