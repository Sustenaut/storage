// The storage service (src/storage.js), with an R2 bucket in memory and
// GitHub answered here.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { handle, clean, jpegSize } from "../src/storage.js";

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
      objects.set(key, { key, bytes, customMetadata: options?.customMetadata || {}, httpEtag: '"e"', uploaded: new Date() });
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
  "visit-ee": { repository: "schryer/visit-ee", origins: ["https://temp.schryer.eu"], in_use: "https://temp.schryer.eu/photos.json" },
};
const call = (request) => handle(request, env, TENANTS);

let env, realFetch, sitePhotos, canPush;
beforeEach(() => {
  env = { STORAGE: bucket(), CLEAN_TOKEN: "sweep" };
  sitePhotos = [];
  canPush = true;
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    url = String(url);
    if (url === "https://api.github.com/repos/schryer/visit-ee") {
      if (options.headers.Authorization !== "Bearer good") return new Response("{}", { status: 401 });
      return Response.json({ permissions: { push: canPush } });
    }
    if (url === "https://api.github.com/user") return Response.json({ login: "schryer" });
    if (url === "https://temp.schryer.eu/photos.json") return Response.json({ photos: sitePhotos });
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

test("only the clean-up's token starts it, and other sites' paths are unknown", async () => {
  assert.equal((await call(new Request("https://storage.example/_clean", { method: "POST" }))).status, 401);
  assert.equal((await call(new Request("https://storage.example/_clean", { method: "POST", headers: { Authorization: "Bearer sweep" } }))).status, 200);
  assert.equal((await call(new Request("https://storage.example/elsewhere/p/aaaaaaaaaaaaaaaa/480.jpg"))).status, 404);
  assert.equal((await call(new Request("https://storage.example/visit-ee/p/aaaaaaaaaaaaaaaa/480.jpg"))).status, 404);
});
