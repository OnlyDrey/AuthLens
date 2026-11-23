BeforeAll {
    $script:Iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

Describe 'Compiled Inno installer isolation' {
    It 'compiles <Mode> <Version> with only its own validation and transaction arguments' -ForEach @(
        @{Mode='Desktop';Version='2.0.0-alpha.1';Numeric='2.0.0.1'},@{Mode='Server';Version='2.0.0-alpha.1';Numeric='2.0.0.1'},
        @{Mode='Desktop';Version='2.0.0';Numeric='2.0.0.0'},@{Mode='Server';Version='2.0.0';Numeric='2.0.0.0'}) {
        if (-not $script:Iscc) { Set-ItResult -Skipped -Because 'Inno Setup 6 unavailable; compile and execute both installers on the Windows acceptance machine.'; return }
        # Compile real scripts with synthetic bytes, never launch Setup or touch installed state.
        $repo = Join-Path $TestDrive ($Mode+'-'+$Version)
        $installer = Join-Path $repo 'backend/installer'
        $payload = Join-Path $repo 'payload'; $tools = Join-Path $repo 'tools'
        foreach ($dir in $installer,(Join-Path $repo 'assets/branding'),(Join-Path $payload 'desktop'),(Join-Path $payload 'server'),$tools) {
            New-Item -ItemType Directory -Force $dir | Out-Null
        }
        Copy-Item (Join-Path $PSScriptRoot '../../installer/*.iss') $installer
        Copy-Item (Join-Path $PSScriptRoot '../../../assets/branding/app.ico') (Join-Path $repo 'assets/branding')
        Copy-Item (Join-Path $PSScriptRoot '../../../LICENSE.md') $repo
        foreach ($file in (Join-Path $payload 'desktop/AuthLens.exe'),(Join-Path $payload 'server/AuthLens.Api.exe'),(Join-Path $tools 'Install-AuthLens.ps1')) {
            Set-Content -LiteralPath $file 'synthetic compile fixture; never execute'
        }
        $source = Join-Path $installer "AuthLens-$Mode.iss"
        $expanded = Join-Path $repo 'expanded.iss'
        Add-Content -LiteralPath $source ('#expr SaveToFile("' + $expanded + '")')
        $output=Join-Path $repo 'compiled'
        & $script:Iscc '/Q' "/O$output" "/DFullVersion=$Version" "/DNumericVersion=$Numeric" "/DReleaseDir=$payload" '/DPackageName=synthetic' "/DToolsDir=$tools" $source
        $LASTEXITCODE | Should -Be 0
        $binary=@(Get-ChildItem -LiteralPath $output -Filter '*.exe')
        $binary.Count|Should -Be 1
        Push-Location (Resolve-Path (Join-Path $PSScriptRoot '../../..'))
        try{
            # Inspect resources only: these synthetic installers must never execute.
            & node --input-type=module -e "import {verifyExecutable} from './scripts/verify-branding.mjs'; console.log(JSON.stringify(verifyExecutable(process.argv[1])))" $binary[0].FullName
            $LASTEXITCODE|Should -Be 0
        }finally{Pop-Location}
        $code = Get-Content -LiteralPath $expanded -Raw
        $code | Should -Match 'This exact Setup payload already exists'
        $code | Should -Match 'any existing journal'
        $code | Should -Match 'any recovery journal before retrying'
        $code | Should -Not -Match 'Retain the installation journal|or use another verified package'
        $code | Should -Match 'ssPostInstall'
        $code | Should -Match 'if Code <> 0 then begin'
        $code | Should -Match 'LoadStringFromFile\(Diagnostic, Detail\)'
        $code | Should -Match 'RaiseException'
        $code | Should -Match ('-Mode ' + $Mode + ' -Package')
        if ($Mode -eq 'Desktop') {
            $code | Should -Not -Match 'ComparePackedVersion\(ThisVersion, InstalledVersion\)'
            $code | Should -Not -Match 'CONFIGFILE|ConfigFile|PrepareOnly|ExtractTemporaryFiles|Server root security|ServiceRunsFrom'
            $code | Should -Match "DesktopData\(''\)"
            $code | Should -Match '-DataDirectory'
            $code | Should -Match 'PrivilegesRequired=lowest'
            $code | Should -Match '\{localappdata\}\\AuthLens\\data'
        } else {
            $code | Should -Not -Match 'DesktopData|-DataDirectory|param:DATADIR|WebViewKey'
            $code | Should -Match 'CreateServerDraft'
            $code | Should -Match '-CommitNewConfiguration'
            $code | Should -Match 'param:CONFIGFILE'
            $code | Should -Match '-ResolveOnly'
            $code | Should -Match '-PreflightOnly -Package'
            $code | Should -Match '-PrepareOnly -Package'
            $code | Should -Match 'UsePreviousAppDir=no'
            $code | Should -Match "WizardForm.DirEdit.Text := ServerValue\('program_directory'\)"
            $code | Should -Match "RegKeyExists\(HKLM, ServicesKey \+ 'AuthLens'\)"
            $code | Should -Match 'SetupLogging=yes'
            $code | Should -Not -Match 'ComparePackedVersion\(ThisVersion, InstalledVersion\)'
            $code | Should -Match 'ExtractTemporaryFiles'
            $code | Should -Match 'PrivilegesRequired=admin'
            $code | Should -Match 'function InitializeUninstall'
            $code | Should -Match 'InstallerMetadataArguments'
            $code | Should -Match "ServerValue\('operation'\) <> 'fresh installation'"
            $code | Should -Match 'GetSHA256OfFile'
            $code | Should -Match 'SetupMetadataFile'
        }
    }
}
