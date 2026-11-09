// Terraform's provider network mirror (src/storage.js, providerIndex), from the
// archives a tenant with "providers" keeps, with GitHub's OIDC issuer answered here.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, byVersion } from "../src/storage.js";
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
  return {
    objects,
    async put(k, bytes, options) {
      objects.set(k, { key: k, bytes, customMetadata: options?.customMetadata || {}, httpEtag: '"e"', uploaded: new Date(0) });
    },
    async get(k) {
      const o = objects.get(k);
      return o && { ...o, body: o.bytes };
    },
    // Two objects a page, so the index reads every page.
    async list({ prefix, cursor }) {
      const all = [...objects.values()].filter((o) => o.key.startsWith(prefix));
      const at = Number(cursor || 0);
      return { objects: all.slice(at, at + 2), truncated: at + 2 < all.length, cursor: String(at + 2) };
    },
  };
}

const TENANTS = { terraform: REAL_TENANTS.terraform, wheels: REAL_TENANTS.wheels };
const ORIGIN = "https://storage.example";
const call = (request) => handle(request, env, TENANTS);
const zip = (n) => new Uint8Array([0x50, 0x4b, 0x03, 0x04, n]);
const sha = async (bytes) => Buffer.from(await crypto.subtle.digest("SHA-256", bytes)).toString("hex");

async function put(name, subject, bytes = zip(1), bearer) {
  const form = new FormData();
  form.append("file", new Blob([bytes]), name);
  if (subject !== undefined) form.append("subject", subject);
  return call(new Request(`${ORIGIN}/terraform/files`, { method: "POST", body: form, headers: { Authorization: `Bearer ${bearer || (await token("Sustenaut/storage"))}` } }));
}
const get = (path, method = "GET") => call(new Request(`${ORIGIN}${path}`, { method }));

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
afterEach(() => (globalThis.fetch = realFetch));

test("the terraform tenant is public, kept, never cleaned, serves the mirror protocol, and only storage's own main writes it", () => {
  const t = REAL_TENANTS.terraform;
  assert.equal(t.private, undefined);
  assert.equal(t.repository, undefined);
  assert.equal(t.providers, true);
  assert.deepEqual(t.write, ["github:Sustenaut/storage@refs/heads/main"]);
  assert.deepEqual(t.files, { types: ["zip"], max_bytes: 104857600, kept: true });
  assert.equal(t.in_use, undefined);
});

test("index.json lists the versions mirrored, and <version>.json their archives with the zh: hash a lock pins", async () => {
  const google = "registry.terraform.io/hashicorp/google";
  for (const [name, n] of [
    ["terraform-provider-google_7.0.0_linux_amd64.zip", 1],
    ["terraform-provider-google_7.0.0_darwin_arm64.zip", 2],
    ["terraform-provider-google_6.9.0_linux_amd64.zip", 3],
  ]) assert.equal((await put(name, google, zip(n))).status, 200, name);
  assert.equal((await put("terraform-provider-tls_4.0.0_linux_amd64.zip", "registry.terraform.io/hashicorp/tls", zip(4))).status, 200);

  const index = await get("/terraform/registry.terraform.io/hashicorp/google/index.json");
  assert.equal(index.status, 200);
  assert.match(index.headers.get("Cache-Control"), /max-age=300/);
  assert.deepEqual(await index.json(), { versions: { "6.9.0": {}, "7.0.0": {} } }, "another provider's archive isn't listed");

  const version = await get("/terraform/registry.terraform.io/hashicorp/google/7.0.0.json");
  assert.equal(version.status, 200);
  const linux = await sha(zip(1));
  const darwin = await sha(zip(2));
  assert.deepEqual(await version.json(), {
    archives: {
      linux_amd64: { url: `${ORIGIN}/terraform/f/${linux}/terraform-provider-google_7.0.0_linux_amd64.zip`, hashes: [`zh:${linux}`] },
      darwin_arm64: { url: `${ORIGIN}/terraform/f/${darwin}/terraform-provider-google_7.0.0_darwin_arm64.zip`, hashes: [`zh:${darwin}`] },
    },
  });
  const archive = await get(`/terraform/f/${linux}/terraform-provider-google_7.0.0_linux_amd64.zip`);
  assert.equal(archive.status, 200, "the archive is where the version says");
  assert.deepEqual(new Uint8Array(await archive.arrayBuffer()), zip(1));

  assert.equal((await get("/terraform/registry.terraform.io/hashicorp/google/5.0.0.json")).status, 404);
  assert.deepEqual(await (await get("/terraform/registry.terraform.io/hashicorp/nothing/index.json")).json(), { versions: {} });
  assert.equal((await get("/terraform/registry.terraform.io/hashicorp/google/index.json", "HEAD")).status, 200);
});

test("an archive is taken only named as a provider release names it, under its provider's address", async () => {
  const google = "registry.terraform.io/hashicorp/google";
  assert.equal((await put("google.zip", google)).status, 400);
  assert.equal((await put("terraform-provider-google_7.0.0_linux_amd64.zip", undefined)).status, 400, "no subject");
  assert.equal((await put("terraform-provider-google_7.0.0_linux_amd64.zip", "hashicorp/google")).status, 400, "no hostname");
  assert.equal((await put("terraform-provider-google_7.0.0_linux_amd64.zip", "registry.terraform.io/hashicorp/tls")).status, 400, "another provider");
  assert.equal((await put("terraform-provider-google_7.0.0_linux_amd64.zip", google, new TextEncoder().encode("not a zip"))).status, 400);
  assert.equal((await put("terraform-provider-google_7.0.0_linux_amd64.zip", google, zip(1), await token("Sustenaut/business-plan"))).status, 403);
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a tenant without providers has no mirror routes", async () => {
  assert.equal((await get("/wheels/registry.terraform.io/hashicorp/google/index.json")).status, 404);
});

test("versions are listed in release order, not as text", async () => {
  assert.deepEqual(["10.0.0", "9.1.0", "9.0.10", "9.0.9", "10.0.0-beta1", "10.0.0-alpha2"].sort(byVersion),
    ["9.0.9", "9.0.10", "9.1.0", "10.0.0-alpha2", "10.0.0-beta1", "10.0.0"]);
  assert.equal(byVersion("1.2.3", "1.2.3"), 0);
  for (const [name, n] of [["terraform-provider-tls_10.0.0_linux_amd64.zip", 1], ["terraform-provider-tls_9.0.0_linux_amd64.zip", 2]])
    assert.equal((await put(name, "registry.terraform.io/hashicorp/tls", zip(n))).status, 200);
  const { versions } = await (await get("/terraform/registry.terraform.io/hashicorp/tls/index.json")).json();
  assert.deepEqual(Object.keys(versions), ["9.0.0", "10.0.0"]);
});
