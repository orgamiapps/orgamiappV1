"use strict";

const {readFileSync, statSync} = require("node:fs");
const {join} = require("node:path");

const root = join(__dirname, "..");

function verify(config, robots, files) {
  const failures = [];
  const rewrites = config.hosting?.rewrites || [];
  const catchAll = rewrites.findIndex((entry) => entry.source === "**");
  for (const [source, functionId] of [["/event/**", "publicWeb"],
    ["/community/**", "publicWeb"], ["/manage", "publicWeb"],
    ["/manage/**", "publicWeb"], ["/communications/sms-status", "twilioStatusCallbackV1"],
    ["/communications/sms-inbound", "twilioInboundV1"], ["/sitemap.xml", "publicWeb"],
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

function main() {
  const config = JSON.parse(readFileSync(join(root, "firebase.json"), "utf8"));
  const robots = readFileSync(join(root, "web", "robots.txt"), "utf8");
  const files = Object.fromEntries([
    "public.css", "registration.css", "actions.js",
  ].map((name) => [name, statSync(join(root, "web", "public-web", "v1", name)).size]));
  const failures = verify(config, robots, files);
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

module.exports = {verify};
