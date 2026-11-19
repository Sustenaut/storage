// The actions of this service's own that are no request to it: its clean-up,
// its token checks and the other functions it exports, and what tenants.json,
// openapi.json and the header of src/storage.js say. Each leaves its result
// (or its refusal) for pubtest's Thens, through attempt.
import { When } from "@cucumber/cucumber";
import { readFile } from "node:fs/promises";
import { clean, jpegSize, byVersion } from "../src/storage.js";
import { verify, allowed, isJwt } from "../src/jwt.js";
import { POLICIES } from "@sustenaut/integrations/caller.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };
import SPEC from "../openapi.json" with { type: "json" };
import K8S from "../src/k8s.json" with { type: "json" };
import { sample } from "./support/samples.js";
import { PINNED } from "./support/tokens.js";

// --- The clean-up ----------------------------------------------------------------

When("the clean-up runs at {string}", function (when) {
  return this.attempt(() => clean(this.env, this.tenants, Date.parse(when)));
});

When("the clean-up runs", function () {
  return this.attempt(() => clean(this.env, this.tenants, Date.now()));
});

// --- What src/storage.js and src/jwt.js export -----------------------------------------

When("the size of {string} is read", function (description) {
  return this.attempt(() => jpegSize(sample(description)));
});

When("the versions {string} are put in release order", function (list) {
  return this.attempt(() => JSON.parse(list).sort(byVersion));
});

When("{string} and {string} are compared in release order", function (a, b) {
  return this.attempt(() => byVersion(a, b));
});

When("the token is verified", async function () {
  const token = await this.token();
  return this.attempt(() => verify(token));
});

When("the token is verified again", async function () {
  const token = await this.token();
  return this.attempt(() => verify(token));
});

When("the token is verified {int} minutes later", async function (minutes) {
  const token = await this.token();
  return this.attempt(() => verify(token, { now: Date.now() + minutes * 60e3 }));
});

When("the token is verified against the pinned keys of the k3s server", async function () {
  const token = await this.token();
  return this.attempt(() => verify(token, { issuers: PINNED }));
});

When("{string} is matched against the list {string}", function (principal, list) {
  return this.attempt(() => allowed(principal, JSON.parse(list)));
});

When("{string} is matched against no list", function (principal) {
  return this.attempt(() => allowed(principal, undefined));
});

When("{string} is taken for a JWT or not", function (token) {
  return this.attempt(() => isJwt(token));
});

When("the call policy {string} is read", function (name) {
  return this.attempt(() => POLICIES[name]);
});

// --- tenants.json ------------------------------------------------------------------------

When("tenants.json's {string} is read", function (name) {
  return this.attempt(() => {
    if (!REAL_TENANTS[name]) throw new Error(`tenants.json has no ${name}`);
    return REAL_TENANTS[name];
  });
});

// Whether a principal is on a tenant's read or write list, word for word.
When("tenants.json's {string} is asked whether it lists {string} as a reader or writer", function (name, principal) {
  return this.attempt(() => [...REAL_TENANTS[name].read, ...REAL_TENANTS[name].write].includes(principal));
});

// Whoever takes a buffer's files writes there too: a record of each load in batches/,
// and a file that won't load moved to rejected/. So every principal on a buffer's
// delete list must be on its write list, and on its read list.
When("the deleters of tenants.json's buffers are looked up", function () {
  return this.attempt(() => {
    const buffers = Object.entries(REAL_TENANTS).filter(([, t]) => t.private && t.inbox);
    const problems = [];
    for (const [name, t] of buffers) {
      for (const principal of t.delete ?? []) {
        if (!t.write?.includes(principal)) problems.push(`${name}: ${principal} deletes but may not write batches/ or rejected/`);
        if (!t.read?.includes(principal)) problems.push(`${name}: ${principal} deletes but may not read`);
      }
    }
    return { found: buffers.length > 0, problems };
  });
});

When("src\\/k8s.json is read", function () {
  return this.attempt(() => ({ ...K8S, kinds: [...new Set(K8S.jwks.keys.map((k) => k.kty))], hasKeys: K8S.jwks.keys.length > 0 }));
});

// --- openapi.json and the header of src/storage.js -----------------------------------------

const METHODS = ["get", "put", "post", "delete", "head", "patch", "options", "trace"];
const operations = Object.entries(SPEC.paths).flatMap(([at, item]) =>
  METHODS.filter((m) => item[m]).map((m) => ({ at, method: m.toUpperCase(), item, op: item[m], where: `${m.toUpperCase()} ${at}` })));
const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const lookup = (ref) => (/^#\//.test(ref) ? ref.slice(2).split("/").reduce((node, key) => node?.[key], SPEC) : undefined);
const resolved = (x) => (x.$ref ? lookup(x.$ref) : x);
const parameters = ({ item, op }) => [...(item.parameters || []), ...(op.parameters || [])].map(resolved);

function* refs(node) {
  if (Array.isArray(node)) for (const x of node) yield* refs(x);
  else if (node && typeof node === "object") {
    if (typeof node.$ref === "string") yield node.$ref;
    for (const v of Object.values(node)) yield* refs(v);
  }
}

// Each rule a spec's operations keep, as the problems with it: none when it holds.
const RULES = {
  "it is OpenAPI 3.1, with a title and a version": () => [
    ...(/^3\.1\.\d+$/.test(SPEC.openapi) ? [] : [`openapi is ${SPEC.openapi}`]),
    ...(SPEC.info?.title && SPEC.info?.version ? [] : ["info has no title or version"]),
  ],
  "every reference resolves": () => [...refs(SPEC)].filter((ref) => !lookup(ref)).map((ref) => `${ref} doesn't resolve`),
  "every operation has a unique operationId of letters": () => {
    const seen = new Set();
    return operations.flatMap(({ op, where }) => {
      const problems = [];
      if (!/^[a-z][A-Za-z]+$/.test(op.operationId ?? "")) problems.push(`${where}: operationId ${op.operationId}`);
      if (seen.has(op.operationId)) problems.push(`${where}: ${op.operationId} is used twice`);
      seen.add(op.operationId);
      return problems;
    });
  },
  "every operation has a summary": () => operations.filter(({ op }) => !op.summary).map(({ where }) => where),
  "every operation answers HTTP statuses, a success among them": () => operations.flatMap(({ op, where }) => {
    const codes = Object.keys(op.responses ?? {});
    if (!codes.length || !codes.every((c) => /^[1-5]\d\d$/.test(c))) return [`${where}: ${codes}`];
    return codes.some((c) => c.startsWith("2")) ? [] : [`${where} has no success`];
  }),
  "every error is an Error": () => operations.flatMap(({ op, where }) => Object.keys(op.responses)
    .filter((c) => /^[45]/.test(c))
    .filter((c) => resolved(op.responses[c]).content?.["application/json"]?.schema?.$ref !== "#/components/schemas/Error")
    .map((c) => `${where} ${c}: errors are {error}`)),
  "every operation says who may call it, by a scheme the spec has": () => {
    const schemes = Object.keys(SPEC.components.securitySchemes);
    return operations.flatMap(({ op, where }) => (!Array.isArray(op.security) ? [`${where} says nobody`]
      : op.security.flatMap((need) => Object.keys(need).filter((n) => !schemes.includes(n)).map((n) => `${where}: ${n}`))));
  },
  "every name in a path is a required path parameter with an example, and nothing else is": () => operations.flatMap((o) => {
    const inPath = parameters(o).filter((p) => p.in === "path");
    const named = [...o.at.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort(byCodeUnit);
    const problems = JSON.stringify(inPath.map((p) => p.name).sort(byCodeUnit)) === JSON.stringify(named) ? [] : [`${o.where}: ${inPath.map((p) => p.name)}`];
    return [...problems, ...inPath.filter((p) => !(p.required && p.schema && p.example !== undefined)).map((p) => `${o.where} ${p.name}`)];
  }),
};

When("openapi.json is checked for the rule {string}", function (name) {
  return this.attempt(() => {
    if (!RULES[name]) throw new Error(`no rule ${name}`);
    return RULES[name]();
  });
});

When("openapi.json's operations are listed", function () {
  return this.attempt(() => operations.map((o) => o.where).sort(byCodeUnit));
});

// An operation's path with its example parameters, the tenant "all", and the prefix of a listing of files.
When("the example of {string} is read from openapi.json", function (where) {
  return this.attempt(() => {
    const o = operations.find((x) => x.where === where);
    let url = o.at;
    for (const p of parameters(o).filter((x) => x.in === "path")) url = url.replace(`{${p.name}}`, p.name === "tenant" ? "all" : p.example);
    const query = parameters(o).find((p) => p.name === "prefix");
    return query ? `${url}?prefix=${encodeURIComponent(query.examples.files.value)}` : url;
  });
});

When("the routes the header of src\\/storage.js lists are read", function () {
  return this.attempt(async () => {
    const source = await readFile(new URL("../src/storage.js", import.meta.url), "utf8");
    const header = source.slice(0, source.indexOf("\nimport "));
    const listed = [...header.matchAll(/^\/\/ {3}([A-Z]+(?:,[A-Z]+)*) (\/\S*)/gm)].flatMap(([, methods, at]) => methods.split(",").map((m) => `${m} ${at}`));
    return [...new Set(listed)].sort(byCodeUnit);
  });
});
