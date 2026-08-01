[CmdletBinding()]
param(
  [string]$Version = "1.0.0",
  [string]$ApiUrl = "https://us-central1-orgami-66nxok.cloudfunctions.net/adminApi",
  [switch]$SkipTests
)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$appRoot = Join-Path $repoRoot "apps\attendus_admin"
$releaseRoot = Join-Path $appRoot "build\windows\x64\runner\Release"
$distRoot = Join-Path $repoRoot "dist"

if ([string]::IsNullOrWhiteSpace($env:ATTENDUS_FIREBASE_API_KEY)) {
  throw "Set ATTENDUS_FIREBASE_API_KEY to the Firebase web API key after restricting it to required Firebase APIs and the distributed application."
}
if ([string]::IsNullOrWhiteSpace($env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID) -or $env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID -notmatch '^[A-Za-z0-9-]+\.apps\.googleusercontent\.com$') {
  throw "Set ATTENDUS_GOOGLE_OAUTH_CLIENT_ID to a Google OAuth 2.0 Desktop app client ID for orgami-66nxok."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter is required on the build machine." }

Push-Location $appRoot
try {
  flutter pub get
  if (-not $SkipTests) { flutter test }
  flutter analyze
  flutter build windows --release --build-name $Version --dart-define="ATTENDUS_FIREBASE_API_KEY=$($env:ATTENDUS_FIREBASE_API_KEY)" --dart-define="ATTENDUS_GOOGLE_OAUTH_CLIENT_ID=$($env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID)" --dart-define="ATTENDUS_ADMIN_API_URL=$ApiUrl"
} finally { Pop-Location }

$exe = Join-Path $releaseRoot "attendus_admin.exe"
if (-not (Test-Path -LiteralPath $exe)) { throw "Windows release executable was not produced at $exe" }
$runtimeFiles = @("flutter_windows.dll", "data\app.so", "data\flutter_assets\AssetManifest.bin")
foreach ($runtimeFile in $runtimeFiles) { if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $runtimeFile))) { throw "Release smoke test failed: missing $runtimeFile" } }

$isccCandidates = @(@(
  (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
if ($isccCandidates.Count -gt 0) {
  & $isccCandidates[0] "/DMyAppVersion=$Version" "/DBuildRoot=$releaseRoot" "/DOutputRoot=$distRoot" (Join-Path $repoRoot "installer\attendus_admin.iss")
  $installer = Join-Path $distRoot "AttendusAdmin-$Version-windows-x64-setup.exe"
} else {
  & (Join-Path $repoRoot "scripts\package_admin_msix.ps1") -Version $Version
  $installer = Join-Path $distRoot "AttendusAdmin-$Version-windows-x64.msix"
}
if (-not (Test-Path -LiteralPath $installer)) { throw "Installer smoke test failed: expected $installer" }
Get-FileHash -Algorithm SHA256 -LiteralPath $installer
Write-Output "Installer: $installer"
