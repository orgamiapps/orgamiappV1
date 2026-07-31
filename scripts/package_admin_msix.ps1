[CmdletBinding()]
param([string]$Version = "1.0.0", [string]$Publisher = "CN=Attendus Local Development")
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseRoot = Join-Path $repoRoot "apps\attendus_admin\build\windows\x64\runner\Release"
$stageRoot = Join-Path $repoRoot "build\attendus_admin_msix"
$assetsRoot = Join-Path $stageRoot "Assets"
$distRoot = Join-Path $repoRoot "dist"
$output = Join-Path $distRoot "AttendusAdmin-$Version-windows-x64.msix"
$sdkBin = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName "x64" } | Where-Object { Test-Path (Join-Path $_ "makeappx.exe") } | Select-Object -First 1
if (-not $sdkBin) { throw "Windows SDK x64 MakeAppx.exe is required." }
if (-not (Test-Path (Join-Path $releaseRoot "attendus_admin.exe"))) { throw "Build the Windows release before packaging MSIX." }

$resolvedParent = (Resolve-Path (Split-Path $stageRoot -Parent)).Path
if (-not $resolvedParent.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean a staging path outside the repository." }
if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageRoot,$assetsRoot,$distRoot | Out-Null
Copy-Item -Path (Join-Path $releaseRoot "*") -Destination $stageRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "installer\msix\AppxManifest.xml") -Destination (Join-Path $stageRoot "AppxManifest.xml")
Get-ChildItem -LiteralPath $stageRoot -File | Where-Object { $_.Extension -in @('.lib','.exp') } | Remove-Item -Force
$manifestPath = Join-Path $stageRoot "AppxManifest.xml"
[xml]$manifest = Get-Content -LiteralPath $manifestPath
$parts = $Version.Split('.')
if ($parts.Count -ne 3 -or [bool]($parts | Where-Object { $_ -notmatch '^\d+$' })) { throw "Version must use major.minor.patch." }
$manifest.Package.Identity.Version = "$Version.0"
$manifest.Package.Identity.Publisher = $Publisher
$manifest.Save($manifestPath)

Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Join-Path $repoRoot "attendus_logo_only.png"))
try {
  $sizes = @{"StoreLogo.png"=@(50,50); "Square44x44Logo.png"=@(44,44); "Square150x150Logo.png"=@(150,150); "Wide310x150Logo.png"=@(310,150)}
  foreach ($name in $sizes.Keys) {
    $width,$height = $sizes[$name]
    $bitmap = New-Object System.Drawing.Bitmap($width,$height)
    try { $graphics = [System.Drawing.Graphics]::FromImage($bitmap); try { $graphics.Clear([System.Drawing.Color]::Transparent); $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $scale = [Math]::Min($width / $source.Width, $height / $source.Height); $drawWidth = [int]($source.Width * $scale); $drawHeight = [int]($source.Height * $scale); $graphics.DrawImage($source, [int](($width-$drawWidth)/2), [int](($height-$drawHeight)/2), $drawWidth, $drawHeight) } finally { $graphics.Dispose() }; $bitmap.Save((Join-Path $assetsRoot $name), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
  }
} finally { $source.Dispose() }

if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
& (Join-Path $sdkBin "makeappx.exe") pack /d $stageRoot /p $output /o
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw "MSIX packaging failed." }

if ($env:ATTENDUS_SIGNING_PFX) {
  if (-not $env:ATTENDUS_SIGNING_PFX_PASSWORD) { throw "ATTENDUS_SIGNING_PFX_PASSWORD is required when signing." }
  & (Join-Path $sdkBin "signtool.exe") sign /fd SHA256 /f $env:ATTENDUS_SIGNING_PFX /p $env:ATTENDUS_SIGNING_PFX_PASSWORD $output
  if ($LASTEXITCODE -ne 0) { throw "MSIX signing failed." }
}
Get-FileHash -Algorithm SHA256 -LiteralPath $output
Write-Output "MSIX: $output"
