// Server-only wizard; all deployment decisions stay in the hash-verified PowerShell adapter.
var
  ServerConfigPage: TInputFileWizardPage;
  ServerCreatePage: TInputOptionWizardPage;
  ServerTlsModePage: TInputOptionWizardPage;
  ServerEditPaths, ServerEditNetwork, ServerEditTls: TInputQueryWizardPage;
  ServerPathsPage, ServerNetworkPage, ServerIdentityPage, ServerValidationPage: TOutputMsgWizardPage;
  ServerFirewallPage: TInputOptionWizardPage;
  ServerFirewallScope: TInputQueryWizardPage;
  ServerConfig, ServerConfigHash, ServerRoot, ServerPlanFile, ServerError, ServerOperation: String;
  ServerToolsReady, ServerPayloadReady, ServerResolved, ServerPreflighted, ServerVerified: Boolean;
  ServerAttempt: Integer;
  ServerGenerateTls: Boolean;

function ServerFirewallArguments(): String;
begin
  Result := '';
  if ServerFirewallPage.SelectedValueIndex <> 1 then Exit;
  if (Pos('"', ServerFirewallScope.Values[0]) > 0) or (Pos(#13, ServerFirewallScope.Values[0]) > 0) or (Pos(#10, ServerFirewallScope.Values[0]) > 0) or
     (Pos('"', ServerFirewallScope.Values[1]) > 0) or (Pos(#13, ServerFirewallScope.Values[1]) > 0) or (Pos(#10, ServerFirewallScope.Values[1]) > 0) then
    RaiseException('Invalid firewall scope. Enter explicit IP addresses/subnets and Private or Domain profiles.');
  Result := ' -ApproveFirewall -FirewallSources "' + ServerFirewallScope.Values[0] + '" -FirewallProfiles "' + ServerFirewallScope.Values[1] + '"';
end;

function JsonString(Value: String): String;
begin
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  StringChangeEx(Value, #13, '\r', True);
  StringChangeEx(Value, #10, '\n', True);
  StringChangeEx(Value, #9, '\t', True);
  Result := '"' + Value + '"';
end;

function JsonList(Value: String): String;
var Item: String; P: Integer;
begin
  Result := '[';
  while Trim(Value) <> '' do begin
    P := Pos(',', Value);
    if P = 0 then begin Item := Trim(Value); Value := ''; end
    else begin Item := Trim(Copy(Value, 1, P - 1)); Delete(Value, 1, P); end;
    if Result <> '[' then Result := Result + ',';
    Result := Result + JsonString(Item);
  end;
  Result := Result + ']';
end;

function CreateServerDraft(): Boolean;
var Draft, Contents, TlsDirectory: String; Lines: TArrayOfString; Port: Integer;
begin
  Result := False;
  Port := StrToIntDef(ServerEditNetwork.Values[1], 0);
  if (Port < 1) or (Port > 65535) then begin ServerError := 'HTTPS port must be 1..65535.'; Exit; end;
  ServerAttempt := ServerAttempt + 1;
  ServerGenerateTls := ServerTlsModePage.SelectedValueIndex = 1;
  if ServerGenerateTls then begin
    TlsDirectory := ExpandConstant('{commonappdata}\AuthLensSetup\TLS-') + Lowercase(Copy(GetSHA256OfString(ExpandConstant('{tmp}') + GetDateTimeString('yyyymmddhhnnsszzz', '-', ':') + IntToStr(ServerAttempt)), 1, 32));
    ServerEditTls.Values[0] := TlsDirectory + '\server.pfx';
    ServerEditTls.Values[1] := TlsDirectory + '\cert-password';
  end;
  Draft := ExpandConstant('{tmp}\AuthLens-configuration-') + IntToStr(ServerAttempt) + '.json';
  Contents := '{"Root":' + JsonString(Trim(ServerEditPaths.Values[0])) +
    ',"ListenAddress":' + JsonString(Trim(ServerEditNetwork.Values[0])) + ',"Port":' + IntToStr(Port) +
    ',"AllowedHosts":' + JsonList(ServerEditNetwork.Values[2]) +
    ',"ProxyHosts":' + JsonList(ServerEditNetwork.Values[3]) +
    ',"TrustedProxies":' + JsonList(ServerEditNetwork.Values[4]) +
    ',"CertificatePath":' + JsonString(Trim(ServerEditTls.Values[0])) +
    ',"CertificatePasswordFile":' + JsonString(Trim(ServerEditTls.Values[1]));
  if Trim(ServerEditPaths.Values[1]) <> '' then Contents := Contents + ',"DataDirectory":' + JsonString(Trim(ServerEditPaths.Values[1]));
  if Trim(ServerEditPaths.Values[2]) <> '' then Contents := Contents + ',"BackupRoot":' + JsonString(Trim(ServerEditPaths.Values[2]));
  Contents := Contents + '}';
  SetArrayLength(Lines, 1); Lines[0] := Contents;
  if FileExists(Draft) or not SaveStringsToUTF8File(Draft, Lines, False) then begin ServerError := 'Cannot create a new private configuration draft.'; Exit; end;
  ServerConfigPage.Values[0] := Draft;
  Result := True;
end;

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
  Arguments := Arguments + ServerFirewallArguments();
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
  if ServerGenerateTls then begin
    EnsureServerPayload();
    Result := RunServerHelper('-GenerateTlsDraft -Package "' + ServerPackage() + '" -Yes', True);
    if Result then ServerGenerateTls := False;
  end else Result := RunServerHelper('-ResolveOnly', True);
  if not Result then Exit;
  ServerConfig := ServerValue('config_file'); ServerConfigHash := ServerValue('config_sha256'); ServerRoot := ServerValue('root');
  if (ServerValue('program_directory') = '') or (ServerConfigHash = '') then begin
    ServerError := 'The verified helper returned an incomplete directory plan.'; Result := False; Exit;
  end;
  WizardForm.DirEdit.Text := ServerValue('program_directory');
  ServerConfigPage.Values[0] := ServerConfig;
  ServerPathsPage.MsgLabel.Caption := 'Configuration: ' + ServerConfig + #13#10 + 'Root: ' + ServerRoot + #13#10 + 'Program staging: ' + WizardDirValue() + #13#10 + 'Data: ' + ServerValue('data_directory') + #13#10 + 'Backups: ' + ServerValue('backup_directory') + #13#10#13#10 + 'Paths are derived from the validated configuration. Fresh wizard choices are published only after approval. Existing installations are never relocated.';
  ServerNetworkPage.MsgLabel.Caption := 'HTTPS listen address: ' + ServerValue('listen_address') + #13#10 + 'Port: ' + ServerValue('port') + #13#10 + 'Certificate: ' + ServerValue('certificate') + #13#10 + 'Allowed hosts: ' + ServerValue('allowed_hosts') + #13#10 + 'Public proxy hosts: ' + ServerValue('proxy_hosts') + #13#10 + 'Trusted proxy peers: ' + ServerValue('trusted_proxies') + #13#10#13#10 + 'Fresh TLS is imported into a new protected versioned directory under the selected root. Existing TLS/network settings are preserved during upgrade. Setup never adds trusted roots, disables certificate verification or trusts arbitrary proxies.';
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
  ServerCreatePage := CreateInputOptionPage(wpWelcome, 'Configuration source', 'Create a fresh configuration or preserve an existing installation', 'Fresh configuration is published only after validated preparation. Existing configuration and certificate files are never overwritten.', True, False);
  ServerCreatePage.Add('Discover or select existing deployment configuration (upgrade)');
  ServerCreatePage.Add('Configure a fresh Server through this wizard');
  ServerCreatePage.SelectedValueIndex := 0;
  ServerConfigPage := CreateInputFilePage(ServerCreatePage.ID, 'Server configuration and detection', 'Choose the deployment configuration', 'Leave blank for registered/managed configuration discovery. Service ownership and release metadata are validated; detection never changes services or databases.');
  ServerConfigPage.Add('Deployment configuration:', 'JSON configuration|*.json|All files|*.*', '.json');
  InitialConfig := ExpandConstant('{param:CONFIGFILE|}');
  if InitialConfig = '' then RegQueryStringValue(HKLM, '{#VersionKey}', 'ConfigFile', InitialConfig);
  ServerConfigPage.Values[0] := InitialConfig;
  ServerEditPaths := CreateInputQueryPage(ServerConfigPage.ID, 'Fresh installation directories', 'Choose private AuthLens storage', 'Advanced paths may be left blank to use directories under the installation root. Existing installations cannot be relocated.');
  ServerEditPaths.Add('Installation root:', False); ServerEditPaths.Values[0] := 'C:\ProgramData\AuthLens';
  ServerEditPaths.Add('Advanced application data directory (optional):', False);
  ServerEditPaths.Add('Advanced predeployment backup directory (optional):', False);
  ServerEditNetwork := CreateInputQueryPage(ServerEditPaths.ID, 'HTTPS and reverse proxy', 'Choose explicit network boundaries', 'Use 127.0.0.1 for local HTTPS. LAN requires an assigned IP and certificate-valid hosts. Proxy hosts and trusted peers are comma-separated; leave blank without a reverse proxy.');
  ServerEditNetwork.Add('Listening IP address:', False); ServerEditNetwork.Values[0] := '127.0.0.1';
  ServerEditNetwork.Add('HTTPS port:', False); ServerEditNetwork.Values[1] := '18795';
  ServerEditNetwork.Add('Allowed hosts (comma-separated):', False);
  ServerEditNetwork.Add('Public reverse-proxy hosts (optional):', False);
  ServerEditNetwork.Add('Trusted proxy IP addresses (optional):', False);
  ServerTlsModePage := CreateInputOptionPage(ServerEditNetwork.ID, 'HTTPS certificate', 'Select existing TLS or generate a local certificate', 'Generated certificates are self-signed and are NOT automatically trusted. No trusted store is changed. Review client trust separately; public server.cer is retained beside the protected draft. Both options create new private imported files under the installation root after approval.', True, False);
  ServerTlsModePage.Add('Use an existing PFX certificate and protected password file');
  ServerTlsModePage.Add('Generate local HTTPS: new 3072-bit RSA key, server authentication, one-year validity');
  ServerTlsModePage.SelectedValueIndex := 0;
  ServerEditTls := CreateInputQueryPage(ServerTlsModePage.ID, 'Existing TLS certificate', 'Select protected certificate material', 'Provide an existing PFX and its protected password file. Password contents are never entered here or passed on a command line. Certificate name, validity and private key are validated before provisioning. Client trust remains an explicit administrator responsibility.');
  ServerEditTls.Add('Absolute PFX certificate path:', False);
  ServerEditTls.Add('Absolute certificate password file path:', False);
  ServerPathsPage := CreateOutputMsgPage(ServerEditTls.ID, 'Installation directories', 'Validated configuration owns the directory selection', '');
  ServerNetworkPage := CreateOutputMsgPage(ServerPathsPage.ID, 'Network and TLS', 'Review preserved HTTPS and reverse-proxy settings', '');
  ServerIdentityPage := CreateOutputMsgPage(ServerNetworkPage.ID, 'Windows Service', 'Review the explicit service identity', '');
  ServerFirewallPage := CreateInputOptionPage(ServerIdentityPage.ID, 'Windows Firewall security approval', 'Choose whether to authorize a source-restricted inbound rule', 'Default preserves all rules. Loopback never needs an exception. A new rule is restricted to the selected local IP, TCP port, AuthLens service, remote addresses and Private/Domain profiles. Administrator-created rules remain untouched.', True, False);
  ServerFirewallPage.Add('Preserve firewall configuration; no new inbound exception');
  ServerFirewallPage.Add('I explicitly authorize the source-restricted rule reviewed below');
  ServerFirewallPage.SelectedValueIndex := 0;
  ServerFirewallScope := CreateInputQueryPage(ServerFirewallPage.ID, 'Review approved firewall scope', 'Only the following traffic will be allowed', 'Comma-separated literal IP addresses or CIDR subnets are required. No wildcard, Public or Any profile is accepted. The rule is applied only after the Server transaction succeeds.');
  ServerFirewallScope.Add('Allowed source addresses/subnets:', False);
  ServerFirewallScope.Add('Profiles (Private and/or Domain):', False); ServerFirewallScope.Values[1] := 'Private';
  if CompareText(ExpandConstant('{param:APPROVEFIREWALL|No}'), 'Yes') = 0 then begin
    ServerFirewallPage.SelectedValueIndex := 1;
    ServerFirewallScope.Values[0] := ExpandConstant('{param:FIREWALLSOURCES|}');
    ServerFirewallScope.Values[1] := ExpandConstant('{param:FIREWALLPROFILES|Private}');
  end;
  ServerValidationPage := CreateOutputMsgPage(ServerFirewallScope.ID, 'Read-only preflight', 'Validation runs before confirmation and system provisioning', 'The helper verifies package identity, installation/service ownership, directory isolation, ACLs, assigned address, port ownership and staging/backup storage. The packaged host validates HTTPS/proxy policy, certificate names/private key/expiry, database integrity and schema without initializing data. Upgrade rollback compatibility is checked. Backup verification, service-identity key access and actual TLS/readiness are repeated in the protected transaction.');
  if WizardSilent then if not ResolveServerWizard() then RaiseException(ServerError);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = ServerConfigPage.ID then Result := ResolveServerWizard();
  if CurPageID = ServerEditTls.ID then begin
    Result := CreateServerDraft();
    if Result then Result := ResolveServerWizard();
  end;
  if (CurPageID = ServerTlsModePage.ID) and (ServerTlsModePage.SelectedValueIndex = 1) then begin
    Result := CreateServerDraft();
    if Result then Result := ResolveServerWizard();
  end;
  if (CurPageID = ServerValidationPage.ID) or ((CurPageID = wpReady) and not ServerPreflighted) then Result := PreflightServerWizard();
  if not Result then SuppressibleMsgBox(ServerError, mbError, MB_OK, IDOK);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := PageID = wpSelectDir;
  if PageID = ServerFirewallScope.ID then Result := ServerFirewallPage.SelectedValueIndex <> 1;
  if PageID = ServerConfigPage.ID then Result := ServerCreatePage.SelectedValueIndex = 1;
  if (PageID = ServerEditPaths.ID) or (PageID = ServerEditNetwork.ID) or (PageID = ServerTlsModePage.ID) then Result := ServerCreatePage.SelectedValueIndex <> 1;
  if PageID = ServerEditTls.ID then Result := (ServerCreatePage.SelectedValueIndex <> 1) or (ServerTlsModePage.SelectedValueIndex = 1);
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'Operation: ' + ServerValue('operation') + NewLine + 'AuthLens {#FullVersion}' + NewLine + 'Root: ' + ServerRoot + NewLine + 'Program staging: ' + WizardDirValue() + NewLine + 'Data preserved: ' + ServerValue('data_directory') + NewLine + 'Backups preserved: ' + ServerValue('backup_directory') + NewLine + 'Existing configuration, TLS, encryption keys, accounts and history are preserved.' + NewLine + 'New immutable payload/release and transaction evidence will be created. The owned service may stop/restart after verified backup and rollback checks.' + NewLine + 'No DNS, legacy installation or external proxy changes.';
  if ServerFirewallPage.SelectedValueIndex = 1 then Result := Result + NewLine + 'Explicitly approved firewall: TCP ' + ServerValue('listen_address') + ':' + ServerValue('port') + ', sources ' + ServerFirewallScope.Values[0] + ', profiles ' + ServerFirewallScope.Values[1]
  else Result := Result + NewLine + 'Firewall configuration preserved; no new rule.';
end;

function InstallerArguments(): String;
begin
  Result := ' -ConfigFile "' + ServerConfig + '" -InstallRoot "' + ExpandConstant('{app}') + '" -ExpectedConfigSha256 ' + ServerConfigHash + ' -Operation ' + ServerOperation;
  Result := Result + ServerFirewallArguments();
end;

function InstallerMetadataArguments(): String;
var Receipt, Text: String;
begin
  Result := '';
  if ServerValue('operation') <> 'fresh installation' then Exit;
  Receipt := ExpandConstant('{app}\setup\{#PackageName}\setup-metadata.ini');
  if FileExists(Receipt) then RaiseException('Setup metadata evidence already exists; it will not be overwritten. Use explicit recovery.');
  Text := '[AuthLensSetup]' + #13#10 + 'schema=1' + #13#10 +
    'manifest_sha256=' + Lowercase(GetSHA256OfFile(ExpandConstant('{app}\setup\{#PackageName}\payload\{#PackageName}\build-manifest.json'))) + #13#10 +
    'unins000.exe=' + Lowercase(GetSHA256OfFile(ExpandConstant('{app}\unins000.exe'))) + #13#10 +
    'unins000.dat=' + Lowercase(GetSHA256OfFile(ExpandConstant('{app}\unins000.dat'))) + #13#10;
  if not SaveStringToFile(Receipt, Text, False) then RaiseException('Setup metadata evidence could not be recorded; no deployment was started.');
  Result := ' -SetupMetadataFile "' + Receipt + '"';
end;

function PrepareInstaller(): String;
begin
  Result := '';
  if not ServerPreflighted then if not PreflightServerWizard() then begin Result := ServerError; Exit; end;
  if ServerCreatePage.SelectedValueIndex = 1 then begin
    if not RunServerHelper('-PrepareOnly -CommitNewConfiguration -ImportTls -Package "' + ServerPackage() + '" -Yes', True) then begin Result := ServerError; Exit; end;
    ServerConfig := ServerValue('config_file'); ServerConfigHash := ServerValue('config_sha256');
  end else if not RunServerHelper('-PrepareOnly -Package "' + ServerPackage() + '" -Yes', False) then Result := ServerError;
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
