// openapi.json against the code: the spec is well formed, it names every route the
// header of src/storage.js lists and no other, and the code answers every route in it.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { handle } from "../src/storage.js";
import SPEC from "../openapi.json" with { type: "json" };

const METHODS = ["get", "put", "post", "delete", "head", "patch", "options", "trace"];
const operations = Object.entries(SPEC.paths).flatMap(([path, item]) =>
  METHODS.filter((m) => item[m]).map((m) => ({ path, method: m.toUpperCase(), item, op: item[m] })));

function resolve(ref) {
  assert.match(ref, /^#\//, ref);
  const found = ref.slice(2).split("/").reduce((node, key) => node?.[key], SPEC);
  assert.ok(found, `${ref} resolves`);
  return found;
}

function* refs(node) {
  if (Array.isArray(node)) for (const x of node) yield* refs(x);
  else if (node && typeof node === "object") {
    if (typeof node.$ref === "string") yield node.$ref;
    for (const v of Object.values(node)) yield* refs(v);
  }
}

test("the spec is OpenAPI 3.1, every reference resolves, and every operation is complete", () => {
  assert.match(SPEC.openapi, /^3\.1\.\d+$/);
  assert.ok(SPEC.info.title && SPEC.info.version);
  for (const ref of refs(SPEC)) resolve(ref);
  const schemes = Object.keys(SPEC.components.securitySchemes);
  const ids = new Set();
  for (const { path, method, item, op } of operations) {
    const where = `${method} ${path}`;
    assert.match(op.operationId, /^[a-z][A-Za-z]+$/, where);
    assert.ok(!ids.has(op.operationId), `${op.operationId} is used once`);
    ids.add(op.operationId);
    assert.ok(op.summary, where);
    const codes = Object.keys(op.responses);
    assert.ok(codes.length && codes.every((c) => /^[1-5]\d\d$/.test(c)), where);
    assert.ok(codes.some((c) => c.startsWith("2")), `${where} has a success`);
    for (const c of codes.filter((c) => /^[45]/.test(c))) {
      const response = op.responses[c].$ref ? resolve(op.responses[c].$ref) : op.responses[c];
      assert.equal(response.content["application/json"].schema.$ref, "#/components/schemas/Error", `${where} ${c}: errors are {error}`);
    }
    assert.ok(Array.isArray(op.security), `${where} says who may call it`);
    for (const need of op.security) for (const name of Object.keys(need)) assert.ok(schemes.includes(name), `${where}: ${name}`);
    // Every {name} in the path is a required path parameter, and nothing else is.
    const params = [...(item.parameters || []), ...(op.parameters || [])].map((p) => (p.$ref ? resolve(p.$ref) : p));
    const inPath = params.filter((p) => p.in === "path");
    assert.deepEqual(inPath.map((p) => p.name).sort(), [...path.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort(), where);
    for (const p of inPath) assert.ok(p.required && p.schema && p.example !== undefined, `${where} ${p.name}`);
  }
});

test("the spec has every route the header of src/storage.js lists, and no other", async () => {
  const source = await readFile(new URL("../src/storage.js", import.meta.url), "utf8");
  const header = source.slice(0, source.indexOf("\nimport "));
  const listed = [...header.matchAll(/^\/\/ {3}([A-Z]+(?:,[A-Z]+)*) (\/\S*)/gm)].flatMap(([, methods, path]) => methods.split(",").map((m) => `${m} ${path}`));
  assert.ok(listed.length > 10);
  assert.deepEqual(operations.map((o) => `${o.method} ${o.path}`).sort(), [...new Set(listed)].sort());
});

// A tenant with everything, a GitHub token that may push to it, and an empty bucket:
// a request that reaches its route gets past the route's own checks or fails them, but
// never gets "no such route".
const TENANTS = {
  all: { private: true, editors: true, repository: "o/all", files: { types: ["pdf"] }, heads: true, inbox: true, providers: true, simple: true, read: [], write: [], delete: [] },
};
const bucket = {
  get: async () => null,
  put: async () => {},
  delete: async () => {},
  list: async () => ({ objects: [], truncated: false }),
};
let realFetch;
beforeEach(() => {
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    if (String(url) === "https://api.github.com/repos/o/all") return Response.json({ permissions: { push: true } });
    if (String(url) === "https://api.github.com/user") return Response.json({ login: "editor" });
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => (globalThis.fetch = realFetch));

function sample({ path, item, op }) {
  const params = [...(item.parameters || []), ...(op.parameters || [])].map((p) => (p.$ref ? resolve(p.$ref) : p));
  let url = path;
  for (const p of params.filter((x) => x.in === "path")) url = url.replace(`{${p.name}}`, p.name === "tenant" ? "all" : p.example);
  const query = params.find((p) => p.name === "prefix");
  return query ? `${url}?prefix=${encodeURIComponent(query.examples.files.value)}` : url;
}

async function answer(method, path) {
  const response = await handle(new Request(`https://storage.example${path}`, { method, headers: { Authorization: "Bearer gho_editor" } }), { STORAGE: bucket }, TENANTS);
  const body = method === "HEAD" ? {} : await response.json().catch(() => ({}));
  return { status: response.status, error: body.error || "" };
}

for (const operation of operations) {
  test(`the code answers ${operation.method} ${operation.path}`, async () => {
    const { status, error } = await answer(operation.method, sample(operation));
    assert.ok(!error.startsWith("no such route"), `${status} ${error}`);
    assert.notEqual(status, 405);
  });
}

test("and a request for no route says so", async () => {
  for (const [method, path] of [["GET", "/all/nothing"], ["POST", `/all/p/0123456789abcdef/960.jpg`], ["PUT", `/all/f/${"a".repeat(64)}/a.pdf`], ["PATCH", "/all/head/board"], ["POST", "/all/inbox/a.avro"], ["DELETE", "/all/files"]]) {
    const { status, error } = await answer(method, path);
    assert.ok(error.startsWith("no such route"), `${method} ${path}: ${status} ${error}`);
  }
});
