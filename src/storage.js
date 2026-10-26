// storage.sustenaut.eu: photos (and later other files) for the sites that
// use it, kept in an R2 bucket and served from Cloudflare Pages Functions
// (functions/[[path]].js), so none of them lives in a site's git
// repository or in its Pages deployment.
//
// Each site is a tenant (tenants.json), with its own part of the bucket:
//
//   GET  /<tenant>/p/<id>/<width>.<jpg|webp>   a photo, cached for good: ids
//                                               are content hashes, so a
//                                               photo never changes
//   POST /<tenant>/upload                       a photo from the tenant's
//                                               editor
//   POST /_clean                                the nightly clean-up
//
// An upload is the sizes the editor made in the browser (multipart fields
// named "<width>.<jpg|webp>"), sent with the editor's GitHub token: they
// are stored only if that token may push to the tenant's repository. The
// answer is the photo's description, which the site keeps in its content.
//
// The clean-up deletes a tenant's photos that its site no longer uses (its
// in_use list) once they are GRACE_DAYS old, so a photo waiting in an open
// pull request survives. .github/workflows/clean.yml calls it nightly. It
// needs no secret: it only does what the sites' own public lists say, and
// runs at most once in CLEAN_EVERY_HOURS however often it is called.

import TENANTS from "../tenants.json" with { type: "json" };

export const WIDTHS = [480, 960, 1600];
const FORMATS = { jpg: "image/jpeg", webp: "image/webp" };
const MAX_BYTES = 3 * 1024 * 1024;
const GRACE_DAYS = 30;
const CLEAN_EVERY_HOURS = 20;
const LAST_CLEAN = "_clean/last";
const PHOTO = /^\/([a-z0-9-]+)\/p\/([0-9a-f]{16})\/(\d+)\.(jpg|webp)$/;

// env: STORAGE, the R2 bucket.
// tenants: tenants.json, or the tests' own.
export async function handle(request, env, tenants = TENANTS) {
  const url = new URL(request.url);
  const tenantId = url.pathname.split("/")[1];
  const tenant = tenants[tenantId];
  const cors = corsHeaders(request, tenant);
  try {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method === "POST" && url.pathname === "/_clean") {
      const now = Date.now();
      const last = await env.STORAGE.get(LAST_CLEAN);
      if (last && now - Number(await last.text()) < CLEAN_EVERY_HOURS * 3600e3) throw status(429, "cleaned recently");
      await env.STORAGE.put(LAST_CLEAN, String(now));
      return json(await clean(env, tenants, now), 200);
    }
    if (!tenant) throw status(404, "not found");
    if (request.method === "GET" || request.method === "HEAD") return await serve(url, env, request);
    if (request.method === "POST" && url.pathname === `/${tenantId}/upload`) return json(await upload(request, env, tenantId, tenant), 200, cors);
    throw status(404, "not found");
  } catch (err) {
    return json({ error: err.message }, err.status || 500, cors);
  }
}

// A photo, from Cloudflare's cache where it can be (the Cache API works on
// the custom domain, not on pages.dev), else from the bucket.
async function serve(url, env, request) {
  const m = url.pathname.match(PHOTO);
  if (!m) throw status(404, "not found");
  const cache = request.method === "GET" && globalThis.caches?.default;
  const hit = cache && (await cache.match(request));
  if (hit) return hit;
  const object = await env.STORAGE.get(url.pathname.slice(1));
  if (!object) throw status(404, "not found");
  const response = new Response(request.method === "HEAD" ? null : object.body, {
    headers: {
      "Content-Type": FORMATS[m[4]],
      "Cache-Control": "public, max-age=31536000, immutable",
      "Access-Control-Allow-Origin": "*",
      ETag: object.httpEtag,
    },
  });
  if (cache) await cache.put(request, response.clone());
  return response;
}

// Stores the sizes of one photo, and answers its description.
export async function upload(request, env, tenantId, tenant) {
  const login = await editor(request, tenant.repository);
  const form = await request.formData();
  const files = {};
  for (const [name, file] of form.entries()) {
    const m = name.match(/^(\d+)\.(jpg|webp)$/);
    if (!m || typeof file === "string") throw status(400, `unexpected field ${name}`);
    const width = Number(m[1]);
    if (width < 1 || width > WIDTHS.at(-1)) throw status(400, `${name}: wider than ${WIDTHS.at(-1)}`);
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length > MAX_BYTES) throw status(413, `${name} is over ${MAX_BYTES} bytes`);
    if (!looksLike(m[2], bytes)) throw status(400, `${name} is not a ${m[2]}`);
    files[name] = { width, format: m[2], bytes };
  }
  const jpgs = Object.values(files).filter((f) => f.format === "jpg").sort((a, b) => a.width - b.width);
  if (!jpgs.length) throw status(400, "no JPEG");
  const widths = jpgs.map((f) => f.width);
  const formats = Object.values(files).some((f) => f.format === "webp") ? ["webp", "jpg"] : ["jpg"];
  for (const w of widths) if (formats.includes("webp") && !files[`${w}.webp`]) throw status(400, `no ${w}.webp`);

  // Named by the largest JPEG's content: the same photo twice is one photo.
  const largest = jpgs.at(-1);
  const id = await hash(largest.bytes);
  const { width, height } = jpegSize(largest.bytes);
  const uploaded = new Date().toISOString();
  await Promise.all(
    Object.entries(files).map(([name, f]) =>
      env.STORAGE.put(`${tenantId}/p/${id}/${name}`, f.bytes, {
        httpMetadata: { contentType: FORMATS[f.format] },
        customMetadata: { uploaded, by: login },
      }),
    ),
  );
  return { id, width, height, widths, formats };
}

// The GitHub login behind the request's token, if it may push to the
// repository; anything else is refused.
async function editor(request, repository) {
  const token = (request.headers.get("Authorization") || "").replace(/^Bearer\s*/i, "").trim();
  if (!token) throw status(401, "sign in first");
  const headers = { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "User-Agent": "sustenaut-storage" };
  const repo = await fetch(`https://api.github.com/repos/${repository}`, { headers });
  if (!repo.ok) throw status(403, `GitHub said ${repo.status} for ${repository}`);
  if (!(await repo.json()).permissions?.push) throw status(403, `that token can't write to ${repository}`);
  const user = await fetch("https://api.github.com/user", { headers });
  return user.ok ? (await user.json()).login || "?" : "?";
}

// Deletes each tenant's photos its site doesn't use and that are older
// than GRACE_DAYS. A tenant whose list can't be read, or comes back empty
// while it has photos, is left alone rather than emptied on a bad day.
export async function clean(env, tenants = TENANTS, now = Date.now()) {
  const report = {};
  for (const [tenantId, tenant] of Object.entries(tenants)) {
    const response = await fetch(tenant.in_use).catch((err) => ({ ok: false, status: err.message }));
    if (!response.ok) {
      report[tenantId] = { skipped: `${tenant.in_use}: ${response.status}` };
      continue;
    }
    const used = new Set((await response.json()).photos || []);
    const objects = [];
    let cursor;
    do {
      const page = await env.STORAGE.list({ prefix: `${tenantId}/p/`, cursor, include: ["customMetadata"] });
      objects.push(...page.objects);
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);
    if (!used.size && objects.length) {
      report[tenantId] = { skipped: `${tenant.in_use} lists no photos` };
      continue;
    }
    const cutoff = now - GRACE_DAYS * 86400e3;
    const doomed = objects
      .filter((o) => !used.has(o.key.split("/")[2]))
      .filter((o) => Date.parse(o.customMetadata?.uploaded || o.uploaded) < cutoff)
      .map((o) => o.key);
    for (let i = 0; i < doomed.length; i += 1000) await env.STORAGE.delete(doomed.slice(i, i + 1000));
    report[tenantId] = { deleted: doomed };
  }
  return report;
}

function corsHeaders(request, tenant) {
  const origin = request.headers.get("Origin");
  const ok = origin && tenant && (tenant.origins.includes(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin));
  return ok
    ? { "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Methods": "POST, GET", "Access-Control-Allow-Headers": "Authorization", Vary: "Origin" }
    : { Vary: "Origin" };
}

function looksLike(format, b) {
  if (format === "jpg") return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  return String.fromCharCode(...b.slice(0, 4)) === "RIFF" && String.fromCharCode(...b.slice(8, 12)) === "WEBP";
}

// A JPEG's size, from its first start-of-frame marker.
export function jpegSize(b) {
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) throw status(400, "not a JPEG");
    const marker = b[i + 1];
    const length = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      return { height: (b[i + 5] << 8) | b[i + 6], width: (b[i + 7] << 8) | b[i + 8] };
    }
    i += 2 + length;
  }
  throw status(400, "a JPEG without a size");
}

async function hash(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest.slice(0, 8)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function status(code, message) {
  const err = new Error(message);
  err.status = code;
  return err;
}

function json(body, code, headers = {}) {
  return new Response(JSON.stringify(body), { status: code, headers: { "Content-Type": "application/json", ...headers } });
}
