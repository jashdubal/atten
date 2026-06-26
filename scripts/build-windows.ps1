param(
    [ValidateSet("cpu", "cuda")]
    [string] $BackendFlavor = "cpu",
    [string] $Configuration = "Release",
    [string] $Runtime = "win-x64",
    [string] $ModelSource = "",
    [string] $Output = ".build/windows-artifacts"
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
    Copy-Item -Recurse (Join-Path $Root "resources") (Join-Path $Publish "resources")

    $AssetName = if ($BackendFlavor -eq "cuda") { "Atten-Windows-x64-CUDA.zip" } else { "Atten-Windows-x64.zip" }
    $Zip = Join-Path $ArtifactRoot $AssetName
    Compress-Archive -Path (Join-Path $Publish "*") -DestinationPath $Zip -Force
    Write-Host "Built $Zip"
}
finally {
    Pop-Location
}
