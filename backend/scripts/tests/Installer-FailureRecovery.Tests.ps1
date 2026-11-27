BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Install-AuthLens.ps1'),[ref]$tokens,[ref]$errors)
    @($errors).Count|Should -Be 0
    foreach($name in 'Get-InstallerTechnicalDiagnostic','Get-InstallerJournalState','Write-InstallerResult'){
        $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $script:DiagnosticFunctions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Extent.Text}) -join "`n"
    $script:CatchBody=$ast.Find({param($n)$n -is [Management.Automation.Language.TryStatementAst] -and $n.Extent.Text -like '*$known=@*'},$true).CatchClauses[0].Body.Extent.Text
}
Describe 'StrictMode byte measurement on Windows PowerShell 5.1 and later' {
    It 'reproduces the old empty measurement defect on Windows PowerShell' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
        {Set-StrictMode -Version Latest;(@()|Measure-Object Length -Sum).Sum}|Should -Throw '*Sum*'
    }
    It 'returns an Int64 zero for an empty collection and sums populated files' {
        Set-StrictMode -Version Latest
        $zero=Get-ALInstallerFileBytes @()
        $zero|Should -BeOfType ([long])
        $zero|Should -Be 0
        Get-ALInstallerFileBytes @([pscustomobject]@{Length=12},[pscustomobject]@{Length=31})|Should -Be 43
        {Get-ALInstallerFileBytes @([pscustomobject]@{Invalid=0})}|Should -Throw
    }
}
Describe 'Sanitized unexpected exception evidence before journal creation' {
    BeforeEach {
        $stage='Server installation preflight';$operationId=('a'*32)
        $buildIdentity='AuthLens 2.0.0; source_sha='+('b'*40)+'; target=win-x64 (verified manifest)'
        $journalPath=Join-Path $TestDrive 'absent.json'
        $ResultFile=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
    }
    It 'retains the property error type, safe message, ID, category, source, line, stack, stage, operation and build' {
        try{& {Set-StrictMode -Version Latest;([pscustomobject]@{}).Sum}}catch{$failure=$_}
        $technical=Get-InstallerTechnicalDiagnostic $failure
        foreach($text in 'PropertyNotFoundException',"property 'Sum'",'FullyQualifiedErrorId: PropertyNotFoundStrict','CategoryInfo:','Source script:','Line:','Script stack trace:','Server installation preflight',$operationId,('b'*40)){$technical|Should -Match ([regex]::Escape($text))}
        Write-InstallerResult @{schema=1;technical_diagnostic=$technical}
        $result=Get-Content $ResultFile -Raw|ConvertFrom-Json
        $result.technical_diagnostic|Should -Be $technical
        $result.deployment_journal_exists|Should -BeFalse
        Test-Path $journalPath|Should -BeFalse
    }
    It 'does not echo arbitrary messages, targets, quoted credentials or invocation source' {
        try{throw 'password="two word password" token=abcdef encryption-key=opaque-value UNLABELLED-SECRET'}catch{$failure=$_}
        $technical=Get-InstallerTechnicalDiagnostic $failure
        $technical|Should -Not -Match 'two word|abcdef|opaque-value|UNLABELLED-SECRET|throw '
        $technical|Should -Match 'REDACTED arbitrary exception message'
    }
    It 'executes the actual adapter catch in a child process and persists useful diagnostics without a journal' {
        $fixture=Join-Path $TestDrive 'failure-probe.ps1'
        $diagnostic=Join-Path $TestDrive 'diagnostic.txt'
        $report=Join-Path $TestDrive 'result.json'
        $preamble=@'
param($DiagnosticFile,$ResultFile,$journalPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$stage='Server installation preflight';$operationId=('a'*32)
$buildIdentity='AuthLens 2.0.0; source_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; target=win-x64 (verified manifest)'
$Mode='Server';$SetupMetadataFile='';$FailedPreflightReceipt='';$installerPublicErrors=@()
'@
        ($preamble+"`n"+$script:DiagnosticFunctions+"`ntry { ([pscustomobject]@{}).Sum } catch "+$script:CatchBody)|Set-Content $fixture -Encoding UTF8
        $run=Invoke-TestPowerShell @('-ExecutionPolicy','Bypass','-File',$fixture,'-DiagnosticFile',$diagnostic,'-ResultFile',$report,'-journalPath',$journalPath)
        $run.Code|Should -Be 2
        $run.Output|Should -Match 'PropertyNotFoundException'
        Get-Content $diagnostic -Raw|Should -Match "Exception message: The property 'Sum'"
        $result=Get-Content $report -Raw|ConvertFrom-Json
        $result.exit_code|Should -Be 2
        $result.deployment_journal_exists|Should -BeFalse
        $result.technical_diagnostic|Should -Match 'Script stack trace:'
        Test-Path $journalPath|Should -BeFalse
    }
    It 'retains literal product errors but excludes interpolated errors from the public catalog' {
        $installerPublicErrors=@(Get-ALInstallerPublicErrors)
        $installerPublicErrors|Should -Contain 'Failure evidence integrity changed; no files were adopted.'
        try{throw 'Failure evidence integrity changed; no files were adopted.'}catch{$failure=$_}
        Get-InstallerTechnicalDiagnostic $failure|Should -Match 'Exception message: Failure evidence integrity changed; no files were adopted.'
        @($installerPublicErrors|Where-Object{$_ -like '*$(*'}).Count|Should -Be 0
    }
}
Describe 'Verified failure evidence is opt-in and never adopted by filename alone' {
    BeforeEach {
        $stage=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $package=Join-Path $stage 'payload/pkg'
        New-Item -ItemType Directory -Force $package|Out-Null
        $configFile=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.json')
        Set-Content $configFile 'synthetic config'
        $resolved=[pscustomobject]@{Config=[pscustomobject]@{ConfigFile=$configFile;WorkRoot=(Join-Path $stage 'deployment')}}
        $journal=Get-ALJournalPath $resolved.Config
        $id=[guid]::NewGuid().ToString('N')
        @{schema=1;operation_id=$id;status='refused_or_failed';stage='Server installation preflight';exit_code=2;deployment_journal_exists=$false;deployment_journal_status='not_created_or_unavailable';deployment_journal_expected=$journal}|ConvertTo-Json|Set-Content (Join-Path $stage 'operation-result.json')
        foreach($path in @('payload/pkg/build-manifest.json','setup-metadata.ini','transaction-diagnostic.txt','tools/installer-tools.json','tools/Install-AuthLens.ps1','tools/verify-release.ps1','tools/deploy/AuthLens.Deploy.psm1','tools/deploy/Deploy-AuthLens.ps1','tools/deploy/AuthLens.Paths.ps1','tools/deploy/AuthLens.Acl.ps1','tools/deploy/AuthLens.Installer.ps1','tools/recovery/New-AuthLensRecoveryBundle.ps1','tools/recovery/Test-AuthLensRestoreRehearsal.ps1','tools/acceptance/AuthLens.Acceptance.psm1')){
            $target=Join-Path $stage $path
            New-Item -ItemType Directory -Force (Split-Path $target)|Out-Null
            Set-Content $target ('synthetic '+$path)
        }
        Mock -ModuleName AuthLens.Deploy Assert-ALAclPlan {}
        Mock -ModuleName AuthLens.Deploy Assert-ALFailedPreflightOwner {}
        $receipt=Join-Path $stage 'preflight-failure.json'
        @{schema=1;operation_id=$id;files=@(Get-ALFailedPreflightInventory $resolved $package $stage)}|ConvertTo-Json -Depth 6|Set-Content $receipt
    }
    It 'verifies the exact retained files without changing evidence or creating a journal' {
        $before=@(Get-ChildItem $stage -Recurse -File|ForEach-Object{(Get-FileHash $_.FullName).Hash})
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Not -Throw
        @(Get-ChildItem $stage -Recurse -File|ForEach-Object{(Get-FileHash $_.FullName).Hash})|Should -Be $before
        Test-Path $journal|Should -BeFalse
    }
    It 'refuses changed <File> even with an unchanged trusted filename' -ForEach @(@{File='operation-result.json'},@{File='transaction-diagnostic.txt'},@{File='tools/Install-AuthLens.ps1'},@{File='setup-metadata.ini'},@{File='tools/unrelated.txt'}) {
        Add-Content (Join-Path $stage $File) 'tampered'
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Throw
    }
    It 'refuses transaction failures and foreign receipt paths' {
        $result=Get-Content (Join-Path $stage 'operation-result.json') -Raw|ConvertFrom-Json
        $result.stage='Server deployment transaction'
        $result|ConvertTo-Json|Set-Content (Join-Path $stage 'operation-result.json')
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Throw '*pre-deployment*'
        {Assert-ALFailedPreflightEvidence $resolved $package (Join-Path $TestDrive 'foreign.json')}|Should -Throw '*outside*'
    }
    It 'refuses a real journal even when the retained result says none was created' {
        New-Item -ItemType Directory -Force (Split-Path $journal)|Out-Null
        Set-Content $journal 'retained journal sentinel'
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Throw '*pre-deployment*'
        Get-Content $journal|Should -Be 'retained journal sentinel'
    }
    It 'refuses missing evidence' {
        Remove-Item -LiteralPath (Join-Path $stage 'transaction-diagnostic.txt')
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Throw
    }
    It 'refuses unsafe evidence ownership' {
        Mock -ModuleName AuthLens.Deploy Assert-ALFailedPreflightOwner {throw 'unsafe owner'}
        {Assert-ALFailedPreflightEvidence $resolved $package $receipt}|Should -Throw '*unsafe owner*'
    }
}
Describe 'Fresh Server registration is visibly pending until transaction success' {
    It 'defers version and verified registration and labels the retained uninstall entry' {
        $iss=Get-Content (Join-Path $PSScriptRoot '../../installer/AuthLens-Server.iss') -Raw
        $callbacks=Get-Content (Join-Path $PSScriptRoot '../../installer/AuthLens-Server-Code.iss') -Raw
        $iss|Should -Match 'UninstallDisplayName=\{code:ServerRegistrationName\}'
        $iss|Should -Match 'ValueName: "SetupState"; ValueData: "pending-verification".*Check: ServerFreshInstall'
        $iss|Should -Not -Match 'ValueName: "FileVersion"'
        $callbacks|Should -Match 'pending verification; recovery required'
        $success=$callbacks.Substring($callbacks.IndexOf('procedure AfterInstallerSuccess();'))
        $success|Should -Match "'SetupState', 'verified'"
        $success|Should -Match "'FileVersion', '\{#NumericVersion\}'"
    }
}
Describe 'Failure evidence administrative ownership policy' {
    It 'refuses an actual non-administrative owner reported by the ACL API' {
        Mock -ModuleName AuthLens.Deploy Get-Acl {
            $acl=[pscustomobject]@{}
            $acl|Add-Member ScriptMethod GetOwner {param($type) [pscustomobject]@{Value='S-1-5-21-1-2-3-1000'}}
            $acl
        }
        {Assert-ALFailedPreflightOwner $TestDrive}|Should -Throw '*administrative ownership*'
    }
    It 'refuses a specific non-administrative write grant even with an administrative owner' {
        Mock -ModuleName AuthLens.Deploy Get-Acl {
            $acl=[pscustomobject]@{}
            $acl|Add-Member ScriptMethod GetOwner {param($type) [pscustomobject]@{Value='S-1-5-32-544'}}
            $acl|Add-Member ScriptMethod GetAccessRules {param($explicit,$inherited,$type) [pscustomobject]@{AccessControlType='Allow';IdentityReference=[pscustomobject]@{Value='S-1-5-21-1-2-3-1000'};FileSystemRights=2}}
            $acl
        }
        {Assert-ALFailedPreflightOwner $TestDrive}|Should -Throw '*non-administrative mutation*'
    }
}
