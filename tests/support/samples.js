// The bytes a scenario's files hold, named in plain words in a feature:
//
//   a 480x360 JPEG                  a JPEG's first bytes, its start-of-frame giving its size
//   a 480x360 JPEG padded by N bytes
//   a WebP                          a WebP's first bytes
//   a PDF                           %PDF-1.7, the line "report", %%EOF
//   a PDF reading "T"               the same with the line T
//   a PDF reading "T" N times       the line is T, N times over
//   an SVG                          an empty SVG
//   a CBOR map                      a publet object's first bytes: a map of three
//   an Avro file of N bytes         Avro's first bytes, then zeros up to N
//   the bytes 50 4b 03 04           those bytes, in hex
//   the text T                      T, as UTF-8
//   the text "T" N times            T, N times over
//   nothing                         no bytes at all
const encode = (text) => new TextEncoder().encode(text);

export function jpeg(width, height, extra = 0) {
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 255, width >> 8, width & 255, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1];
  return new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0, 0, ...sof, ...new Array(extra).fill(0), 0xff, 0xd9]);
}

const pdf = (text) => encode(`%PDF-1.7\n${text}\n%%EOF`);

const SAMPLES = [
  [/^an? (\d+)x(\d+) JPEG(?: padded by (\d+) bytes)?$/, (w, h, extra) => jpeg(Number(w), Number(h), Number(extra || 0))],
  [/^a WebP$/, () => encode("RIFF\0\0\0\0WEBPVP8 ")],
  [/^a PDF$/, () => pdf("report")],
  [/^a PDF reading "(.*)"(?: (\d+) times)?$/, (text, n) => pdf(text.repeat(Number(n || 1)))],
  [/^an SVG$/, () => encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>')],
  [/^a CBOR map$/, () => new Uint8Array([0xa3, 0x61, 0x76, 0x01, 0x61, 0x6b, 0x02, 0x61, 0x64, 0x03])],
  [/^an Avro file of (\d+) bytes$/, (n) => {
    const bytes = new Uint8Array(Number(n));
    bytes.set([0x4f, 0x62, 0x6a, 0x01, 0x07].slice(0, Number(n)));
    return bytes;
  }],
  [/^the bytes ((?:[0-9a-f]{2} ?)+)$/, (hex) => bytes(hex)],
  [/^the text "(.*)" (\d+) times$/, (text, n) => encode(text.repeat(Number(n)))],
  [/^the text (.*)$/s, (text) => encode(text)],
  [/^nothing$/, () => new Uint8Array()],
];

/** The bytes a description names; anything else is a mistake in the feature. */
export function sample(description) {
  for (const [pattern, make] of SAMPLES) {
    const m = description.match(pattern);
    if (m) return make(...m.slice(1));
  }
  throw new Error(`no sample is described as ${JSON.stringify(description)}`);
}

/** Bytes written in hex, with or without spaces between them. */
export function bytes(hex) {
  return Uint8Array.from(hex.replace(/\s+/g, "").match(/../g) ?? [], (b) => parseInt(b, 16));
}

export const hex = (data) => Buffer.from(data).toString("hex").replace(/(..)(?!$)/g, "$1 ");
