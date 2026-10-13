#ifndef SourceDir
  #error SourceDir must point to a complete published Harbor folder.
#endif
#ifndef InstallerOutput
  #error InstallerOutput is required.
#endif
#ifndef Variant
  #define Variant "self-contained"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{F0A496B2-19E8-4B46-931A-E6FECF194027}
AppName=Harbor
AppVersion={#AppVersion}
AppPublisher=Mark4551124015
AppPublisherURL=https://github.com/Mark4551124015/Harbor_ssh
AppSupportURL=https://github.com/Mark4551124015/Harbor_ssh/issues
DefaultDirName={localappdata}\Programs\Harbor
DefaultGroupName=Harbor
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#InstallerOutput}
OutputBaseFilename=Harbor-Windows-x64-{#Variant}-Setup
SetupIconFile={#SourceDir}\Assets\harbor.ico
UninstallDisplayIcon={app}\app\Harbor.Windows.exe
LicenseFile={#SourceDir}\LICENSE
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no
Uninstallable=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[InstallDelete]
; This subfolder contains only installer-managed application files. Cleaning it
; lets either variant replace the other without leaving an old .NET runtime.
Type: filesandordirs; Name: "{app}\app"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Harbor"; Filename: "{app}\app\Harbor.Windows.exe"; WorkingDir: "{app}\app"
Name: "{autodesktop}\Harbor"; Filename: "{app}\app\Harbor.Windows.exe"; WorkingDir: "{app}\app"; Tasks: desktopicon

[Run]
Filename: "{app}\app\Harbor.Windows.exe"; Description: "Launch Harbor"; Flags: nowait postinstall skipifsilent

[Code]
#if Variant == "framework-dependent"
function RuntimeDirectoryExists(Root: String): Boolean;
var
  Entry: TFindRec;
begin
  Result := False;
  if Root = '' then Exit;
  if FindFirst(AddBackslash(Root) + 'shared\Microsoft.NETCore.App\10.0.*', Entry) then
  begin
    try
      repeat
        if ((Entry.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
           (Pos('-', Entry.Name) = 0) and
           FileExists(AddBackslash(Root) + 'shared\Microsoft.NETCore.App\' + Entry.Name + '\coreclr.dll') then
        begin
          Result := True;
          Exit;
        end;
      until not FindNext(Entry);
    finally
      FindClose(Entry);
    end;
  end;
end;

function DotNet10Installed: Boolean;
var
  Versions: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if RegGetValueNames(HKLM64, 'SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App', Versions) then
    for I := 0 to GetArrayLength(Versions) - 1 do
      if (Copy(Versions[I], 1, 5) = '10.0.') and (Pos('-', Versions[I]) = 0) then
      begin
        Result := True;
        Exit;
      end;
  Result := RuntimeDirectoryExists(GetEnv('DOTNET_ROOT_X64')) or
            RuntimeDirectoryExists(GetEnv('DOTNET_ROOT')) or
            RuntimeDirectoryExists(ExpandConstant('{commonpf64}\dotnet'));
end;

function InitializeSetup: Boolean;
var
  ErrorCode: Integer;
begin
  Result := DotNet10Installed;
  if not Result then
  begin
    Log('The .NET 10 x64 runtime is required for this Harbor installer.');
    if not WizardSilent then
      if MsgBox('This version of Harbor requires the .NET 10 x64 runtime.' + #13#10 +
        'Install the runtime first, or use the self-contained Harbor installer.' + #13#10#13#10 +
        'Open the Microsoft .NET download page now?', mbConfirmation, MB_YESNO) = IDYES then
        ShellExec('open', 'https://dotnet.microsoft.com/en-us/download/dotnet/10.0', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;
#endif
