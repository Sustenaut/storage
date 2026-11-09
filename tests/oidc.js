// GitHub's OIDC issuer for the tests: a key made here, its key set, and tokens
// it signs, for any repository and ref, with any claim or header overridden.
import { AUDIENCE } from "../src/jwt.js";

export const ISSUER = "https://token.actions.githubusercontent.com";
export const JWKS = `${ISSUER}/.well-known/jwks`;
export const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
export const issuerKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
export const otherKey = await crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
export const publicJwk = { ...(await crypto.subtle.exportKey("jwk", issuerKey.publicKey)), kid: "k1", use: "sig" };

export const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
export const now = () => Math.floor(Date.now() / 1000);

// A GitHub Actions token for a repository and ref, with any claim overridden.
export async function token(repository, ref = "refs/heads/main", { claims = {}, header = {}, key = issuerKey.privateKey } = {}) {
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "k1", ...header }));
  const body = { iss: ISSUER, aud: AUDIENCE, repository, ref, iat: now(), nbf: now() - 5, exp: now() + 300, ...claims };
  const p = b64url(JSON.stringify(body));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}
