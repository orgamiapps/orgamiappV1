param(
  [ValidateSet("production", "staging")]
  [string]$Environment = "production",
  [string]$ProjectId = "",
  [string]$MapsKeyDisplayName = "",
  [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$environmentConfig = @{
  production = @{
    ProjectId = "orgami-66nxok"
    MapsKeyDisplayName = "Attendus Maps Web"
    RetainUrl = "https://attendus.app/"
    ValidationUrls = @(
      "https://attendus.app/",
      "https://orgami-66nxok.web.app/"
    )
  }
  staging = @{
    ProjectId = "attendus-staging"
    MapsKeyDisplayName = "Attendus Maps Web Staging"
    RetainUrl = "https://attendus-staging.web.app/"
    ValidationUrls = @(
      "https://attendus-staging.web.app/",
      "https://attendus-staging.firebaseapp.com/"
    )
  }
}[$Environment]

if (-not $ProjectId) { $ProjectId = $environmentConfig.ProjectId }
if ($ProjectId -ne $environmentConfig.ProjectId) {
  throw "$Environment builds must target project $($environmentConfig.ProjectId), not $ProjectId."
}
if (-not $MapsKeyDisplayName) {
  $MapsKeyDisplayName = $environmentConfig.MapsKeyDisplayName
}

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
$releaseId = (& git rev-parse HEAD).Trim()
if (-not $releaseId) {
  throw "Unable to determine the Git release identifier."
}
$artifactReleaseId = $releaseId
if ($Environment -eq "staging") {
  $hashBytes = [System.Text.Encoding]::UTF8.GetBytes("$releaseId`:staging")
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $artifactReleaseId = ([System.BitConverter]::ToString(
      $sha256.ComputeHash($hashBytes)
    ) -replace "-", "").ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}

Invoke-Checked { dart run tools/check_maps_web_key.dart } "Maps key validation"
Invoke-Checked {
  flutter build web --release --pwa-strategy=none --no-wasm-dry-run `
    "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$mapsKey" `
    "--dart-define=ATTENDUS_RELEASE_ID=$artifactReleaseId" `
    "--dart-define=ATTENDUS_FIREBASE_ENV=$Environment"
} "Flutter web build"

Invoke-Checked {
  dart run tools/configure_web_environment.dart --environment $Environment
} "Web environment configuration"

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
  dart run tools/retain_web_releases.dart $environmentConfig.RetainUrl
} "Retained release download"
Invoke-Checked {
  dart run tools/package_web_release.dart --release-id $artifactReleaseId
} "Release packaging"
Invoke-Checked {
  dart run tools/check_deferred_web_chunks.dart
} "Release asset validation"
Invoke-Checked { dart run tools/check_web_bundle_size.dart } "Bundle budget"

if ($Deploy) {
  Invoke-Checked {
    firebase deploy --project $ProjectId --only hosting
  } "Firebase Hosting deployment"
  foreach ($validationUrl in $environmentConfig.ValidationUrls) {
    Invoke-Checked {
      dart run tools/check_deferred_web_chunks.dart $validationUrl
    } "Release validation for $validationUrl"
  }
}

Write-Output "Attendus $Environment web release pipeline completed."
