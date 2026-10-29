// Private tenants and OpenID Connect tokens (src/jwt.js), with GitHub's
// OIDC issuer and its key set answered here, from a key made for the tests.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, clean } from "../src/storage.js";
import { verify, allowed, isJwt, forgetKeys, AUDIENCE } from "../src/jwt.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };

const ISSUER = "https://token.actions.githubusercontent.com";
const JWKS = `${ISSUER}/.well-known/jwks`;
const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const issuerKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const otherKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const publicJwk = { ...(await crypto.subtle.exportKey("jwk", issuerKey.publicKey)), kid: "k1", use: "sig" };

const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
const now = () => Math.floor(Date.now() / 1000);

// A GitHub Actions token for a repository and ref, with any claim overridden.
async function token(repository, ref = "refs/heads/main", { claims = {}, header = {}, key = issuerKey.privateKey } = {}) {
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "k1", ...header }));
  const body = { iss: ISSUER, aud: AUDIENCE, repository, ref, iat: now(), nbf: now() - 5, exp: now() + 300, ...claims };
  const p = b64url(JSON.stringify(body));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}

function bucket() {
  const objects = new Map();
  return {
    objects,
    async put(key, bytes, options) {
      objects.set(key, { key, bytes, customMetadata: options?.customMetadata || {}, httpEtag: '"e"', uploaded: new Date(0) });
    },
    async get(key) {
      const o = objects.get(key);
      return o && { ...o, body: o.bytes };
    },
    async list({ prefix }) {
      return { objects: [...objects.values()].filter((o) => o.key.startsWith(prefix)), truncated: false };
    },
    async delete(keys) {
      for (const k of keys) objects.delete(k);
    },
  };
}

const TENANTS = {
  publications: REAL_TENANTS.publications,
  // A public tenant that also takes a workflow's uploads.
  photos: { repository: "schryer/visit-ee", origins: [], write: ["github:schryer/visit-ee@refs/heads/main"], files: { types: ["pdf"] } },
  // A public tenant that takes only GitHub tokens.
  plain: { repository: "schryer/visit-ee", origins: [], files: { types: ["pdf"] } },
};
const call = (request) => handle(request, env, TENANTS);
const gz = () => new Uint8Array([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, 1, 2, 3]);
const pdf = () => new TextEncoder().encode("%PDF-1.7 a paper");

let env, realFetch, realCaches, fetches, cached;
beforeEach(() => {
  env = { STORAGE: bucket() };
  forgetKeys();
  fetches = [];
  cached = [];
  realFetch = globalThis.fetch;
  realCaches = globalThis.caches;
  globalThis.caches = {
    default: {
      match: async (request) => (cached.push(["match", request.url]), undefined),
      put: async (request) => cached.push(["put", request.url]),
    },
  };
  globalThis.fetch = async (url, options = {}) => {
    url = String(url);
    fetches.push(url);
    if (url === JWKS) return Response.json({ keys: [publicJwk] });
    if (url === "https://api.github.com/repos/schryer/visit-ee") {
      if (options.headers.Authorization !== "Bearer good") return new Response("{}", { status: 401 });
      return Response.json({ permissions: { push: true } });
    }
    if (url === "https://api.github.com/user") return Response.json({ login: "schryer" });
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
  globalThis.caches = realCaches;
});

function put(tenant, bearer, name, bytes) {
  const form = new FormData();
  form.append("file", new Blob([bytes]), name);
  return call(new Request(`https://storage.example/${tenant}/files`, { method: "POST", body: form, headers: { Authorization: `Bearer ${bearer}` } }));
}
const get = (path, bearer, method = "GET") =>
  call(new Request(`https://storage.example${path}`, { method, headers: bearer ? { Authorization: `Bearer ${bearer}` } : {} }));

const BP_MAIN = () => token("schryer/business-plan");
const PUB_SITE = (ref) => token("Sustenaut/pub-site", ref);

test("the publications tenant is private: business-plan's main writes it, pub-site reads it, kept", () => {
  const t = REAL_TENANTS.publications;
  assert.equal(t.private, true);
  assert.deepEqual(t.write, ["github:schryer/business-plan@refs/heads/main"]);
  assert.deepEqual(t.read, ["github:Sustenaut/pub-site"]);
  assert.deepEqual(t.files.types, ["gz"]);
  assert.equal(t.files.kept, true);
  assert.equal(t.in_use, undefined);
  assert.equal(t.repository, undefined, "no GitHub token can write it");
});

test("a workflow's token writes a private file, and a reader gets it, never cached or shared", async () => {
  const response = await put("publications", await BP_MAIN(), "publication-0-objects.tar.gz", gz());
  assert.equal(response.status, 200);
  const file = await response.json();
  assert.equal(file.kept, true);
  assert.match(file.url, /^\/publications\/f\/[0-9a-f]{64}\/publication-0-objects\.tar\.gz$/);
  const stored = env.STORAGE.objects.get(file.url.slice(1));
  assert.equal(stored.customMetadata.by, "github:schryer/business-plan@refs/heads/main");

  for (const method of ["GET", "HEAD"]) {
    const read = await get(file.url, await PUB_SITE("refs/pull/3/merge"), method);
    assert.equal(read.status, 200, method);
    assert.equal(read.headers.get("Content-Type"), "application/gzip");
    assert.equal(read.headers.get("Cache-Control"), "private, no-store");
    assert.equal(read.headers.get("Access-Control-Allow-Origin"), null);
    assert.match(read.headers.get("Vary"), /Authorization/);
    if (method === "GET") assert.deepEqual(new Uint8Array(await read.arrayBuffer()), gz());
  }
  // A writer may read what it wrote.
  assert.equal((await get(file.url, await BP_MAIN())).status, 200);
  assert.deepEqual(cached, [], "the Cache API is never asked");
});

test("a private file is refused without a token of a principal on its lists, before anything is looked up", async () => {
  const { url } = await (await put("publications", await BP_MAIN(), "p.tar.gz", gz())).json();
  assert.equal((await get(url)).status, 401);
  assert.equal((await get(url, "ghp_aPersonalToken")).status, 401, "GitHub tokens aren't taken");
  assert.equal((await get(url, await token("schryer/visit-ee"))).status, 403);
  assert.equal((await get(url, await token("Sustenaut/pub-site-fork"))).status, 403, "a name is matched whole");
  assert.equal((await get("/publications/f/" + "0".repeat(64) + "/x.tar.gz")).status, 401, "no token learns nothing, even of what isn't there");
  assert.equal((await get("/publications/f/" + "0".repeat(64) + "/x.tar.gz", await PUB_SITE())).status, 404);
});

test("only the writers' principals, at their ref, write a private tenant; GitHub tokens never do", async () => {
  assert.equal((await put("publications", await PUB_SITE(), "p.tar.gz", gz())).status, 403, "a reader can't write");
  assert.equal((await put("publications", await token("schryer/business-plan", "refs/heads/feature"), "p.tar.gz", gz())).status, 403, "only main");
  assert.equal((await put("publications", await token("schryer/business-plan", "refs/pull/9/merge"), "p.tar.gz", gz())).status, 403);
  assert.equal((await put("publications", "good", "p.tar.gz", gz())).status, 401);
  assert.equal((await put("publications", "ghs_app", "p.tar.gz", gz())).status, 401);
  assert.equal((await put("publications", await BP_MAIN(), "p.pdf", pdf())).status, 415);
  assert.equal((await put("publications", await BP_MAIN(), "p.tar.gz", pdf())).status, 400, "a .gz must be gzip");
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a public tenant takes a workflow's token when its write list names it, and GitHub tokens as before", async () => {
  assert.equal((await put("photos", await token("schryer/visit-ee"), "a.pdf", pdf())).status, 200);
  assert.equal((await put("photos", await token("schryer/visit-ee", "refs/heads/x"), "a.pdf", pdf())).status, 403);
  assert.equal((await put("plain", await token("schryer/visit-ee"), "a.pdf", pdf())).status, 403, "no write list, no tokens");
  assert.equal((await put("plain", "good", "a.pdf", pdf())).status, 200);
  const { url } = await (await put("photos", "good", "b.pdf", pdf())).json();
  const read = await get(url);
  assert.equal(read.status, 200, "public files need no token");
  assert.equal(read.headers.get("Access-Control-Allow-Origin"), "*");
  assert.match(read.headers.get("Cache-Control"), /public/);
});

test("tokens are refused unless RS256, from a trusted issuer, signed by its key, for this audience and in date", async () => {
  const repo = "schryer/business-plan";
  const refused = async (t) => assert.rejects(verify(t), (err) => err.status === 401);
  assert.equal(await verify(await token(repo)), "github:schryer/business-plan@refs/heads/main");
  await refused(await token(repo, "refs/heads/main", { claims: { aud: "sts.amazonaws.com" } }));
  await refused(await token(repo, "refs/heads/main", { claims: { aud: undefined } }));
  await refused(await token(repo, "refs/heads/main", { claims: { exp: now() - 120 } }));
  await refused(await token(repo, "refs/heads/main", { claims: { exp: undefined } }));
  await refused(await token(repo, "refs/heads/main", { claims: { nbf: now() + 600 } }));
  await refused(await token(repo, "refs/heads/main", { claims: { iss: "https://token.actions.example" } }));
  await refused(await token(repo, "refs/heads/main", { claims: { iss: "__proto__" } }));
  await refused(await token(repo, "refs/heads/main", { key: otherKey.privateKey }));
  await refused(await token(repo, "refs/heads/main", { header: { alg: "HS256" } }));
  await refused(await token(repo, "refs/heads/main", { header: { kid: "k2" } }));
  await refused(await token(repo, "refs/heads/main", { claims: { repository: undefined } }));
  const [h, p] = (await token(repo)).split(".");
  await refused(`${b64url(JSON.stringify({ alg: "none" }))}.${p}.`);
  await refused(`${h}.${b64url(JSON.stringify({ iss: ISSUER, aud: AUDIENCE, repository: "Sustenaut/pub-site", ref: "refs/heads/main", exp: now() + 60 }))}.${(await token(repo)).split(".")[2]}`);
  await refused("not.a.token");
  // A minute of clock skew is allowed.
  assert.ok(await verify(await token(repo, "refs/heads/main", { claims: { exp: now() - 30 } })));
});

test("an audience list is taken when it includes this service", async () => {
  assert.ok(await verify(await token("Sustenaut/pub-site", "refs/heads/main", { claims: { aud: ["other", AUDIENCE] } })));
});

test("the issuer's keys are fetched once, then again only when old or for a key they lack", async () => {
  const t = await PUB_SITE();
  await verify(t);
  await verify(t);
  assert.equal(fetches.filter((u) => u === JWKS).length, 1);
  const unknown = await token("Sustenaut/pub-site", "refs/heads/main", { header: { kid: "new" } });
  await assert.rejects(verify(unknown));
  assert.equal(fetches.filter((u) => u === JWKS).length, 1, "an unknown key doesn't ask again within a minute");
  await assert.rejects(verify(unknown, { now: Date.now() + 2 * 60e3 }));
  assert.equal(fetches.filter((u) => u === JWKS).length, 2, "but does after it");
  await verify(t, { now: Date.now() + 13 * 60e3 }).catch(() => {});
  assert.equal(fetches.filter((u) => u === JWKS).length, 3, "and after ten minutes");
});

test("a principal matches a list entry by repository without case, and by ref when the entry names one", () => {
  const p = "github:Sustenaut/pub-site@refs/heads/main";
  assert.ok(allowed(p, ["github:Sustenaut/pub-site"]));
  assert.ok(allowed(p, ["github:sustenaut/PUB-SITE@refs/heads/main"]));
  assert.ok(!allowed(p, ["github:Sustenaut/pub-site@refs/heads/Main"]));
  assert.ok(!allowed(p, ["github:Sustenaut/pub"]));
  assert.ok(!allowed(p, ["auth:Sustenaut/pub-site"]));
  assert.ok(!allowed(p, []));
  assert.ok(!allowed(p, undefined));
});

test("GitHub tokens aren't taken for JWTs", () => {
  for (const t of ["ghp_abc", "ghs_abc", "github_pat_11AB_cd", "gho_x", "good"]) assert.ok(!isJwt(t), t);
  assert.ok(isJwt("eyJh.eyJi.c2ln"));
});

test("the clean-up leaves a private tenant alone", async () => {
  await put("publications", await BP_MAIN(), "p.tar.gz", gz());
  env.STORAGE.objects.get([...env.STORAGE.objects.keys()][0]).customMetadata.kept = "false";
  const report = await clean(env, { publications: { ...TENANTS.publications, in_use: "https://example/in-use.json" } }, Date.now() + 365 * 86400e3);
  assert.deepEqual(report.publications, { skipped: "private: nothing is cleaned" });
  assert.equal(env.STORAGE.objects.size, 1);
});
