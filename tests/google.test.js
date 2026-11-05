// Google identity tokens, as a Cloud Run service's metadata server gives them, with
// Google's key set answered here, from a key made for the tests.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { verify, allowed, forgetKeys, AUDIENCE } from "../src/jwt.js";

const CERTS = "https://www.googleapis.com/oauth2/v3/certs";
const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const googleKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const otherKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
const jwk = { ...(await crypto.subtle.exportKey("jwk", googleKey.publicKey)), kid: "g1", use: "sig", alg: "RS256" };
const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
const now = () => Math.floor(Date.now() / 1000);
const ACCOUNT = "plan@sustenaut.iam.gserviceaccount.com";

async function token(claims = {}, key = googleKey.privateKey) {
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "g1" }));
  const p = b64url(JSON.stringify({
    iss: "https://accounts.google.com", aud: AUDIENCE, azp: "1234", sub: "1234", email: ACCOUNT,
    email_verified: true, iat: now(), exp: now() + 3600, ...claims,
  }));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}

let realFetch, fetched;
beforeEach(() => {
  forgetKeys();
  fetched = [];
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    if (String(url) === CERTS) return Response.json({ keys: [jwk] });
    throw new Error(`unexpected fetch ${url}`);
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

const refused = (t) => assert.rejects(verify(t), (err) => err.status === 401);

test("a service account's identity token names its verified address", async () => {
  assert.equal(await verify(await token()), `gcp:${ACCOUNT}`);
  assert.equal(await verify(await token({ iss: "accounts.google.com" })), `gcp:${ACCOUNT}`);
  assert.deepEqual(fetched, [CERTS]);
});

test("a Google token for another audience, out of date, or not signed by Google is refused", async () => {
  await refused(await token({ aud: "https://someone-else.example" }));
  await refused(await token({ exp: now() - 3600 }));
  await refused(await token({}, otherKey.privateKey));
});

test("only a verified service account's address is a principal", async () => {
  await refused(await token({ email_verified: false }));
  await refused(await token({ email_verified: "true" }));
  await refused(await token({ email: undefined }));
  // A person's Google account, and addresses dressed up as an account's.
  await refused(await token({ email: "someone@gmail.com" }));
  await refused(await token({ email: "plan@sustenaut.iam.gserviceaccount.com.example" }));
  await refused(await token({ email: "Plan@sustenaut.iam.gserviceaccount.com" }));
});

test("a tenant's list names Google accounts exactly", () => {
  assert.ok(allowed(`gcp:${ACCOUNT}`, [`gcp:${ACCOUNT}`]));
  assert.ok(!allowed("gcp:other@sustenaut.iam.gserviceaccount.com", [`gcp:${ACCOUNT}`]));
  assert.ok(!allowed(`gcp:${ACCOUNT}`, ["github:Sustenaut/business-plan"]));
  // The part after @ is never read as a ref: an account of the same name in another project isn't ours.
  assert.ok(!allowed("gcp:plan@someone-else.iam.gserviceaccount.com", ["gcp:plan"]));
  assert.ok(!allowed("k8s:opportunity/app@x", ["k8s:opportunity/app"]));
});
