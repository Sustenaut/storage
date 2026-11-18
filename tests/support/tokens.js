// The issuers whose tokens the service takes, with keys made for the tests:
// GitHub's OIDC issuer (its key set answered by a fake service), the k3s server
// (its key pinned, as src/k8s.json pins the real one's) and Google.
import { AUDIENCE, ISSUERS } from "../../src/jwt.js";

export const GITHUB_ISSUER = "https://token.actions.githubusercontent.com";
export const K8S_ISSUER = "https://kubernetes.default.svc.cluster.local";
export const GOOGLE_ISSUER = "https://accounts.google.com";
const RSA = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
const made = () => crypto.subtle.generateKey(RSA, true, ["sign", "verify"]);
export const KEYS = { github: await made(), k8s: await made(), google: await made(), other: await made() };
const jwk = async (key, kid, extra = {}) => ({ ...(await crypto.subtle.exportKey("jwk", key.publicKey)), kid, use: "sig", ...extra });

/** The key sets the issuers publish: GitHub's and Google's are fetched. */
export const KEY_SETS = {
  github: { keys: [await jwk(KEYS.github, "k1")] },
  google: { keys: [await jwk(KEYS.google, "g1", { alg: "RS256" })] },
};

/** The issuers as src/jwt.js knows them, but with the k3s server's key the tests' own. */
export const PINNED = {
  [K8S_ISSUER]: { ...ISSUERS[K8S_ISSUER], keys: { keys: [await jwk(KEYS.k8s, "k8s1")] } },
};

const b64url = (data) => Buffer.from(data).toString("base64url");
const now = () => Math.floor(Date.now() / 1000);

/** A claim's value as a feature writes it: JSON, or now±seconds, or else text. */
export function claimValue(text) {
  const relative = text.match(/^now ?([+-]) ?(\d+)$/);
  if (relative) return now() + (relative[1] === "+" ? 1 : -1) * Number(relative[2]);
  if (text === "now") return now();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

/** What a token is made of, before it is signed: an issuer's usual claims. */
export function recipe(kind, ...args) {
  if (kind === "github") {
    const [repository, ref] = args;
    return {
      header: { alg: "RS256", typ: "JWT", kid: "k1" }, key: KEYS.github,
      claims: { iss: GITHUB_ISSUER, aud: AUDIENCE, repository, ref, iat: now(), nbf: now() - 5, exp: now() + 300 },
    };
  }
  if (kind === "pod") {
    const [ns, sa] = args;
    return {
      header: { alg: "RS256", kid: "k8s1" }, key: KEYS.k8s,
      claims: {
        iss: K8S_ISSUER, aud: [AUDIENCE], sub: `system:serviceaccount:${ns}:${sa}`, iat: now(), nbf: now(), exp: now() + 600,
        "kubernetes.io": { namespace: ns, serviceaccount: { name: sa, uid: "u" }, pod: { name: "app-1", uid: "p" } },
      },
    };
  }
  const [email] = args;
  return {
    header: { alg: "RS256", typ: "JWT", kid: "g1" }, key: KEYS.google,
    claims: { iss: GOOGLE_ISSUER, aud: AUDIENCE, azp: "1234", sub: "1234", email, email_verified: true, iat: now(), exp: now() + 3600 },
  };
}

/** The token a recipe makes: its header and claims, signed with its key. A
 * claim set to undefined is left out. */
export async function sign({ header, claims, key }) {
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(claims));
  const s = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(s))}`;
}

export const part = (object) => b64url(JSON.stringify(object));

/** A GitHub Actions token for a repository at a ref. */
export const actionsToken = (repository, ref = "refs/heads/main") => sign(recipe("github", repository, ref));
