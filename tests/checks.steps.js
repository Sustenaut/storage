// The checks pubtest has no step for: what the bucket holds and was asked, the
// bytes of an answer that isn't text, what the service kept of GitHub's yeses,
// sent to the call log or Cloudflare's cache, and whether its requests had a
// timeout. Each is a candidate for pubtest.
import { Then } from "@cucumber/cucumber";
import assert from "node:assert/strict";
import { allowedCache, callLog } from "../src/storage.js";
import { hex } from "./support/samples.js";
import { signature } from "../src/notify.js";

const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const lines = (doc) => String(doc).split("\n").map((l) => l.trim()).filter(Boolean);

// --- The bucket --------------------------------------------------------------------

Then("the bucket holds:", function (doc) {
  assert.deepEqual([...this.env.STORAGE.objects.keys()].sort(byCodeUnit), lines(doc));
});

Then("the bucket holds {int} objects", function (n) {
  assert.equal(this.env.STORAGE.objects.size, n, [...this.env.STORAGE.objects.keys()].join("\n"));
});

function stored(world, key) {
  const o = world.env.STORAGE.objects.get(key);
  assert.ok(o, `the bucket has no ${key}: ${[...world.env.STORAGE.objects.keys()].join(", ")}`);
  return o;
}

Then("the bucket's {string} has the metadata {string} set to {string}", function (key, name, value) {
  assert.equal(stored(this, key).customMetadata[name], value);
});

Then("the bucket's {string} has no metadata {string}", function (key, name) {
  assert.equal(stored(this, key).customMetadata[name], undefined);
});

Then("the bucket's {string} includes {string}", function (key, text) {
  const got = new TextDecoder().decode(stored(this, key).bytes);
  assert.ok(got.includes(text), got);
});

Then("the bucket was last listed with:", function (doc) {
  assert.deepEqual(this.env.STORAGE.listed.at(-1), JSON.parse(doc));
});

Then("the bucket was never listed", function () {
  assert.deepEqual(this.env.STORAGE.listed, []);
});

// --- The answer, as bytes ---------------------------------------------------------------

Then("the answer's bytes are {string}", function (bytes) {
  assert.ok(this.pubtest.answer, "no request was sent");
  assert.equal(hex(this.pubtest.answer.bytes), bytes.toLowerCase());
});

Then(/^the answer(?: has no body|'s body is empty)$/, function () {
  assert.ok(this.pubtest.answer, "no request was sent");
  assert.equal(this.pubtest.answer.bytes.length, 0);
});

// --- What it sent ------------------------------------------------------------------------

Then("it sent {int} requests, each with a timeout", function (n) {
  assert.equal(this.sent.length, n, JSON.stringify(this.sent));
  assert.ok(this.sent.every((s) => s.timeout), JSON.stringify(this.sent));
});

Then("the Cache API was never asked", function () {
  assert.deepEqual(this.cacheAsked, []);
});

// --- GitHub's yeses, as the service keeps them ------------------------------------------

// Each kept yes as [key, what is kept]: a row per yes.
Then("the kept yeses are:", function (doc) {
  assert.deepEqual([...allowedCache.entries], JSON.parse(doc));
});

Then("{int} yeses are kept", function (n) {
  assert.equal(allowedCache.entries.size, n);
});

Then("no yes is kept as {string}", function (key) {
  assert.ok(!allowedCache.entries.has(key));
});

// --- The call log ----------------------------------------------------------------------------

async function handed(world) {
  await Promise.all(world.handed ?? []);
  return world.callLog;
}

Then("{int} promises were handed to waitUntil", function (n) {
  assert.equal(this.handed.length, n);
});

Then("the call log was sent {int} batches", async function (n) {
  assert.equal((await handed(this)).length, n);
});

// The batches it was sent, each to a Durable Object at a URL from a sender, and
// their records: a row per record, its columns the ones the row names.
Then("the call log was sent the records:", async function (table) {
  const records = (await handed(this)).flatMap(({ object, url, sender, records }) =>
    records.map((r) => ({ object, url, sender, ...r })));
  const rows = table.hashes();
  assert.equal(records.length, rows.length, JSON.stringify(records));
  rows.forEach((row, i) => {
    for (const [k, v] of Object.entries(row)) assert.equal(String(records[i][k]), v, `record ${i}: ${k}`);
  });
});

Then("nothing sent to the call log includes {string}", async function (text) {
  assert.ok(!JSON.stringify(await handed(this)).includes(text));
});

Then("no records wait to be sent to the call log", function () {
  assert.deepEqual(callLog.sink.pending, []);
});

// --- A refusal's property, which pubtest can't read ------------------------------------------

Then("the refusal's {string} is {string}", function (name, value) {
  const refused = this.pubtest.refused;
  assert.ok(refused, "it was not refused");
  this.pubtest.refusalRead = true;
  assert.equal(String(refused.error?.[name]), value);
});

// --- The ingest pod's notices ---------------------------------------------------------

// Each notice the ingest pod was sent: its path, its body, and whether its signature is
// the key's over its timestamp and body, the timestamp within a second of now.
Then("the ingest pod was told, signed with {string}, of:", async function (key, doc) {
  await Promise.all(this.handed ?? []);
  const told = [];
  for (const r of this.pubtest.fakes["the ingest pod"]?.requests ?? []) {
    const seconds = r.headers["x-ingest-timestamp"];
    told.push({ request: `${r.method} ${r.path}`, body: JSON.parse(r.body),
      signed: r.headers["x-ingest-signature"] === await signature(key, seconds, r.body),
      now: Math.abs(Number(seconds) - Date.now() / 1000) <= 1 });
  }
  assert.deepEqual(told, JSON.parse(doc));
});

Then("nothing was sent to the ingest pod", async function () {
  await Promise.all(this.handed ?? []);
  assert.deepEqual(this.sent.filter((s) => s.name === "the ingest pod"), []);
});

Then("{int} notice was sent to the ingest pod, with a timeout", async function (n) {
  await Promise.all(this.handed ?? []);
  const sent = this.sent.filter((s) => s.name === "the ingest pod");
  assert.equal(sent.length, n);
  assert.ok(sent.every((s) => s.timeout));
});

// What the service said in its log (console.error), kept by the Given before it.
Then("the log says {string}", async function (text) {
  await Promise.all(this.handed ?? []);
  assert.ok((this.logged ?? []).some((line) => line.includes(text)), `the log says ${JSON.stringify(this.logged)}`);
});
