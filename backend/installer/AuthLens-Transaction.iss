// Shared Pascal Script include: both installers include this inside their [Code] section.
// Application replacement uses the existing verified deployment/backup adapters after payload extraction.
procedure CurStepChanged(CurStep: TSetupStep);
var Arguments, Diagnostic: String; Detail: AnsiString; Code: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  Arguments := '-NoProfile -NonInteractive -File "' + ExpandConstant('{app}\setup\{#PackageName}\tools\Install-AuthLens.ps1') +
    '" -Mode {#InstallerMode} -Package "' + ExpandConstant('{app}\setup\{#PackageName}\payload\{#PackageName}') + '" -Yes';
  Arguments := Arguments + InstallerArguments();
  Arguments := Arguments + InstallerMetadataArguments();
  Diagnostic := ExpandConstant('{app}\setup\{#PackageName}\transaction-diagnostic.txt');
  Arguments := Arguments + ' -DiagnosticFile "' + Diagnostic + '" -ResultFile "' + ExpandConstant('{app}\setup\{#PackageName}\operation-result.json') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 4;
  if Code <> 0 then begin
    Detail := 'No diagnostic returned; retain the Setup log.';
    LoadStringFromFile(Diagnostic, Detail);
    // Keep the dialog concise. Sanitized structural diagnostics remain in the file/result.
    if Pos(#10, String(Detail)) > 0 then Detail := AnsiString(Copy(String(Detail), 1, Pos(#10, String(Detail)) - 1));
    RaiseException('AuthLens transaction failed (exit ' + IntToStr(Code) + '). ' + UTF8Decode(Detail) + ' Retain the operation result, Setup log, staged tools and any existing journal.');
  end;
  AfterInstallerSuccess();
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if DirExists(ExpandConstant('{app}\setup\{#PackageName}')) then begin
    Result := 'This exact Setup payload already exists. It is never overwritten. Preserve it and review the operation result and any recovery journal before retrying.';
    Exit;
  end;
  Result := PrepareInstaller();
end;
