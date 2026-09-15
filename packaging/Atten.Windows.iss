; Atten's traditional Windows installer. The compiled app is intentionally
; unpackaged and self-contained: no Python, .NET runtime, Windows App SDK, or
; model download is required on the user's computer.

#ifndef SourceRoot
  #error SourceRoot must point to the staged publish directory.
#endif
#ifndef MyAppVersion
  #error MyAppVersion must be supplied by the release build.
#endif
#ifndef MyOutputBaseName
  #define MyOutputBaseName "Atten-Windows-x64-Setup"
#endif

#define MyAppName "Atten"
#define MyAppExeName "Atten.Windows.exe"

[Setup]
AppId={{D8D1E84C-3A6A-44E7-9C71-13E8EB0F8C65}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Atten
DefaultDirName={autopf}\Atten
DefaultGroupName=Atten
DisableProgramGroupPage=yes
LicenseFile={#SourceRoot}\Licenses\GPL-3.0-or-later.txt
OutputBaseFilename={#MyOutputBaseName}
OutputDir=.
; The packaged Python/Torch runtime is large. LZMA ultra compression exhausts
; the address space of the standard Inno compiler on hosted Windows runners.
; Deflate has a tiny memory footprint, does not expand already-compressed files,
; and keeps the installer reproducible and buildable on the release runner.
Compression=zip/9
SolidCompression=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
PrivilegesRequired=admin
UninstallDisplayName=Atten
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceRoot}\*"; DestDir: "{app}"; Excludes: "Prerequisites\*,install-validation-error.txt"; Flags: ignoreversion recursesubdirs createallsubdirs
; The Windows App SDK's native components need the Microsoft Visual C++
; runtime. It is not present on every clean Windows installation, and without
; it Atten's window never appears. Extracted only when it has to be installed.
Source: "{#SourceRoot}\Prerequisites\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsVCRedist

[Icons]
Name: "{autoprograms}\Atten"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Atten"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing the Microsoft Visual C++ runtime..."; Check: NeedsVCRedist
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Atten"; Flags: nowait postinstall skipifsilent

[Code]
const
  MinimumInstalledRamGiB = 8;
  RecommendedAvailableRamGiB = 4;
  RequiredDiskMiB = 4096;

type
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys: Int64;
    ullAvailPhys: Int64;
    ullTotalPageFile: Int64;
    ullAvailPageFile: Int64;
    ullTotalVirtual: Int64;
    ullAvailVirtual: Int64;
    ullAvailExtendedVirtual: Int64;
  end;

function GlobalMemoryStatusEx(var MemoryStatus: TMemoryStatusEx): Boolean;
  external 'GlobalMemoryStatusEx@kernel32.dll stdcall';

function BytesToGiB(const Bytes: Int64): Integer;
begin
  Result := Bytes div 1073741824;
end;

// Atten ships the Visual C++ runtime because the app cannot start without it.
// Installing it is skipped when Windows already has a new enough copy.
function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
  Build: Cardinal;
begin
  Result := True;
  if not RegQueryDWordValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
    exit;
  if Installed <> 1 then
    exit;
  if not RegQueryDWordValue(HKEY_LOCAL_MACHINE,
       'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Bld', Build) then
    exit;
  Result := Build < 32530;
end;

procedure InitializeWizard;
var
  RequirementsPage: TOutputMsgWizardPage;
begin
  RequirementsPage := CreateOutputMsgPage(
    wpWelcome,
    'System requirements',
    'Before installing Atten',
    'System requirements' + #13#10 +
    '- 64-bit Windows 10 version 1809 or newer, or Windows 11' + #13#10 +
    '- 8 GB RAM (4 GB available is recommended while generating speech)' + #13#10 +
    '- 4 GB free disk space for the app, offline model, and voice files' + #13#10 +
    '- An x64-compatible processor' + #13#10 + #13#10 +
    'Atten includes its speech engine, model, Python runtime, .NET runtime, Windows App SDK, and the Microsoft Visual C++ runtime it needs. Internet access is not needed after this installer has been downloaded.');
end;

function InitializeSetup(): Boolean;
var
  MemoryStatus: TMemoryStatusEx;
begin
  Result := False;
  if not IsWin64 then begin
    MsgBox('Atten requires 64-bit Windows on an x64-compatible processor.', mbCriticalError, MB_OK);
    exit;
  end;

  MemoryStatus.dwLength := SizeOf(MemoryStatus);
  if GlobalMemoryStatusEx(MemoryStatus) and
     (MemoryStatus.ullTotalPhys < Int64(MinimumInstalledRamGiB) * 1073741824) then begin
    MsgBox(
      'Atten requires at least ' + IntToStr(MinimumInstalledRamGiB) +
      ' GB of installed RAM. This computer reports ' +
      IntToStr(BytesToGiB(MemoryStatus.ullTotalPhys)) + ' GB.',
      mbCriticalError,
      MB_OK);
    exit;
  end;

  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  MemoryStatus: TMemoryStatusEx;
  FreeSpace, TotalSpace: Int64;
  InstallDrive: String;
begin
  Result := True;
  if CurPageID <> wpSelectDir then
    exit;

  InstallDrive := ExtractFileDrive(WizardDirValue);
  if InstallDrive = '' then
    InstallDrive := WizardDirValue;
  InstallDrive := AddBackslash(InstallDrive);

  if not GetSpaceOnDisk64(InstallDrive, FreeSpace, TotalSpace) or
     (FreeSpace < Int64(RequiredDiskMiB) * 1024 * 1024) then begin
    MsgBox(
      'Atten needs at least ' + IntToStr(RequiredDiskMiB div 1024) +
      ' GB of free disk space in the selected installation location.',
      mbCriticalError,
      MB_OK);
    Result := False;
    exit;
  end;

  MemoryStatus.dwLength := SizeOf(MemoryStatus);
  if GlobalMemoryStatusEx(MemoryStatus) and
     (MemoryStatus.ullAvailPhys < Int64(RecommendedAvailableRamGiB) * 1073741824) then begin
    Result := MsgBox(
      'Atten works best with at least ' + IntToStr(RecommendedAvailableRamGiB) +
      ' GB of RAM currently available for model loading. Close memory-intensive applications before generating speech. Continue anyway?',
      mbConfirmation,
      MB_YESNO) = IDYES;
  end;
end;
