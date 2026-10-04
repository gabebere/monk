param(
    [Parameter(Mandatory = $true)]
    [string]$HostPath
)

$ErrorActionPreference = "Stop"
$extensionRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$template = Get-Content (Join-Path $extensionRoot "native-host.template.json") -Raw
$manifestDirectory = Join-Path $env:LOCALAPPDATA "Monk"
$manifestPath = Join-Path $manifestDirectory "native-host.json"
New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
$escapedHostPath = $HostPath.Replace("\", "\\")
$template.Replace("{HOST_PATH}", $escapedHostPath) | Set-Content $manifestPath -Encoding utf8

$registryTargets = @(
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.gbr.monk",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.gbr.monk",
    "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.gbr.monk",
    "HKCU:\Software\Chromium\NativeMessagingHosts\com.gbr.monk"
)

foreach ($target in $registryTargets) {
    New-Item -Path $target -Force | Out-Null
    Set-Item -Path $target -Value $manifestPath
}

Write-Host "Registered Monk native messaging host for Chrome, Edge, Brave, and Chromium."
