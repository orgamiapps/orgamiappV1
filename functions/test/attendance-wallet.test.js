"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const zlib = require("node:zlib");
const forge = require("node-forge");
const wallet = require("../attendance/wallet");

// Read the central directory, independently of the archive writer.
function unzip(buffer) {
  const end = buffer.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  let cursor = buffer.readUInt32LE(end + 16);
  const entries = {};
  for (let i = 0; i < buffer.readUInt16LE(end + 10); i++) {
    assert.equal(buffer.readUInt32LE(cursor), 0x02014b50);
    const method = buffer.readUInt16LE(cursor + 10);
    const size = buffer.readUInt32LE(cursor + 20);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const local = buffer.readUInt32LE(cursor + 42);
    const name = buffer.subarray(cursor + 46, cursor + 46 + nameLength).toString();
    const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
    const compressed = buffer.subarray(start, start + size);
    entries[name] = method === 8 ? zlib.inflateRawSync(compressed) : compressed;
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

test("Apple event and generic packages have a verifiable detached signature and stable serial", async () => {
  const pair = forge.pki.rsa.generateKeyPair(2048);
  const certificate = forge.pki.createCertificate();
  certificate.publicKey = pair.publicKey;
  certificate.serialNumber = "01";
  certificate.validity.notBefore = new Date(Date.now() - 60000);
  certificate.validity.notAfter = new Date(Date.now() + 86400000);
  certificate.setSubject([{name: "commonName", value: "Local test only"}]);
  certificate.setIssuer(certificate.subject.attributes);
  certificate.sign(pair.privateKey, forge.md.sha256.create());
  const unrelated = crypto.generateKeyPairSync("rsa", {modulusLength: 2048});
  await assert.rejects(require("../attendance/cms-signing").signDetached(Buffer.from("manifest"), {
    certificate: forge.pki.certificateToPem(certificate),
    wwdrCertificate: forge.pki.certificateToPem(certificate),
    privateKey: unrelated.privateKey.export({format: "pem", type: "pkcs8"}),
  }), /must match/);
  process.env.APPLE_WALLET_SIGNING = JSON.stringify({certificate: forge.pki.certificateToPem(certificate),
    wwdrCertificate: forge.pki.certificateToPem(certificate), privateKey: forge.pki.privateKeyToPem(pair.privateKey)});
  process.env.APPLE_WALLET_PASS_TYPE_ID = "pass.test.attendus";
  process.env.APPLE_WALLET_TEAM_ID = "TESTTEAM01";
  process.env.ATTENDANCE_WALLET_ORIGIN = "https://example.test";
  for (const kind of ["event", "identity"]) {
    const record = {id: "a".repeat(64), kind, title: "Local test", attendeeName: "Test Attendee", status: "active",
      startsAt: kind === "event" ? new Date().toISOString() : null, expiresAtMs: Date.now() + 86400000,
      appleAuthenticationToken: "b".repeat(64), qrData: "attendus_pass:v2:test"};
    const entries = unzip(await wallet.buildApplePass(record));
    const manifest = JSON.parse(entries["manifest.json"]);
    for (const [name, hash] of Object.entries(manifest)) assert.equal(crypto.createHash("sha1").update(entries[name]).digest("hex"), hash);
    const pass = JSON.parse(entries["pass.json"]);
    assert.equal(pass.serialNumber, record.id);
    assert.ok(pass[kind === "event" ? "eventTicket" : "generic"]);
    assert.equal(pass.webServiceURL, "https://example.test/api/wallet");
    const message = forge.pkcs7.messageFromAsn1(forge.asn1.fromDer(entries.signature.toString("binary")));
    const capture = message.rawCapture;
    const attributes = forge.asn1.create(forge.asn1.Class.UNIVERSAL, forge.asn1.Type.SET, true, capture.authenticatedAttributes);
    const data = Buffer.from(forge.asn1.toDer(attributes).getBytes(), "binary");
    assert.ok(crypto.verify("sha256", data, forge.pki.publicKeyToPem(pair.publicKey), Buffer.from(capture.signature, "binary")));
    const digestAttribute = capture.authenticatedAttributes.find((a) => forge.asn1.derToOid(a.value[0].value) === forge.pki.oids.messageDigest);
    assert.equal(Buffer.from(digestAttribute.value[1].value[0].value, "binary").toString("hex"), crypto.createHash("sha256").update(entries["manifest.json"]).digest("hex"));
    assert.ok(wallet.authorizedApple({get: () => `ApplePass ${record.appleAuthenticationToken}`}, record));
    assert.equal(wallet.authorizedApple({get: () => "ApplePass wrong"}, record), false);
  }
});


test("Google uses event classes and individual objects, preserves IDs, and updates revocation", async () => {
  const key = crypto.generateKeyPairSync("rsa", {modulusLength: 2048});
  const account = {client_email: "test@example.test", private_key: key.privateKey.export({format: "pem", type: "pkcs8"})};
  process.env.GOOGLE_WALLET_ISSUER_ID = "123456789";
  const writes = [];
  const client = {request: async (request) => {
    writes.push(request);
    if (request.method === "PATCH" && writes.length === 1) throw {response: {status: 404}};
  }};
  const base = {id: "c".repeat(64), kind: "event", eventId: "event", attendeeName: "Test", title: "Test Event", location: "Venue",
    startsAt: new Date().toISOString(), expiresAtMs: Date.now() + 86400000, status: "active", qrData: "signed-test"};
  const url = await wallet.googlePass(base, {account, client});
  assert.ok(writes.some(w => w.method === "POST" && w.url.endsWith("eventTicketClass")));
  assert.equal(writes.at(-1).data.classId, writes[0].data.id);
  assert.equal(writes.at(-1).data.barcode.value, "signed-test");
  const objectId = writes.at(-1).data.id;
  const claims = require("jsonwebtoken").verify(url.split("/save/")[1], key.publicKey, {algorithms: ["RS256"]});
  assert.equal(claims.payload.eventTicketObjects[0].id, objectId);
  await wallet.googlePass({...base, status: "revoked"}, {account, client});
  assert.equal(writes.at(-1).data.id, objectId);
  assert.equal(writes.at(-1).data.state, "INACTIVE");
  await wallet.googlePass({...base, kind: "identity", eventId: null}, {account, client});
  assert.ok(writes.at(-1).url.includes("genericObject"));
  assert.equal(writes.at(-1).data.header.defaultValue.value, "Test");
});


test("disabled providers have no deployment secrets or core transport dependency", async () => {
  delete process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED;
  delete process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED;
  delete process.env.APPLE_WALLET_SIGNING;
  delete process.env.GOOGLE_WALLET_SERVICE_ACCOUNT_JSON;
  assert.deepEqual(wallet.providerSecrets(), []);
  const db = {collection: () => { throw Error("Disabled providers must not read delivery state"); }};
  assert.deepEqual(await wallet.deliveryLinks(db, {id: "test", eventId: "event"}), {
    appleWalletUrl: null, googleWalletUrl: null, appleWalletStatus: "disabled",
    googleWalletStatus: "disabled", walletStatus: "disabled",
  });
  const functions = wallet.createWalletFunctions({firestore: () => db});
  assert.deepEqual(functions.attendanceWallet.__endpoint.secretEnvironmentVariables, []);
  assert.deepEqual(functions.deliverAttendanceWallets.__endpoint.secretEnvironmentVariables, []);
  assert.deepEqual(functions.refreshAttendanceWallets.__endpoint.secretEnvironmentVariables.map(v => v.key), ["ATTENDANCE_PASS_SIGNING_KEY"]);
  await functions.deliverAttendanceWallets.run({});
});

test("provider rollout is independently scoped and core responses use cached Google state", async () => {
  process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED = "true";
  const settings = {corePasses: {enabled: true, eventIds: ["event"]},
    googleDelivery: {enabled: false, eventIds: ["event"], userIds: ["owner"]}};
  const db = {collection: name => ({doc: () => ({get: async () => ({data: () => name === "AppConfig" ? settings :
    {credentialVersion: 4, googleWalletUrl: "https://pay.google.com/gp/v/save/mock"}})})})};
  const record = {id: "test", eventId: "event", ownerUid: "owner", credentialVersion: 4};
  assert.equal(await wallet.providerEnabled(db, "google", record), false);
  settings.googleDelivery.enabled = true;
  assert.equal(await wallet.providerEnabled(db, "google", {...record, ownerUid: "other"}), false);
  assert.equal((await wallet.deliveryLinks(db, record)).googleWalletUrl, "https://pay.google.com/gp/v/save/mock");
  assert.equal((await wallet.deliveryLinks(db, {...record, credentialVersion: 5})).googleWalletUrl, null);
  delete process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED;
});


test("SDK registers only explicitly enabled provider secret parameter specifications", () => {
  const params = require("firebase-functions/params");
  const path = require.resolve("../attendance/wallet");
  const cached = require.cache[path];
  const originalParams = [...params.declaredParams];
  const priorApple = process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED;
  const priorGoogle = process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED;
  const providerNames = ["APPLE_WALLET_SIGNING", "GOOGLE_WALLET_SERVICE_ACCOUNT_JSON"];
  try {
    for (const [apple, google] of [[false, false], [true, false], [false, true], [true, true]]) {
      params.declaredParams.splice(0, params.declaredParams.length, ...originalParams.filter(param => !providerNames.includes(param.name)));
      process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED = String(apple);
      process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED = String(google);
      delete require.cache[path];
      const module = require("../attendance/wallet");
      const expected = providerNames.filter((_, index) => index === 0 ? apple : google);
      const declared = params.declaredParams.map(param => param.toSpec())
          .filter(spec => spec.type === "secret" && providerNames.includes(spec.name)).map(spec => spec.name);
      assert.deepEqual(declared, expected);
      assert.deepEqual(module.providerSecrets().map(param => param.name), expected);
    }
  } finally {
    params.declaredParams.splice(0, params.declaredParams.length, ...originalParams);
    require.cache[path] = cached;
    if (priorApple === undefined) delete process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED;
    else process.env.ATTENDANCE_APPLE_DELIVERY_ENABLED = priorApple;
    if (priorGoogle === undefined) delete process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED;
    else process.env.ATTENDANCE_GOOGLE_DELIVERY_ENABLED = priorGoogle;
  }
});
