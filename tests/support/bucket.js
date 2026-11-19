// An R2 bucket in memory, as R2 does what src/storage.js asks of it: conditional
// writes (onlyIf), listings in key order a page at a time with a cursor, and
// custom metadata in a listing only when it is asked for.
export class Bucket {
  constructor() {
    this.objects = new Map();
    this.listed = []; // what each list() asked: { prefix, limit, include }
    this.page = 1000; // the most a listing gives at once, whatever its limit
    this.version = 0;
    this.beforePut = null; // a scenario's way in between a read and a write
    this.failing = null; // a key's ending whose writes fail, as a bucket that's down
  }

  async put(key, value, { customMetadata = {}, httpMetadata, onlyIf } = {}) {
    await this.beforePut?.(key);
    if (this.failing && key.endsWith(this.failing)) throw new Error("the bucket is down");
    const had = this.objects.get(key);
    if (onlyIf?.etagMatches && had?.etag !== onlyIf.etagMatches) return null;
    if (onlyIf?.etagDoesNotMatch === "*" && had) return null;
    const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
    const etag = `v${++this.version}`;
    const o = { key, bytes, size: bytes.length, customMetadata: { ...customMetadata }, httpMetadata, etag, httpEtag: `"${etag}"`, uploaded: new Date() };
    this.objects.set(key, o);
    return { ...o };
  }

  async get(key) {
    const o = this.objects.get(key);
    if (!o) return null;
    return {
      ...o,
      customMetadata: { ...o.customMetadata },
      body: o.bytes.slice(),
      text: async () => new TextDecoder().decode(o.bytes),
      arrayBuffer: async () => o.bytes.slice().buffer,
    };
  }

  async list({ prefix = "", limit = 1000, cursor, include = [] } = {}) {
    this.listed.push({ prefix, limit, include });
    const found = [...this.objects.values()].filter((o) => o.key.startsWith(prefix)).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    const start = cursor ? Number(cursor) : 0;
    const end = start + Math.min(limit, this.page);
    const objects = found.slice(start, end).map(({ bytes, customMetadata, ...o }) =>
      (include.includes("customMetadata") ? { ...o, customMetadata: { ...customMetadata } } : o));
    return end < found.length ? { objects, truncated: true, cursor: String(end) } : { objects, truncated: false };
  }

  async delete(keys) {
    for (const key of [keys].flat()) this.objects.delete(key);
  }
}
