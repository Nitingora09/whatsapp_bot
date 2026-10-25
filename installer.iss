#define MyAppName "WhatsApp Outreach Booster Pro"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Nitin Gora"
#define MyAppURL "https://nitingora09.github.io/whatsapp_bot/"
#define MyAppExeName "whatsapp_bot.exe"

[Setup]
AppId={{5D9E2F1B-4A1C-4B9E-8E2A-1D3C5B7E9F0A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\WhatsAppOutreachBooster
DisableProgramGroupPage=yes
OutputDir=D:\StudioProjects\whatsapp_bot\docs\download
OutputBaseFilename=WhatsAppOutreachBooster-Windows-Setup
SetupIconFile=D:\StudioProjects\whatsapp_bot\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "D:\StudioProjects\whatsapp_bot\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "D:\StudioProjects\whatsapp_bot\whatsapp_server\*"; DestDir: "{app}\whatsapp_server"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "auth_session\*"
Source: "D:\StudioProjects\whatsapp_bot\start_bot.bat"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
