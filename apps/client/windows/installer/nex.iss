; Nex Windows installer (Inno Setup).
; AppVersion is injected by CI: iscc.exe ... /DAppVersion=X.Y.Z
; Executable name matches windows/CMakeLists.txt BINARY_NAME (nex_client).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppName=Nex
AppVersion={#AppVersion}
AppPublisher=Nex
DefaultDirName={autopf}\Nex
DefaultGroupName=Nex
OutputBaseFilename=Nex-Setup-{#AppVersion}
OutputDir=Output
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Path is relative to this .iss file (apps/client/windows/installer/).
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Nex"; Filename: "{app}\nex_client.exe"
Name: "{autodesktop}\Nex"; Filename: "{app}\nex_client.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nex_client.exe"; Description: "Launch Nex"; Flags: nowait postinstall skipifsilent
