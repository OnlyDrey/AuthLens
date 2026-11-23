BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-TestDeploymentModule
    $iscc="${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
Describe 'Native Inno metadata timing on a disposable per-user probe' {
    It 'hashes actual Inno uninstall files at ssPostInstall using the production callback' {
        if(-not(Test-Path $iscc)){Set-ItResult -Skipped -Because 'Inno Setup is required for native metadata timing acceptance';return}
        $base=Join-Path $TestDrive 'metadata-probe';New-Item -ItemType Directory $base|Out-Null
        $app=Join-Path $base 'app';$source=Join-Path $base 'probe.iss'
        Set-Content (Join-Path $base 'manifest.json') '{"product":"AuthLens","synthetic":true}' -Encoding ASCII
        $code=Get-Content (Join-Path $PSScriptRoot '../../installer/AuthLens-Server-Code.iss') -Raw
        $callback=[regex]::Match($code,'(?s)function InstallerMetadataArguments\(\): String;.*?\nend;').Value
        $callback|Should -Not -BeNullOrEmpty
        $id=[guid]::NewGuid().ToString('N')
        $module=(Resolve-Path (Join-Path $PSScriptRoot '../deploy/AuthLens.Deploy.psm1')).Path.Replace("'","''")
        $verify=Join-Path $base 'verify.ps1'
        @"
param([string]`$App)
`$ErrorActionPreference='Stop'
Import-Module '$module'
`$stage=Join-Path `$App 'setup/synthetic'
Assert-ALFreshSetupMetadata `$App `$stage (Join-Path `$stage 'payload/synthetic') (Join-Path `$stage 'setup-metadata.ini')
Set-Content (Join-Path `$App 'verified.txt') 'verified at ssPostInstall'
"@|Set-Content $verify -Encoding UTF8
        @"
#define PackageName "synthetic"
[Setup]
AppId=AuthLens-Metadata-Probe-$id
AppName=AuthLens Metadata Probe
AppVersion=1
DefaultDirName=$app
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=$base
OutputBaseFilename=probe
[Files]
Source: "$base\manifest.json"; DestDir: "{app}\setup\synthetic\payload\synthetic"; DestName: "build-manifest.json"
[Code]
function ServerValue(Name: String): String;
begin Result := 'fresh installation'; end;
$callback
procedure CurStepChanged(Step: TSetupStep);
var Code: Integer;
begin
  if Step <> ssPostInstall then Exit;
  InstallerMetadataArguments();
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$verify" -App "' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 99;
  if Code <> 0 then RaiseException('Metadata verifier failed: ' + IntToStr(Code));
end;
"@|Set-Content $source -Encoding UTF8
        & $iscc /Q $source
        $LASTEXITCODE|Should -Be 0
        try {
            $process=Start-Process -FilePath (Join-Path $base 'probe.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART',('/LOG="'+(Join-Path $base 'setup.log')+'"')) -WindowStyle Hidden -Wait -PassThru
            $process.ExitCode|Should -Be 0
            Get-Content (Join-Path $app 'verified.txt')|Should -Be 'verified at ssPostInstall'
            $stage=Join-Path $app 'setup/synthetic';$package=Join-Path $stage 'payload/synthetic'
            # unins000.dat can receive final log records after this checkpoint; verify the immutable executable and manifest here.
            $receipt=Get-Content (Join-Path $stage 'setup-metadata.ini')
            $receipt[2]|Should -Be ('manifest_sha256='+(Get-FileHash (Join-Path $package 'build-manifest.json')).Hash.ToLowerInvariant())
            $receipt[3]|Should -Be ('unins000.exe='+(Get-FileHash (Join-Path $app 'unins000.exe')).Hash.ToLowerInvariant())
            $receipt[4]|Should -Match '^unins000.dat=[a-f0-9]{64}$'
        } finally {
            # Only this unique probe's supported uninstaller is run; never AuthLens or any existing installation.
            $uninstall=Join-Path $app 'unins000.exe'
            if(Test-Path $uninstall){
                $process=Start-Process -FilePath $uninstall -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -Wait -PassThru
                $process.ExitCode|Should -Be 0
            }
        }
    }
}
