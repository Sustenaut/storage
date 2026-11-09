// A private tenant's files, listed for its readers a page at a time, with what their
// uploads said of them, such as a subject.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, allowedCache } from "../src/storage.js";

// As R2 lists: in key order, a page at a time, with a cursor, metadata only if asked.
function bucket() {
  const objects = new Map();
  const asked = [];
  return {
    objects, asked,
    async put(key, bytes, options = {}) {
      objects.set(key, { key, bytes, size: bytes.length, uploaded: new Date("2026-11-01T00:00:00Z"), customMetadata: options.customMetadata || {} });
    },
    async get(key) {
      const o = objects.get(key);
      return o && { ...o, body: o.bytes };
    },
    async list({ prefix, limit = 1000, cursor, include = [] }) {
      asked.push({ prefix, limit, include });
      const found = [...objects.values()].filter((o) => o.key.startsWith(prefix)).sort((a, b) => (a.key < b.key ? -1 : 1));
      const start = cursor ? Number(cursor) : 0;
      const page = found.slice(start, start + limit).map((o) => (include.includes("customMetadata") ? o : { ...o, customMetadata: undefined }));
      return { objects: page, truncated: start + limit < found.length, cursor: String(start + limit) };
    },
  };
}

const TENANTS = {
  deals: { private: true, editors: true, repository: "o/deals", origins: [], files: { types: ["pdf"] } },
  calls: { private: true, inbox: true, read: [], write: [] },
  closed: { private: true, read: [], write: [] },
  open: { repository: "o/open", origins: [], files: { types: ["pdf"] } },
};

let env, realFetch;
beforeEach(() => {
  env = { STORAGE: bucket() };
  allowedCache.entries.clear();
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    const token = options.headers.Authorization;
    if (String(url) === "https://api.github.com/repos/o/deals" || String(url) === "https://api.github.com/repos/o/open") {
      if (token === "Bearer nobody") return new Response("{}", { status: 404 });
      return Response.json({ permissions: { push: token === "Bearer editor" } });
    }
    if (String(url) === "https://api.github.com/user") return Response.json({ login: "an-editor" });
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => (globalThis.fetch = realFetch));

const call = (path, { token = "editor", method = "GET", body } = {}) =>
  handle(new Request(`https://storage.example${path}`, { method, body, headers: token ? { Authorization: `Bearer ${token}` } : {} }), env, TENANTS);

const pdf = (text) => new TextEncoder().encode(`%PDF-1.7\n${text}\n%%EOF`);

async function send(name, fields = {}, token = "editor") {
  const form = new FormData();
  form.append("file", new Blob([pdf(name)]), name);
  for (const [k, v] of Object.entries(fields)) form.append(k, v);
  return call("/deals/files", { method: "POST", body: form, token });
}

test("a reader lists the tenant's files with what their uploads said, and an upload may name its subject", async () => {
  const sent = await (await send("offer.pdf", { label: "The offer", subject: "card-42", kept: "true" })).json();
  assert.equal(sent.subject, "card-42");
  await send("notes.pdf");
  const response = await call("/deals/list?prefix=f/");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "private, no-store");
  const { files, cursor } = await response.json();
  assert.equal(cursor, null);
  const offer = files.find((f) => f.name === "offer.pdf");
  assert.deepEqual(offer, {
    name: "offer.pdf", id: sent.id, url: `/deals/f/${sent.id}/offer.pdf`, size: pdf("offer.pdf").length,
    uploaded: env.STORAGE.objects.get(`deals/f/${sent.id}/offer.pdf`).customMetadata.uploaded,
    metadata: { label: "The offer", kept: "true", by: "an-editor", subject: "card-42" },
  });
  assert.deepEqual(files.find((f) => f.name === "notes.pdf").metadata, { kept: "false", by: "an-editor" });
  assert.deepEqual(env.STORAGE.asked.at(-1), { prefix: "deals/f/", limit: 1000, include: ["customMetadata"] });
});

test("a subject is cut to the label's length, and kept only when given", async () => {
  const long = "s".repeat(250);
  const sent = await (await send("a.pdf", { subject: `  ${long}  ` })).json();
  assert.equal(sent.subject, "s".repeat(200));
  assert.equal(env.STORAGE.objects.get(`deals/f/${sent.id}/a.pdf`).customMetadata.subject, "s".repeat(200));
  const plain = await (await send("b.pdf")).json();
  assert.equal(env.STORAGE.objects.get(`deals/f/${plain.id}/b.pdf`).customMetadata.subject, undefined);
});

test("a listing comes a page at a time, and a prefix narrows it to an id or a name", async () => {
  const ids = [];
  for (const n of ["a", "b", "c"]) ids.push((await (await send(`${n}.pdf`)).json()).id);
  const first = await (await call("/deals/list?prefix=f/&limit=2")).json();
  assert.equal(first.files.length, 2);
  assert.ok(first.cursor);
  const next = await (await call(`/deals/list?prefix=f/&limit=2&cursor=${first.cursor}`)).json();
  assert.deepEqual([next.files.length, next.cursor], [1, null]);
  assert.deepEqual([...first.files, ...next.files].map((f) => f.id).sort(), [...ids].sort());
  const one = await (await call(`/deals/list?prefix=f/${ids[0]}/`)).json();
  assert.deepEqual(one.files.map((f) => f.id), [ids[0]]);
  assert.equal((await call(`/deals/list?prefix=f/${ids[0].slice(0, 6)}`)).status, 200);
});

test("only a reader lists: no token, or a token that can't push, is refused", async () => {
  assert.equal((await call("/deals/list?prefix=f/", { token: null })).status, 401);
  assert.equal((await call("/deals/list?prefix=f/", { token: "reader-only" })).status, 403);
  assert.equal((await call("/deals/list?prefix=f/", { token: "nobody" })).status, 403);
});

test("a prefix outside f/, a bad one, or a bad limit is refused", async () => {
  for (const q of ["prefix=", "prefix=inbox/", "prefix=f/../", "prefix=f/xyz", `prefix=f/${"a".repeat(65)}`, `prefix=f/${"a".repeat(64)}/../x`, "prefix=f/&limit=0", "prefix=f/&limit=1001", "prefix=f/&limit=x"]) {
    const status = (await call(`/deals/list?${q}`)).status;
    assert.ok(status === 400 || status === 404, `${q}: ${status}`);
    assert.notEqual(status, 200, q);
  }
  assert.equal((await call("/deals/list?prefix=f/&limit=1001")).status, 400);
  assert.equal((await call("/deals/list?prefix=f/xyz")).status, 400);
});

test("a public tenant is never listed, nor a private one's files without \"files\"", async () => {
  assert.equal((await call("/open/list?prefix=f/")).status, 404);
  assert.equal((await call("/closed/list?prefix=f/")).status, 404);
  // A buffer without files still takes only its folders.
  const buffer = await call("/calls/list?prefix=f/", { token: null });
  assert.equal(buffer.status, 401);
  assert.equal(env.STORAGE.asked.length, 0);
});
