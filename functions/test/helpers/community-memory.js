"use strict";
// Buffered serial transactions expose read-after-write mistakes and discard all
// pending mutations on failure. Emulator cases separately verify real conflicts.
function memoryAdmin(initial = {}) {
  const values = new Map(Object.entries(initial));
  let queue = Promise.resolve();
  const clone = (value) => {
    if (value instanceof Date) return new Date(value);
    if (Array.isArray(value)) return value.map(clone);
    if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)]));
    return value;
  };
  const snapshot = (ref) => ({ref, id: ref.id, exists: values.has(ref.path),
    data: () => clone(values.get(ref.path)), get: (field) => clone(values.get(ref.path)?.[field])});
  function document(path) {
    return {path, id: path.split("/").pop(), collection: (name) => collection(`${path}/${name}`),
      get: async () => snapshot(document(path))};
  }
  function collection(path, filters = [], max = Infinity, after = null, group = false, order = "__name__") {
    const query = {path, doc: (id) => document(`${path}/${id}`),
      where: (field, operator, value) => collection(path, [...filters, [field, operator, value]], max, after, group, order),
      limit: (n) => collection(path, filters, n, after, group, order),
      orderBy: (field) => collection(path, filters, max, after, group, field),
      startAfter: (cursor) => collection(path, filters, max, cursor.ref.path, group, order),
      get: async () => {
        const docs = [...values.keys()].filter((key) => group ? key.split("/").at(-2) === path : key.startsWith(`${path}/`) && key.split("/").length === path.split("/").length + 1)
            .sort().map((key) => snapshot(document(key)))
            .filter((doc) => (!after || doc.ref.path > after) && (order === "__name__" || doc.get(order) !== undefined) &&
              filters.every(([field, operator, value]) => operator === "in" ? value.includes(doc.get(field)) :
                operator === "array-contains" ? (doc.get(field) || []).includes(value) :
                  operator === "<=" ? doc.get(field) !== undefined && doc.get(field) <= value :
                    operator === ">=" ? doc.get(field) !== undefined && doc.get(field) >= value : doc.get(field) === value))
            .sort((left, right) => order === "__name__" ? left.ref.path.localeCompare(right.ref.path) : Number(left.get(order)) - Number(right.get(order))).slice(0, max);
        return {docs, size: docs.length, empty: !docs.length};
      }};
    return query;
  }
  const db = {collection, collectionGroup: (name) => collection(name, [], Infinity, null, true), doc: document, values, runTransaction: (callback) => {
    const run = queue.then(async () => {
      const pending = [];
      const tx = {get: async (ref) => {
        if (pending.length) throw Error("Read after write");
        return ref.get();
      }};
      for (const operation of ["create", "set", "update", "delete"]) tx[operation] = (ref, data, options) => pending.push({operation, ref, data, options});
      const result = await callback(tx);
      const next = new Map(values);
      for (const {operation, ref, data, options} of pending) {
        if (operation === "create" && next.has(ref.path)) throw Error("Already exists");
        if (operation === "update" && !next.has(ref.path)) throw Error("Missing document");
        if (operation === "delete") next.delete(ref.path);
        else next.set(ref.path, clone(options?.merge || operation === "update" ? {...next.get(ref.path), ...data} : data));
      }
      values.clear(); for (const [key, value] of next) values.set(key, value);
      return result;
    });
    queue = run.catch(() => {});
    return run;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => new Date()};
  firestore.Timestamp = {fromDate: (value) => value, fromMillis: (value) => new Date(value)};
  firestore.FieldPath = {documentId: () => "__name__"};
  return {firestore, db};
}
module.exports = {memoryAdmin};
