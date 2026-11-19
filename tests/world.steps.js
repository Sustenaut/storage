// The world a scenario sets up, in this service's words: its tenants, what its
// bucket holds, the forms and tokens it sends, the time, and how the services it
// calls (pubtest's fake services, tests/features/support.js) answer or fail.
import { Given } from "@cucumber/cucumber";
import fs from "node:fs";
import path from "node:path";
import { mock } from "node:test";
import { allowedCache } from "../src/storage.js";
import { verify } from "../src/jwt.js";
import REAL_TENANTS from "../tenants.json" with { type: "json" };
import { STEPS } from "@sustenaut/pubtest";
import { sample } from "./support/samples.js";
import { KEY_SETS, KEYS, actionsToken, claimValue, part, recipe, sign } from "./support/tokens.js";

function scratch(world, name) {
  if (!world.pubtest.directory) throw new Error("a file of this suite's needs pubtest's scratch directory first");
  return path.join(world.pubtest.directory, name);
}

// A request of a Given's own, to the Worker, which must be answered as said.
async function sent(world, method, at, headers, body, wanted) {
  const answer = await world.pubtest.client(method, at, headers, body);
  if (answer.status !== wanted) throw new Error(`${method} ${at} answered ${answer.status}, not ${wanted}: ${answer.text}`);
  return answer;
}

// --- Tenants -----------------------------------------------------------------

Given("the tenant {string} is:", function (name, doc) {
  this.tenants[name] = JSON.parse(doc);
});

Given("the tenant {string} as tenants.json has it", function (name) {
  if (!REAL_TENANTS[name]) throw new Error(`tenants.json has no ${name}`);
  this.tenants[name] = REAL_TENANTS[name];
});

Given("the tenant {string} as tenants.json has it, but with:", function (name, doc) {
  this.tenants[name] = { ...REAL_TENANTS[name], ...JSON.parse(doc) };
});

Given("every tenant of tenants.json", function () {
  Object.assign(this.tenants, REAL_TENANTS);
});

// --- The bucket ----------------------------------------------------------------

// A row per object: its key, its content (tests/support/samples.js), and any
// other column a piece of its custom metadata, left out when the cell is empty.
Given("the bucket already holds:", async function (table) {
  for (const { key, content, ...meta } of table.hashes()) {
    const customMetadata = Object.fromEntries(Object.entries(meta).filter(([, v]) => v !== ""));
    await this.env.STORAGE.put(key, sample(content), { customMetadata });
  }
});

Given("the bucket lists {int} objects a page", function (n) {
  this.env.STORAGE.page = n;
});

Given("the bucket's writes to keys ending {string} fail", function (ending) {
  this.env.STORAGE.failing = ending;
});

Given("the bucket's writes work again", function () {
  this.env.STORAGE.failing = null;
});

// --- What requests carry -----------------------------------------------------------

// A multipart form, written to a file for pubtest's `I send "M" to "P" with the
// file "F"`, its Content-Type (with the form's boundary) on every request after
// it. A row with a file name is a file of that content (tests/support/samples.js);
// one without is a text field holding the content as it is, or as the JSON
// string it is when it starts with a quote (to keep its spaces).
Given("the form {string} holding:", async function (name, table) {
  const form = new FormData();
  for (const { field, file, content } of table.hashes()) {
    if (file) form.append(field, new Blob([sample(content)]), file);
    else form.append(field, content.startsWith('"') ? JSON.parse(content) : content);
  }
  const encoded = new Response(form);
  fs.writeFileSync(scratch(this, name), new Uint8Array(await encoded.arrayBuffer()));
  this.pubtest.headers["content-type"] = encoded.headers.get("content-type");
});

Given("a file {string} holding the bytes of {string}", function (name, description) {
  fs.writeFileSync(scratch(this, name), sample(description));
});

Given("requests carry a GitHub Actions token for {string} at {string}", async function (repository, ref) {
  this.pubtest.headers.authorization = `Bearer ${await actionsToken(repository, ref)}`;
});

Given("I have sent {string} to {string}, answered {int}", async function (method, at, wanted) {
  await sent(this, method, at, this.pubtest.headers, undefined, wanted);
});

Given("I have sent {string} to {string} with the file {string}, answered {int}", async function (method, at, name, wanted) {
  const headers = { "content-type": "application/octet-stream", ...this.pubtest.headers };
  await sent(this, method, at, headers, fs.readFileSync(scratch(this, name)), wanted);
});

// --- Heads ---------------------------------------------------------------------------

// Moves a head as the main branch of a repository on the tenant's write list
// does: from where it points now (If-Match), or first (If-None-Match: *).
async function moveHead(world, repository, name, tenant, hash) {
  const now = await world.env.STORAGE.get(`${tenant}/h/${name}`);
  const from = now ? { "if-match": `"${JSON.parse(await now.text()).hash}"` } : { "if-none-match": "*" };
  const headers = { authorization: `Bearer ${await actionsToken(repository)}`, ...from };
  await sent(world, "PUT", `/${tenant}/head/${name}`, headers, JSON.stringify({ hash }), 200);
}

Given("{string} has moved the head {string} of {string} to {string}", function (repository, name, tenant, hash) {
  return moveHead(this, repository, name, tenant, hash);
});

// Another writer gets in after the scenario's own move has read the head, before it writes.
Given("{string} moves the head {string} of {string} to {string} just before the next move writes it", function (repository, name, tenant, hash) {
  let racing = false;
  this.env.STORAGE.beforePut = async (key) => {
    if (racing || key !== `${tenant}/h/${name}`) return;
    racing = true;
    await moveHead(this, repository, name, tenant, hash);
  };
});

// --- Time ------------------------------------------------------------------------------

Given("the time is {string}", function (when) {
  mock.timers.enable({ apis: ["Date"], now: Date.parse(when) });
});

Given("{int} seconds have passed", function (n) {
  mock.timers.tick(n * 1000);
});

// --- The services it calls -------------------------------------------------------------

// An issuer's key set, made for the tests (tests/support/tokens.js), as the fake service of its name answers it.
const [, , answers] = STEPS.find(([, expression]) => expression === "the {string} service answers {string} with {int} and:");
const PUBLISHED = {
  "GitHub's OIDC issuer": ["GET /.well-known/jwks", KEY_SETS.github],
  Google: ["GET /oauth2/v3/certs", KEY_SETS.google],
};

Given("the {string} service publishes its test keys", async function (name) {
  const [request, keys] = PUBLISHED[name];
  await answers(this.pubtest, name, request, 200, JSON.stringify(keys));
});

Given("the {string} service does not answer in time", function (name) {
  this.down[name] = () => new DOMException("The operation timed out.", "TimeoutError");
});

Given("the {string} service can't be reached", function (name) {
  this.down[name] = () => new TypeError("fetch failed");
});

// What the Worker hands the call log (its CALL_LOG Durable Object binding), kept.
Given("the call log is bound", function () {
  const sent = (this.callLog = []);
  this.env.CALL_LOG = {
    idFromName: (name) => ({ name }),
    get: (id) => ({
      fetch: async (url, init) => (sent.push({ object: id.name, url, ...JSON.parse(init.body) }), Response.json({ kept: 1 })),
    }),
  };
});

Given("requests are handled with a waitUntil", function () {
  this.handed = [];
  this.options = { waitUntil: (promise) => this.handed.push(promise) };
});

// GitHub's yeses, as the Worker keeps them: for other tokens, each good for a minute more.
Given("the cache already keeps {int} yeses for other tokens", function (n) {
  for (let i = 0; i < n; i++) allowedCache.entries.set(`k${i}`, { login: "x", app: false, until: allowedCache.now() + 60e3 });
});

// --- Tokens ------------------------------------------------------------------------------

// The token under test, made when it is used, from the latest recipe and its changes.
function making(world, made) {
  world.made = made;
  world.token = async () => (typeof world.made === "string" ? world.made : sign(world.made));
}

Given("a GitHub Actions token for {string} at {string}", function (repository, ref) {
  making(this, recipe("github", repository, ref));
});

Given("a pod token for the service account {string} of {string}", function (account, namespace) {
  making(this, recipe("pod", namespace, account));
});

Given("a Google identity token for {string}", function (email) {
  making(this, recipe("google", email));
});

Given("its claim {string} is {string}", function (claim, value) {
  this.made.claims[claim] = claimValue(value);
});

Given("it has no claim {string}", function (claim) {
  delete this.made.claims[claim];
});

Given("its header's {string} is {string}", function (name, value) {
  this.made.header[name] = value;
});

Given("it is signed with another key", function () {
  this.made.key = KEYS.other;
});

Given("it is signed with the key of GitHub's OIDC issuer", function () {
  this.made.key = KEYS.github;
});

Given("the token {string}", function (token) {
  making(this, token);
});

// A token whose header is the one given and whose signature is none at all.
Given("it is sent unsigned, with the header {string}", async function (header) {
  const [, claims] = (await sign(this.made)).split(".");
  making(this, `${part(JSON.parse(header))}.${claims}.`);
});

// A token whose claims are another's, under the signature made for its own.
Given("its claims are swapped for:", async function (doc) {
  const [header, , signature] = (await sign(this.made)).split(".");
  const claims = Object.fromEntries(Object.entries(JSON.parse(doc)).map(([k, v]) => [k, typeof v === "string" ? claimValue(v) : v]));
  making(this, `${header}.${part(claims)}.${signature}`);
});

Given("the issuer's keys have been fetched", async function () {
  await verify(await actionsToken("Sustenaut/pub-site"));
});

// --- GitHub's answers ----------------------------------------------------------------------

// What the fake "GitHub" service answers a request, from now on: a later Given
// replaces an earlier one's answer, as GitHub's own answer changes.
const [, , aFake] = STEPS.find(([, expression]) => expression === "a fake {string} service");
async function gitHubAnswers(world, request, status, body = "") {
  await aFake(world.pubtest, "GitHub");
  world.pubtest.fakes.GitHub.answers[request] = [[status, typeof body === "string" ? body : JSON.stringify(body), {}]];
}

Given("GitHub lets the token push to {string}", function (repository) {
  return gitHubAnswers(this, `GET /repos/${repository}`, 200, { permissions: { admin: false, push: true, pull: true } });
});

Given("GitHub lets the token read but not push to {string}", function (repository) {
  return gitHubAnswers(this, `GET /repos/${repository}`, 200, { permissions: { admin: false, push: false, pull: true } });
});

Given("GitHub answers {int} for the repository {string}", function (status, repository) {
  return gitHubAnswers(this, `GET /repos/${repository}`, status, "{}");
});

Given("GitHub knows the token as {string}", function (login) {
  return gitHubAnswers(this, "GET /user", 200, { login });
});

// An installation token's repositories: a row per repository, and whether it may push.
Given("GitHub lists the installation's repositories:", function (table) {
  const repositories = table.hashes().map(({ repository, push }) => ({ full_name: repository, permissions: { admin: false, push: push === "yes", pull: true } }));
  return gitHubAnswers(this, "GET /installation/repositories", 200, { total_count: repositories.length, repositories });
});

Given("GitHub answers {int} for the installation's repositories", function (status) {
  return gitHubAnswers(this, "GET /installation/repositories", status, "{}");
});
