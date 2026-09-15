param(
    [ValidateSet("cpu", "cuda")]
    [string] $BackendFlavor = "cpu",
    [string] $Configuration = "Release",
    [string] $Runtime = "win-x64",
    [string] $ModelSource = "",
    [string] $Output = ".build/windows-artifacts",
    [string] $Version = ""
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildRoot = Join-Path $Root ".build/windows-package"
$Dist = Join-Path $BuildRoot "pyinstaller-dist"
$ModelDestination = Join-Path $BuildRoot "Models/Kokoro-82M"
$AppProject = Join-Path $Root "apps/windows/Atten.Windows/Atten.Windows.csproj"
$Spec = Join-Path $Root "packaging/atten-backend-windows-$BackendFlavor.spec"
$Publish = Join-Path $BuildRoot "publish"
$ArtifactRoot = Join-Path $Root $Output
$InstallerScript = Join-Path $Root "packaging/Atten.Windows.iss"

Remove-Item -Recurse -Force $BuildRoot, $ArtifactRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $BuildRoot, $ArtifactRoot | Out-Null

Push-Location $Root
try {
    uv sync --frozen --group release --no-editable
    uv run --frozen --group release pyinstaller `
        --clean `
        --noconfirm `
        --distpath $Dist `
        --workpath (Join-Path $BuildRoot "pyinstaller-work") `
        $Spec

    $prepareArgs = @($ModelDestination)
    if ($ModelSource -ne "") {
        $prepareArgs += @("--source", $ModelSource)
    }
    uv run --frozen python (Join-Path $Root "scripts/prepare-model") @prepareArgs

    # WinUI's PRI generation tasks are supplied by the Visual Studio Windows
    # App SDK workload. Prefer its MSBuild when available; the fallback keeps
    # the script usable on a dotnet-only development machine.
    $publishDir = "$Publish\"
    if (Get-Command msbuild -ErrorAction SilentlyContinue) {
        msbuild $AppProject `
            /restore `
            /t:Publish `
            /p:Configuration=$Configuration `
            /p:Platform=x64 `
            /p:RuntimeIdentifier=$Runtime `
            /p:SelfContained=true `
            /p:PublishDir=$publishDir
    }
    else {
        dotnet publish $AppProject `
            -c $Configuration `
            -r $Runtime `
            -o $Publish `
            /p:SelfContained=true
    }

    New-Item -ItemType Directory -Force (Join-Path $Publish "Backend") | Out-Null
    Copy-Item -Recurse (Join-Path $Dist "atten-backend") (Join-Path $Publish "Backend/atten-backend")
    New-Item -ItemType Directory -Force (Join-Path $Publish "Models") | Out-Null
    Copy-Item -Recurse $ModelDestination (Join-Path $Publish "Models/Kokoro-82M")
    Copy-Item (Join-Path $Root "resources/voices.json") (Join-Path $Publish "resources/voices.json") -Force

    $Licenses = Join-Path $Publish "Licenses"
    New-Item -ItemType Directory -Force $Licenses | Out-Null
    Copy-Item (Join-Path $Root "LICENSE") (Join-Path $Licenses "GPL-3.0-or-later.txt")
    Copy-Item (Join-Path $Root "legal/THIRD_PARTY_NOTICES.md") $Licenses
    Copy-Item (Join-Path $Root "legal/MODEL_ATTRIBUTION.md") $Licenses
    Copy-Item (Join-Path $Root "legal/CORRESPONDING_SOURCE.md") $Licenses

    # Exercise the real PyInstaller executable with the staged model before it
    # is handed to the installer. This catches missing DLLs and model files on
    # the Windows build machine rather than after a user installs the app.
    $PreviousModelRoot = $env:ATTEN_MODEL_ROOT
    $PreviousOffline = $env:HF_HUB_OFFLINE
    try {
        $env:ATTEN_MODEL_ROOT = Join-Path $Publish "Models/Kokoro-82M"
        $env:HF_HUB_OFFLINE = "1"
        & (Join-Path $Publish "Backend/atten-backend/atten-backend.exe") --backend-info --device cpu --json
        if ($LASTEXITCODE -ne 0) {
            throw "The packaged Windows backend failed its startup check (exit code $LASTEXITCODE)."
        }
    }
    finally {
        $env:ATTEN_MODEL_ROOT = $PreviousModelRoot
        $env:HF_HUB_OFFLINE = $PreviousOffline
    }

    # Atten.Windows.exe is a windowed executable, so PowerShell does not wait
    # for it and $LASTEXITCODE says nothing about how it finished. Start-Process
    # -Wait is what makes these checks real rather than decorative.
    $AppExe = Join-Path $Publish "Atten.Windows.exe"
    $ValidationError = Join-Path $Publish "install-validation-error.txt"
    $LaunchLog = Join-Path $env:LOCALAPPDATA "Atten/logs/startup.log"

    function Invoke-AppCheck([string] $Mode, [string] $Description) {
        Remove-Item $ValidationError, $LaunchLog -Force -ErrorAction SilentlyContinue
        $Probe = Start-Process -FilePath $AppExe -ArgumentList $Mode -PassThru
        if (-not $Probe.WaitForExit(300000)) {
            $Probe.Kill($true)
            throw "$Description The app never finished its $Mode check."
        }
        if ($Probe.ExitCode -ne 0) {
            $Detail = if (Test-Path $ValidationError) { Get-Content $ValidationError -Raw }
                      elseif (Test-Path $LaunchLog) { Get-Content $LaunchLog -Raw }
                      else { "The app exited with $($Probe.ExitCode) before it could write a diagnostic." }
            throw "$Description $Detail"
        }
    }

    # Proves the self-contained Windows App SDK deployment and the app's
    # resource, backend, and model discovery all work from the staged build.
    Invoke-AppCheck "--validate-install" "The published Windows app failed its installation check:"

    # Proves the app can actually build and show its main window. Without this
    # a crash during window creation ships silently: the user launches Atten
    # and nothing at all appears.
    Invoke-AppCheck "--validate-launch" "The published Windows app failed its launch check:"

    # Diagnostics written by the checks above must not reach the installer.
    Remove-Item $ValidationError -Force -ErrorAction SilentlyContinue

    # The Windows App SDK's native components need the Microsoft Visual C++
    # runtime, which a clean Windows machine does not necessarily have. Ship
    # the redistributable so the installed app still starts entirely offline.
    $Prerequisites = Join-Path $Publish "Prerequisites"
    New-Item -ItemType Directory -Force $Prerequisites | Out-Null
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
        -OutFile (Join-Path $Prerequisites "VC_redist.x64.exe") -UseBasicParsing

    if ([string]::IsNullOrWhiteSpace($Version)) {
        [xml] $ProjectXml = Get-Content $AppProject
        $Version = $ProjectXml.Project.PropertyGroup.Version | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "Pass -Version or define a <Version> in $AppProject before building an installer."
    }

    $IsccCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6/ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6/ISCC.exe")
    )
    $Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($null -eq $Iscc) {
        throw "Inno Setup 6 was not found. Install it from https://jrsoftware.org/isinfo.php before building a Windows installer."
    }

    $AssetBaseName = if ($BackendFlavor -eq "cuda") { "Atten-Windows-x64-CUDA-Setup" } else { "Atten-Windows-x64-Setup" }
    & $Iscc "/DSourceRoot=$Publish" "/DMyAppVersion=$Version" "/DMyOutputBaseName=$AssetBaseName" "/O$ArtifactRoot" $InstallerScript
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed to build the Windows installer (exit code $LASTEXITCODE)."
    }

    $AssetName = "$AssetBaseName.exe"
    $Installer = Join-Path $ArtifactRoot $AssetName
    if (-not (Test-Path $Installer)) {
        throw "Inno Setup did not produce the expected installer: $Installer"
    }
    $Checksum = (Get-FileHash $Installer -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -Path (Join-Path $ArtifactRoot "SHA256SUMS-Windows.txt") -Value "$Checksum *$AssetName" -NoNewline
    Write-Host "Built $Installer"
}
finally {
    Pop-Location
}
