"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {catalogDifference, readDartCatalog, verifyDiscoveryCategoryCatalog} =
  require("./check_discovery_category_catalog");

test("Flutter and Functions discovery catalogs match", () => {
  assert.equal(verifyDiscoveryCategoryCatalog(), 15);
});

test("catalog verifier detects label and order drift", () => {
  const flutter = readDartCatalog("const x = [DiscoveryCategory('one', 'One', Icons.add)];");
  assert.deepEqual(flutter, [{id: "one", label: "One"}]);
  assert.notEqual(catalogDifference([{id: "one", label: "Changed"}], flutter), null);
});
