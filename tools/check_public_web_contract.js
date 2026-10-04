"use strict";

const {existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync} = require("node:fs");
const {createHash} = require("node:crypto");
const {join} = require("node:path");

const root = join(__dirname, "..");
const ASSET_NAMES = ["public.css", "registration-email-v2.css", "actions-email-v2.js"];
const manifestPath = join(root, "functions", "public-web", "asset-manifest.json");
const assetsDirectory = join(root, "web", "public-web", "v1", "assets");
const canonicalAsset = (source) => String(source).replace(/\r\n/g, "\n");
const assetHash = (bytes) => createHash("sha256").update(bytes).digest("hex");

function assetManifest(sources) {
  // Git normalizes these text assets to LF. Use the same content identity on
  // Windows developer checkouts and Linux release builds.
  return {schemaVersion: 1, algorithm: "sha256-lf", assets: Object.fromEntries(
    ASSET_NAMES.map((name) => [name, assetHash(canonicalAsset(sources[name]))]),
  )};
}

function readRetainedAssets(directory) {
  const retained = {};
  if (!existsSync(directory)) return retained;
  for (const version of readdirSync(directory, {withFileTypes: true})) {
    if (!version.isDirectory() || !/^[a-f0-9]{64}$/.test(version.name)) {
      throw new Error(`Unexpected immutable public asset directory: ${version.name}`);
    }
    for (const file of readdirSync(join(directory, version.name), {withFileTypes: true})) {
      if (!file.isFile() || !ASSET_NAMES.includes(file.name)) {
        throw new Error(`Unexpected immutable public asset file: ${version.name}/${file.name}`);
      }
      retained[`${version.name}/${file.name}`] = readFileSync(join(directory, version.name, file.name));
    }
  }
  return retained;
}

function verifyRetainedAssets(manifest, retained) {
  const failures = [];
  for (const [path, bytes] of Object.entries(retained)) {
    const [version, name, extra] = path.split("/");
    if (extra !== undefined || !/^[a-f0-9]{64}$/.test(version) || !ASSET_NAMES.includes(name) ||
        assetHash(bytes) !== version || Buffer.from(bytes).includes(Buffer.from("\r\n"))) {
      failures.push(`Immutable public asset path/content mismatch: ${path}`);
    }
  }
  if (manifest) for (const name of ASSET_NAMES) {
    if (!Object.hasOwn(retained, `${manifest.assets?.[name]}/${name}`)) {
      failures.push(`Current immutable public asset is missing: ${name}`);
    }
  }
  return failures;
}

function writeImmutableAssets(directory, sources) {
  const manifest = assetManifest(sources);
  const priorFailures = verifyRetainedAssets(null, readRetainedAssets(directory));
  if (priorFailures.length) throw new Error(priorFailures.join("\n"));
  for (const name of ASSET_NAMES) {
    const versionDirectory = join(directory, manifest.assets[name]);
    const target = join(versionDirectory, name);
    const bytes = Buffer.from(canonicalAsset(sources[name]), "utf8");
    mkdirSync(versionDirectory, {recursive: true});
    if (existsSync(target)) {
      if (!readFileSync(target).equals(bytes)) throw new Error(`Refusing to overwrite immutable public asset: ${target}`);
    } else writeFileSync(target, bytes, {flag: "wx"});
  }
  return manifest;
}

function verifyAssetManifest(sources, manifest, renderer) {
  const failures = [];
  const expected = assetManifest(sources);
  if (!renderer.includes("`/public-web/v1/assets/${version}/${name}`")) {
    failures.push("Renderer must use physical immutable public asset paths");
  }
  if (manifest?.schemaVersion !== expected.schemaVersion ||
      manifest?.algorithm !== expected.algorithm ||
      Object.keys(manifest?.assets || {}).sort().join() !== ASSET_NAMES.slice().sort().join()) {
    failures.push("Public asset manifest schema or file inventory does not match");
  }
  for (const name of ASSET_NAMES) {
    if (manifest?.assets?.[name] !== expected.assets[name]) {
      failures.push(`${name} changed; run node tools/check_public_web_contract.js --write-asset-manifest`);
    }
    if (renderer.includes(`/public-web/v1/${name}`)) {
      failures.push(`${name} has a renderer URL that bypasses publicAssetUrl`);
    }
    if (!renderer.includes(`publicAssetUrl("${name}")`)) {
      failures.push(`${name} is missing its versioned renderer reference`);
    }
  }
  return failures;
}

function verify(config, robots, files) {
  const failures = [];
  const rewrites = config.hosting?.rewrites || [];
  const catchAll = rewrites.findIndex((entry) => entry.source === "**");
  for (const [source, functionId] of [["/event/**", "publicWeb"],
    ["/community/**", "publicWeb"], ["/manage", "publicWeb"],
    ["/manage/**", "publicWeb"], ["/sitemap.xml", "publicWeb"],
    ["/sitemaps/**", "publicWeb"]]) {
    const index = rewrites.findIndex((entry) => entry.source === source &&
      entry.function?.functionId === functionId);
    if (index === -1) failures.push(`Missing publicWeb rewrite for ${source}`);
    if (catchAll !== -1 && index > catchAll) failures.push(`${source} follows catch-all`);
  }
  if (!robots.includes("Sitemap: https://attendus.app/sitemap.xml")) {
    failures.push("robots.txt does not declare the canonical sitemap");
  }
  for (const [name, bytes] of Object.entries(files)) {
    if (bytes > 75000) failures.push(`${name} exceeds the 75KB public asset budget`);
  }
  const initialBytes = Object.values(files).reduce((total, bytes) => total + bytes, 0);
  if (initialBytes > 75000) failures.push(`public assets total ${initialBytes} bytes exceeds 75KB`);
  return failures;
}

function verifyEmailOnly(sources) {
  const forbidden = [
    /twilio/i,
    /sendBulkSms/,
    /PhoneAuthProvider/,
    /communications\/sms-/,
    /channel\s*:\s*[^\n]*["']sms["']/,
    /TWILIO_[A-Z_]+/,
  ];
  const failures = [];
  for (const [name, source] of Object.entries(sources)) {
    for (const pattern of forbidden) {
      if (pattern.test(source)) failures.push(`${name} contains disabled SMS integration code`);
    }
  }
  return failures;
}

function main() {
  const assetSources = Object.fromEntries(ASSET_NAMES.map((name) =>
    [name, readFileSync(join(root, "web", "public-web", "v1", name), "utf8")]));
  if (process.argv.includes("--write-asset-manifest")) {
    const manifest = writeImmutableAssets(assetsDirectory, assetSources);
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    process.stdout.write("Updated public asset manifest and immutable copies; prior copies retained. Commit both.\n");
    return;
  }
  const config = JSON.parse(readFileSync(join(root, "firebase.json"), "utf8"));
  const robots = readFileSync(join(root, "web", "robots.txt"), "utf8");
  const files = Object.fromEntries(ASSET_NAMES
      .map((name) => [name, statSync(join(root, "web", "public-web", "v1", name)).size]));
  const sources = Object.fromEntries([
    "firebase.json", "functions/index.js", "functions/communications/delivery.js",
    "functions/notifications/admin-dispatch.js", "functions/package.json",
    "web/public-web/v1/actions-email-v2.js",
  ].map((name) => [name, readFileSync(join(root, ...name.split("/")), "utf8")]));
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const failures = [...verify(config, robots, files), ...verifyEmailOnly(sources),
    ...verifyAssetManifest(assetSources, manifest,
        readFileSync(join(root, "functions", "public-web", "renderer.js"), "utf8")),
    ...verifyRetainedAssets(manifest, readRetainedAssets(assetsDirectory))];
  if (failures.length) throw new Error(failures.join("\n"));
  process.stdout.write(`Public web contract passed (${JSON.stringify(files)}).\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {verify, verifyEmailOnly, assetManifest, verifyAssetManifest,
  readRetainedAssets, verifyRetainedAssets, writeImmutableAssets};
