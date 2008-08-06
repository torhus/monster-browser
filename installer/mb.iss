; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{E5D3BD22-CD4C-4823-A383-3971BCE0052C}
AppName=Monster Browser
AppVerName=Monster Browser 0.4b
AppPublisherURL=http://monsterbrowser.googlepages.com/
AppSupportURL=http://monsterbrowser.googlepages.com/
AppUpdatesURL=http://monsterbrowser.googlepages.com/
DefaultDirName={pf}\MonsterBrowser
DefaultGroupName=Monster Browser
AllowNoIcons=yes
SourceDir=..
OutputDir=installer
OutputBaseFilename=Monster Browser 0.4b Setup
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "MonsterBrowser.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.TXT"; DestDir: "{app}"; Flags: ignoreversion
Source: "CHANGELOG.TXT"; DestDir: "{app}"; Flags: ignoreversion
Source: "GeoIP.dat"; DestDir: "{app}"; Flags: ignoreversion
Source: "GeoIP.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "qstat.exe"; DestDir: "{app}"; Flags: ignoreversion
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\Monster Browser"; Filename: "{app}\MonsterBrowser.exe";
Name: "{group}\{cm:ProgramOnTheWeb,Monster Browser}"; Filename: "http://monsterbrowser.googlepages.com/"
Name: "{group}\{cm:UninstallProgram,Monster Browser}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Monster Browser"; Filename: "{app}\MonsterBrowser.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Monster Browser"; Filename: "{app}\MonsterBrowser.exe"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\MonsterBrowser.exe"; Description: "{cm:LaunchProgram,Monster Browser}"; Flags: nowait postinstall skipifsilent

