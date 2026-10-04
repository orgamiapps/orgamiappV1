"use strict";

// Web-only qualification preserves existing native association bytes; it does
// not invent signing identities or turn a native device gate into a web gate.
const fs = require("node:fs");
const path = require("node:path");
async function retain(environment, output) {
  const origin = {production: "https://attendus.app", staging: "https://attendus-staging.web.app"}[environment];
  if (!origin || !output) throw Error("Expected production|staging and a web output directory");
  const result = {};
  for (const name of ["apple-app-site-association", "assetlinks.json"]) {
    const response = await fetch(`${origin}/.well-known/${name}`, {signal: AbortSignal.timeout(30000), cache: "no-store"});
    if (![200, 404].includes(response.status)) throw Error(`Cannot capture prior association: HTTP ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer()); let json = null;
    try { json = JSON.parse(bytes.toString()); } catch (_) { /* SPA fallback means no published association. */ }
    const published = response.status === 200 && (name === "assetlinks.json" ? Array.isArray(json) : json?.applinks != null);
    const target = path.resolve(output, ".well-known", name);
    if (published) { fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, bytes); }
    else if (fs.existsSync(target)) fs.unlinkSync(target);
    result[name] = {origin, status: response.status, retained: published};
  }
  return result;
}
if (require.main === module) retain(process.argv[2], process.argv[3]).then((result) => console.log(JSON.stringify(result))).catch((error) => { console.error(error.message); process.exitCode = 1; });
module.exports = {retain};
