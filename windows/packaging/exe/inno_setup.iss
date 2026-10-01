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
; Update mode settings
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes

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
  Path := ExpandConstant('{commonappdata}\FlClashX.StrictBroker');
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
  Processes := ['FlClashX.exe', 'FlClashAgent.exe', 'FlClashCore.exe', 'FlClashHelperService.exe', 'FlClashStrictBroker.exe'];

  // First try graceful shutdown
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Wait for processes to terminate gracefully
  Sleep(1000);

  // Force kill any remaining processes
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Give time for cleanup
  Sleep(1000);
end;

function IsAppInstalled(): Boolean;
var
  UninstallKey: String;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';
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
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';
  
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

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Check if app is already installed
  IsUpgrade := IsAppInstalled();
  if IsUpgrade then
    PreviousVersion := GetInstalledVersion();
  
  // Stop service if running
  Exec('sc.exe', 'stop "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
{{STRICT_UPGRADE_STOP}}
  Sleep(1000);
  
  // The signed updater already requested a full graceful exit. Never turn a
  // failed graceful shutdown into a force-kill of this or another installation.
  // /NOCLOSEAPPLICATIONS leaves locked files to the installer's error handling.
  if not IsManagedUpdate() then KillProcesses;
  
  Result := True;
end;

procedure InitializeWizard();
begin
  if IsUpgrade then
  begin
    WizardForm.Caption := '{{DISPLAY_NAME}} - Обновление';
    if PreviousVersion <> '' then
      WizardForm.WelcomeLabel2.Caption := 
        'Обнаружена установленная версия ' + PreviousVersion + '.' + #13#10 + #13#10 +
        'Программа установит версию {{APP_VERSION}}.' + #13#10 + #13#10 +
        'Нажмите «Далее», чтобы продолжить обновление, или «Отмена», чтобы выйти.'
    else
      WizardForm.WelcomeLabel2.Caption := 
        'Обнаружена установленная версия программы.' + #13#10 + #13#10 +
        'Программа установит версию {{APP_VERSION}}.' + #13#10 + #13#10 +
        'Нажмите «Далее», чтобы продолжить обновление, или «Отмена», чтобы выйти.';
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if IsUpgrade then
  begin
    Result := 'Обновление' + NewLine;
    if PreviousVersion <> '' then
      Result := Result + 'Текущая версия: ' + PreviousVersion + NewLine;
    Result := Result + 'Новая версия: {{APP_VERSION}}' + NewLine + NewLine;
  end
  else
    Result := 'Новая установка' + NewLine + NewLine;
    
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
    ServiceExe := ExpandConstant('{commonpf}\FlClashX Service\FlClashHelperService.exe');
    Exec('sc.exe', 'config "FlClashHelperService" binPath= "' + ServiceExe + '" start= auto',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode <> 0 then
      Exec('sc.exe', 'create "FlClashHelperService" binPath= "' + ServiceExe + '" start= auto',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      Exec('sc.exe', 'sdset "FlClashHelperService" "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCLCSWRPWPDTLOCRRC;;;BA)(A;;CCLCSWRPWPLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      Exec('sc.exe', 'start "FlClashHelperService"', '', SW_HIDE, ewNoWait, ResultCode);
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
      Exec('sc.exe', 'stop "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
      
      // Kill all processes
      KillProcesses;
      
      // Delete service
      Exec('sc.exe', 'delete "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
{{STRICT_UNINSTALL_BLOCK}}
      Sleep(500);
      DelTree(ExpandConstant('{commonpf}\FlClashX Service'), True, True, True);
    end;
    
    usPostUninstall:
    begin
      if DirExists(ExpandConstant('{userappdata}\com.follow\clashx')) then
      begin
        if MsgBox('Удалить пользовательские данные программы?', mbConfirmation, MB_YESNO) = IDYES then
        begin
          DelTree(ExpandConstant('{userappdata}\com.follow\clashx'), True, True, True);
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
Source: "{{SOURCE_DIR}}\\FlClashHelperService.exe"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\FlClashCore.exe"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\concrt140.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_1.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_2.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_atomic_wait.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\msvcp140_codecvt_ids.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140_1.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\vcruntime140_threads.dll"; DestDir: "{commonpf}\FlClashX Service"; Flags: ignoreversion
{{STRICT_PACKAGE_FILES}}
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
