// The ingest pod's word that a file arrived in a buffer's inbox: after storage takes a
// file under a buffer tenant's inbox/, it tells integrations' ingest pod, which then reads
// that file alone instead of listing every buffer (integrations.ingest.notify):
//
//   POST https://integrations.sustenaut.eu/ingest/notify
//   X-Ingest-Timestamp: <Unix seconds>
//   X-Ingest-Signature: sha256=<hex HMAC-SHA256 under INGEST_NOTIFY_KEY of "<timestamp>." and the body>
//   {"tenant": ..., "name": "inbox/...", "size": ...}
//
// INGEST_NOTIFY_KEY is the project's secret (the value of Bitwarden's INGEST_NOTIFY_KEY);
// without it nothing is sent, and the pod's sweep finds the file as before.
// INGEST_NOTIFY_URL, when set, is where the notices go instead.
//
// A notice is the call log's plumbing, so it goes by plain fetch and leaves no call record:
// recorded, each file taken would make one more record for calls-storage. It never
// rejects, and never touches the answer: it is sent after it (waitUntil), and one that
// fails is only said in the log, as the sweep finds what it named.

export const NOTIFY_URL = "https://integrations.sustenaut.eu/ingest/notify";
const TIMEOUT_MS = 10_000;

export async function signature(key, seconds, body) {
  const text = new TextEncoder();
  const hmac = await crypto.subtle.importKey("raw", text.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", hmac, text.encode(`${seconds}.${body}`)));
  return `sha256=${[...mac].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

// True once the pod has taken the notice; false when there is no key or it didn't.
export async function notify(env, tenant, name, size) {
  const key = env.INGEST_NOTIFY_KEY;
  if (!key) return false;
  const body = JSON.stringify({ tenant, name, size });
  const seconds = String(Math.floor(Date.now() / 1000));
  try {
    const response = await fetch(env.INGEST_NOTIFY_URL || NOTIFY_URL, {
      method: "POST", body, signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { "Content-Type": "application/json", "User-Agent": "sustenaut-storage", "X-Ingest-Timestamp": seconds,
        "X-Ingest-Signature": await signature(key, seconds, body) },
    });
    if (response.ok) return true;
    console.error(`storage: ingest didn't take the notice of ${tenant}/${name}: HTTP ${response.status}`);
  } catch (err) {
    console.error(`storage: ingest didn't take the notice of ${tenant}/${name}: ${err?.message ?? err}`);
  }
  return false;
}
