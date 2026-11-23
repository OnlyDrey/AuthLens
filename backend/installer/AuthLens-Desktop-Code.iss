// Desktop-only callbacks; Server never includes this file.
function DesktopData(Param: String): String;
begin
  Result := ExpandConstant('{param:DATADIR|}');
  if Result = '' then RegQueryStringValue(HKCU, '{#VersionKey}', 'DataDirectory', Result);
  if Result = '' then Result := ExpandConstant('{localappdata}\AuthLens\data');
end;

procedure AfterInstallerSuccess();
begin
end;

function InstallerArguments(): String;
begin
  Result := ' -InstallRoot "' + ExpandConstant('{app}') + '" -DataDirectory "' + DesktopData('') + '"';
end;

function InstallerMetadataArguments(): String;
begin
  Result := '';
end;

function PrepareInstaller(): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\AuthLens.exe')) then
    WizardForm.Caption := 'AuthLens Desktop - upgrade'
  else WizardForm.Caption := 'AuthLens Desktop - fresh installation';
  Log(WizardForm.Caption);
end;
