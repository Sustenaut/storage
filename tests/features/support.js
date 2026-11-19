// cucumber-js's setup for these scenarios: pubtest's steps (GRAMMAR.md), with
// its HTTP client sending each request to the Worker's handler, and each
// scenario's world: an R2 bucket in memory, the tenants it names, and the web
// the Worker reaches, which is pubtest's fake services.
import * as cucumber from "@cucumber/cucumber";
import { After, Before, setDefaultTimeout } from "@cucumber/cucumber";
import { mock } from "node:test";
import { register, Answer } from "@sustenaut/pubtest";
import { handle, allowedCache } from "../../src/storage.js";
import { forgetKeys } from "../../src/jwt.js";
import { Bucket } from "../support/bucket.js";

setDefaultTimeout(60_000);

// What a request to the Worker answers, with its body's bytes kept too, for a
// file that isn't text.
const worker = (world) => async (method, path, headers, body) => {
  const request = new Request(new URL(path, "https://storage.example"), { method, headers, body: body ?? undefined, redirect: "manual" });
  const response = await handle(request, world.env, world.tenants, world.options);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const answer = new Answer(response.status, Object.fromEntries(response.headers.entries()), new TextDecoder().decode(bytes));
  answer.bytes = bytes;
  return answer;
};

register(cucumber, { client: worker });

// The hosts the Worker calls, by the name of the fake service that answers each.
export const SERVICES = {
  "api.github.com": "GitHub",
  "token.actions.githubusercontent.com": "GitHub's OIDC issuer",
  "www.googleapis.com": "Google",
};
const serviceOf = (host) => SERVICES[host] ?? host;

const realFetch = globalThis.fetch;
const realCaches = globalThis.caches;

Before(function () {
  this.env = { STORAGE: new Bucket() };
  this.tenants = {};
  this.options = {};
  this.sent = []; // every request the Worker sent, with whether it had a timeout
  this.down = {}; // a service that can't be reached or doesn't answer in time, by name
  this.cacheAsked = [];
  forgetKeys();
  allowedCache.entries.clear();
  // A request to a host goes to the fake service of its name, or fails as the
  // scenario says that service does; a host no scenario set up is a mistake.
  globalThis.fetch = async (url, options = {}) => {
    const target = new URL(String(url));
    const name = serviceOf(target.host);
    this.sent.push({ name, url: String(url), timeout: options.signal instanceof AbortSignal });
    if (this.down[name]) throw this.down[name]();
    const fake = this.pubtest.fakes[name];
    if (!fake) throw new Error(`unexpected fetch ${url}`);
    return realFetch(`${fake.url}${target.pathname}${target.search}`, options);
  };
  // Cloudflare's Cache API, which keeps nothing and says what it was asked.
  globalThis.caches = {
    default: {
      match: async (request) => (this.cacheAsked.push(["match", request.url]), undefined),
      put: async (request) => this.cacheAsked.push(["put", request.url]),
    },
  };
});

After(function () {
  globalThis.fetch = realFetch;
  globalThis.caches = realCaches;
  mock.timers.reset();
});
