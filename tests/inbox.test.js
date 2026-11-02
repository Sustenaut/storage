// Buffers: files in folders, listed and deleted, with tokens from a key made for the tests.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle } from "../src/storage.js";
import { forgetKeys, AUDIENCE } from "../src/jwt.js";

const ISSUER = "https://token.actions.githubusercontent.com";
const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const key = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const jwk = { ...(await crypto.subtle.exportKey("jwk", key.publicKey)), kid: "k1", use: "sig" };
const b64url = (bytes) => Buffer.from(bytes).toString("base64url");

async function token(repository) {
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "k1" }));
  const p = b64url(JSON.stringify({ iss: ISSUER, aud: AUDIENCE, repository, ref: "refs/heads/main", iat: now, nbf: now, exp: now + 300 }));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}

// As R2 lists: in key order, a page at a time, with a cursor.
function bucket() {
  const objects = new Map();
  return {
    objects,
    async put(k, bytes) {
      objects.set(k, { key: k, bytes, size: bytes.length, uploaded: new Date(0) });
    },
    async get(k) {
      const o = objects.get(k);
      return o && { ...o, body: o.bytes };
    },
    async delete(k) {
      objects.delete(k);
    },
    async list({ prefix, limit = 1000, cursor }) {
      const found = [...objects.values()].filter((o) => o.key.startsWith(prefix)).sort((a, b) => (a.key < b.key ? -1 : 1));
      const start = cursor ? Number(cursor) : 0;
      const end = start + limit;
      return { objects: found.slice(start, end), truncated: end < found.length, cursor: String(end) };
    },
  };
}

const SENDER = "github:Sustenaut/sender@refs/heads/main";
const INGEST = "github:Sustenaut/ingest@refs/heads/main";
const TENANTS = {
  calls: { private: true, inbox: true, read: ["github:Sustenaut/reader@refs/heads/main"], write: [SENDER, INGEST], delete: [INGEST] },
  other: { private: true, inbox: true, read: [], write: ["github:Sustenaut/stranger@refs/heads/main"], delete: [] },
  plain: { private: true, read: [], write: [SENDER] },
  open: { inbox: true, repository: "o/r", write: [SENDER] },
};

let env, realFetch;
beforeEach(() => {
  env = { STORAGE: bucket() };
  forgetKeys();
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    if (String(url) === `${ISSUER}/.well-known/jwks`) return Response.json({ keys: [jwk] });
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

const request = async (path, { method = "GET", as = "Sustenaut/sender", body } = {}) =>
  handle(new Request(`https://storage.example${path}`, {
    method,
    headers: as ? { Authorization: `Bearer ${await token(as)}` } : {},
    body,
  }), env, TENANTS);

const AVRO = new Uint8Array([0x4f, 0x62, 0x6a, 0x01, 0x07]);
const FILE = "/calls/inbox/calls/2026-11-02/171800-web-abc.avro";

test("a sender stores a file, and it can be read back, uncached", async () => {
  const stored = await request(FILE, { method: "PUT", body: AVRO });
  assert.equal(stored.status, 200);
  assert.deepEqual(await stored.json(), { name: "inbox/calls/2026-11-02/171800-web-abc.avro", size: 5 });
  const got = await request(FILE, { as: "Sustenaut/reader" });
  assert.equal(got.status, 200);
  assert.equal(got.headers.get("Content-Type"), "application/avro");
  assert.equal(got.headers.get("Cache-Control"), "private, no-store");
  assert.deepEqual(new Uint8Array(await got.arrayBuffer()), AVRO);
  assert.equal((await request(FILE, { method: "HEAD", as: "Sustenaut/reader" })).status, 200);
  assert.equal((await request("/calls/inbox/calls/none.avro", { as: "Sustenaut/reader" })).status, 404);
});

test("sending a name again replaces the file, so a retry is safe", async () => {
  await request(FILE, { method: "PUT", body: AVRO });
  assert.equal((await request(FILE, { method: "PUT", body: AVRO })).status, 200);
  assert.equal(env.STORAGE.objects.size, 1);
});

test("a file must be what its folder holds", async () => {
  assert.equal((await request(FILE, { method: "PUT", body: "not avro" })).status, 400);
  assert.equal((await request("/calls/batches/job.json", { method: "PUT", body: "{not json" })).status, 400);
  assert.equal((await request("/calls/batches/job.json", { method: "PUT", body: '{"files":[]}' })).status, 200);
  assert.equal((await request("/calls/rejected/calls/a.avro", { method: "PUT", body: AVRO })).status, 200);
});

test("a name outside the folders, or a way out of them, isn't a buffer's", async () => {
  for (const path of ["/calls/inbox/a.json", "/calls/batches/a.avro", "/calls/other/a.avro", "/calls/inbox/../a.avro", "/calls/inbox/.hidden/a.avro"]) {
    const answer = await request(path, { method: "PUT", body: AVRO });
    assert.notEqual(answer.status, 200, path);
  }
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a file over the limit is refused", async () => {
  const big = new Uint8Array(50 * 1024 * 1024 + 1);
  big.set(AVRO);
  assert.equal((await request(FILE, { method: "PUT", body: big })).status, 413);
});

test("listing gives the oldest name first, a page at a time", async () => {
  for (const n of ["171800-b", "171600-a", "172000-c"]) {
    await request(`/calls/inbox/calls/2026-11-02/${n}.avro`, { method: "PUT", body: AVRO });
  }
  await request("/calls/rejected/calls/x.avro", { method: "PUT", body: AVRO });
  const first = await (await request("/calls/list?prefix=inbox/&limit=2", { as: "Sustenaut/reader" })).json();
  assert.deepEqual(first.files.map((f) => f.name), ["inbox/calls/2026-11-02/171600-a.avro", "inbox/calls/2026-11-02/171800-b.avro"]);
  assert.equal(first.files[0].size, 5);
  assert.ok(first.cursor);
  const next = await (await request(`/calls/list?prefix=inbox/&limit=2&cursor=${first.cursor}`, { as: "Sustenaut/reader" })).json();
  assert.deepEqual(next.files.map((f) => f.name), ["inbox/calls/2026-11-02/172000-c.avro"]);
  assert.equal(next.cursor, null);
});

test("a listing is only of a buffer's folders, with a sensible limit", async () => {
  for (const q of ["prefix=f/", "prefix=", "prefix=inbox/../", "prefix=inbox/&limit=0", "prefix=inbox/&limit=1001", "prefix=inbox/&limit=x"]) {
    assert.equal((await request(`/calls/list?${q}`, { as: "Sustenaut/reader" })).status, 400, q);
  }
});

test("only the delete list may delete, and writing isn't enough", async () => {
  await request(FILE, { method: "PUT", body: AVRO });
  assert.equal((await request(FILE, { method: "DELETE" })).status, 403);
  assert.equal((await request(FILE, { method: "DELETE", as: "Sustenaut/reader" })).status, 403);
  assert.equal(env.STORAGE.objects.size, 1);
  assert.equal((await request(FILE, { method: "DELETE", as: "Sustenaut/ingest" })).status, 204);
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a person's token can't delete, and no token can't do anything", async () => {
  await request(FILE, { method: "PUT", body: AVRO });
  const withGithubToken = await handle(new Request(`https://storage.example${FILE}`, { method: "DELETE", headers: { Authorization: "Bearer ghp_x" } }), env, TENANTS);
  assert.equal(withGithubToken.status, 401);
  for (const method of ["GET", "PUT", "DELETE"]) {
    assert.equal((await request(FILE, { method, as: null, body: method === "PUT" ? AVRO : undefined })).status, 401, method);
  }
  assert.equal((await request("/calls/list?prefix=inbox/", { as: null })).status, 401);
});

test("one project's writers can't reach another's buffer", async () => {
  await request(FILE, { method: "PUT", body: AVRO });
  const stranger = "Sustenaut/stranger";
  assert.equal((await request(FILE, { as: stranger })).status, 403);
  assert.equal((await request(FILE, { method: "PUT", as: stranger, body: AVRO })).status, 403);
  assert.equal((await request(FILE, { method: "DELETE", as: stranger })).status, 403);
  assert.equal((await request("/calls/list?prefix=inbox/", { as: stranger })).status, 403);
  assert.equal((await request("/other/inbox/a.avro", { method: "PUT", body: AVRO })).status, 403);
});

test("a tenant without a buffer, or a public one, has none of this", async () => {
  assert.equal((await request("/plain/inbox/a.avro", { method: "PUT", body: AVRO })).status, 404);
  assert.equal((await request("/open/inbox/a.avro", { method: "PUT", body: AVRO })).status, 404);
  assert.equal((await request("/open/list?prefix=inbox/")).status, 404);
});

test("other methods on a buffer's file aren't allowed", async () => {
  assert.equal((await request(FILE, { method: "POST", body: AVRO })).status, 405);
});
