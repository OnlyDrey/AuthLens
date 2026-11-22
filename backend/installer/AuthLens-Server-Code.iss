// Server-only wizard; all deployment decisions stay in the hash-verified PowerShell adapter.
var
  ServerConfigPage: TInputFileWizardPage;
  ServerPathsPage, ServerNetworkPage, ServerIdentityPage, ServerFirewallPage, ServerValidationPage: TOutputMsgWizardPage;
  ServerConfig, ServerConfigHash, ServerRoot, ServerPlanFile, ServerError, ServerOperation: String;
  ServerToolsReady, ServerPayloadReady, ServerResolved, ServerPreflighted, ServerVerified: Boolean;
  ServerAttempt: Integer;

function ServerValue(Name: String): String;
begin
  Result := GetIniString('AuthLens', Name, '', ServerPlanFile);
end;

procedure EnsureServerTools();
begin
  if ServerToolsReady then Exit;
  ExtractTemporaryFiles('{tmp}\AuthLensPrerequisites\{#PackageName}\tools\*');
  ServerToolsReady := True;
end;

function ServerPackage(): String;
begin
  Result := ExpandConstant('{tmp}\AuthLensPrerequisites\{#PackageName}\payload\{#PackageName}');
end;

procedure EnsureServerPayload();
begin
  if ServerPayloadReady then Exit;
  ExtractTemporaryFiles('{tmp}\AuthLensPrerequisites\{#PackageName}\payload\{#PackageName}\*');
  ServerPayloadReady := True;
end;

function RunServerHelper(Flags: String; NeedPlan: Boolean): Boolean;
var Arguments, Diagnostic, Report, RequestedDir: String; Detail: AnsiString; Code: Integer;
begin
  EnsureServerTools();
  ServerAttempt := ServerAttempt + 1;
  Diagnostic := ExpandConstant('{tmp}\AuthLens-diagnostic-') + IntToStr(ServerAttempt) + '.txt';
  Report := ExpandConstant('{tmp}\AuthLens-result-') + IntToStr(ServerAttempt) + '.json';
  if NeedPlan then ServerPlanFile := ExpandConstant('{tmp}\AuthLens-plan-') + IntToStr(ServerAttempt) + '.ini';
  Arguments := '-NoProfile -NonInteractive -File "' + ExpandConstant('{tmp}\AuthLensPrerequisites\{#PackageName}\tools\Install-AuthLens.ps1') + '" -Mode Server ' + Flags;
  if ServerConfig <> '' then Arguments := Arguments + ' -ConfigFile "' + ServerConfig + '"';
  RequestedDir := ExpandConstant('{param:DIR|}');
  if ServerResolved then RequestedDir := WizardDirValue();
  if (Pos('"', RequestedDir) > 0) or (Pos(#13, RequestedDir) > 0) or (Pos(#10, RequestedDir) > 0) then begin
    ServerError := 'Invalid explicit program directory.'; Result := False; Exit;
  end;
  if RequestedDir <> '' then Arguments := Arguments + ' -InstallRoot "' + RequestedDir + '"';
  if ServerConfigHash <> '' then Arguments := Arguments + ' -ExpectedConfigSha256 ' + ServerConfigHash;
  Arguments := Arguments + ' -Operation ' + ServerOperation + ' -DiagnosticFile "' + Diagnostic + '" -ResultFile "' + Report + '"';
  if NeedPlan then Arguments := Arguments + ' -PlanFile "' + ServerPlanFile + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 4;
  if LoadStringFromFile(Report, Detail) then Log(UTF8Decode(Detail));
  Result := Code = 0;
  if not Result then begin
    Detail := 'No diagnostic returned; retain the automatic Setup log and the private temporary reports.';
    LoadStringFromFile(Diagnostic, Detail);
    ServerError := 'Server preparation refused (exit ' + IntToStr(Code) + '). No service was changed. ' + UTF8Decode(Detail);
    Log(ServerError);
  end;
end;

function ResolveServerWizard(): Boolean;
begin
  ServerResolved := False; ServerPreflighted := False; ServerConfigHash := '';
  ServerConfig := Trim(ServerConfigPage.Values[0]);
  if (Pos('"', ServerConfig) > 0) or (Pos(#13, ServerConfig) > 0) or (Pos(#10, ServerConfig) > 0) then begin
    ServerError := 'Select an ordinary absolute deployment configuration file.'; Result := False; Exit;
  end;
  Result := RunServerHelper('-ResolveOnly', True);
  if not Result then Exit;
  ServerConfig := ServerValue('config_file'); ServerConfigHash := ServerValue('config_sha256'); ServerRoot := ServerValue('root');
  if (ServerValue('program_directory') = '') or (ServerConfigHash = '') then begin
    ServerError := 'The verified helper returned an incomplete directory plan.'; Result := False; Exit;
  end;
  WizardForm.DirEdit.Text := ServerValue('program_directory');
  ServerConfigPage.Values[0] := ServerConfig;
  ServerPathsPage.MsgLabel.Caption := 'Configuration: ' + ServerConfig + #13#10 + 'Root: ' + ServerRoot + #13#10 + 'Program staging: ' + WizardDirValue() + #13#10 + 'Data: ' + ServerValue('data_directory') + #13#10 + 'Backups: ' + ServerValue('backup_directory') + #13#10#13#10 + 'Paths are derived from the validated configuration. Existing installations are never relocated. Advanced data/backup choices must be explicitly configured before review.';
  ServerNetworkPage.MsgLabel.Caption := 'HTTPS listen address: ' + ServerValue('listen_address') + #13#10 + 'Port: ' + ServerValue('port') + #13#10 + 'Certificate: ' + ServerValue('certificate') + #13#10 + 'Allowed hosts: ' + ServerValue('allowed_hosts') + #13#10 + 'Public proxy hosts: ' + ServerValue('proxy_hosts') + #13#10 + 'Trusted proxy peers: ' + ServerValue('trusted_proxies') + #13#10#13#10 + 'Existing TLS and network settings are preserved. Setup never generates/replaces keys, disables certificate verification or trusts arbitrary proxies.';
  ServerIdentityPage.MsgLabel.Caption := 'Service: ' + ServerValue('service_name') + #13#10 + 'Identity: ' + ServerValue('service_account') + #13#10#13#10 + 'Fresh Setup uses NT SERVICE\AuthLens. Existing identities are preserved and checked. Password-bearing accounts and gMSA provisioning are not exposed until service-logon and credential validation are supported.';
  ServerResolved := True;
end;

function PreflightServerWizard(): Boolean;
begin
  if not ServerResolved then begin Result := ResolveServerWizard(); if not Result then Exit; end;
  EnsureServerPayload();
  Result := RunServerHelper('-PreflightOnly -Package "' + ServerPackage() + '"', True);
  if Result then begin
    ServerPreflighted := True;
    WizardForm.Caption := 'AuthLens Server - ' + ServerValue('operation');
  end;
end;

procedure InitializeWizard();
var InitialConfig: String;
begin
  ServerOperation := ExpandConstant('{param:OPERATION|Auto}');
  if (CompareText(ServerOperation, 'Auto') <> 0) and (CompareText(ServerOperation, 'Install') <> 0) and (CompareText(ServerOperation, 'Upgrade') <> 0) then
    RaiseException('Setup supports /OPERATION=Auto, Install or Upgrade. Use the supported read-only CLI for repair and uninstall planning; no destructive fallback is performed.');
  ServerConfigPage := CreateInputFilePage(wpWelcome, 'Server configuration and detection', 'Choose the deployment configuration', 'Leave blank for registered/managed configuration discovery. Fresh installation requires an operator-prepared JSON configuration and TLS files. Service ownership and release metadata are validated; detection never changes services or databases.');
  ServerConfigPage.Add('Deployment configuration:', 'JSON configuration|*.json|All files|*.*', '.json');
  InitialConfig := ExpandConstant('{param:CONFIGFILE|}');
  if InitialConfig = '' then RegQueryStringValue(HKLM, '{#VersionKey}', 'ConfigFile', InitialConfig);
  ServerConfigPage.Values[0] := InitialConfig;
  ServerPathsPage := CreateOutputMsgPage(ServerConfigPage.ID, 'Installation directories', 'Validated configuration owns the directory selection', '');
  ServerNetworkPage := CreateOutputMsgPage(ServerPathsPage.ID, 'Network and TLS', 'Review preserved HTTPS and reverse-proxy settings', '');
  ServerIdentityPage := CreateOutputMsgPage(ServerNetworkPage.ID, 'Windows Service', 'Review the explicit service identity', '');
  ServerFirewallPage := CreateOutputMsgPage(ServerIdentityPage.ID, 'Windows Firewall', 'No firewall changes will be made', 'Setup does not own firewall rules yet. Existing rules remain untouched. Loopback requires no inbound exception; LAN/proxy access needs a separately approved source-restricted rule. No broad rule or silent exception is created.');
  ServerValidationPage := CreateOutputMsgPage(ServerFirewallPage.ID, 'Read-only preflight', 'Validation runs before confirmation and system provisioning', 'The helper verifies package identity, installation/service ownership, directory isolation, ACLs, assigned address, port ownership and staging/backup storage. The packaged host validates HTTPS/proxy policy, certificate names/private key/expiry, database integrity and schema without initializing data. Upgrade rollback compatibility is checked. Backup verification, service-identity key access and actual TLS/readiness are repeated in the protected transaction.');
  if WizardSilent then if not ResolveServerWizard() then RaiseException(ServerError);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ServerConfigPage.ID then Result := ResolveServerWizard();
  if (CurPageID = ServerValidationPage.ID) or ((CurPageID = wpReady) and not ServerPreflighted) then Result := PreflightServerWizard();
  if not Result then SuppressibleMsgBox(ServerError, mbError, MB_OK, IDOK);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := PageID = wpSelectDir;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'Operation: ' + ServerValue('operation') + NewLine + 'AuthLens {#FullVersion}' + NewLine + 'Root: ' + ServerRoot + NewLine + 'Program staging: ' + WizardDirValue() + NewLine + 'Data preserved: ' + ServerValue('data_directory') + NewLine + 'Backups preserved: ' + ServerValue('backup_directory') + NewLine + 'Configuration, TLS, encryption keys, accounts and history are preserved.' + NewLine + 'New immutable payload/release and transaction evidence will be created. The owned service may stop/restart after verified backup and rollback checks.' + NewLine + 'No firewall, DNS, legacy installation or external proxy changes.';
end;

function InstallerArguments(): String;
begin
  Result := ' -ConfigFile "' + ServerConfig + '" -InstallRoot "' + ExpandConstant('{app}') + '" -ExpectedConfigSha256 ' + ServerConfigHash + ' -Operation ' + ServerOperation;
end;

function PrepareInstaller(): String;
begin
  Result := '';
  if not ServerPreflighted then if not PreflightServerWizard() then begin Result := ServerError; Exit; end;
  if not RunServerHelper('-PrepareOnly -Package "' + ServerPackage() + '" -Yes', False) then Result := ServerError;
end;

procedure AfterInstallerSuccess();
begin
  // Persist discovery hints only after the shared deployment transaction returned verified success.
  if not RegWriteStringValue(HKLM, '{#VersionKey}', 'Root', ServerRoot) or
     not RegWriteStringValue(HKLM, '{#VersionKey}', 'ProgramDirectory', ExpandConstant('{app}')) or
     not RegWriteStringValue(HKLM, '{#VersionKey}', 'ConfigFile', ServerConfig) then
    RaiseException('Server transaction succeeded but installer discovery registration failed. Retain the verified service and transaction evidence; review registration before retrying.');
  ServerVerified := True;
end;

function ServerAccessUrl(Param: String): String;
var Address: String;
begin
  Address := ServerValue('listen_address'); Result := '';
  if (Address = '') or (Address = '0.0.0.0') or (Address = '::') then Exit;
  if Pos(':', Address) > 0 then Address := '[' + Address + ']';
  Result := 'https://' + Address + ':' + ServerValue('port');
end;

function ServerAccessUsable(): Boolean;
begin
  Result := ServerVerified and (ServerAccessUrl('') <> '');
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and ServerVerified then begin
    WizardForm.FinishedLabel.Caption := 'AuthLens {#FullVersion} transaction completed with service/API/TLS/database readiness checks.' + #13#10 +
      'Backend URL: ' + ServerAccessUrl('') + #13#10 +
      'Operation report: ' + ExpandConstant('{app}\setup\{#PackageName}\operation-result.json') + #13#10#13#10 +
      'Retain the deployment journal, encrypted backups and recovery tools. Fresh installations still need administrator activation and host backup-key provisioning/escrow. External proxy, DNS and client trust remain separate acceptance checks.';
  end;
end;
