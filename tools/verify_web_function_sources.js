"use strict";

// Read-only verification of every deployed Gen2 source generation. An ACTIVE
// function can still contain an earlier release after a partial CLI failure.
const {execFileSync} = require("node:child_process");
const {digest, sha256, PROJECTS, relativeFile} = require("./web_release_contract");
const {googleClient, pages} = require("./web_release_state");
const MAX_ARCHIVE = 32 * 1024 * 1024;
const NUMBERS = {"attendus-staging": "925344893088", "orgami-66nxok": "951311475019"};
const ZIP_HASHES = `import sys,io,zipfile,json,hashlib,stat
with zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read())) as z:
 entries=z.infolist(); assert 0<len(entries)<=5000, 'archive entry limit'
 assert sum(i.file_size for i in entries)<=128*1024*1024, 'archive content limit'
 seen=set(); result={}
 for i in entries:
  n=i.filename; assert i.orig_filename==n, 'normalized archive path'; parts=n.rstrip('/').split('/')
  assert n and not n.startswith('/') and chr(92) not in n and ':' not in n and chr(0) not in n, 'unsafe archive path'
  assert all(p not in ('','.','..') and not p.endswith((' ','.')) for p in parts), 'unsafe archive path'
  assert n.casefold() not in seen, 'duplicate archive path'
  seen.add(n.casefold()); assert not stat.S_ISLNK(i.external_attr>>16) and not i.flag_bits&1, 'unsupported archive entry'
  if not i.is_dir(): result[n]=hashlib.sha256(z.read(i)).hexdigest()
 print(json.dumps(result))`;
function archiveManifest(bytes) {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_ARCHIVE) throw Error("Function source archive exceeds bounds");
  try {
    return JSON.parse(execFileSync(process.platform === "win32" ? "python" : "python3", ["-c", ZIP_HASHES],
        {input: bytes, maxBuffer: 4 * 1024 * 1024, stdio: ["pipe", "pipe", "pipe"]}));
  } catch (_) { throw Error("Function source archive is invalid or unsafe"); }
}
function expectedFiles(candidate) {
  const expected = {};
  for (const [name, hash] of Object.entries(candidate.sourceFiles || {})) {
    if (!name.startsWith("functions/")) continue;
    if (!/^[a-f0-9]{64}$/.test(hash)) throw Error("Invalid candidate source hash");
    expected[relativeFile(name.slice(10))] = hash;
  }
  if (!expected["index.js"] || !expected["package-lock.json"]) throw Error("Candidate backend source manifest is incomplete");
  return expected;
}
function sourceIdentity(source, projectId, id) {
  if (source?.bucket !== `gcf-v2-sources-${NUMBERS[projectId]}-us-central1` || source.object !== `${id}/function-source.zip` || !/^[1-9][0-9]*$/.test(String(source.generation || ""))) throw Error("Function source is outside its exact project/function generation");
  return {bucket: source.bucket, object: source.object, generation: String(source.generation)};
}
function inventory(candidate, state) {
  if (!Object.values(PROJECTS).includes(candidate.projectId) || PROJECTS[candidate.environment] !== candidate.projectId || state.projectId !== candidate.projectId) throw Error("Function verification project differs");
  const wanted = candidate.deployment.functions;
  const rows = state.functionSources || [];
  const result = rows.map((fn) => {
    const id = fn.name?.split("/").at(-1);
    if (!wanted.includes(id) || fn.environment !== "GEN_2" || fn.name !== `projects/${candidate.projectId}/locations/us-central1/functions/${id}`) throw Error("Unexpected function source inventory");
    return {name: fn.name, id, source: sourceIdentity(fn.source, candidate.projectId, id)};
  }).sort((a, b) => a.name.localeCompare(b.name));
  if (digest(result.map((fn) => fn.id).sort()) !== digest([...wanted].sort()) || new Set(result.map((fn) => fn.name)).size !== result.length) throw Error("Incomplete or duplicate function source inventory");
  return result;
}
async function verifyFunctionSources({candidate, state, client = null, inspectArchive = archiveManifest}) {
  const startedAt = new Date().toISOString(), expected = expectedFiles(candidate), original = inventory(candidate, state);
  client ||= await googleClient();
  const queue = [...original], verified = [], inspected = new Map();
  await Promise.all(Array.from({length: 4}, async () => {
    while (queue.length) {
      const fn = queue.shift(), source = fn.source;
      const url = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(source.bucket)}/o/${encodeURIComponent(source.object)}`;
      const metadata = (await client.request({url, params: {generation: source.generation}})).data;
      if (String(metadata.generation) !== source.generation || metadata.bucket !== source.bucket || metadata.name !== source.object || !Number.isSafeInteger(Number(metadata.size)) || Number(metadata.size) <= 0 || Number(metadata.size) > MAX_ARCHIVE) throw Error("Function source metadata differs");
      const bytes = Buffer.from((await client.request({url, params: {generation: source.generation, alt: "media"}, responseType: "arraybuffer"})).data);
      if (bytes.length !== Number(metadata.size)) throw Error("Function source byte count differs");
      const hash = sha256(bytes);
      if (!inspected.has(hash)) {
        const files = inspectArchive(bytes);
        if (digest(files) !== digest(expected)) throw Error(`Deployed function source differs from frozen candidate: ${fn.id}`);
        inspected.set(hash, Object.keys(files).length);
      }
      verified.push({...fn, sha256: hash, bytes: bytes.length, fileCount: inspected.get(hash)});
    }
  }));
  // Reject deployment drift during the byte reads without retaining environment
  // values, secret references, or archive contents in the published receipt.
  const live = await pages(client, `https://cloudfunctions.googleapis.com/v2/projects/${candidate.projectId}/locations/us-central1/functions`, "functions",
      {pageSize: 1000, fields: "functions(name,environment,state,buildConfig(source,sourceProvenance)),nextPageToken,unreachable"});
  if (live.some((fn) => fn.state !== "ACTIVE")) throw Error("Functions changed state during source verification");
  const fresh = inventory(candidate, {projectId: candidate.projectId, functionSources: live.map((fn) => ({name: fn.name, environment: fn.environment,
    source: fn.buildConfig?.sourceProvenance?.resolvedStorageSource || fn.buildConfig?.source?.storageSource}))});
  if (digest(fresh) !== digest(original)) throw Error("Function sources changed during byte verification");
  return {schemaVersion: 1, projectId: candidate.projectId, sourceSha: candidate.sourceSha, candidateRunId: candidate.candidateRunId,
    candidateSha256: digest(candidate), startedAt, verifiedAt: new Date().toISOString(), sourceFilesSha256: digest(expected),
    functions: verified.sort((a, b) => a.name.localeCompare(b.name)), uniqueArchives: inspected.size};
}
module.exports = {archiveManifest, expectedFiles, sourceIdentity, inventory, verifyFunctionSources};
