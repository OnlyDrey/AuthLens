# D-008: named (non-broad, unexpected) principals with access to private AuthLens material are reported for review without changing the
# meaning of 'safe' and without removing anything. ACL reads are replaced; no real ACL is touched.
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    $script:Operator = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
    $script:Service = 'S-1-5-80-1284631550-1226822301-1217020581-411410024-2017394666'
    function New-Rule([string]$Sid, [int64]$Rights = 2032127, [bool]$Inherited = $false) {
        [pscustomobject]@{ Sid = $Sid; Rights = $Rights; Allow = $true; Inherited = $Inherited; ContainerInherit = $true; ObjectInherit = $true; InheritOnly = $false }
    }
}

Describe 'Get-ALAclNamedFindings' {
    It 'reports a named account with full control on private material' {
        $f = @(InModuleScope AuthLens.Deploy -Parameters @{ r = @(New-Rule $script:Operator) } { param($r) Get-ALAclNamedFindings $r 'private' $true @() })
        $f.Count | Should -Be 1; $f[0].sid | Should -Be $script:Operator; $f[0].access | Should -Be 'write'
    }
    It 'does not report SYSTEM, Administrators, TrustedInstaller, CREATOR OWNER or the expected service identity' {
        $rules = @(New-Rule 'S-1-5-18'), (New-Rule 'S-1-5-32-544'), (New-Rule 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'), (New-Rule 'S-1-3-0'), (New-Rule $script:Service)
        @(InModuleScope AuthLens.Deploy -Parameters @{ r = $rules; s = $script:Service } { param($r, $s) Get-ALAclNamedFindings $r 'private' $true @($s) }).Count | Should -Be 0
    }
    It 'leaves broad principals to the broad audit' {
        @(InModuleScope AuthLens.Deploy -Parameters @{ r = @(New-Rule 'S-1-5-11') } { param($r) Get-ALAclNamedFindings $r 'private' $true @() }).Count | Should -Be 0
    }
    It 'ignores named read and execute on binaries but reports named write there' {
        @(InModuleScope AuthLens.Deploy -Parameters @{ r = @(New-Rule $script:Operator 1179817) } { param($r) Get-ALAclNamedFindings $r 'binaries' $true @() }).Count | Should -Be 0
        @(InModuleScope AuthLens.Deploy -Parameters @{ r = @(New-Rule $script:Operator 1245631) } { param($r) Get-ALAclNamedFindings $r 'binaries' $true @() }).Count | Should -Be 1
    }
}

Describe 'Get-ALAclReport with named principals' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $script:dir | Out-Null
        Mock -ModuleName AuthLens.Deploy Assert-ALAclRequiredAccess { }
        Mock -ModuleName AuthLens.Deploy Get-ALAclItems { @() }
    }
    It 'keeps safe true (no broad access) and flags the named account for review with remediation guidance' {
        Mock -ModuleName AuthLens.Deploy Get-ALAclRules { @((New-Rule 'S-1-5-18'), (New-Rule 'S-1-5-32-544'), (New-Rule $script:Service), (New-Rule $script:Operator)) }
        $plan = @([pscustomobject]@{ Path = $script:dir; Class = 'private'; Role = 'TLS'; Recurse = $true })
        $r = InModuleScope AuthLens.Deploy -Parameters @{ p = $plan; s = $script:Service } { param($p, $s) Get-ALAclReport $p -ExpectedSids @($s) }
        $r.safe | Should -BeTrue
        $r.named_principal_access | Should -BeTrue
        @($r.entries[0].named_principals).Count | Should -Be 1
        $r.review_required | Should -Match 'icacls <path> /remove:g'
        $r.review_required | Should -Match 'never removes named accounts'
    }
    It 'reports nothing for an installation that grants only SYSTEM, Administrators and the service' {
        Mock -ModuleName AuthLens.Deploy Get-ALAclRules { @((New-Rule 'S-1-5-18'), (New-Rule 'S-1-5-32-544'), (New-Rule $script:Service)) }
        $plan = @([pscustomobject]@{ Path = $script:dir; Class = 'private'; Role = 'data'; Recurse = $true })
        $r = InModuleScope AuthLens.Deploy -Parameters @{ p = $plan; s = $script:Service } { param($p, $s) Get-ALAclReport $p -ExpectedSids @($s) }
        $r.named_principal_access | Should -BeFalse; $r.review_required | Should -Be ''
    }
    It 'still reports a broad principal as unsafe' {
        Mock -ModuleName AuthLens.Deploy Get-ALAclRules { @((New-Rule 'S-1-5-18'), (New-Rule 'S-1-5-32-545' 1179817)) }
        $plan = @([pscustomobject]@{ Path = $script:dir; Class = 'private'; Role = 'keys'; Recurse = $false })
        (InModuleScope AuthLens.Deploy -Parameters @{ p = $plan } { param($p) Get-ALAclReport $p }).safe | Should -BeFalse
    }
}
