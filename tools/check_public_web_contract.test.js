"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const {verify, verifyEmailOnly, assetManifest, verifyAssetManifest, readRetainedAssets,
  verifyRetainedAssets, writeImmutableAssets} = require("./check_public_web_contract");
const rendererFor = (sources) => '`/public-web/v1/assets/${version}/${name}`\n' +
  Object.keys(sources).map((name) => `publicAssetUrl("${name}")`).join("\n");
function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "attendus-immutable-assets-"));
  assert.equal(path.dirname(path.resolve(directory)), path.resolve(os.tmpdir()));
  t.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  return directory;
}

test("public rewrites must precede the Flutter catch-all", () => {
  const config = {hosting: {rewrites: [
    {source: "**", destination: "/index.html"},
    {source: "/event/**", function: {functionId: "publicWeb"}},
  ]}};
  const failures = verify(config,
      "Sitemap: https://attendus.app/sitemap.xml", {"public.css": 10});
  assert.equal(failures.some((entry) => entry.includes("follows catch-all")), true);
});

test("email-only contract rejects SMS provider code", () => {
  assert.deepEqual(verifyEmailOnly({"delivery.js": "channel: 'email'"}), []);
  assert.equal(
      verifyEmailOnly({"delivery.js": "const TWILIO_AUTH_TOKEN = 'x'"}).length > 0,
      true,
  );
});

test("public asset versions change with content and remain stable across checkout line endings", () => {
  const sources = {"public.css": "body {}\n", "registration-email-v2.css": "input {}\n",
    "actions-email-v2.js": "run();\n"};
  const manifest = assetManifest(sources);
  const renderer = rendererFor(sources);
  assert.deepEqual(verifyAssetManifest(sources, manifest, renderer), []);
  assert.deepEqual(assetManifest(Object.fromEntries(Object.entries(sources)
      .map(([name, value]) => [name, value.replaceAll("\n", "\r\n")]))), manifest);
  const changed = {...sources, "actions-email-v2.js": "fixed();\n"};
  assert.notEqual(assetManifest(changed).assets["actions-email-v2.js"], manifest.assets["actions-email-v2.js"]);
  assert.match(verifyAssetManifest(changed, manifest, renderer).join(), /actions-email-v2\.js changed/);
});

test("public asset contract rejects unversioned page or manage references and incomplete inventory", () => {
  const sources = {"public.css": "a", "registration-email-v2.css": "b", "actions-email-v2.js": "c"};
  const manifest = assetManifest(sources);
  const renderer = rendererFor(sources);
  assert.match(verifyAssetManifest(sources, manifest,
      `${renderer}<link href="/public-web/v1/public.css">`).join(), /bypasses publicAssetUrl/);
  assert.match(verifyAssetManifest(sources, {...manifest, assets: {...manifest.assets, extra: "d"}}, renderer).join(), /inventory/);
  assert.match(verifyAssetManifest(sources, manifest,
      renderer.replace('/assets/${version}/${name}', '/${name}?v=${version}')).join(), /physical immutable/);
});

test("immutable generator writes LF bytes and retains prior asset versions", (t) => {
  const directory = temporaryDirectory(t);
  const sources = {"public.css": "body {}\r\n", "registration-email-v2.css": "input {}\r\n",
    "actions-email-v2.js": "run();\r\n"};
  const first = writeImmutableAssets(directory, sources);
  const before = readRetainedAssets(directory);
  assert.deepEqual(verifyRetainedAssets(first, before), []);
  assert.equal(before[`${first.assets["public.css"]}/public.css`].toString(), "body {}\n");
  const next = writeImmutableAssets(directory, {...sources, "actions-email-v2.js": "fixed();\n"});
  const after = readRetainedAssets(directory);
  assert.equal(Object.keys(after).length, 4);
  assert.deepEqual(verifyRetainedAssets(next, after), []);
  for (const [name, bytes] of Object.entries(before)) assert.deepEqual(after[name], bytes);
  assert.deepEqual(writeImmutableAssets(directory, {...sources, "actions-email-v2.js": "fixed();\n"}), next);
});

test("immutable validation rejects altered old bytes, wrong paths and missing current copies", (t) => {
  const directory = temporaryDirectory(t);
  const sources = {"public.css": "body {}\n", "registration-email-v2.css": "input {}\n", "actions-email-v2.js": "run();\n"};
  const first = writeImmutableAssets(directory, sources);
  const next = writeImmutableAssets(directory, {...sources, "actions-email-v2.js": "fixed();\n"});
  const retained = readRetainedAssets(directory);
  const oldPath = `${first.assets["actions-email-v2.js"]}/actions-email-v2.js`;
  assert.match(verifyRetainedAssets(next, {...retained, [oldPath]: Buffer.from("tampered")}).join(), /mismatch/);
  assert.match(verifyRetainedAssets(next, {...retained, "wrong/public.css": Buffer.from("body {}\n")}).join(), /mismatch/);
  const missing = {...retained}; delete missing[`${next.assets["public.css"]}/public.css`];
  assert.match(verifyRetainedAssets(next, missing).join(), /missing/);
  fs.writeFileSync(path.join(directory, oldPath), "tampered");
  assert.throws(() => writeImmutableAssets(directory, sources), /mismatch/);
  assert.equal(fs.readFileSync(path.join(directory, oldPath), "utf8"), "tampered");
});
