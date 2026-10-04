param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $windowsRoot "artifacts"
$appOutput = Join-Path $artifacts "app"
$hostOutput = Join-Path $appOutput "browser-host"

dotnet run --project (Join-Path $windowsRoot "src/Monk.Core.SmokeTests/Monk.Core.SmokeTests.csproj") `
    --configuration $Configuration

dotnet publish (Join-Path $windowsRoot "src/Monk.App/Monk.App.csproj") `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    --output $appOutput

dotnet publish (Join-Path $windowsRoot "src/Monk.BrowserHost/Monk.BrowserHost.csproj") `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    --output $hostOutput

$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($null -eq $iscc) {
    Write-Host "App published to $appOutput"
    Write-Host "Inno Setup was not found; install Inno Setup 6 to produce setup.exe."
    exit 0
}

& $iscc.Source (Join-Path $windowsRoot "installer/Monk.iss")
Write-Host "Installer written to $(Join-Path $artifacts 'installer')"
