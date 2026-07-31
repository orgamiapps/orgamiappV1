#define MyAppName "Attendus Admin"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Attendus"
#define MyAppExeName "attendus_admin.exe"
#ifndef BuildRoot
  #define BuildRoot "..\apps\attendus_admin\build\windows\x64\runner\Release"
#endif
#ifndef OutputRoot
  #define OutputRoot "..\dist"
#endif

[Setup]
AppId={{A37D6A9D-2A9B-4B41-A8CD-57432B7A4EF0}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Attendus Admin
DefaultGroupName=Attendus Admin
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
OutputDir={#OutputRoot}
OutputBaseFilename=AttendusAdmin-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\apps\attendus_admin\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=no
CloseApplications=yes
RestartApplications=no
MinVersion=10.0.22000

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildRoot}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Attendus Admin"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Attendus Admin"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Attendus Admin"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  Result := IsWin64;
  if not Result then MsgBox('Attendus Admin requires 64-bit Windows 11.', mbError, MB_OK);
end;
