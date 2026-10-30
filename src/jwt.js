// Who is behind an OpenID Connect token (a JWT), for the tenants that name
// their readers and writers (tenants.json "read" and "write").
//
// Only the issuers below are trusted, each with its own key set and its own
// way of naming the caller (a principal):
//
//   github:<owner>/<repo>@<ref>   a GitHub Actions job, from its OIDC token
//                                 (permissions: id-token: write, audience
//                                 storage.sustenaut.eu)
//   k8s:<namespace>/<account>     a pod on the Sustenaut k3s server, from
//                                 its projected service-account token
//                                 (audience storage.sustenaut.eu)
//   auth:<client>                 a client of auth.sustenaut.eu (Keycloak),
//                                 once its issuer is added here
//
// A token must be RS256, for the audience AUDIENCE, from a trusted issuer,
// signed by a key of that issuer's key set, and not expired or not yet
// valid (with LEEWAY seconds of clock skew). Anything else is refused.
//
// The k3s server's keys are pinned in k8s.json rather than fetched: its API
// isn't public. Its issuer name is k3s's default, which every cluster shares,
// so the pinned key is what makes a token ours. A new cluster (or a rotated
// service-account key) needs k8s.json updated, from
//   ssh root@sustenaut k3s kubectl get --raw /openid/v1/jwks

import K8S from "./k8s.json" with { type: "json" };

export const AUDIENCE = "storage.sustenaut.eu";
const LEEWAY = 60;
const KEYS_FOR_MS = 10 * 60e3; // a key set is fetched again after this
const UNKNOWN_KID_EVERY_MS = 60e3; // and at most this often for a key it doesn't have

export const ISSUERS = {
  "https://token.actions.githubusercontent.com": {
    jwks: "https://token.actions.githubusercontent.com/.well-known/jwks",
    principal: (c) => (c.repository && c.ref ? `github:${c.repository}@${c.ref}` : null),
  },
  [K8S.issuer]: {
    keys: K8S.jwks,
    principal: (c) => {
      const k = c["kubernetes.io"] || {};
      const ns = k.namespace, sa = k.serviceaccount?.name;
      return ns && sa && c.sub === `system:serviceaccount:${ns}:${sa}` ? `k8s:${ns}/${sa}` : null;
    },
  },
  // auth.sustenaut.eu, when a client there asks for this audience:
  // "https://auth.sustenaut.eu/realms/sustenaut": {
  //   jwks: "https://auth.sustenaut.eu/realms/sustenaut/protocol/openid-connect/certs",
  //   principal: (c) => (c.azp ? `auth:${c.azp}` : null),
  // },
};

// Whether a bearer token is a JWT rather than a GitHub token (ghp_, ghs_,
// github_pat_, gho_…), which never contain dots.
export const isJwt = (token) => /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token);

// The token's principal, or a 401 error saying why it was refused.
export async function verify(token, { issuers = ISSUERS, now = Date.now() } = {}) {
  const [h, p, s] = token.split(".");
  let header, claims;
  try {
    header = JSON.parse(text(b64url(h)));
    claims = JSON.parse(text(b64url(p)));
  } catch {
    throw unauthorized("not a token");
  }
  if (header.alg !== "RS256") throw unauthorized("tokens must be RS256");
  const issuer = Object.hasOwn(issuers, claims.iss) ? issuers[claims.iss] : null;
  if (!issuer) throw unauthorized("an issuer this service doesn't trust");
  const key = issuer.keys ? await pinnedKey(issuer.keys, header.kid) : await keyFor(issuer.jwks, header.kid, now);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64url(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw unauthorized("a bad signature");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(AUDIENCE)) throw unauthorized(`a token for another audience, not ${AUDIENCE}`);
  const seconds = now / 1000;
  if (typeof claims.exp !== "number" || claims.exp + LEEWAY < seconds) throw unauthorized("an expired token");
  if (typeof claims.nbf === "number" && claims.nbf - LEEWAY > seconds) throw unauthorized("a token not valid yet");
  const principal = issuer.principal(claims);
  if (!principal) throw unauthorized("a token that doesn't say who it is");
  return principal;
}

// Whether a principal is among a tenant's: "github:<repo>" allows any ref of
// that repository, "github:<repo>@<ref>" only that ref. Repositories are
// compared without case, as GitHub does; refs exactly.
export function allowed(principal, list = []) {
  return list.some((entry) => {
    if (entry === principal) return true;
    const [name, ref] = split(entry);
    const [pName, pRef] = split(principal);
    return name.toLowerCase() === pName.toLowerCase() && (ref === undefined || ref === pRef);
  });
}

function split(principal) {
  const at = principal.indexOf("@");
  return at < 0 ? [principal, undefined] : [principal.slice(0, at), principal.slice(at + 1)];
}

// Key sets, kept per isolate.
const sets = new Map(); // jwks url -> { at, keys: Map(kid -> CryptoKey), tried }

async function keyFor(url, kid, now) {
  let set = sets.get(url);
  if (!set || now - set.at > KEYS_FOR_MS || (!set.keys.has(kid) && now - set.tried > UNKNOWN_KID_EVERY_MS)) {
    set = await fetchKeys(url, now, set);
    sets.set(url, set);
  }
  const key = set.keys.get(kid);
  if (!key) throw unauthorized("a key this service doesn't know");
  return key;
}

// A pinned key set, imported once.
const pinned = new WeakMap(); // jwks object -> Promise(Map(kid -> CryptoKey))

async function pinnedKey(jwks, kid) {
  if (!pinned.has(jwks)) pinned.set(jwks, importKeys(jwks.keys || []));
  const key = (await pinned.get(jwks)).get(kid);
  if (!key) throw unauthorized("a key this service doesn't know");
  return key;
}

async function fetchKeys(url, now, old) {
  const response = await fetch(url).catch(() => null);
  if (!response?.ok) {
    if (old) return { ...old, tried: now };
    throw unauthorized("the issuer's keys can't be read now");
  }
  const { keys = [] } = await response.json();
  return { at: now, tried: now, keys: await importKeys(keys) };
}

async function importKeys(keys) {
  const imported = new Map();
  for (const jwk of keys) {
    if (jwk.kty !== "RSA" || (jwk.use && jwk.use !== "sig") || !jwk.kid) continue;
    const { kty, n, e } = jwk;
    imported.set(jwk.kid, await crypto.subtle.importKey("jwk", { kty, n, e, alg: "RS256", ext: true }, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]));
  }
  return imported;
}

// For the tests: forget the key sets.
export const forgetKeys = () => sets.clear();

function b64url(s) {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

const text = (bytes) => new TextDecoder().decode(bytes);

function unauthorized(message) {
  const err = new Error(`refused: ${message}`);
  err.status = 401;
  return err;
}
