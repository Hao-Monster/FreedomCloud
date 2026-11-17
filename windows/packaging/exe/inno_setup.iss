[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}
UninstallDisplayIcon={uninstallexe}
ChangesAssociations=yes
ShowLanguageDialog=yes
; Update mode settings
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
; Defer stopping running services/processes to CurStepChanged(ssInstall) after
; installation is confirmed instead of letting Restart Manager act on wpPreparing.
CloseApplications=no
RestartApplications=no

[CustomMessages]
chineseSimplified.UpgradeWindowCaption={{DISPLAY_NAME}} - 更新
english.UpgradeWindowCaption={{DISPLAY_NAME}} - Update
chineseSimplified.UpgradeWelcomeWithPrev=检测到已安装版本 %1。%n%n安装程序将更新至版本 {{APP_VERSION}}。%n%n点击“下一步”继续更新，或点击“取消”退出。
english.UpgradeWelcomeWithPrev=Detected installed version %1.%n%nSetup will update to version {{APP_VERSION}}.%n%nClick "Next" to continue updating, or "Cancel" to exit.
chineseSimplified.UpgradeWelcomeNoPrev=检测到已安装本程序。%n%n安装程序将更新至版本 {{APP_VERSION}}。%n%n点击“下一步”继续更新，或点击“取消”退出。
english.UpgradeWelcomeNoPrev=An existing installation was detected.%n%nSetup will update to version {{APP_VERSION}}.%n%nClick "Next" to continue updating, or "Cancel" to exit.
chineseSimplified.MemoUpgradeHeader=更新安装
english.MemoUpgradeHeader=Update Installation
chineseSimplified.MemoCurrentVersion=当前版本：%1
english.MemoCurrentVersion=Current version: %1
chineseSimplified.MemoNewVersion=目标版本：{{APP_VERSION}}
english.MemoNewVersion=Target version: {{APP_VERSION}}
chineseSimplified.MemoFreshInstallHeader=全新安装
english.MemoFreshInstallHeader=Fresh Installation
chineseSimplified.ConfirmDeleteUserData=是否同时删除用户配置与本地数据？
english.ConfirmDeleteUserData=Do you also want to remove user configuration and local application data?
chineseSimplified.TermsDialogInstruction=服务条款
english.TermsDialogInstruction=Terms of Service
chineseSimplified.TermsDialogBody=本软件只供人们用于Ai和用于学习,用于跨境电商和游戏加速,禁止用于传播违法资料禁止用于发表违法言论,请务必遵守国家法律,一旦发现有违法行为本软件有权利结束服务
english.TermsDialogBody=This software is strictly for AI, learning, cross-border e-commerce, and game acceleration. Distributing illegal materials or publishing unlawful statements is prohibited. Please comply with national laws; this software reserves the right to terminate service if any illegal activity is discovered.
chineseSimplified.TermsAcceptButton=接受
english.TermsAcceptButton=Accept
chineseSimplified.TermsDeclineButton=不接受
english.TermsDeclineButton=Decline

[Code]
const
  SHCNE_ASSOCCHANGED = $08000000;
  SHCNF_IDLIST = $0000;

type
  TStrictServiceStatus = record
    ServiceType, CurrentState, ControlsAccepted, Win32ExitCode,
      ServiceSpecificExitCode, CheckPoint, WaitHint: Cardinal;
  end;

var
  IsUpgrade: Boolean;
  PreviousVersion: String;
  StrictBrokerExe: String;

procedure SHChangeNotify(wEventId: Integer; uFlags: Integer; dwItem1: Integer; dwItem2: Integer); external 'SHChangeNotify@shell32.dll stdcall';

function ConvertStringSecurityDescriptorToSecurityDescriptor(Sddl: String; Revision: Cardinal; var Descriptor: LongWord; Size: LongWord): Boolean;
  external 'ConvertStringSecurityDescriptorToSecurityDescriptorW@advapi32.dll stdcall';
function SetKernelObjectSecurity(Handle: THandle; Information: Cardinal; Descriptor: LongWord): Boolean;
  external 'SetKernelObjectSecurity@advapi32.dll stdcall';
function CreateFileForSecurity(Name: String; Access, Share: Cardinal; Attributes: LongWord; Creation, Flags: Cardinal; Template: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';
function CloseSecurityHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function FreeSecurityDescriptor(Memory: LongWord): LongWord;
  external 'LocalFree@kernel32.dll stdcall';

function StrictFileAttributes(Name: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

procedure SecureStrictRecoveryDirectory;
var
  Path: String;
  Descriptor: LongWord;
  Handle: THandle;
begin
  Path := ExpandConstant('{commonappdata}\FreedomNet.StrictBroker');
  if not ForceDirectories(Path) then
    RaiseException('Cannot create Strict Broker recovery directory.');
  if (StrictFileAttributes(Path) and $400) <> 0 then
    RaiseException('Strict Broker recovery directory must not be a reparse point.');
  Descriptor := 0;
  if not ConvertStringSecurityDescriptorToSecurityDescriptor(
      'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)', 1, Descriptor, 0) then
    RaiseException('Cannot create Strict Broker recovery security descriptor.');
  try
    // Pin the directory itself (OPEN_REPARSE_POINT), never follow a replaced
    // junction. The Broker independently validates path, owner and exact ACL.
    Handle := CreateFileForSecurity(Path, $000C0000, 3, 0, 3, $02200000, 0);
    if Handle = THandle(-1) then
      RaiseException('Cannot secure Strict Broker recovery directory.');
    try
      if not SetKernelObjectSecurity(Handle, $80000005, Descriptor) then
        RaiseException('Cannot set Strict Broker recovery permissions.');
    finally
      CloseSecurityHandle(Handle);
    end;
  finally
    FreeSecurityDescriptor(Descriptor);
  end;
end;

// Use the trusted system executable and preserve launch failure separately
// from the service command exit status.
procedure StrictSc(Arguments: String; var Code: Integer);
begin
  if not Exec(ExpandConstant('{sys}\sc.exe'), Arguments, '', SW_HIDE,
      ewWaitUntilTerminated, Code) then
    RaiseException('Cannot run the Windows service controller.');
end;

function OpenStrictSCManager(Machine, Database: LongWord; Access: Cardinal): THandle;
  external 'OpenSCManagerW@advapi32.dll stdcall';
function OpenStrictService(Manager: THandle; Name: String; Access: Cardinal): THandle;
  external 'OpenServiceW@advapi32.dll stdcall';
function QueryStrictServiceStatus(Service: THandle; var Status: TStrictServiceStatus): Boolean;
  external 'QueryServiceStatus@advapi32.dll stdcall';
function CloseStrictServiceHandle(Handle: THandle): Boolean;
  external 'CloseServiceHandle@advapi32.dll stdcall';

procedure StopStrictService(Name: String);
var
  Code, Attempt: Integer;
  Manager, Service: THandle;
  Status: TStrictServiceStatus;
begin
  StrictSc('query "' + Name + '"', Code);
  if Code = 1060 then Exit;
  if Code <> 0 then RaiseException('Cannot query strict service: ' + Name);
  Manager := OpenStrictSCManager(0, 0, 1);
  if Manager = 0 then RaiseException('Cannot open Windows service manager.');
  try
    Service := OpenStrictService(Manager, Name, 4);
    if Service = 0 then RaiseException('Cannot open strict service: ' + Name);
    try
      if not QueryStrictServiceStatus(Service, Status) then
        RaiseException('Cannot inspect strict service: ' + Name);
      if Status.CurrentState = 1 then Exit;
      if Status.CurrentState <> 3 then
      begin
        StrictSc('stop "' + Name + '"', Code);
        if (Code <> 0) and (Code <> 1062) then
          RaiseException('Cannot stop strict service: ' + Name);
      end;
      for Attempt := 1 to 30 do
      begin
        if not QueryStrictServiceStatus(Service, Status) then
          RaiseException('Cannot inspect stopping strict service: ' + Name);
        if Status.CurrentState = 1 then Exit;
        Sleep(1000);
      end;
      RaiseException('Strict service did not stop within 30 seconds: ' + Name);
    finally
      CloseStrictServiceHandle(Service);
    end;
  finally
    CloseStrictServiceHandle(Manager);
  end;
end;

procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['FreedomNet.exe', 'FreedomNetAgent.exe', 'FreedomNetCore.exe', 'FreedomNetHelperService.exe'];

  // First try graceful shutdown
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Wait for processes to terminate gracefully
  Sleep(1000);

  // Force kill any remaining processes
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Give time for cleanup
  Sleep(1000);
end;

function IsAppInstalled(): Boolean;
var
  UninstallKey: String;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{{APP_ID}}}_is1';
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, UninstallKey) or 
            RegKeyExists(HKEY_CURRENT_USER, UninstallKey);
end;

function IsUpgradeInstallation(): Boolean;
begin
  Result := IsUpgrade;
end;

function GetInstalledVersion(): String;
var
  UninstallKey: String;
  Version: String;
begin
  Result := '';
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{{APP_ID}}}_is1';
  
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, UninstallKey, 'DisplayVersion', Version) then
    Result := Version
  else if RegQueryStringValue(HKEY_CURRENT_USER, UninstallKey, 'DisplayVersion', Version) then
    Result := Version;
end;

function IsManagedUpdate(): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ParamCount do
    if CompareText(ParamStr(Index), '/FCXUPDATE') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function FormatSetupText(const Msg: String): String;
begin
  Result := Msg;
  StringChange(Result, '%n', #13#10);
end;

procedure ShowTermsOfServiceDialog;
var
  ButtonLabels: TArrayOfString;
  Choice: Integer;
begin
  ButtonLabels := [
    CustomMessage('TermsAcceptButton'),
    CustomMessage('TermsDeclineButton')
  ];
  Choice := SuppressibleTaskDialogMsgBox(
    FormatSetupText(CustomMessage('TermsDialogInstruction')),
    FormatSetupText(CustomMessage('TermsDialogBody')),
    mbInformation,
    MB_YESNO,
    ButtonLabels,
    0,
    IDYES
  );
  if Choice = IDYES then
    Log('Terms of service dialog completed: accepted.')
  else
    Log('Terms of service dialog completed: declined (continuing installation).');
end;

function InitializeSetup(): Boolean;
begin
  if (not WizardSilent) and (not IsManagedUpdate()) then
    ShowTermsOfServiceDialog;

  // Check if app is already installed
  IsUpgrade := IsAppInstalled();
  if IsUpgrade then
    PreviousVersion := GetInstalledVersion();

  Result := True;
end;

procedure InitializeWizard();
begin
  if IsUpgrade then
  begin
    WizardForm.Caption := CustomMessage('UpgradeWindowCaption');
    if PreviousVersion <> '' then
      WizardForm.WelcomeLabel2.Caption :=
        FmtMessage(FormatSetupText(CustomMessage('UpgradeWelcomeWithPrev')), [PreviousVersion])
    else
      WizardForm.WelcomeLabel2.Caption :=
        FormatSetupText(CustomMessage('UpgradeWelcomeNoPrev'));
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if IsUpgrade then
  begin
    Result := CustomMessage('MemoUpgradeHeader') + NewLine;
    if PreviousVersion <> '' then
      Result := Result + FmtMessage(CustomMessage('MemoCurrentVersion'), [PreviousVersion]) + NewLine;
    Result := Result + CustomMessage('MemoNewVersion') + NewLine + NewLine;
  end
  else
    Result := CustomMessage('MemoFreshInstallHeader') + NewLine + NewLine;
    
  if MemoDirInfo <> '' then
    Result := Result + MemoDirInfo + NewLine + NewLine;
  if MemoGroupInfo <> '' then
    Result := Result + MemoGroupInfo + NewLine + NewLine;
  if MemoTasksInfo <> '' then
    Result := Result + MemoTasksInfo + NewLine;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ServiceExe: String;
begin
  if CurStep = ssInstall then
  begin
    // Stop services and running processes only after installation is confirmed
    // (after user clicks Install, or automatically in silent/managed runs)
    // right before [Files] extraction so cancelling the wizard never kills the
    // active proxy core or strands HKCU system proxy settings.
    Exec(ExpandConstant('{sys}\sc.exe'), 'stop "FreedomNetHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
{{STRICT_UPGRADE_STOP}}
    Sleep(1000);

    // The signed updater already requested a full graceful exit. Never turn a
    // failed graceful shutdown into a force-kill of this or another installation.
    // /NOCLOSEAPPLICATIONS leaves locked files to the installer's error handling.
    if not IsManagedUpdate() then KillProcesses;
  end;

  if CurStep = ssPostInstall then
  begin
    // Refresh icon cache/associations
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0);
    Sleep(500);
    // Configure the service during the already-elevated install. This prevents
    // a second UAC prompt when the app first enables the virtual adapter. Keep
    // upgrades idempotent: repair the binary path in place, create only when
    // the service does not exist.
    // The service and the SYSTEM-launched core live in a dedicated protected
    // Program Files directory. Never point SCM at a portable/user-writable
    // application directory.
    ServiceExe := ExpandConstant('{commonpf}\FreedomNet Service\FreedomNetHelperService.exe');
    Exec(ExpandConstant('{sys}\sc.exe'), 'config "FreedomNetHelperService" binPath= "\"' + ServiceExe + '\"" start= auto',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode <> 0 then
      Exec(ExpandConstant('{sys}\sc.exe'), 'create "FreedomNetHelperService" binPath= "\"' + ServiceExe + '\"" start= auto',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      Exec(ExpandConstant('{sys}\sc.exe'), 'sdset "FreedomNetHelperService" "D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      Exec(ExpandConstant('{sys}\sc.exe'), 'start "FreedomNetHelperService"', '', SW_HIDE, ewNoWait, ResultCode);
{{STRICT_SERVICE_BLOCK}}
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  case CurUninstallStep of
    usUninstall:
    begin
      // Stop service first
      Exec(ExpandConstant('{sys}\sc.exe'), 'stop "FreedomNetHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
      
      // Kill all processes
      KillProcesses;
      
      // Delete service
      Exec(ExpandConstant('{sys}\sc.exe'), 'delete "FreedomNetHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
{{STRICT_UNINSTALL_BLOCK}}
      Sleep(500);
      DelTree(ExpandConstant('{commonpf}\FreedomNet Service'), True, True, True);
    end;
    
    usPostUninstall:
    begin
      if DirExists(ExpandConstant('{userappdata}\FreedomNet\FreedomNet')) then
      begin
        if MsgBox(CustomMessage('ConfirmDeleteUserData'), mbConfirmation, MB_YESNO) = IDYES then
        begin
          DelTree(ExpandConstant('{userappdata}\FreedomNet\FreedomNet'), True, True, True);
        end;
      end;
    end;
  end;
end;
[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce; Check: not IsUpgradeInstallation
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{{SOURCE_DIR}}\\FreedomNetHelperService.exe"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\FreedomNetCore.exe"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\concrt140.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_1.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_2.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_atomic_wait.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_codecvt_ids.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140_1.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140_threads.dll"; DestDir: "{commonpf}\FreedomNet Service"; Flags: ignoreversion
{{STRICT_PACKAGE_FILES}}
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
