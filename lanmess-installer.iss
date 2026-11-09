[Setup]
AppName=LANMess
AppVersion=1.1.10
AppPublisher=LANMess
DefaultDirName={localappdata}\LANMess
DefaultGroupName=LANMess
OutputBaseFilename=LANMess-Setup
Compression=lzma2
SolidCompression=yes
; Keep lowest if you want per‑user installs, but then you must handle Python installation without admin rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=lanmess.ico
UninstallDisplayIcon={app}\lanmess.ico

[Files]
Source: "lanmess-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "lanmess.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\LANMess"; Filename: "{app}\LANMess.bat"; IconFilename: "{app}\lanmess.ico"
Name: "{group}\LANMess"; Filename: "{app}\LANMess.bat"; IconFilename: "{app}\lanmess.ico"

[Run]
; Do NOT use runhidden – you want to see errors if the script fails.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\lanmess-install.ps1"" -InstallDir ""{app}"""; \
  Flags: waituntilterminated

; Only launch the batch file if it was actually created.
Filename: "{app}\LANMess.bat"; Description: "Launch LANMess"; \
  Flags: postinstall nowait skipifsilent; Check: FileExists(ExpandConstant('{app}\LANMess.bat'))    