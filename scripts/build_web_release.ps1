param(
  [string]$ProjectId = "orgami-66nxok",
  [string]$MapsKeyDisplayName = "Attendus Maps Web",
  [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command,
    [Parameter(Mandatory = $true)]
    [string]$Description
  )
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE."
  }
}

Invoke-Checked { flutter clean } "Flutter clean"
Invoke-Checked { flutter pub get } "Flutter dependency restore"

$keyResource = (& gcloud services api-keys list `
  --project=$ProjectId `
  --filter="displayName='$MapsKeyDisplayName'" `
  --format="value(name)").Trim()
if (-not $keyResource) {
  throw "The dedicated Maps web key was not found."
}
$mapsKey = (& gcloud services api-keys get-key-string $keyResource `
  --format="value(keyString)").Trim()
if (-not $mapsKey) {
  throw "The dedicated Maps web key value was unavailable."
}
$env:GOOGLE_MAPS_WEB_API_KEY = $mapsKey

Invoke-Checked { dart run tools/check_maps_web_key.dart } "Maps key validation"
Invoke-Checked {
  flutter build web --release --pwa-strategy=none --no-wasm-dry-run `
    "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$mapsKey"
} "Flutter web build"

$requiredBuildFiles = @(
  "build/web/.last_build_id",
  "build/web/favicon.png",
  "build/web/icons/Icon-192.png",
  "build/web/main.dart.js",
  "build/web/flutter_bootstrap.js"
)
foreach ($requiredFile in $requiredBuildFiles) {
  if (-not (Test-Path -LiteralPath $requiredFile)) {
    throw "Flutter web build is incomplete: missing $requiredFile"
  }
}

Copy-Item -LiteralPath web/flutter_service_worker_retirement.js `
  -Destination build/web/flutter_service_worker.js -Force
Invoke-Checked {
  dart run tools/retain_web_releases.dart https://attendus.app/
} "Retained release download"
Invoke-Checked { dart run tools/package_web_release.dart } "Release packaging"
Invoke-Checked {
  dart run tools/check_deferred_web_chunks.dart
} "Release asset validation"
Invoke-Checked { dart run tools/check_web_bundle_size.dart } "Bundle budget"

if ($Deploy) {
  Invoke-Checked {
    firebase deploy --project $ProjectId --only hosting
  } "Firebase Hosting deployment"
  Invoke-Checked {
    dart run tools/check_deferred_web_chunks.dart https://attendus.app/
  } "Custom-domain release validation"
  Invoke-Checked {
    dart run tools/check_deferred_web_chunks.dart `
      "https://$ProjectId.web.app/"
  } "Firebase-domain release validation"
}

Write-Output "Attendus web release pipeline completed."
