// Server-only callbacks; Desktop never includes this file.
function InstallerArguments(): String;
begin
  Result := ' -ConfigFile "' + ExpandConstant('{param:CONFIGFILE|}') + '" -InstallRoot "' + ExpandConstant('{app}') + '"';
end;

function PrepareInstaller(): String;
var Arguments, Config, Diagnostic: String; Detail: AnsiString; Code: Integer;
begin
  Result := '';
  Config := ExpandConstant('{param:CONFIGFILE|}');
  if Config = '' then begin
    Result := 'Server Setup requires /CONFIGFILE="absolute deployment configuration path". Configuration, credentials, TLS and keys are never inferred or replaced.';
    Exit;
  end;
  // Provision the dedicated root with its protected DACL before Inno creates payload directories underneath it.
  ExtractTemporaryFiles('{tmp}\AuthLensPrerequisites\{#PackageName}\tools\*');
  Diagnostic := ExpandConstant('{tmp}\AuthLens-prepare-diagnostic.txt');
  // A previous attempt's diagnostic is evidence, never overwritten.
  if FileExists(Diagnostic) then begin
    Result := 'An earlier preparation diagnostic exists: ' + Diagnostic + '. Retain it and restart Setup for a new attempt.';
    Exit;
  end;
  Arguments := '-NoProfile -NonInteractive -File "' + ExpandConstant('{tmp}\AuthLensPrerequisites\{#PackageName}\tools\Install-AuthLens.ps1') +
    '" -Mode Server -PrepareOnly -ConfigFile "' + Config + '" -InstallRoot "' + ExpandConstant('{app}') + '" -DiagnosticFile "' + Diagnostic + '" -Yes';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 4;
  if Code <> 0 then begin
    Detail := 'No diagnostic was returned; verify PowerShell launch and retain the Setup log.';
    LoadStringFromFile(Diagnostic, Detail);
    Result := 'Server root security preparation refused (exit ' + IntToStr(Code) + '). No service was changed. ' + Detail;
    Log(Result);
  end;
end;
