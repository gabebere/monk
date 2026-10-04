#define MyAppName "Monk"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Monk"
#define MyAppExeName "Monk.exe"

[Setup]
AppId={{80A8B5A4-1C36-46AE-BD7F-5B9E81335CE4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Monk
DefaultGroupName=Monk
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=MonkSetup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=110
WizardResizable=no
SetupMutex=Monk.Windows.Setup
AppMutex=Monk.Windows.SingleInstance
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\src\Monk.App\Assets\monk.ico
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Monk for Windows installer
VersionInfoProductName={#MyAppName}
WizardSmallImageFile=..\..\Monk\AppIcon.icon\Assets\monklogotransparent.png

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\artifacts\app\*"; DestDir: "{app}"; Excludes: "browser-host\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\artifacts\app\browser-host\*"; DestDir: "{app}\browser-host"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\browser-extension\*"; DestDir: "{app}\browser-extension"; Excludes: "native-host.template.json,install-native-host.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Monk"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\Monk"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "browsersetup"; Description: "Open the one-minute browser setup guide"; GroupDescription: "Website blocking:"; Flags: checkedonce

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Monk"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.gbr.monk"; ValueType: string; ValueName: ""; ValueData: "{localappdata}\Monk\native-host.json"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\com.gbr.monk"; ValueType: string; ValueName: ""; ValueData: "{localappdata}\Monk\native-host.json"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.gbr.monk"; ValueType: string; ValueName: ""; ValueData: "{localappdata}\Monk\native-host.json"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Chromium\NativeMessagingHosts\com.gbr.monk"; ValueType: string; ValueName: ""; ValueData: "{localappdata}\Monk\native-host.json"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Monk"; Flags: nowait postinstall skipifsilent
Filename: "{app}\browser-extension\setup.html"; Description: "Open the browser setup guide"; Flags: shellexec postinstall skipifsilent unchecked; Tasks: browsersetup

[UninstallDelete]
Type: files; Name: "{localappdata}\Monk\native-host.json"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath: String;
  HostPath: String;
  Contents: String;
begin
  if CurStep <> ssPostInstall then
    exit;

  ManifestPath := ExpandConstant('{localappdata}\Monk\native-host.json');
  HostPath := ExpandConstant('{app}\browser-host\Monk.BrowserHost.exe');
  StringChangeEx(HostPath, '\', '\\', True);
  Contents := '{' + #13#10 +
    '  "name": "com.gbr.monk",' + #13#10 +
    '  "description": "Monk local website policy host",' + #13#10 +
    '  "path": "' + HostPath + '",' + #13#10 +
    '  "type": "stdio",' + #13#10 +
    '  "allowed_origins": ["chrome-extension://gnojnlbmnlklcolioococcllgipfpnhi/"]' + #13#10 +
    '}' + #13#10;
  ForceDirectories(ExtractFileDir(ManifestPath));
  SaveStringToFile(ManifestPath, Contents, False);
end;
