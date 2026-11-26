BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    . (Join-Path $PSScriptRoot '../Build-Workflow.ps1')
    $script:ReadinessPath=Join-Path $PSScriptRoot '../Test-AuthLensUpgradeReadiness.ps1'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($script:ReadinessPath,[ref]$tokens,[ref]$errors)
    @($errors).Count|Should -Be 0
    # Define functions only. Never execute the administrative inspection entry point against this machine.
    foreach($definition in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $adapter=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Install-AuthLens.ps1'),[ref]$tokens,[ref]$errors)
    foreach($name in 'Get-InstallerJournalState','Write-InstallerResult'){
        $definition=$adapter.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    function New-TestInstallerMetadata($Construction,$FixtureManifest,$InstallerNames,$Directory) {
        # A function scope contains the real producer's local $field loop variable.
        $manifest=$FixtureManifest;$names=$InstallerNames;$Output=$Directory
        . ([scriptblock]::Create($Construction))
        $metadata|ConvertTo-Json -Depth 6|ConvertFrom-Json
    }
}

Describe 'Build identity contracts from the actual installer metadata producer' {
    BeforeEach {
        $identity=[pscustomobject]@{product='AuthLens';version='2.0.0';source_sha=('a'*40);
            branch='experiment/dotnet-backend';build_timestamp_utc='2026-11-23T18:15:59Z'}
        $manifest=[pscustomobject]@{schema=1;product=$identity.product;version=$identity.version;source_sha=$identity.source_sha;
            branch=$identity.branch;build_timestamp_utc=$identity.build_timestamp_utc;source_dirty=$false;target_platform='win-x64';
            executables=[pscustomobject]@{desktop='desktop/AuthLens.exe';server='server/AuthLens.Api.exe'}}
        $names=@('AuthLens-2.0.0-Setup.exe','AuthLens-Server-2.0.0-Setup.exe');$Output=$TestDrive
        foreach($name in $names){Set-Content -LiteralPath (Join-Path $Output $name) 'synthetic metadata input; never execute'}
        # Execute ONLY the real JSON metadata construction, not a build/compiler/installer.
        $producer=Get-Content (Join-Path $PSScriptRoot '../build-installers.ps1') -Raw
        $construction=[regex]::Match($producer,'(?s)\$metadata=\[ordered\]@\{\}.*?(?=\[IO.File\]::WriteAllText)').Value
        $construction|Should -Not -BeNullOrEmpty
        # The producer's foreach ($field ...) must not overwrite Pester's case data in this scope.
        # PowerShell variable names are case-insensitive, including $field and $Field.
        $installerDocument=New-TestInstallerMetadata $construction $manifest $names $Output
    }
    It 'accepts schema-1 release metadata and the real unversioned installer contract without inventing a schema field' {
        $installerDocument.PSObject.Properties.Name|Should -Not -Contain 'schema'
        {Assert-ReadinessManifestIdentity $manifest $identity 'release_manifest'}|Should -Not -Throw
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Not -Throw
        # Ensure the entry point uses this contract validator, not the old unconditional .schema read.
        $source=Get-Content $script:ReadinessPath -Raw
        $source|Should -Match 'Assert-ReadinessManifestIdentity \$metadata \$summary.identity'
        $source|Should -Not -Match '\$metadata\.schema'
    }
    It 'still rejects unsupported release and installer schema declarations' {
        $manifest.schema=2
        {Assert-ReadinessManifestIdentity $manifest $identity 'release_manifest'}|Should -Throw '*release_manifest_schema_unsupported*'
        $installerDocument|Add-Member -NotePropertyName schema -NotePropertyValue 2
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw '*installer_manifest_contract_unsupported*'
    }
    It 'reports a missing required field without leaking another field value' {
        $installerDocument.PSObject.Properties.Remove('source_sha')
        $installerDocument.product='SYNTHETIC_PRIVATE_MARKER'
        try{Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest';throw 'Expected refusal'}
        catch{$_.Exception.Message|Should -Be 'installer_manifest_field_missing_source_sha'}
    }
    It 'retains exact build identity checks with field-specific safe codes' -ForEach @(
        @{IdentityField='version';IdentityValue='2.0.1'},
        @{IdentityField='source_sha';IdentityValue=('b'*40)},@{IdentityField='branch';IdentityValue='other'}) {
        @('version','source_sha','branch')|Should -Contain $IdentityField
        ($installerDocument.executables -is [pscustomobject])|Should -BeTrue
        $installerDocument.$IdentityField=$IdentityValue
        $installerDocument.executables.desktop|Should -Be 'desktop/AuthLens.exe'
        $installerDocument.executables.server|Should -Be 'server/AuthLens.Api.exe'
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw ('*installer_manifest_mismatch_'+$IdentityField+'*')
    }
    It 'keeps producer loop variables inside a child scope' {
        $Field='version'
        $roundTrip=New-TestInstallerMetadata $construction $manifest $names $Output
        $Field|Should -Be 'version'
        ($roundTrip.executables -is [pscustomobject])|Should -BeTrue
        {Assert-ReadinessManifestIdentity $roundTrip $identity 'installer_manifest'}|Should -Not -Throw
    }
    It 'rejects a non-object executable mapping separately from identity mismatches' -ForEach @(
        @{ExecutableValue=$null},@{ExecutableValue='not an object'},@{ExecutableValue=@('desktop/AuthLens.exe','server/AuthLens.Api.exe')}) {
        $installerDocument.executables=$ExecutableValue
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw '*installer_manifest_executables_object_required*'
    }
    It 'rejects missing executable members as structural failures' -ForEach @(
        @{ExecutableMember='desktop'},@{ExecutableMember='server'}) {
        $installerDocument.executables.PSObject.Properties.Remove($ExecutableMember)
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw ('*installer_manifest_executables_field_missing_'+$ExecutableMember+'*')
    }
    It 'retains Boolean dirty-source and executable-isolation guards' {
        $installerDocument.source_dirty='false'
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw '*installer_manifest_source_dirty_type_invalid*'
        $installerDocument.source_dirty=$true
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw '*installer_manifest_source_dirty*'
        $installerDocument.source_dirty=$false;$installerDocument.executables.server='desktop/AuthLens.exe'
        {Assert-ReadinessManifestIdentity $installerDocument $identity 'installer_manifest'}|Should -Throw '*installer_manifest_identity_or_executable_mismatch*'
    }
}

Describe 'Read-only upgrade readiness input and artifact boundaries' {
    It 'accepts only actual Boolean true as verification evidence' {
        (Test-ReadinessTrue $true)|Should -BeTrue
        foreach($value in @($false,'true',1,$null)){(Test-ReadinessTrue $value)|Should -BeFalse}
    }
    It 'refuses missing arguments without prompting or inspecting installed state' {
        $child=Invoke-TestPowerShell @('-ExecutionPolicy','Bypass','-File',$script:ReadinessPath)
        $child.Code|Should -Be 1
        $child.Output|Should -Match 'AUTHLENS-UPGRADE-READINESS:'
        $child.Output|Should -Match 'windows_and_build_directory_required'
        $child.Output|Should -Match '"service_and_protected_files":"not_observed"'
        $child.Output|Should -Not -Match 'Supply values|Enter a value'
    }
    It 'rejects relative, UNC and alternate-stream input before reading it' -ForEach @(
        @{Path='relative/build'},@{Path='\\server\share\build'},@{Path='C:\build\file:stream'}) {
        {Resolve-ReadinessPath $Path}|Should -Throw '*invalid_local_path*'
    }
    Context 'Manifest binding' {
        BeforeEach {
            Mock Resolve-ReadinessPath {param($Path,$Within) [IO.Path]::GetFullPath($Path)}
            $root=$TestDrive
            $summary=[pscustomobject]@{artifacts=@([pscustomobject]@{path='installer/setup.exe';size=1;sha256=('a'*64)})}
        }
        It 'rejects parent traversal, absolute paths and duplicate normalized paths' {
            foreach($path in '../outside','/outside','C:/outside'){
                $summary.artifacts[0].path=$path
                {Get-ReadinessArtifactMap $summary $root}|Should -Throw '*invalid_build_artifact_inventory*'
            }
            $summary.artifacts=@(
                [pscustomobject]@{path='installer/setup.exe';size=1;sha256=('a'*64)},
                [pscustomobject]@{path='INSTALLER\SETUP.EXE';size=1;sha256=('a'*64)})
            {Get-ReadinessArtifactMap $summary $root}|Should -Throw '*invalid_build_artifact_inventory*'
        }
        It 'requires a file to be bound to the build summary and match both size and hash' {
            $file=Join-Path $root 'artifact.bin';[IO.File]::WriteAllBytes($file,[byte[]]@(1,2,3))
            $hash=(Get-FileHash $file).Hash
            $map=@{'artifact.bin'=[pscustomobject]@{size=3;sha256=$hash}}
            {Assert-ReadinessArtifact $map $root 'artifact.bin'}|Should -Not -Throw
            $map['artifact.bin'].size=4
            {Assert-ReadinessArtifact $map $root 'artifact.bin'}|Should -Throw '*build_artifact_checksum_mismatch*'
            $map['artifact.bin'].size=3;$map['artifact.bin'].sha256=('a'*64)
            {Assert-ReadinessArtifact $map $root 'artifact.bin'}|Should -Throw '*build_artifact_checksum_mismatch*'
            {Assert-ReadinessArtifact $map $root 'not-listed.bin'}|Should -Throw '*artifact_not_bound_to_build_summary*'
        }
        It 'does not replace the first observed fingerprint when a protected file changes' {
            $file=Join-Path $root 'protected.txt';Set-Content $file 'retained baseline'
            $baseline=[pscustomobject]@{files=@{}}
            Add-ReadinessFile $baseline $file
            $before=$baseline.files[$file]
            Set-Content $file 'changed after baseline'
            {Add-ReadinessFile $baseline $file}|Should -Throw '*protected_file_changed_during_check*'
            $baseline.files[$file]|Should -Be $before
        }
        It 'names the category, side and file of a protected-file mismatch without its content (QA-017/021)' {
            $file=Join-Path $root 'mismatch.txt';Set-Content $file 'SYNTHETIC_PRIVATE_MARKER'
            $baseline=[pscustomobject]@{files=@{}}
            $script:ReadinessMismatch=$null
            {Add-ReadinessFile $baseline $file ('b'*64) ([ordered]@{category='config';side='installation source';file='config\installed-product.json'})}|Should -Throw '*protected_file_hash_mismatch*'
            $script:ReadinessMismatch.category|Should -Be 'config'
            $script:ReadinessMismatch.file|Should -Be 'config\installed-product.json'
            ($script:ReadinessMismatch|ConvertTo-Json)|Should -Not -Match 'SYNTHETIC_PRIVATE_MARKER'
        }
        It 'reports malformed JSON with a fixed code rather than its sensitive contents' {
            $file=Join-Path $root 'invalid.json';Set-Content $file '{"private":"SYNTHETIC_PRIVATE_MARKER"'
            try{Read-ReadinessJson $file;throw 'Expected refusal'}
            catch{$_.Exception.Message|Should -Be 'metadata_json_invalid'}
        }
    }
}

Describe 'Fixed supported upgrade preflight contract' {
    BeforeEach {
        Mock Get-ALShell {'approved-shell'}
        $identity=[pscustomobject]@{source_sha=('a'*40);version='2.0.0'}
        $fingerprint=('b'*64)
        $expectedJournal='C:\AuthLens\deployment\journal.json'
        $proof=@{schema=1;deployment_journal=$expectedJournal;deployment_journal_expected=$expectedJournal;status='completed';exit_code=0;deployment_journal_exists=$true;result=@{
            read_only=$true;operation='upgrade';package_network_database_verified=$true;source_sha=$identity.source_sha;
            version=$identity.version;config_sha256=$fingerprint;config_file='C:\AuthLens\config\deploy.json'}}
        Mock Invoke-ALProcess {[pscustomobject]@{ExitCode=0;Output=@('AUTHLENS-INSTALLER-RESULT: '+($proof|ConvertTo-Json -Depth 5 -Compress))}}
    }
    It 'invokes only the fixed read-only entry point without logging raw output' {
        Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal
        Should -Invoke Invoke-ALProcess -Times 1 -ParameterFilter {
            $File -eq 'approved-shell' -and -not $LogFile -and
            $Arguments -contains '-NonInteractive' -and $Arguments -contains '-PreflightOnly' -and
            $Arguments -contains 'Upgrade' -and $Arguments -contains 'Bypass' -and
            $Arguments -notcontains '-Yes' -and $Arguments -notcontains '-PrepareOnly' -and
            $Arguments -notcontains '-ResultFile' -and $Arguments -notcontains '-PlanFile'
        }
    }
    It 'rejects successful exit without read-only, correct identity and explicit upgrade proof' -ForEach @(
        @{Field='read_only';Value=$false},@{Field='read_only';Value='true'},@{Field='operation';Value='fresh installation'},
        @{Field='package_network_database_verified';Value=$false},@{Field='source_sha';Value=('c'*40)},
        @{Field='config_sha256';Value=('c'*64)},@{Field='version';Value='2.0.0-alpha.1'}) {
        $proof.result[$Field]=$Value
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal}|Should -Throw '*preflight_result_binding_mismatch*'
    }
    It 'does not expose child diagnostics containing secret-like data on refusal' {
        Mock Invoke-ALProcess {[pscustomobject]@{ExitCode=2;Output=@('password=SYNTHETIC_NOT_A_SECRET')}}
        try{Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal;throw 'Expected refusal'}
        catch{$_.Exception.Message|Should -Be 'supported_upgrade_preflight_refused'}
    }
    It 'rejects missing or ambiguous structured results' {
        Mock Invoke-ALProcess {[pscustomobject]@{ExitCode=0;Output=@('not a proof')}}
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal}|Should -Throw '*preflight_result_missing_or_ambiguous*'
        $line='AUTHLENS-INSTALLER-RESULT: '+($proof|ConvertTo-Json -Depth 5 -Compress)
        Mock Invoke-ALProcess {[pscustomobject]@{ExitCode=0;Output=@($line,$line)}}
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal}|Should -Throw '*preflight_result_missing_or_ambiguous*'
    }
    It 'rejects unsupported schema or journal proof' -ForEach @(
        @{ProofField='schema';ProofValue=2},@{ProofField='schema';ProofValue='1'},
        @{ProofField='deployment_journal_exists';ProofValue='true'},
        @{ProofField='deployment_journal';ProofValue=$null},
        @{ProofField='deployment_journal_expected';ProofValue='C:\unrelated\journal.json'}) {
        $proof[$ProofField]=$ProofValue
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal}|Should -Throw '*preflight_result_binding_mismatch*'
    }
    It 'reports a missing schema with a fixed structural code' {
        $proof.Remove('schema')
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $expectedJournal}|Should -Throw '*preflight_result_field_missing_schema*'
    }
    It 'accepts the structured result emitted by the current installer writer' {
        $journalPath=Join-Path $TestDrive 'journal.json';$ResultFile=Join-Path $TestDrive 'installer-result.json'
        Set-Content $journalPath 'synthetic terminal journal; no deployment is run'
        Write-InstallerResult @{schema=1;status='completed';exit_code=0;result=$proof.result}
        $proof=Get-Content $ResultFile -Raw|ConvertFrom-Json
        {Invoke-ReadinessPreflight $TestDrive $TestDrive 'C:\AuthLens\config\deploy.json' $fingerprint $identity $journalPath}|Should -Not -Throw
    }
}

Describe 'Installer registration compatibility and incomplete-state refusal' {
    BeforeEach {
        Mock Get-ALServerSetupRegistration {[pscustomobject]@{Root='C:\AuthLens';ConfigFile='C:\AuthLens\config\deploy.json';ProgramDirectory='C:\AuthLens\app'}}
        Mock Test-Path {$true} -ParameterFilter {$LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\Software\AuthLens\Server'}
        $record=[pscustomobject]@{FileVersion='2.0.0.0'}
        Mock Get-ItemProperty {$record} -ParameterFilter {$LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\Software\AuthLens\Server'}
    }
    It 'accepts older verified installations without a marker and fingerprints version metadata' {
        $before=Get-ReadinessRegistration|ConvertFrom-Json
        $before.setup_state|Should -Be 'not_recorded'
        $before.file_version|Should -Be '2.0.0.0'
        $before.registration.ProgramDirectory|Should -Be 'C:\AuthLens\app'
    }
    It 'accepts the new verified marker and refuses pending or unknown state' {
        $record|Add-Member SetupState 'verified'
        (Get-ReadinessRegistration|ConvertFrom-Json).setup_state|Should -Be 'verified'
        foreach($state in @('pending-verification','unknown','')){
            $record.SetupState=$state
            {Get-ReadinessRegistration}|Should -Throw '*installer_registration_not_verified*'
        }
    }
    It 'changes the baseline fingerprint when installation version changes' {
        $before=Get-ReadinessRegistration
        $record.FileVersion='2.0.1.0'
        Get-ReadinessRegistration|Should -Not -Be $before
    }
}

Describe 'Read-only post-checks' {
    BeforeEach {
        $service=[pscustomobject]@{Exists=$true;State='Running';StartMode='Auto';Account='NT SERVICE\AuthLens';PathName='approved command';ProcessId=123}
        $baseline=[pscustomobject]@{service=$service;registration='registered';release='C:\AuthLens\releases\old';files=@{'protected'='original'}}
        Mock Get-ALService {$service.PSObject.Copy()}
        Mock Get-ReadinessRegistration {'registered'}
        Mock Get-ALCurrentLink {'current'}
        Mock Get-ALLink {'C:\AuthLens\releases\old'}
        Mock Get-ReadinessHash {'original'}
    }
    It 'accepts unchanged state and rejects altered configuration/TLS/recovery bytes' {
        {Assert-ReadinessBaseline $baseline ([pscustomobject]@{})}|Should -Not -Throw
        Mock Get-ReadinessHash {'changed'}
        {Assert-ReadinessBaseline $baseline ([pscustomobject]@{})}|Should -Throw '*protected_file_changed_during_check*'
    }
    It 'rejects service restart and release-pointer changes' {
        Mock Get-ALService {$now=$service.PSObject.Copy();$now.ProcessId=456;$now}
        {Assert-ReadinessBaseline $baseline ([pscustomobject]@{})}|Should -Throw '*service_changed_during_check*'
        Mock Get-ALService {$service.PSObject.Copy()}
        Mock Get-ALLink {'C:\AuthLens\releases\other'}
        {Assert-ReadinessBaseline $baseline ([pscustomobject]@{})}|Should -Throw '*installation_identity_changed_during_check*'
    }
}

Describe 'WP32 candidate layouts in readiness (category layout and legacy run directories)' {
    It 'maps build/ and installer/ summary paths to Build\version\build-id and Installer\version\build-id and refuses other prefixes' {
        $candidate=[pscustomobject]@{BuildDirectory=(Join-Path $TestDrive 'Build\2.0.0\2026-11-25_2145-b10dd50');InstallerDirectory=(Join-Path $TestDrive 'Installer\2.0.0\2026-11-25_2145-b10dd50')}
        New-Item -ItemType Directory -Force $candidate.BuildDirectory,$candidate.InstallerDirectory|Out-Null
        $file=Join-Path $candidate.InstallerDirectory 'installer-manifest.json';Set-Content $file '{}'
        $hash=(Get-FileHash $file).Hash.ToLowerInvariant()
        $summary=[pscustomobject]@{artifacts=@([pscustomobject]@{path='installer/installer-manifest.json';size=(Get-Item $file).Length;sha256=$hash})}
        $map=Get-ReadinessArtifactMap $summary $candidate
        {Assert-ReadinessArtifact $map $candidate 'installer/installer-manifest.json'}|Should -Not -Throw
        Resolve-ReadinessArtifactPath $candidate 'build/build-manifest.json'|Should -Be (Join-Path $candidate.BuildDirectory 'build-manifest.json')
        {Resolve-ReadinessArtifactPath $candidate 'acceptance/results.json'}|Should -Throw '*invalid_build_artifact_inventory*'
        Set-Content $file '{"changed":true}'
        {Assert-ReadinessArtifact $map $candidate 'installer/installer-manifest.json'}|Should -Throw '*build_artifact_checksum_mismatch*'
    }
    It 'accepts the seven-helper inventory of earlier packages and the QA-028 inventory with recovery tooling only' {
        $source=Get-Content $script:ReadinessPath -Raw
        $source|Should -Match "recovery/New-AuthLensRecoveryBundle.ps1','recovery/Test-AuthLensRestoreRehearsal.ps1','acceptance/AuthLens.Acceptance.psm1'"
        $source|Should -Match 'packaged_helper_inventory_refused'
        $source|Should -Match 'Get-AuthLensSetupNames \$candidate'
        $source|Should -Match "summary.layout -ceq 'category'"
    }
}

Describe 'Installation ACL status gate (WP31 SEC-5)' {
    BeforeEach {
        $config=[pscustomobject]@{Root='C:\AuthLens';WorkRoot='C:\AuthLens\deployment'}
        Mock Get-ALAclPlan {@()}
        Mock Get-ALAclExpectedSids {@()}
        Mock Get-ALAclAuthorizations {@()}
    }
    It 'reports REVIEW_REQUIRED and UNSAFE without failing in report mode' {
        Mock Get-ALAclReport {[pscustomobject]@{status='REVIEW_REQUIRED';safe=$true}}
        Get-ReadinessAclStatus $config $false|Should -Be 'REVIEW_REQUIRED'
        Mock Get-ALAclReport {[pscustomobject]@{status='UNSAFE';safe=$true}}
        Get-ReadinessAclStatus $config $false|Should -Be 'UNSAFE'
    }
    It 'refuses anything but SAFE in strict mode and passes SAFE' {
        Mock Get-ALAclReport {[pscustomobject]@{status='REVIEW_REQUIRED';safe=$true}}
        {Get-ReadinessAclStatus $config $true}|Should -Throw 'acl_status_review_required'
        Mock Get-ALAclReport {[pscustomobject]@{status='UNSAFE';safe=$true}}
        {Get-ReadinessAclStatus $config $true}|Should -Throw 'acl_status_unsafe'
        Mock Get-ALAclReport {[pscustomobject]@{status='SAFE';safe=$true}}
        Get-ReadinessAclStatus $config $true|Should -Be 'SAFE'
    }
    It 'treats an unverifiable audit as a refusal in strict mode and as UNVERIFIABLE otherwise' {
        Mock Get-ALAclReport {throw 'required access unverified'}
        Get-ReadinessAclStatus $config $false|Should -Be 'UNVERIFIABLE'
        {Get-ReadinessAclStatus $config $true}|Should -Throw 'acl_status_unverifiable'
    }
    It 'falls back to the broad-only safe flag for older reports without status' {
        Mock Get-ALAclReport {[pscustomobject]@{safe=$false}}
        Get-ReadinessAclStatus $config $false|Should -Be 'UNSAFE'
    }
}
