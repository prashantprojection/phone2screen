; Phone2Screen Inno Setup 6 Installer Script
#ifndef AppVersion
  #define AppVersion "0.4.0"
#endif

[Setup]
AppId={{A3C91E4B-7D24-4B8F-9A12-6E4C8B1F09D2}
AppName=Phone2Screen
AppVersion={#AppVersion}
AppVerName=Phone2Screen v{#AppVersion}
AppPublisher=Phone2Screen
VersionInfoVersion={#AppVersion}.0
DefaultDirName={localappdata}\Programs\Phone2Screen
DefaultGroupName=Phone2Screen
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\phone2screen.exe
OutputDir=..\..\dist
OutputBaseFilename=Phone2Screen-Setup-v{#AppVersion}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "registervcam"; Description: "Register Phone2Screen Camera virtual webcam (DirectShow, per-user)"; GroupDescription: "Studio Integrations:"
Name: "firewallrule"; Description: "Allow LAN Discovery & Web Companion in Windows Firewall (UDP 41234, TCP 8080-8083, 8443)"; GroupDescription: "Studio Integrations:"; Check: IsAdminInstallMode

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.pdb,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\scripts\setup_windows_webcam.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Phone2Screen"; Filename: "{app}\phone2screen.exe"
Name: "{group}\{cm:UninstallProgram,Phone2Screen}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Phone2Screen"; Filename: "{app}\phone2screen.exe"; Tasks: desktopicon

[Run]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\p2s_vcam.dll"""; Flags: waituntilterminated runhidden; StatusMsg: "Registering Phone2Screen Camera..."; Tasks: registervcam
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Remove-NetFirewallRule -DisplayName 'Phone2Screen LAN Discovery UDP 41234','Phone2Screen Signaling TCP 8080-8443' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'Phone2Screen LAN Discovery UDP 41234' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 41234 -Profile Private,Domain | Out-Null; New-NetFirewallRule -DisplayName 'Phone2Screen Signaling TCP 8080-8443' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080-8083,8443 -Profile Private,Domain | Out-Null"""; Flags: waituntilterminated runhidden; StatusMsg: "Adding Windows Firewall rules..."; Tasks: firewallrule; Check: IsAdminInstallMode
Filename: "{app}\phone2screen.exe"; Description: "{cm:LaunchProgram,Phone2Screen}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\regsvr32.exe"; Parameters: "/u /s ""{app}\p2s_vcam.dll"""; Flags: waituntilterminated runhidden; RunOnceId: "UnregisterP2SVCam"
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup_windows_webcam.ps1"" -Action Unregister -DllPath ""{app}\p2s_vcam.dll"""; Flags: waituntilterminated runhidden; RunOnceId: "CleanupP2SVCamAndFirewall"
