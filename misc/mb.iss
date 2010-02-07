; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{E5D3BD22-CD4C-4823-A383-3971BCE0052C}
AppName=Monster Browser
AppVerName=Monster Browser 0.6a
AppPublisherURL=http://sites.google.com/site/monsterbrowser/
AppSupportURL=http://sites.google.com/site/monsterbrowser/
AppUpdatesURL=http://sites.google.com/site/monsterbrowser/
DefaultDirName={pf}\Monster Browser
DefaultGroupName=Monster Browser
AllowNoIcons=yes
SourceDir=..
OutputDir=misc
OutputBaseFilename=Monster Browser 0.6a Setup
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

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
Name: "{group}\{cm:ProgramOnTheWeb,Monster Browser}"; Filename: "http://sites.google.com/site/monsterbrowser/"
Name: "{group}\{cm:UninstallProgram,Monster Browser}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Monster Browser"; Filename: "{app}\MonsterBrowser.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Monster Browser"; Filename: "{app}\MonsterBrowser.exe"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\MonsterBrowser.exe"; Description: "{cm:LaunchProgram,Monster Browser}"; Flags: nowait postinstall skipifsilent

[Code]
const
  SettingsFile = 'settings.ini';
  GamesFile = 'mods.ini';

{ Move multiple files, and return the number of files successfully moved.
  SourceFiles is of the form "C:\path\sourcedir\*.xyz".
  TargetDir is of the form "C:\path\targetdir".
}
function MoveFiles(SourceFiles, TargetDir: String) : Integer;
var
  FindRec: TFindRec;
  SourceDir, SourceFile: String;
begin
  Result := 0;
  if FindFirst(SourceFiles, FindRec) then begin
    SourceDir := ExtractFilePath(SourceFiles);
    TargetDir := AddBackslash(TargetDir);
    repeat
      SourceFile := SourceDir + FindRec.Name;
      if FileCopy(SourceFile, TargetDir + FindRec.Name, True) = True then begin
        Result := Result + 1;
        DeleteFile(SourceFile);
      end;
    until not FindNext(FindRec);
    FindClose(FindRec);
    end;
end;


{ Move Monster Browser's INI files.  Returns the number of files moved. }
function MoveSettings(SourceDir, TargetDir: String) : Integer;
begin
  Result := 0;
  SourceDir := AddBackslash(SourceDir);
  TargetDir := AddBackslash(TargetDir);
  { RenameFile gives some of the files the wrong permissions,
    so using FileCopy and DeleteFile instead. }
  if FileCopy(SourceDir + SettingsFile, TargetDir + SettingsFile, True) = True then begin
    Result := Result + 1;
    DeleteFile(SourceDir + SettingsFile);
  end;
  if FileCopy(SourceDir + GamesFile, TargetDir + GamesFile, True) = True then begin
    Result := Result + 1;
    DeleteFile(SourceDir + GamesFile);
  end;
end;


{ Move settings and data, delete the log file. Returns true on success. }
function MoveAllAndCleanUp(SourceDir, TargetDir: String) : Boolean;
var
  MovedCount : Integer;
begin
  Result := False;
  MovedCount := 0;
  MovedCount := MovedCount + MoveSettings(SourceDir, TargetDir);
  MovedCount := MovedCount + MoveFiles(SourceDir + '\*.xml', TargetDir);
  DeleteFile(SourceDir + '\LOG.TXT');
  if MovedCount > 0 then
    Result := True;
end;

{ Find Monster Browser's location in the virtual store. }
function FindVirtualStoreDir: String;
var
  Base, Rest, AppDir : String;
begin
  Base := ExpandConstant('{localappdata}\VirtualStore');
  if DirExists(Base) then begin
    AppDir := ExpandConstant('{app}');
    { Remove the drive name }
    Rest := Copy(Appdir, 3, Length(AppDir));
    Result := Base + Rest;
  end
end;


procedure CurStepChanged(CurStep: TSetupStep);
var
  AppDir, SettingsDir, VirtualDir: String;
  IsPortable: Boolean;
  Success : Boolean;
begin
  if CurStep = ssPostInstall then begin
    IsPortable := FileExists(ExpandConstant('{app}\portable.txt'));
    if not IsPortable then begin
      Success := False;
      SettingsDir := ExpandConstant('{userappdata}\Monster Browser');
      AppDir := ExpandConstant('{app}');
      CreateDir(SettingsDir)
      
      { Move files from the app dir. If no files were found in the app dir, try
        the virtual store instead. }
      if DirExists(SettingsDir) = True then begin
        if MoveAllAndCleanUp(AppDir, SettingsDir) then begin
          Success := True;
        end
        else begin
          VirtualDir := FindVirtualStoreDir();
          if DirExists(VirtualDir) then begin
              Success := MoveAllAndCleanUp(VirtualDir, SettingsDir);
              if Success then
                RemoveDir(VirtualDir);
          end;
        end;
      end;

      if Success then
        SuppressibleMsgBox('Your Monster Browser settings and data files have been moved to ''' +
                            SettingsDir + '''.', mbInformation, MB_OK, IDOK);
    end;
  end;
end;

