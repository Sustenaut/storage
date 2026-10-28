// storage.sustenaut.eu: photos and other files for the sites that use it, kept in an R2 bucket and served from Cloudflare Pages Functions
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
//   GET  /<tenant>/f/<id>/<name>                a file, cached for good: the
//                                               id is its content's SHA-256
//   POST /<tenant>/files                        a file, for tenants whose
//                                               tenants.json entry has "files"
//   POST /_clean                                the nightly clean-up
//
// An upload is the sizes the editor made in the browser (multipart fields
// named "<width>.<jpg|webp>"), sent with the editor's GitHub token: they
// are stored only if that token may push to the tenant's repository. The
// answer is the photo's description, which the site keeps in its content.
//
// A file is one multipart field "file" (with optional "name", "label" and
// "kept"), of a type the tenant allows (checked by extension and, where the
// format has one, its magic bytes). A service may upload with its GitHub
// App's installation token instead of a person's token; the file is then
// recorded as uploaded by the app.
//
// The clean-up deletes a tenant's photos and files that its site no longer
// uses (its in_use list) once they are GRACE_DAYS old, so a photo waiting in an open
// pull request survives. .github/workflows/clean.yml calls it nightly. It
// needs no secret: it only does what the sites' own public lists say, and
// runs at most once in CLEAN_EVERY_HOURS however often it is called. Kept
// files (client documents that went out) are never deleted, a tenant
// whose list has no "files" key never has files deleted, and a tenant
// without an in_use list has nothing deleted.

import TENANTS from "../tenants.json" with { type: "json" };

export const WIDTHS = [480, 960, 1600];
const FORMATS = { jpg: "image/jpeg", webp: "image/webp" };
const MAX_BYTES = 3 * 1024 * 1024;
const GRACE_DAYS = 30;
const CLEAN_EVERY_HOURS = 20;
const LAST_CLEAN = "_clean/last";
const PHOTO = /^\/([a-z0-9-]+)\/p\/([0-9a-f]{16})\/(\d+)\.(jpg|webp)$/;
const FILE = /^\/([a-z0-9-]+)\/f\/([0-9a-f]{64})\/([A-Za-z0-9][A-Za-z0-9._-]{0,119})$/;
const FILE_MAX_BYTES = 25 * 1024 * 1024; // when the tenant names none; Pages takes 100 MB a request
const LABEL_CHARS = 200;

// The file types a tenant may allow: Content-Type, whether a browser shows
// it inline, and a check of its first bytes.
const ascii = (b, at, text) => String.fromCharCode(...b.slice(at, at + text.length)) === text;
const isZip = (b) => ascii(b, 0, "PK\x03\x04"); // docx, pptx and xlsx are zip archives
const isText = (b) => !b.slice(0, 4096).includes(0);
export const FILE_TYPES = {
  pdf: { type: "application/pdf", inline: true, check: (b) => ascii(b, 0, "%PDF-") },
  png: { type: "image/png", inline: true, check: (b) => ascii(b, 0, "\x89PNG\r\n\x1a\n") },
  jpg: { type: "image/jpeg", inline: true, check: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  jpeg: { type: "image/jpeg", inline: true, check: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  webp: { type: "image/webp", inline: true, check: (b) => ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP") },
  gif: { type: "image/gif", inline: true, check: (b) => ascii(b, 0, "GIF8") },
  svg: { type: "image/svg+xml", inline: true, check: (b) => isText(b) && /<svg[\s>]/i.test(new TextDecoder().decode(b.slice(0, 4096))) },
  csv: { type: "text/csv; charset=utf-8", inline: false, check: isText },
  txt: { type: "text/plain; charset=utf-8", inline: true, check: isText },
  docx: { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", inline: false, check: isZip },
  pptx: { type: "application/vnd.openxmlformats-officedocument.presentationml.presentation", inline: false, check: isZip },
  xlsx: { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", inline: false, check: isZip },
  // A publet object: its id is already its content's SHA-256, so the check is only that it is one, a CBOR map.
  cbor: { type: "application/cbor", inline: false, check: (b) => b.length > 0 && b[0] >= 0xa0 && b[0] <= 0xbf },
  json: { type: "application/json", inline: true, check: isJson },
};

function isJson(b) {
  try {
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(b));
    return true;
  } catch {
    return false;
  }
}

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
    if (request.method === "GET" || request.method === "HEAD") return await serve(url, env, request, tenant);
    if (request.method === "POST" && url.pathname === `/${tenantId}/upload`) return json(await upload(request, env, tenantId, tenant), 200, cors);
    if (request.method === "POST" && url.pathname === `/${tenantId}/files`) return json(await uploadFile(request, env, tenantId, tenant), 200, cors);
    throw status(404, "not found");
  } catch (err) {
    return json({ error: err.message }, err.status || 500, cors);
  }
}

// A photo, from Cloudflare's cache where it can be (the Cache API works on
// the custom domain, not on pages.dev), else from the bucket.
async function serve(url, env, request, tenant) {
  const photo = url.pathname.match(PHOTO);
  const file = !photo && url.pathname.match(FILE);
  const kind = file && FILE_TYPES[extension(file[3])];
  if (!photo && !(kind && tenant.files)) throw status(404, "not found");
  const cache = request.method === "GET" && globalThis.caches?.default;
  const hit = cache && (await cache.match(request));
  if (hit) return hit;
  const object = await env.STORAGE.get(url.pathname.slice(1));
  if (!object) throw status(404, "not found");
  const headers = {
    "Content-Type": photo ? FORMATS[photo[4]] : kind.type,
    "Cache-Control": "public, max-age=31536000, immutable",
    "Access-Control-Allow-Origin": "*",
    ETag: object.httpEtag,
  };
  if (file) {
    // An uploaded file never runs as a page of this site: an SVG's scripts stay off.
    Object.assign(headers, {
      "Content-Disposition": `${kind.inline ? "inline" : "attachment"}; filename="${file[3]}"`,
      "Content-Security-Policy": "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox",
      "X-Content-Type-Options": "nosniff",
    });
  }
  const response = new Response(request.method === "HEAD" ? null : object.body, { headers });
  if (cache) await cache.put(request, response.clone());
  return response;
}

// Stores the sizes of one photo, and answers its description.
export async function upload(request, env, tenantId, tenant) {
  const { login } = await editor(request, tenant.repository);
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

// Stores one file, named by its content, and answers its description.
export async function uploadFile(request, env, tenantId, tenant) {
  if (!tenant.files) throw status(404, "this site keeps no files here");
  const who = await editor(request, tenant.repository);
  const form = await request.formData();
  const file = form.get("file");
  for (const field of form.keys()) {
    if (!["file", "name", "label", "kept", "for"].includes(field)) throw status(400, `unexpected field ${field}`);
  }
  if (!file || typeof file === "string") throw status(400, "no file");
  const name = String(form.get("name") || file.name || "").trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/.test(name)) throw status(400, "the name is letters, digits, dots, dashes and underscores, at most 120");
  const ext = extension(name);
  const kind = FILE_TYPES[ext];
  if (!kind || !tenant.files.types.includes(ext)) throw status(415, `${tenantId} takes ${tenant.files.types.join(", ")}, not .${ext}`);
  const max = Math.min(tenant.files.max_bytes || FILE_MAX_BYTES, 100 * 1024 * 1024);
  if (file.size > max) throw status(413, `${name} is over ${max} bytes`);
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.length > max) throw status(413, `${name} is over ${max} bytes`);
  if (!kind.check(bytes)) throw status(400, `${name} is not a .${ext} file`);
  const label = String(form.get("label") || "").trim().slice(0, LABEL_CHARS);
  // A tenant whose files are all kept (sources: papers and signed objects) keeps every upload.
  const kept = tenant.files.kept === true || form.get("kept") === "true";

  const id = await hash(bytes, 32);
  const key = `${tenantId}/f/${id}/${name}`;
  const before = await env.STORAGE.get(key);
  // Once kept, always kept: uploading a kept document again as a normal file doesn't unkeep it.
  const keep = kept || before?.customMetadata?.kept === "true";
  const customMetadata = { uploaded: new Date().toISOString(), by: who.login, kept: String(keep) };
  if (label) customMetadata.label = label;
  if (who.app && form.get("for")) customMetadata.for = String(form.get("for")).slice(0, LABEL_CHARS);
  await env.STORAGE.put(key, bytes, { httpMetadata: { contentType: kind.type }, customMetadata });
  return { id, name, url: `/${key}`, type: kind.type, size: bytes.length, label, kept: keep };
}

// Who is behind the request's token, if it may push to the repository;
// anything else is refused. A person's token is checked on the repository
// itself; a GitHub App's installation token (ghs_…), which can't ask who its
// user is, must list the repository among its installation's, with push
// (contents: write).
async function editor(request, repository) {
  const token = (request.headers.get("Authorization") || "").replace(/^Bearer\s*/i, "").trim();
  if (!token) throw status(401, "sign in first");
  const headers = { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "User-Agent": "sustenaut-storage" };
  if (token.startsWith("ghs_")) return { login: "github-app", app: true, ...(await installation(headers, repository)) };
  return { login: await person(headers, repository), app: false };
}

async function installation(headers, repository) {
  for (let page = 1; page <= 10; page++) {
    const r = await fetch(`https://api.github.com/installation/repositories?per_page=100&page=${page}`, { headers });
    if (!r.ok) throw status(403, `GitHub said ${r.status} for the app's repositories`);
    const { repositories = [] } = await r.json();
    const repo = repositories.find((x) => x.full_name?.toLowerCase() === repository.toLowerCase());
    if (repo) {
      if (!repo.permissions?.push) throw status(403, `the app can't write to ${repository}`);
      return {};
    }
    if (repositories.length < 100) break;
  }
  throw status(403, `the app isn't installed on ${repository}`);
}

async function person(headers, repository) {
  const repo = await fetch(`https://api.github.com/repos/${repository}`, { headers });
  if (!repo.ok) throw status(403, `GitHub said ${repo.status} for ${repository}`);
  if (!(await repo.json()).permissions?.push) throw status(403, `that token can't write to ${repository}`);
  const user = await fetch("https://api.github.com/user", { headers });
  return user.ok ? (await user.json()).login || "?" : "?";
}

function extension(name) {
  const dot = name.lastIndexOf(".");
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
}

// Deletes each tenant's photos its site doesn't use and that are older
// than GRACE_DAYS. A tenant whose list can't be read, or comes back empty
// while it has photos, is left alone rather than emptied on a bad day.
export async function clean(env, tenants = TENANTS, now = Date.now()) {
  const report = {};
  for (const [tenantId, tenant] of Object.entries(tenants)) {
    if (!tenant.in_use) {
      report[tenantId] = { skipped: "no in_use list: nothing is cleaned" };
      continue;
    }
    const response = await fetch(tenant.in_use).catch((err) => ({ ok: false, status: err.message }));
    if (!response.ok) {
      report[tenantId] = { skipped: `${tenant.in_use}: ${response.status}` };
      continue;
    }
    const lists = await response.json();
    const cutoff = now - GRACE_DAYS * 86400e3;
    const doomed = [];
    const skipped = [];
    // Photos, then files; files only when the list says which are used, and never kept ones.
    const kinds = [["p", "photos", lists.photos || []]];
    if (Array.isArray(lists.files)) kinds.push(["f", "files", lists.files]);
    for (const [prefix, what, list] of kinds) {
      const used = new Set(list);
      const objects = (await listAll(env, `${tenantId}/${prefix}/`)).filter((o) => o.customMetadata?.kept !== "true");
      if (!used.size && objects.length) {
        skipped.push(`${tenant.in_use} lists no ${what}`);
        continue;
      }
      doomed.push(
        ...objects
          .filter((o) => !used.has(o.key.split("/")[2]))
          .filter((o) => Date.parse(o.customMetadata?.uploaded || o.uploaded) < cutoff)
          .map((o) => o.key),
      );
    }
    for (let i = 0; i < doomed.length; i += 1000) await env.STORAGE.delete(doomed.slice(i, i + 1000));
    report[tenantId] = skipped.length ? { deleted: doomed, skipped: skipped.join("; ") } : { deleted: doomed };
  }
  return report;
}

async function listAll(env, prefix) {
  const objects = [];
  let cursor;
  do {
    const page = await env.STORAGE.list({ prefix, cursor, include: ["customMetadata"] });
    objects.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return objects;
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

async function hash(bytes, length = 8) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest.slice(0, length)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function status(code, message) {
  const err = new Error(message);
  err.status = code;
  return err;
}

function json(body, code, headers = {}) {
  return new Response(JSON.stringify(body), { status: code, headers: { "Content-Type": "application/json", ...headers } });
}
