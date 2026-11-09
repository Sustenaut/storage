// The storage service (src/storage.js), with an R2 bucket in memory and
// GitHub answered here.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, clean, jpegSize, allowedCache, callLog } from "../src/storage.js";
import { POLICIES } from "@sustenaut/integrations/caller.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };

// A JPEG's first bytes, with a start-of-frame giving its size.
function jpeg(width, height, extra = 0) {
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 255, width >> 8, width & 255, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1];
  return new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0, 0, ...sof, ...new Array(extra).fill(0), 0xff, 0xd9]);
}
const webp = () => new TextEncoder().encode("RIFF\0\0\0\0WEBPVP8 ");

function bucket() {
  const objects = new Map();
  return {
    objects,
    async put(key, bytes, options) {
      objects.set(key, { key, bytes, customMetadata: options?.customMetadata || {}, httpMetadata: options?.httpMetadata, httpEtag: '"e"', uploaded: new Date() });
    },
    async get(key) {
      const o = objects.get(key);
      return o && { ...o, body: o.bytes, text: async () => (typeof o.bytes === "string" ? o.bytes : new TextDecoder().decode(o.bytes)) };
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
  "visit-ee": { repository: "schryer/visit-ee", origins: ["https://temp.schryer.eu"], in_use: "https://temp.schryer.eu/photos.json" },
  opportunity: {
    repository: "Sustenaut/business-plan",
    origins: ["https://opportunity.sustenaut.eu"],
    in_use: "https://opportunity.sustenaut.eu/storage-in-use.json",
    files: { types: ["pdf", "pptx", "png", "svg", "csv"], max_bytes: 1000 },
  },
};
const call = (request) => handle(request, env, TENANTS);

let env, realFetch, sitePhotos, canPush, inUse, appRepos, clock, asked;
beforeEach(() => {
  env = { STORAGE: bucket() };
  clock = Date.parse("2026-11-01T00:00:00Z");
  allowedCache.now = () => clock;
  allowedCache.entries.clear();
  asked = [];
  sitePhotos = [];
  canPush = true;
  inUse = { photos: [], files: [] };
  appRepos = [{ full_name: "Sustenaut/business-plan", permissions: { admin: false, push: true, pull: true } }];
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    url = String(url);
    asked.push(url);
    if (url === "https://api.github.com/repos/schryer/visit-ee") {
      if (options.headers.Authorization !== "Bearer good") return new Response("{}", { status: 401 });
      return Response.json({ permissions: { push: canPush } });
    }
    if (url === "https://api.github.com/repos/Sustenaut/business-plan") {
      if (options.headers.Authorization !== "Bearer good") return new Response("{}", { status: 401 });
      return Response.json({ permissions: { push: canPush } });
    }
    // An installation token: GitHub answers /installation/repositories but not /user.
    if (url.startsWith("https://api.github.com/installation/repositories")) {
      if (options.headers.Authorization !== "Bearer ghs_app") return new Response("{}", { status: 401 });
      return Response.json({ total_count: appRepos.length, repositories: appRepos });
    }
    if (url === "https://api.github.com/user") {
      if (options.headers.Authorization.startsWith("Bearer ghs_")) return new Response("{}", { status: 403 });
      return Response.json({ login: "schryer" });
    }
    if (url === "https://temp.schryer.eu/photos.json") return Response.json({ photos: sitePhotos });
    if (url === "https://opportunity.sustenaut.eu/storage-in-use.json") return Response.json(inUse);
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => (globalThis.fetch = realFetch));

function upload(token, parts) {
  const form = new FormData();
  for (const [name, bytes] of Object.entries(parts)) form.append(name, new Blob([bytes]), name);
  return call(
    new Request("https://storage.example/visit-ee/upload", { method: "POST", body: form, headers: { Authorization: `Bearer ${token}`, Origin: "https://temp.schryer.eu" } }),
  );
}

test("an editor's upload is stored and named by its content", async () => {
  const response = await upload("good", { "480.jpg": jpeg(480, 360), "960.jpg": jpeg(960, 720), "480.webp": webp(), "960.webp": webp() });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "https://temp.schryer.eu");
  const photo = await response.json();
  assert.match(photo.id, /^[0-9a-f]{16}$/);
  assert.deepEqual({ ...photo, id: "" }, { id: "", width: 960, height: 720, widths: [480, 960], formats: ["webp", "jpg"] });
  assert.deepEqual([...env.STORAGE.objects.keys()].sort(), ["480.jpg", "480.webp", "960.jpg", "960.webp"].map((n) => `visit-ee/p/${photo.id}/${n}`));
  assert.equal(env.STORAGE.objects.get(`visit-ee/p/${photo.id}/960.jpg`).customMetadata.by, "schryer");

  const served = await call(new Request(`https://storage.example/visit-ee/p/${photo.id}/960.jpg`));
  assert.equal(served.status, 200);
  assert.equal(served.headers.get("Content-Type"), "image/jpeg");
  assert.match(served.headers.get("Cache-Control"), /immutable/);
});

test("only someone who may push to the repository can upload", async () => {
  assert.equal((await upload("bad", { "480.jpg": jpeg(480, 360) })).status, 403);
  canPush = false;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 403);
  assert.equal((await upload("", { "480.jpg": jpeg(480, 360) })).status, 401);
  assert.equal(env.STORAGE.objects.size, 0);
});

test("an upload must be photos of allowed sizes", async () => {
  assert.equal((await upload("good", { "480.jpg": new TextEncoder().encode("<svg/>") })).status, 400);
  assert.equal((await upload("good", { "4000.jpg": jpeg(4000, 3000) })).status, 400);
  assert.equal((await upload("good", { "evil.html": jpeg(480, 360) })).status, 400);
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360, Math.ceil(3.1 * 1024 * 1024)) })).status, 413);
});

test("the clean-up deletes old photos no place uses, and nothing else", async () => {
  const day = 86400e3, now = Date.parse("2026-12-01T00:00:00Z");
  const put = (id, daysOld) => env.STORAGE.put(`visit-ee/p/${id}/480.jpg`, jpeg(480, 360), { customMetadata: { uploaded: new Date(now - daysOld * day).toISOString() } });
  await put("aaaaaaaaaaaaaaaa", 90); // in use
  await put("bbbbbbbbbbbbbbbb", 90); // unused and old: goes
  await put("cccccccccccccccc", 3); // unused but new: maybe in an open pull request
  sitePhotos = ["aaaaaaaaaaaaaaaa"];
  const result = await clean(env, TENANTS, now);
  assert.deepEqual(result["visit-ee"].deleted, ["visit-ee/p/bbbbbbbbbbbbbbbb/480.jpg"]);
  assert.deepEqual([...env.STORAGE.objects.keys()].sort(), ["visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg", "visit-ee/p/cccccccccccccccc/480.jpg"]);

  // An empty list while photos exist looks like a broken site: keep all.
  sitePhotos = [];
  assert.match((await clean(env, TENANTS, now + 365 * day))["visit-ee"].skipped, /lists no photos/);
});

test("a JPEG's size comes from its frame header", () => {
  assert.deepEqual(jpegSize(jpeg(1600, 1067)), { width: 1600, height: 1067 });
});

test("the clean-up runs once a day however often it is called, and other sites' paths are unknown", async () => {
  sitePhotos = ["aaaaaaaaaaaaaaaa"];
  assert.equal((await call(new Request("https://storage.example/_clean", { method: "POST" }))).status, 200);
  assert.equal((await call(new Request("https://storage.example/_clean", { method: "POST" }))).status, 429);
  assert.equal((await call(new Request("https://storage.example/elsewhere/p/aaaaaaaaaaaaaaaa/480.jpg"))).status, 404);
  assert.equal((await call(new Request("https://storage.example/visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg"))).status, 404);
});

// --- Files -------------------------------------------------------------------

const pdf = (text = "report") => new TextEncoder().encode(`%PDF-1.7\n${text}\n%%EOF`);
const svg = (body = "") => new TextEncoder().encode(`<svg xmlns="http://www.w3.org/2000/svg">${body}</svg>`);
const pptx = () => new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]);

function sendFile(token, bytes, fields = {}, tenant = "opportunity") {
  const form = new FormData();
  form.append("file", new Blob([bytes]), fields.filename || "file.bin");
  for (const [k, v] of Object.entries(fields)) if (k !== "filename") form.append(k, v);
  return call(new Request(`https://storage.example/${tenant}/files`, { method: "POST", body: form, headers: { Authorization: `Bearer ${token}` } }));
}

test("a file is stored under its content's SHA-256 and served with its type, for good", async () => {
  const response = await sendFile("good", pdf(), { name: "market-report.pdf", label: "OPP-02 market report v3" });
  assert.equal(response.status, 200);
  const file = await response.json();
  assert.match(file.id, /^[0-9a-f]{64}$/);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", pdf()));
  assert.equal(file.id, [...digest].map((x) => x.toString(16).padStart(2, "0")).join(""));
  assert.deepEqual({ ...file, id: "" }, { id: "", name: "market-report.pdf", url: `/opportunity/f/${file.id}/market-report.pdf`, type: "application/pdf", size: pdf().length, label: "OPP-02 market report v3", subject: "", kept: false });
  const stored = env.STORAGE.objects.get(`opportunity/f/${file.id}/market-report.pdf`);
  assert.equal(stored.customMetadata.by, "schryer");
  assert.equal(stored.customMetadata.label, "OPP-02 market report v3");

  const served = await call(new Request(`https://storage.example${file.url}`));
  assert.equal(served.status, 200);
  assert.equal(served.headers.get("Content-Type"), "application/pdf");
  assert.match(served.headers.get("Cache-Control"), /immutable/);
  assert.match(served.headers.get("Content-Disposition"), /^inline; filename="market-report.pdf"/);
  assert.match(served.headers.get("Content-Security-Policy"), /sandbox/);

  // The file's own name is used when no name is given; Office files download rather than open.
  const deck = await (await sendFile("good", pptx(), { filename: "deck.pptx" })).json();
  const got = await call(new Request(`https://storage.example${deck.url}`));
  assert.equal(got.headers.get("Content-Type"), "application/vnd.openxmlformats-officedocument.presentationml.presentation");
  assert.match(got.headers.get("Content-Disposition"), /^attachment/);
});

test("files must be of a type the tenant allows, look like it, and fit", async () => {
  assert.equal((await sendFile("good", pdf(), { name: "page.html" })).status, 415);
  assert.equal((await sendFile("good", pdf(), { name: "notes.docx" })).status, 415); // a known type this tenant doesn't take
  assert.equal((await sendFile("good", svg(), { name: "fake.pdf" })).status, 400); // wrong magic bytes
  assert.equal((await sendFile("good", pdf(), { name: "fake.pptx" })).status, 400);
  assert.equal((await sendFile("good", pdf("x".repeat(1000)), { name: "big.pdf" })).status, 413);
  assert.equal((await sendFile("good", pdf(), { name: "../evil.pdf" })).status, 400);
  assert.equal((await sendFile("good", pdf(), { name: "a.pdf", extra: "x" })).status, 400);
  assert.equal((await sendFile("good", svg(), { name: "figure.svg" })).status, 200);
  assert.equal(env.STORAGE.objects.size, 1);
  // A tenant without "files" refuses them, and doesn't serve the path either.
  assert.equal((await sendFile("good", pdf(), { name: "a.pdf" }, "visit-ee")).status, 404);
  assert.equal((await call(new Request(`https://storage.example/visit-ee/f/${"a".repeat(64)}/a.pdf`))).status, 404);
});

test("only someone who may push to the tenant's repository can upload a file", async () => {
  assert.equal((await sendFile("", pdf(), { name: "a.pdf" })).status, 401);
  assert.equal((await sendFile("bad", pdf(), { name: "a.pdf" })).status, 403);
  canPush = false;
  assert.equal((await sendFile("good", pdf(), { name: "a.pdf" })).status, 403);
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a GitHub App installation token uploads when its installation can write to the repository", async () => {
  const response = await sendFile("ghs_app", pdf(), { name: "offer.pdf", kept: "true", for: "david@example.org" });
  assert.equal(response.status, 200);
  const file = await response.json();
  const meta = env.STORAGE.objects.get(`opportunity/f/${file.id}/offer.pdf`).customMetadata;
  assert.deepEqual({ by: meta.by, for: meta.for, kept: meta.kept }, { by: "github-app", for: "david@example.org", kept: "true" });

  // A person's token can't claim to upload for someone else.
  const mine = await (await sendFile("good", pdf("mine"), { name: "mine.pdf", for: "someone@example.org" })).json();
  assert.equal(env.STORAGE.objects.get(`opportunity/f/${mine.id}/mine.pdf`).customMetadata.for, undefined);

  assert.equal((await sendFile("ghs_other", pdf(), { name: "a.pdf" })).status, 403);
  appRepos = [{ full_name: "Sustenaut/business-plan", permissions: { admin: false, push: false, pull: true } }];
  clock += 60e3; // the app's earlier yes has expired
  assert.equal((await sendFile("ghs_app", pdf("2"), { name: "b.pdf" })).status, 403);
  appRepos = [{ full_name: "schryer/visit-ee", permissions: { admin: false, push: true, pull: true } }];
  assert.equal((await sendFile("ghs_app", pdf("3"), { name: "c.pdf" })).status, 403);
});

test("kept files are never cleaned, others are cleaned like photos, and only when the list names files", async () => {
  const day = 86400e3, now = Date.parse("2026-12-01T00:00:00Z");
  const put = (id, name, daysOld, kept = false) =>
    env.STORAGE.put(`opportunity/f/${id}/${name}`, pdf(), { customMetadata: { uploaded: new Date(now - daysOld * day).toISOString(), kept: String(kept) } });
  const [a, b, c, d] = ["a", "b", "c", "d"].map((x) => x.repeat(64));
  await put(a, "used.pdf", 90);
  await put(b, "unused.pdf", 90); // goes
  await put(c, "sent-to-client.pdf", 400, true); // kept: stays
  await put(d, "new.pdf", 2); // in an open change, maybe: stays
  inUse = { photos: [], files: [a] };
  const tenants = { opportunity: TENANTS.opportunity };
  assert.deepEqual((await clean(env, tenants, now)).opportunity, { deleted: [`opportunity/f/${b}/unused.pdf`] });
  assert.deepEqual([...env.STORAGE.objects.keys()].sort(), [a, c, d].map((id, i) => `opportunity/f/${id}/${["used.pdf", "sent-to-client.pdf", "new.pdf"][i]}`).sort());

  // No "files" key: files are never cleaned.
  inUse = { photos: [] };
  assert.deepEqual((await clean(env, tenants, now + 365 * day)).opportunity, { deleted: [] });
  // An empty list while there are files that could go looks like a broken site: keep them.
  inUse = { photos: [], files: [] };
  assert.match((await clean(env, tenants, now + 365 * day)).opportunity.skipped, /lists no files/);
  assert.equal(env.STORAGE.objects.size, 3);
});

test("a kept file stays kept when the same file is uploaded again", async () => {
  const first = await (await sendFile("good", pdf(), { name: "offer.pdf", kept: "true" })).json();
  const again = await (await sendFile("good", pdf(), { name: "offer.pdf" })).json();
  assert.equal(again.id, first.id);
  assert.equal(again.kept, true);
  assert.equal(env.STORAGE.objects.get(`opportunity/f/${first.id}/offer.pdf`).customMetadata.kept, "true");
});

test("the opportunity tenant takes the files the opportunity site needs", () => {
  const t = REAL_TENANTS.opportunity;
  assert.equal(t.private, true);
  assert.deepEqual(t.read, ["k8s:opportunity/app"]);
  assert.equal(t.repository, "Sustenaut/business-plan");
  assert.deepEqual(t.origins, ["https://opportunity.sustenaut.eu"]);
  assert.deepEqual(t.files.types, ["pdf", "pptx", "docx", "png", "jpg", "svg", "csv", "xlsx"]);
  assert.equal(REAL_TENANTS["visit-ee"].files, undefined); // photos only
});

// --- Sources -----------------------------------------------------------------

const SOURCES = { repository: "Sustenaut/business-plan", origins: [], files: { types: ["pdf", "cbor", "json"], max_bytes: 1000, kept: true } };
const sources = (token, bytes, fields) => {
  const form = new FormData();
  form.append("file", new Blob([bytes]), "file.bin");
  for (const [k, v] of Object.entries(fields)) form.append(k, v);
  return handle(new Request("https://storage.example/sources/files", { method: "POST", body: form, headers: { Authorization: `Bearer ${token}` } }), env, { sources: SOURCES });
};
// A publet object starts with a CBOR map: 0xa0 to 0xbf.
const cbor = () => new Uint8Array([0xa3, 0x61, 0x76, 0x01, 0x61, 0x6b, 0x02, 0x61, 0x64, 0x03]);

test("a sources tenant keeps papers, publet objects and their index, all kept", async () => {
  const object = await (await sources("good", cbor(), { name: "bafy-claim.cbor" })).json();
  assert.equal(object.kept, true);
  assert.equal(env.STORAGE.objects.get(`sources/f/${object.id}/bafy-claim.cbor`).customMetadata.kept, "true");
  const index = await (await sources("good", new TextEncoder().encode('{"e.pump": "bafy"}'), { name: "index.json" })).json();
  assert.equal(index.kept, true);
  assert.equal((await sources("good", pdf(), { name: "diehl-cheng-2025.pdf" })).status, 200);

  const got = await handle(new Request(`https://storage.example${object.url}`), env, { sources: SOURCES });
  assert.equal(got.headers.get("Content-Type"), "application/cbor");
  assert.match(got.headers.get("Content-Disposition"), /^attachment/);
  const shown = await handle(new Request(`https://storage.example${index.url}`), env, { sources: SOURCES });
  assert.equal(shown.headers.get("Content-Type"), "application/json");
  assert.match(shown.headers.get("Content-Disposition"), /^inline/);
});

test("a cbor file must be a CBOR map and a json file must parse", async () => {
  assert.equal((await sources("good", new Uint8Array([]), { name: "empty.cbor" })).status, 400);
  assert.equal((await sources("good", new Uint8Array([0x83, 1, 2, 3]), { name: "array.cbor" })).status, 400); // an array, not a map
  assert.equal((await sources("good", new TextEncoder().encode("{not json"), { name: "bad.json" })).status, 400);
  assert.equal((await sources("good", new Uint8Array([0x7b, 0xff, 0x7d]), { name: "bytes.json" })).status, 400); // not UTF-8
  assert.equal((await sources("good", cbor(), { name: "page.html" })).status, 415);
  assert.equal(env.STORAGE.objects.size, 0);
});

test("a tenant without an in_use list has nothing cleaned", async () => {
  const day = 86400e3, now = Date.parse("2026-12-01T00:00:00Z");
  await env.STORAGE.put(`sources/f/${"a".repeat(64)}/old.cbor`, cbor(), { customMetadata: { uploaded: new Date(now - 400 * day).toISOString(), kept: "false" } });
  assert.match((await clean(env, { sources: SOURCES }, now)).sources.skipped, /no in_use/);
  assert.equal(env.STORAGE.objects.size, 1);
});

test("a private tenant with editors takes a GitHub token that may push, for reading and writing, and is never public", async () => {
  const tenants = { sources: { ...SOURCES, private: true, editors: true } };
  const form = new FormData();
  form.append("file", new Blob([cbor()]), "file.bin");
  form.append("name", "bafy-claim.cbor");
  const up = await handle(new Request("https://storage.example/sources/files", { method: "POST", body: form, headers: { Authorization: "Bearer good" } }), env, tenants);
  assert.equal(up.status, 200);
  const { url } = await up.json();
  const read = (headers) => handle(new Request(`https://storage.example${url}`, { headers }), env, tenants);

  assert.equal((await read({})).status, 401, "nothing without a token");
  assert.equal((await read({ Authorization: "Bearer readonly" })).status, 403, "a token that can't push reads nothing");
  const got = await read({ Authorization: "Bearer good" });
  assert.equal(got.status, 200);
  assert.equal(got.headers.get("Cache-Control"), "private, no-store");

  // Without "editors" the same tenant takes no GitHub token, as before.
  const closed = { sources: { ...SOURCES, private: true } };
  assert.equal((await handle(new Request(`https://storage.example${url}`, { headers: { Authorization: "Bearer good" } }), env, closed)).status, 401);
});

test("a private tenant's public_types are open to anyone, and nothing else in it is", async () => {
  const tenants = { sources: { ...SOURCES, private: true, editors: true, public_types: ["pdf"] } };
  const upload = async (bytes, name) => {
    const form = new FormData();
    form.append("file", new Blob([bytes]), "file.bin");
    form.append("name", name);
    const up = await handle(new Request("https://storage.example/sources/files", { method: "POST", body: form, headers: { Authorization: "Bearer good" } }), env, tenants);
    assert.equal(up.status, 200);
    return (await up.json()).url;
  };
  const read = (url) => handle(new Request(`https://storage.example${url}`), env, tenants);
  const paper = await upload(pdf(), "paper.pdf");
  const object = await upload(cbor(), "bafy-claim.cbor");
  const index = await upload(new TextEncoder().encode("{}"), "index.json");

  const got = await read(paper);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get("Content-Type"), "application/pdf");
  assert.equal(got.headers.get("Cache-Control"), "public, max-age=31536000, immutable");
  assert.equal((await read(object)).status, 401);
  assert.equal((await read(index)).status, 401);
  // Naming an object's address .pdf opens nothing: the stored name is part of the address.
  assert.equal((await read(object.replace("bafy-claim.cbor", "bafy-claim.pdf"))).status, 404);
  // Uploading stays closed, and a cbor can't be stored as a pdf.
  const form = new FormData();
  form.append("file", new Blob([pdf()]), "file.bin");
  form.append("name", "other.pdf");
  assert.equal((await handle(new Request("https://storage.example/sources/files", { method: "POST", body: form }), env, tenants)).status, 401);
  const fake = new FormData();
  fake.append("file", new Blob([cbor()]), "file.bin");
  fake.append("name", "fake.pdf");
  assert.equal((await handle(new Request("https://storage.example/sources/files", { method: "POST", body: fake, headers: { Authorization: "Bearer good" } }), env, tenants)).status, 400);
});

test("the pdc tenant is public, and only pub-site's main writes it: kept signed objects and their reading data", () => {
  const t = REAL_TENANTS.pdc;
  assert.equal(t.private, undefined);
  assert.equal(t.repository, undefined, "no editors: no GitHub token can write here");
  assert.deepEqual(t.write, ["github:Sustenaut/pub-site@refs/heads/main"]);
  assert.deepEqual(t.files, { types: ["cbor", "json"], max_bytes: 26214400, kept: true });
  assert.equal(t.in_use, undefined, "nothing is cleaned");
});

test("the facts tenant is private: business-plan's editors upload, its main reads, kept, signed objects only", () => {
  const t = REAL_TENANTS.facts;
  assert.equal(t.private, true);
  assert.equal(t.editors, true);
  assert.equal(t.repository, "Sustenaut/business-plan");
  assert.deepEqual(t.read, ["github:Sustenaut/business-plan@refs/heads/main"]);
  assert.deepEqual(t.files.types, ["cbor"]);
  assert.equal(t.files.kept, true);
  assert.equal(t.public_types, undefined);
});

test("the sources tenant is private: business-plan's main and the review pod read it, its editors still upload and move its heads, kept and never cleaned", () => {
  const t = REAL_TENANTS.sources;
  assert.equal(t.private, true);
  assert.equal(t.editors, true);
  assert.deepEqual(t.public_types, ["pdf"], "only the raw papers are public");
  assert.deepEqual(t.read, ["github:Sustenaut/business-plan@refs/heads/main", "k8s:review/app"]);
  assert.equal(t.heads, true, "the review pod finds the gathered index through a head");
  assert.equal(t.repository, "Sustenaut/business-plan");
  assert.equal(t.in_use, undefined);
  assert.deepEqual(t.files, { types: ["pdf", "cbor", "json"], max_bytes: 26214400, kept: true });
});

test("an avro file must start as Avro does", async () => {
  const tenants = { sources: { ...SOURCES, files: { types: ["avro"] } } };
  const upload = (bytes) => {
    const form = new FormData();
    form.append("file", new Blob([bytes]), "calls.avro");
    return handle(new Request("https://storage.example/sources/files", { method: "POST", body: form, headers: { Authorization: "Bearer good" } }), env, tenants);
  };
  assert.equal((await upload(new Uint8Array([0x4f, 0x62, 0x6a, 0x01, 0x00]))).status, 200);
  assert.equal((await upload(new Uint8Array([0x4f, 0x62, 0x6a, 0x02]))).status, 400);
});

const gitHubAsks = () => asked.filter((u) => u.startsWith("https://api.github.com/")).length;

test("GitHub's yes is kept a minute, so more uploads with the same token don't ask again", async () => {
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 200);
  assert.equal(gitHubAsks(), 2, "the repository, then who the person is");
  clock += 59e3;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 361) })).status, 200);
  assert.equal(gitHubAsks(), 2, "within the minute, GitHub isn't asked");
  const meta = [...env.STORAGE.objects.values()].map((o) => o.customMetadata.by);
  assert.deepEqual(meta, ["schryer", "schryer"], "the login comes from the cache too");
  // The same token for another repository is asked about on its own.
  assert.equal((await sendFile("good", pdf(), { name: "a.pdf" })).status, 200);
  assert.equal(gitHubAsks(), 4);
});

test("a kept yes expires after a minute, and then a revoked permission is refused", async () => {
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 200);
  canPush = false;
  clock += 60e3;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 361) })).status, 403);
  assert.equal(gitHubAsks(), 3);
});

test("a no, or an error, is never kept", async () => {
  canPush = false;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 403);
  canPush = true;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 200, "asked again at once");
  assert.equal((await sendFile("ghs_other", pdf(), { name: "a.pdf" })).status, 403);
  assert.equal((await sendFile("ghs_other", pdf(), { name: "a.pdf" })).status, 403);
  assert.equal(asked.filter((u) => u.includes("/installation/")).length, 2);
});

test("the cache is keyed by a hash of the token and repository, never the token", async () => {
  await upload("good", { "480.jpg": jpeg(480, 360) });
  const [[key, value]] = [...allowedCache.entries];
  assert.match(key, /^[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify([key, value]).includes("good"));
  assert.deepEqual({ ...value, until: 0 }, { login: "schryer", app: false, until: 0 });
});

test("the cache holds at most a thousand yeses, dropping the oldest", async () => {
  for (let i = 0; i < 1000; i++) allowedCache.entries.set(`k${i}`, { login: "x", app: false, until: clock + 60e3 });
  await upload("good", { "480.jpg": jpeg(480, 360) });
  assert.equal(allowedCache.entries.size, 1000);
  assert.ok(!allowedCache.entries.has("k0"));
});

test("every call to GitHub has a timeout, and GitHub not answering is a 503, not a refusal", async () => {
  const signals = [];
  const answering = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    signals.push(options.signal);
    if (String(url).startsWith("https://api.github.com/")) throw new DOMException("The operation timed out.", "TimeoutError");
    return answering(url, options);
  };
  const response = await upload("good", { "480.jpg": jpeg(480, 360) });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /didn't answer within 10 s/);
  assert.equal((await sendFile("ghs_app", pdf(), { name: "a.pdf" })).status, 503);
  assert.equal(allowedCache.entries.size, 0, "a timeout isn't kept");
  assert.ok(signals.length && signals.every((s) => s instanceof AbortSignal));
  globalThis.fetch = answering;
});

test("the clean-up's in_use list has a timeout, and one that times out is skipped", async () => {
  const signals = [];
  const answering = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    signals.push(options.signal);
    throw new DOMException("The operation timed out.", "TimeoutError");
  };
  const report = await clean(env, TENANTS, Date.now());
  assert.match(report["visit-ee"].skipped, /timed out/);
  assert.ok(signals.length === 2 && signals.every((s) => s instanceof AbortSignal));
  globalThis.fetch = answering;
});

test("GitHub that can't be reached at all is a 503 too", async () => {
  const answering = globalThis.fetch;
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };
  const response = await upload("good", { "480.jpg": jpeg(480, 360) });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /can't be reached: fetch failed/);
  globalThis.fetch = answering;
});

// The call-log Durable Object's binding, keeping what each request sends it.
function callLogBinding() {
  const sent = [];
  return {
    sent,
    idFromName: (name) => ({ name }),
    get: (id) => ({ fetch: async (url, init) => (sent.push({ id: id.name, url, body: JSON.parse(init.body) }), Response.json({ kept: 1 })) }),
  };
}

test("each call to GitHub is a record of github.repo-ops check-push, tried once, as a person waits on it", async () => {
  assert.equal(POLICIES.H.timeout * 1000, 10_000);
  env.CALL_LOG = callLogBinding();
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 200);
  const [{ id, url, body }] = env.CALL_LOG.sent;
  assert.deepEqual([id, url, body.sender], ["storage", "https://call-log/records", "storage"]);
  const records = body.records.map((r) => [r.repo, r.app, r.plugin, r.operation, r.status, r.outcome]);
  assert.deepEqual(records, [["storage", "worker", "github.repo-ops", "check-push", 200, "ok"], ["storage", "worker", "github.repo-ops", "check-push", 200, "ok"]]);
  assert.ok(!JSON.stringify(body).includes("good"), "no token in a record");
  const answering = globalThis.fetch;
  let tries = 0;
  globalThis.fetch = async () => (tries++, new Response("{}", { status: 502 }));
  allowedCache.entries.clear();
  const failed = await upload("good", { "480.jpg": jpeg(480, 361) });
  assert.equal(failed.status, 503);
  assert.match((await failed.json()).error, /GitHub said 502; try again/);
  assert.equal(tries, 1);
  globalThis.fetch = answering;
});

test("a request's records go to the call log in one call, handed to waitUntil so the answer doesn't wait", async () => {
  const handed = [];
  env.CALL_LOG = callLogBinding();
  const form = new FormData();
  form.append("480.jpg", new Blob([jpeg(480, 360)]), "480.jpg");
  const request = new Request("https://storage.example/visit-ee/upload", { method: "POST", body: form, headers: { Authorization: "Bearer good" } });
  assert.equal((await handle(request, env, TENANTS, { waitUntil: (p) => handed.push(p) })).status, 200);
  assert.equal(handed.length, 1);
  await handed[0];
  assert.equal(env.CALL_LOG.sent.length, 1);
  assert.equal(env.CALL_LOG.sent[0].body.records.length, 2);
  // A request that made no calls sends nothing.
  await handle(new Request("https://storage.example/nope"), env, TENANTS, { waitUntil: (p) => handed.push(p) });
  await handed[1];
  assert.equal(env.CALL_LOG.sent.length, 1);
});

test("without the binding the records are let go, and nothing is written to the bucket", async () => {
  delete env.CALL_LOG;
  assert.equal((await upload("good", { "480.jpg": jpeg(480, 360) })).status, 200);
  assert.deepEqual(callLog.sink.pending, []);
  assert.ok(![...env.STORAGE.objects.keys()].some((k) => k.startsWith("calls-storage/")));
});

test("the calls-storage tenant is the call log's buffer: only ingest reads, writes or deletes through the API", () => {
  assert.deepEqual(REAL_TENANTS["calls-storage"], {
    private: true, inbox: true, read: ["k8s:integrations/ingest"], write: ["k8s:integrations/ingest"], delete: ["k8s:integrations/ingest"],
  });
});

test("the calls-release-controlplane tenant is a call-log buffer both release deployments write", () => {
  assert.deepEqual(REAL_TENANTS["calls-release-controlplane"], {
    private: true, inbox: true, read: ["k8s:integrations/ingest"],
    write: ["k8s:release/app", "k8s:release-schryer/app", "k8s:integrations/ingest"], delete: ["k8s:integrations/ingest"],
  });
});
