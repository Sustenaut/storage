// Named heads, with the bucket's conditional writes as R2 does them and tokens
// from a key made for the tests.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle } from "../src/storage.js";
import { forgetKeys, AUDIENCE } from "../src/jwt.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };

const ISSUER = "https://token.actions.githubusercontent.com";
const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const key = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const jwk = { ...(await crypto.subtle.exportKey("jwk", key.publicKey)), kid: "k1", use: "sig" };
const b64url = (bytes) => Buffer.from(bytes).toString("base64url");

async function token(repository, ref = "refs/heads/main") {
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "k1" }));
  const p = b64url(JSON.stringify({ iss: ISSUER, aud: AUDIENCE, repository, ref, iat: now, nbf: now - 5, exp: now + 300 }));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}

function bucket() {
  const objects = new Map();
  let version = 0;
  const reading = (o) => o && { ...o, body: o.bytes, text: async () => (typeof o.bytes === "string" ? o.bytes : new TextDecoder().decode(o.bytes)) };
  return {
    objects,
    // Hooks a test uses to come between a read and a write.
    beforePut: null,
    async put(k, bytes, options = {}) {
      await this.beforePut?.(k);
      const had = objects.get(k);
      const { etagMatches, etagDoesNotMatch } = options.onlyIf || {};
      if (etagMatches && had?.etag !== etagMatches) return null;
      if (etagDoesNotMatch === "*" && had) return null;
      const o = { key: k, bytes, customMetadata: options.customMetadata || {}, etag: `v${++version}`, httpEtag: `"v${version}"`, uploaded: new Date(0) };
      objects.set(k, o);
      return o;
    },
    async get(k) {
      return reading(objects.get(k));
    },
    async list({ prefix, limit }) {
      const found = [...objects.values()].filter((o) => o.key.startsWith(prefix)).sort((a, b) => (a.key < b.key ? -1 : 1));
      return { objects: limit ? found.slice(0, limit) : found, truncated: false };
    },
    async delete() {},
  };
}

const WRITE = "Sustenaut/release";
const TENANTS = {
  snaps: { private: true, heads: true, read: ["github:Sustenaut/reader"], write: [`github:${WRITE}@refs/heads/main`], files: { types: ["json"], kept: true } },
  noheads: { private: true, read: [], write: [`github:${WRITE}@refs/heads/main`], files: { types: ["json"], kept: true } },
  open: { repository: "o/r", heads: true, write: [`github:${WRITE}@refs/heads/main`], files: { types: ["json"] } },
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

const request = async (path, { method = "GET", as = WRITE, ref, headers = {}, body } = {}) =>
  handle(
    new Request(`https://storage.example${path}`, {
      method,
      headers: { ...(as ? { Authorization: `Bearer ${await token(as, ref)}` } : {}), ...headers },
      body,
    }),
    env,
    TENANTS,
  );

async function store(text, name = "board.json", tenant = "snaps") {
  const form = new FormData();
  form.append("file", new Blob([text]), name);
  const r = await request(`/${tenant}/files`, { method: "POST", body: form });
  assert.equal(r.status, 200);
  return (await r.json()).id;
}

const move = (hash, headers, tenant = "snaps", extra = {}) =>
  request(`/${tenant}/head/board`, { method: "PUT", headers, body: JSON.stringify({ hash }), ...extra });
const first = { "If-None-Match": "*" };
const from = (hash) => ({ "If-Match": `"${hash}"` });

test("a head serves the file it points at, with its hash as the ETag, uncached", async () => {
  const hash = await store('{"a":1}');
  const moved = await move(hash, first);
  assert.equal(moved.status, 200);
  assert.equal(moved.headers.get("ETag"), `"${hash}"`);
  const r = await request("/snaps/head/board", { as: "Sustenaut/reader" });
  assert.equal(r.status, 200);
  assert.equal(await r.text(), '{"a":1}');
  assert.equal(r.headers.get("ETag"), `"${hash}"`);
  assert.equal(r.headers.get("Content-Type"), "application/json");
  assert.match(r.headers.get("Cache-Control"), /no-store/);
  assert.match(r.headers.get("Content-Security-Policy"), /sandbox/);
});

test("HEAD gives the hash without the file", async () => {
  const hash = await store("{}");
  await move(hash, first);
  const r = await request("/snaps/head/board", { method: "HEAD" });
  assert.equal(r.headers.get("ETag"), `"${hash}"`);
  assert.equal(await r.text(), "");
});

test("a head that has never moved is not found, and takes only If-None-Match: *", async () => {
  const hash = await store("{}");
  assert.equal((await request("/snaps/head/board")).status, 404);
  assert.equal((await request("/snaps/head/board/log")).status, 404);
  assert.equal((await move(hash, {})).status, 412);
  assert.equal((await move(hash, from(hash))).status, 412);
  assert.equal((await move(hash, first)).status, 200);
});

test("moving needs the current hash, and answers 412 otherwise", async () => {
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  const c = await store('{"c":1}');
  await move(a, first);
  assert.equal((await move(b, first)).status, 412);
  assert.equal((await move(b, {})).status, 412);
  assert.equal((await move(b, from(c))).status, 412);
  assert.equal((await move(b, from(a))).status, 200);
  assert.equal((await move(c, from(a))).status, 412, "a is no longer current");
  assert.equal((await request("/snaps/head/board")).headers.get("ETag"), `"${b}"`);
});

test("If-Match takes a bare or weak hash as well as a quoted one", async () => {
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  const c = await store('{"c":1}');
  await move(a, first);
  assert.equal((await move(b, { "If-Match": a })).status, 200);
  assert.equal((await move(c, { "If-Match": `W/"${b}"` })).status, 200);
});

test("of two moves from the same place, only one wins", async () => {
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  const c = await store('{"c":1}');
  await move(a, first);
  // The other writer gets in after this one has read the head.
  let racing = false;
  env.STORAGE.beforePut = async (key) => {
    if (racing || !key.endsWith("/h/board")) return;
    racing = true;
    assert.equal((await move(c, from(a))).status, 200);
  };
  assert.equal((await move(b, from(a))).status, 412);
  assert.equal((await request("/snaps/head/board")).headers.get("ETag"), `"${c}"`);
});

test("two first moves at once: only one wins", async () => {
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  let racing = false;
  env.STORAGE.beforePut = async (key) => {
    if (racing || !key.endsWith("/h/board")) return;
    racing = true;
    assert.equal((await move(b, first)).status, 200);
  };
  assert.equal((await move(a, first)).status, 412);
  assert.equal((await request("/snaps/head/board")).headers.get("ETag"), `"${b}"`);
});

test("the log lists every place, newest first, with time and principal", async (t) => {
  t.mock.timers.enable({ apis: ["Date"], now: Date.parse("2026-10-30T10:00:00Z") });
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  await move(a, first);
  t.mock.timers.tick(60_000);
  await move(b, from(a));
  t.mock.timers.tick(60_000);
  await move(a, from(b));
  const r = await request("/snaps/head/board/log", { as: "Sustenaut/reader" });
  assert.equal(r.status, 200);
  assert.match(r.headers.get("Cache-Control"), /no-store/);
  const principal = `github:${WRITE}@refs/heads/main`;
  assert.deepEqual(await r.json(), {
    name: "board",
    log: [
      { hash: a, time: "2026-10-30T10:02:00.000Z", principal },
      { hash: b, time: "2026-10-30T10:01:00.000Z", principal },
      { hash: a, time: "2026-10-30T10:00:00.000Z", principal },
    ],
  });
});

test("a move that fails loses nothing and adds nothing false to the log", async () => {
  const a = await store('{"a":1}');
  const b = await store('{"b":1}');
  await move(a, first);
  const real = env.STORAGE.put;
  env.STORAGE.put = async function (key, ...rest) {
    if (key.endsWith("/h/board")) throw new Error("the bucket is down");
    return real.call(this, key, ...rest);
  };
  assert.equal((await move(b, from(a))).status, 500);
  env.STORAGE.put = real;
  const { log } = await (await request("/snaps/head/board/log")).json();
  assert.deepEqual(log.map((e) => e.hash), [a]);
  assert.equal((await move(b, from(a))).status, 200);
  const after = await (await request("/snaps/head/board/log")).json();
  assert.deepEqual(after.log.map((e) => e.hash), [b, a]);
});

test("moving to where it already points changes nothing", async () => {
  const a = await store("{}");
  await move(a, first);
  assert.equal((await move(a, from(a))).status, 200);
  const { log } = await (await request("/snaps/head/board/log")).json();
  assert.equal(log.length, 1);
});

test("a head can only point at a stored file", async () => {
  assert.equal((await move("0".repeat(64), first)).status, 404);
  for (const body of ["{}", "not json", "null", '{"hash":"../x"}', '{"hash":1}']) {
    const r = await request("/snaps/head/board", { method: "PUT", headers: first, body });
    assert.equal(r.status, 400, body);
  }
  assert.equal((await request("/snaps/head/board")).status, 404);
});

test("each name is its own head", async () => {
  const a = await store('{"a":1}');
  await move(a, first);
  assert.equal((await request("/snaps/head/other")).status, 404);
  assert.equal((await request("/snaps/head/Bad%20Name")).status, 404);
  assert.equal((await request("/snaps/head/board/log/x")).status, 404);
  assert.equal((await request("/snaps/head/board/log", { method: "PUT", headers: first, body: "{}" })).status, 404);
});

test("only the write list moves a head, and only readers read one", async () => {
  const a = await store("{}");
  assert.equal((await move(a, first, "snaps", { as: "Sustenaut/reader" })).status, 403);
  assert.equal((await move(a, first, "snaps", { ref: "refs/heads/other" })).status, 403);
  assert.equal((await move(a, first, "snaps", { as: null })).status, 401);
  await move(a, first);
  assert.equal((await request("/snaps/head/board", { as: "Sustenaut/stranger" })).status, 403);
  assert.equal((await request("/snaps/head/board", { as: null })).status, 401);
  assert.equal((await request("/snaps/head/board/log", { as: "Sustenaut/stranger" })).status, 403);
});

test("a tenant without heads, or a public one, has none", async () => {
  const hash = await store("{}", "board.json", "noheads");
  assert.equal((await move(hash, first, "noheads")).status, 404);
  assert.equal((await request("/noheads/head/board")).status, 404);
  assert.equal((await move(hash, first, "open")).status, 404);
  assert.equal((await request("/open/head/board", { as: null })).status, 404);
});

test("the release tenants: private, json, kept, written by Sustenaut/release's main, read by the app", () => {
  for (const name of ["release-sustenaut", "release-schryer"]) {
    const t = REAL_TENANTS[name];
    assert.equal(t.private, true);
    assert.equal(t.heads, true);
    assert.deepEqual(t.write, ["github:Sustenaut/release@refs/heads/main"]);
    assert.deepEqual(t.read, ["k8s:release/app"]);
    assert.deepEqual(t.files.types, ["json"]);
    assert.equal(t.files.kept, true);
    assert.equal(t.repository, undefined);
  }
});
