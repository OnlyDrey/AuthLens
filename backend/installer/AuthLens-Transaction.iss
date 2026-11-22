// Shared Pascal Script include: both installers include this inside their [Code] section.
// Application replacement uses the existing verified deployment/backup adapters after payload extraction.
procedure CurStepChanged(CurStep: TSetupStep);
var Arguments, Diagnostic: String; Detail: AnsiString; Code: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  Arguments := '-NoProfile -NonInteractive -File "' + ExpandConstant('{app}\setup\{#PackageName}\tools\Install-AuthLens.ps1') +
    '" -Mode {#InstallerMode} -Package "' + ExpandConstant('{app}\setup\{#PackageName}\payload\{#PackageName}') + '" -Yes';
  Arguments := Arguments + InstallerArguments();
  Diagnostic := ExpandConstant('{app}\setup\{#PackageName}\transaction-diagnostic.txt');
  Arguments := Arguments + ' -DiagnosticFile "' + Diagnostic + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 4;
  if Code <> 0 then begin
    Detail := 'No diagnostic returned; retain the Setup log.';
    LoadStringFromFile(Diagnostic, Detail);
    RaiseException('AuthLens transaction failed (exit ' + IntToStr(Code) + '). ' + Detail + ' Retain the installation journal and recovery tools; no data is deleted.');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if DirExists(ExpandConstant('{app}\setup\{#PackageName}')) then begin
    Result := 'This exact Setup payload already exists. It is never overwritten. Review its recovery journal or use another verified package.';
    Exit;
  end;
  Result := PrepareInstaller();
end;
