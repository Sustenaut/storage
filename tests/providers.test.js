// The mirrors' indexes (src/storage.js): Terraform's provider network mirror, from the
// archives a tenant with "providers" keeps, and a simple repository index (PEP 503) of
// a tenant with "simple", with GitHub's OIDC issuer answered here.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, byVersion } from "../src/storage.js";
import { forgetKeys } from "../src/jwt.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };

import { JWKS, publicJwk, token } from "./oidc.js";

// A bucket that lists two objects a page, so the index reads every page.
function bucket() {
  const objects = new Map();
  const put = async (k, bytes, options) => objects.set(k, { key: k, bytes, customMetadata: options?.customMetadata || {}, httpEtag: '"e"' });
  const get = async (k) => objects.get(k) && { ...objects.get(k), body: objects.get(k).bytes };
  const list = async ({ prefix, cursor = "0" }) => {
    const all = [...objects.values()].filter((o) => o.key.startsWith(prefix));
    const at = Number(cursor);
    return { objects: all.slice(at, at + 2), truncated: at + 2 < all.length, cursor: String(at + 2) };
  };
  return { objects, put, get, list };
}

const TENANTS = { terraform: REAL_TENANTS.terraform, wheels: REAL_TENANTS.wheels, pypi: REAL_TENANTS.pypi };
const ORIGIN = "https://storage.example";
const call = (request) => handle(request, env, TENANTS);
const zip = (n) => new Uint8Array([0x50, 0x4b, 0x03, 0x04, n]);
const sha = async (bytes) => Buffer.from(await crypto.subtle.digest("SHA-256", bytes)).toString("hex");

async function put(name, subject, bytes = zip(1), bearer, tenant = "terraform") {
  const form = new FormData();
  form.append("file", new Blob([bytes]), name);
  if (subject !== undefined) form.append("subject", subject);
  return call(new Request(`${ORIGIN}/${tenant}/files`, { method: "POST", body: form, headers: { Authorization: `Bearer ${bearer || (await token("Sustenaut/storage"))}` } }));
}
const get = (path, method = "GET") => call(new Request(`${ORIGIN}${path}`, { method }));

let env, realFetch;
beforeEach(() => {
  env = { STORAGE: bucket() };
  forgetKeys();
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    if (String(url) === JWKS) return Response.json({ keys: [publicJwk] });
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

test("the pypi tenant is public, kept, never cleaned, serves a simple index, and only storage's own main writes it", () => {
  const t = REAL_TENANTS.pypi;
  assert.equal(t.private, undefined);
  assert.equal(t.repository, undefined);
  assert.equal(t.simple, true);
  assert.deepEqual(t.write, ["github:Sustenaut/storage@refs/heads/main"]);
  assert.deepEqual(t.files, { types: ["whl", "gz", "zip"], max_bytes: 104857600, kept: true });
  assert.equal(t.in_use, undefined);
});

test("a project's simple index links each of its files, with the sha256 a lock pins", async () => {
  const pkg = (name, subject, n) => put(name, subject, n === undefined ? zip(9) : zip(n), undefined, "pypi");
  assert.equal((await pkg("PyYAML-6.0.3-cp314-cp314-manylinux_2_17_x86_64.whl", "pyyaml", 1)).status, 200);
  assert.equal((await pkg("pyyaml-6.0.3.tar.gz", "pyyaml", 2)).status, 400, "a .gz must be gzip");
  const gz = new Uint8Array([0x1f, 0x8b, 8, 0]);
  assert.equal((await put("pyyaml-6.0.3.tar.gz", "pyyaml", gz, undefined, "pypi")).status, 200);
  assert.equal((await pkg("pytest_bdd-8.1.0-py3-none-any.whl", "pytest-bdd", 3)).status, 200);

  const page = await get("/pypi/simple/PyYAML/");
  assert.equal(page.status, 200);
  assert.match(page.headers.get("Content-Type"), /^text\/html/);
  const html = await page.text();
  const wheel = await sha(zip(1));
  const sdist = await sha(gz);
  assert.ok(html.includes(`<a href="${ORIGIN}/pypi/f/${wheel}/PyYAML-6.0.3-cp314-cp314-manylinux_2_17_x86_64.whl#sha256=${wheel}">`), html);
  assert.ok(html.includes(`#sha256=${sdist}">pyyaml-6.0.3.tar.gz</a>`), html);
  assert.ok(!html.includes("pytest_bdd"), "another project's file isn't listed");
  assert.ok((await (await get("/pypi/simple/pytest_bdd/")).text()).includes("pytest_bdd-8.1.0-py3-none-any.whl"), "a name is normalized");
  assert.equal((await get("/pypi/simple/nothing/")).status, 404);
  assert.equal((await get("/pypi/simple/pyyaml/", "HEAD")).status, 200);
  assert.equal((await get("/terraform/simple/pyyaml/")).status, 404, "only a tenant with simple has an index");
});

test("a package's file is taken only under its project's normalized name", async () => {
  const pkg = (name, subject) => put(name, subject, zip(1), undefined, "pypi");
  assert.equal((await pkg("pytest-9.0.3-py3-none-any.whl", undefined)).status, 400, "no subject");
  assert.equal((await pkg("pytest-9.0.3-py3-none-any.whl", "PyTest")).status, 400, "not normalized");
  assert.equal((await pkg("pytest-9.0.3-py3-none-any.whl", "pyyaml")).status, 400, "another project");
  assert.equal((await pkg("pytest_bdd-8.1.0-py3-none-any.whl", "pytest")).status, 400, "a name is matched whole");
  assert.equal(env.STORAGE.objects.size, 0);
});
