param(
  [ValidateSet("production", "staging")]
  [string]$Environment = "production",
  [string]$ProjectId = "",
  [string]$MapsKeyDisplayName = "",
  [switch]$SkipClean,
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

if (-not $SkipClean) {
  Invoke-Checked { flutter clean } "Flutter clean"
}
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
$appCheckKey = (& gcloud recaptcha keys list `
  --project=$ProjectId `
  --filter="displayName='Attendus App Check Web'" `
  --format="value(name.basename())").Trim()
if (-not $appCheckKey) {
  throw "The Attendus App Check Web reCAPTCHA Enterprise key was not found."
}
$env:GOOGLE_MAPS_WEB_API_KEY = $mapsKey
$releaseId = (& git rev-parse HEAD).Trim()
if (-not $releaseId) {
  throw "Unable to determine the Git release identifier."
}
$artifactReleaseId = $releaseId
$worktreeState = (& git status --porcelain=v1 --untracked-files=all) -join "`n"
if ($worktreeState) {
  # Never reuse the immutable URL associated with HEAD for a dirty build.
  # A nonce avoids walking and hashing a potentially large untracked tree.
  $dirtyIdentity = "$releaseId`:$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())`:$([Guid]::NewGuid())"
  $hashBytes = [System.Text.Encoding]::UTF8.GetBytes(
    $dirtyIdentity
  )
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $artifactReleaseId = ([System.BitConverter]::ToString(
      $sha256.ComputeHash($hashBytes)
    ) -replace "-", "").ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
  Write-Warning "Dirty worktree detected; using unique immutable release ID $artifactReleaseId."
}
if ($Environment -eq "staging") {
  $hashBytes = [System.Text.Encoding]::UTF8.GetBytes(
    "$artifactReleaseId`:staging"
  )
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $artifactReleaseId = ([System.BitConverter]::ToString(
      $sha256.ComputeHash($hashBytes)
    ) -replace "-", "").ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}

if ($SkipClean) {
  $webBuildRoot = Join-Path $projectRoot "build\web"
  $retainedReleases = Join-Path $webBuildRoot "releases"
  if (Test-Path -LiteralPath $retainedReleases) {
    $resolvedReleases = (Resolve-Path -LiteralPath $retainedReleases).Path
    $resolvedWebRoot = (Resolve-Path -LiteralPath $webBuildRoot).Path
    if (-not $resolvedReleases.StartsWith(
        "$resolvedWebRoot$([IO.Path]::DirectorySeparatorChar)",
        [StringComparison]::OrdinalIgnoreCase
      )) {
      throw "Refusing to move retained releases outside the web build root."
    }
    $archiveRoot = Join-Path $projectRoot "build\stale-web-releases"
    New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
    $archivePath = Join-Path $archiveRoot ([Guid]::NewGuid().ToString("N"))
    Move-Item -LiteralPath $resolvedReleases -Destination $archivePath
    Write-Warning "Moved stale retained web releases to $archivePath."
  }
}

Invoke-Checked { dart run tools/check_maps_web_key.dart } "Maps key validation"
Invoke-Checked {
  flutter build web --release --pwa-strategy=none --no-wasm-dry-run `
    "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$mapsKey" `
    "--dart-define=ATTENDUS_ENABLE_WEB_APP_CHECK=true" `
    "--dart-define=ATTENDUS_RECAPTCHA_ENTERPRISE_SITE_KEY=$appCheckKey" `
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
  $firebaseCli = Join-Path $projectRoot "functions\node_modules\.bin\firebase.cmd"
  if (-not (Test-Path -LiteralPath $firebaseCli)) {
    throw "Project-local Firebase CLI is unavailable at $firebaseCli."
  }
  Invoke-Checked {
    & $firebaseCli deploy --project $ProjectId --only hosting --non-interactive
  } "Firebase Hosting deployment"
  $validationUrls = $environmentConfig.ValidationUrls
  Invoke-Checked {
    dart run tools/check_deferred_web_chunks.dart $validationUrls
  } "Production release validation"
}

Write-Output "Attendus $Environment web release pipeline completed."
