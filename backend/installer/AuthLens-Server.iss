; AuthLens Server (.NET) machine-wide installer. Built by scripts/build-installers.ps1 from a verified release folder (build-release.ps1):
;   ISCC /DFullVersion=2.0.0 /DNumericVersion=2.0.0.0 /DReleaseDir=<release folder> AuthLens-Server.iss
; Stages an immutable payload under {app}\setup. The existing versioned deployment transaction owns service installation/update and readiness.
; The server's --data-dir is outside program files; no earlier-product service or data directory is adopted.
; Configuration is explicit; backup, rollback compatibility and readiness are mandatory. No process is killed.
; Uninstall verifies ownership and an encrypted backup, then removes only the owned service/firewall rules; data is retained.
; Silent: AuthLens-Server-<version>-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART [/LOG=<file>]
#ifndef FullVersion
  #error FullVersion is required
#endif
#ifndef NumericVersion
  #error NumericVersion is required
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required (a release folder verified by verify-release.ps1)
#endif
#ifndef PackageName
  #error PackageName is required
#endif
#ifndef ToolsDir
  #error ToolsDir is required
#endif
#define InstallerMode "Server"
#define RepoRoot AddBackslash(SourcePath) + "..\.."
#define ProductIcon RepoRoot + "\assets\branding\app.ico"
#define AppIdGuid "B961C010-9B53-4514-9D2A-73A4641E4AAF"
#define VersionKey "Software\AuthLens\Server"

[Setup]
AppId={{{#AppIdGuid}}
AppName=AuthLens
AppVersion={#FullVersion}
AppVerName=AuthLens {#FullVersion}
AppPublisher=AuthLens
DefaultDirName={commonappdata}\AuthLens\app
UsePreviousAppDir=no
SetupLogging=yes
DisableDirPage=auto
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
SetupIconFile={#ProductIcon}
UninstallDisplayIcon={app}\setup\{#PackageName}\payload\{#PackageName}\server\AuthLens.Api.exe
UninstallDisplayName=AuthLens Server
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#NumericVersion}
VersionInfoTextVersion={#FullVersion}
VersionInfoProductName=AuthLens
VersionInfoProductVersion={#NumericVersion}
VersionInfoProductTextVersion={#FullVersion}
VersionInfoDescription=AuthLens Server Setup
OutputBaseFilename=AuthLens-Server-{#FullVersion}-Setup

[Files]
Source: "{#ToolsDir}\*"; DestDir: "{tmp}\AuthLensPrerequisites\{#PackageName}\tools"; Flags: dontcopy recursesubdirs noencryption
Source: "{#ReleaseDir}\*"; DestDir: "{app}\setup\{#PackageName}\payload\{#PackageName}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ReleaseDir}\*"; DestDir: "{tmp}\AuthLensPrerequisites\{#PackageName}\payload\{#PackageName}"; Flags: dontcopy recursesubdirs noencryption
Source: "{#ToolsDir}\*"; DestDir: "{app}\setup\{#PackageName}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\LICENSE.md"; DestDir: "{app}\setup\{#PackageName}"; Flags: ignoreversion

[Icons]
Name: "{group}\AuthLens Service Manager"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -File ""{app}\setup\{#PackageName}\payload\{#PackageName}\Service-Manager.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\setup\{#PackageName}\payload\{#PackageName}\server\AuthLens.Api.exe"

[Registry]
Root: HKLM; Subkey: "{#VersionKey}"; ValueType: string; ValueName: "FileVersion"; ValueData: "{#NumericVersion}"; Flags: uninsdeletekey

[Run]
Filename: "{code:ServerAccessUrl}"; Description: "Open the verified AuthLens backend URL"; Flags: shellexec postinstall skipifsilent; Check: ServerAccessUsable

; No [UninstallDelete] and no [InstallDelete]: data directories, certificates, logs and backups are never removed by Setup or uninstall.

[Code]
const
  ServicesKey = 'SYSTEM\CurrentControlSet\Services\';

function ServiceNames(): TArrayOfString;
begin
  // Only AuthLens: services of earlier products (SAP Lens: sap-lens, SapLens, SapLens2) are never stopped, started or inspected.
  SetArrayLength(Result, 1);
  Result[0] := 'AuthLens';
end;

// Whether service Name exists and its executable lies in Directory (case-insensitive prefix of the unquoted ImagePath).
function ServiceRunsFrom(Name, Directory: String): Boolean;
var ImagePath: String;
begin
  Result := False;
  if not RegQueryStringValue(HKLM, ServicesKey + Name, 'ImagePath', ImagePath) then Exit;
  StringChangeEx(ImagePath, '"', '', True);
  Result := Pos(Uppercase(AddBackslash(ExpandFileName(Directory))), Uppercase(ImagePath)) = 1;
end;

function InitializeSetup(): Boolean;
begin
  // Product SemVer/build checks belong to the verified shared preflight, not the numeric registry version.
  Result := True;
end;

var
  UninstallConfig, UninstallConfigHash, UninstallPlan, UninstallDiagnostic: String;

function RunServerUninstall(Planning: Boolean): Boolean;
var Arguments: String; Code: Integer; Detail: AnsiString;
begin
  Arguments := '-NoProfile -NonInteractive -File "' + ExpandConstant('{app}\setup\{#PackageName}\tools\Install-AuthLens.ps1') + '" -Mode Server -ConfigFile "' + UninstallConfig + '" -InstallRoot "' + ExpandConstant('{app}') + '"';
  if Planning then Arguments := Arguments + ' -Operation UninstallPlan -PlanFile "' + UninstallPlan + '"'
  else Arguments := Arguments + ' -Operation Uninstall -Yes -ExpectedConfigSha256 ' + UninstallConfigHash;
  Arguments := Arguments + ' -DiagnosticFile "' + UninstallDiagnostic + '"';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code);
  if not Result then Code := 4;
  Result := Code = 0;
  if not Result then begin
    Detail := 'Retain the uninstall/deployment journal and verified recovery tools.';
    LoadStringFromFile(UninstallDiagnostic, Detail);
    SuppressibleMsgBox('AuthLens uninstall refused (exit ' + IntToStr(Code) + '). ' + UTF8Decode(Detail) + ' Persistent data, configuration, TLS and recovery material are preserved.', mbError, MB_OK, IDOK);
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := False;
  if not RegQueryStringValue(HKLM, '{#VersionKey}', 'ConfigFile', UninstallConfig) then begin
    // Without a service, an older staging-only installation can be removed without touching persistent state.
    Result := not RegKeyExists(HKLM, ServicesKey + 'AuthLens');
    if not Result then SuppressibleMsgBox('AuthLens service ownership configuration is unavailable. Preserve this installation and complete a verified upgrade/recovery before uninstalling.', mbError, MB_OK, IDOK);
    Exit;
  end;
  if (Pos('"', UninstallConfig) > 0) or (Pos(#13, UninstallConfig) > 0) or (Pos(#10, UninstallConfig) > 0) then Exit;
  UninstallPlan := ExpandConstant('{tmp}\AuthLens-uninstall-') + GetDateTimeString('yyyymmddhhnnsszzz', '', '') + '.ini';
  UninstallDiagnostic := UninstallPlan + '.diagnostic';
  Result := RunServerUninstall(True);
  if Result then begin
    UninstallConfigHash := GetIniString('AuthLens', 'config_sha256', '', UninstallPlan);
    Result := Length(UninstallConfigHash) = 64;
  end;
  if Result and not UninstallSilent then
    Result := SuppressibleMsgBox('Remove the verified AuthLens service and installer-owned firewall rules? All databases, accounts, history, settings, certificates, keys, backups and recovery evidence will be preserved.', mbConfirmation, MB_YESNO, IDNO) = IDYES;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and (UninstallConfig <> '') then
    if not RunServerUninstall(False) then RaiseException('AuthLens service uninstall did not verify. File removal has been stopped; retain all recovery evidence.');
end;

#include "AuthLens-Server-Code.iss"
#include "AuthLens-Transaction.iss"
