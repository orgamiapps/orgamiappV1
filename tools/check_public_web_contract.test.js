"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {verify} = require("./check_public_web_contract");

test("public rewrites must precede the Flutter catch-all", () => {
  const config = {hosting: {rewrites: [
    {source: "**", destination: "/index.html"},
    {source: "/event/**", function: {functionId: "publicWeb"}},
  ]}};
  const failures = verify(config,
      "Sitemap: https://attendus.app/sitemap.xml", {"public.css": 10});
  assert.equal(failures.some((entry) => entry.includes("follows catch-all")), true);
});
