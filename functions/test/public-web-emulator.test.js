"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
if (!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) throw Error("Local Firestore emulator required");
process.env.GCLOUD_PROJECT = "demo-attendus-admin";
process.env.GOOGLE_CLOUD_PROJECT = "demo-attendus-admin";
process.env.FUNCTIONS_EMULATOR = "true";
const admin = require("../firebase-admin-compat");
const db = admin.firestore();
const {createMaintainPublicEventPage, createMaintainPublicCommunityPage} = require("../public-web/renderer");
test.after(async () => db.terminate());

for (const item of [
  {name: "event", source: "Events", mirror: "PublicWebEvents", param: "eventId",
    factory: createMaintainPublicEventPage, label: "title",
    publicData: {title: "Current public event", private: false, status: "active",
      selectedDateTime: "2030-01-01T12:00:00Z", eventDuration: 1, createdAt: "2026-01-01T00:00:00Z"},
    hidden: {private: true}, fields: ["canonicalUrl", "title", "organizationId", "eventEndTime", "lastModified"]},
  {name: "community", source: "Organizations", mirror: "PublicWebCommunities", param: "organizationId",
    factory: createMaintainPublicCommunityPage, label: "name",
    publicData: {name: "Current public community", publicPageEnabled: true, createdAt: "2026-01-01T00:00:00Z"},
    hidden: {publicPageEnabled: false}, fields: ["canonicalUrl", "name", "lastModified"]},
]) {
  test(`actual ${item.name} mirror ignores stale deliveries and preserves recreated source projection`, async () => {
    const id = `public-mirror-${crypto.randomUUID()}`;
    const source = db.collection(item.source).doc(id), mirror = db.collection(item.mirror).doc(id);
    const handler = item.factory(admin);
    try {
      await source.set({...item.publicData, privateContact: "must not project"});
      const stalePublic = await source.get();
      const delivered = {params: {[item.param]: id}, data: {after: stalePublic}};
      await handler.run(delivered);
      assert.deepEqual(Object.keys((await mirror.get()).data()).sort(), item.fields.sort());
      await source.update(item.hidden);
      await handler.run(delivered);
      assert.equal((await mirror.get()).exists, false);
      await source.delete();
      const oldDelete = await source.get();
      await handler.run(delivered);
      assert.equal((await mirror.get()).exists, false);
      await source.set({...item.publicData, [item.label]: "Replacement public source"});
      await handler.run({params: {[item.param]: id}, data: {after: oldDelete}});
      await handler.run(delivered);
      assert.equal((await mirror.get()).get(item.label), "Replacement public source");
    } finally {
      await Promise.all([source.delete(), mirror.delete()]);
    }
  });

  test(`actual ${item.name} mirror transaction retry rereads concurrent privacy change`, async () => {
    const id = `public-retry-${crypto.randomUUID()}`;
    const source = db.collection(item.source).doc(id), mirror = db.collection(item.mirror).doc(id);
    let attempts = 0;
    const proxy = new Proxy(db, {get(target, property) {
      if (property === "runTransaction") return (callback) => target.runTransaction(async (tx) => {
        attempts++;
        // The first attempt was aborted before commit and released its read lock.
        if (attempts === 2) await source.update(item.hidden);
        return callback(new Proxy(tx, {get(transaction, field) {
          if (field === "set" && attempts === 1) return () => {
            const error = new Error("Injected retryable transaction conflict");
            error.code = 10;
            throw error;
          };
          const value = transaction[field];
          return typeof value === "function" ? value.bind(transaction) : value;
        }}));
      });
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    }});
    try {
      await source.set(item.publicData);
      const stalePublic = await source.get();
      await item.factory({firestore: () => proxy}).run({params: {[item.param]: id}, data: {after: stalePublic}});
      assert.equal(attempts, 2);
      assert.equal((await mirror.get()).exists, false);
    } finally {
      await Promise.all([source.delete(), mirror.delete()]);
    }
  });
}
