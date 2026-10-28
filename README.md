# storage

storage.sustenaut.eu keeps photos and other files for the sites
built on sustenaut.eu in a Cloudflare R2 bucket and serves them. The files
then don't sit in each site's git repository or count toward its Pages
deployment, which allows 20,000 files.

It is a Cloudflare Pages project, `sustenaut-storage`. `functions/` runs
the service (`src/storage.js`) and `public/` holds its one page. Its DNS
name is a CNAME to the project, like maps.sustenaut.eu, so it works at
every DNS provider of the zone.

## What it does

Each site that uses it is a **tenant** in `tenants.json` and gets its own
part of the bucket:

| Request | What it does |
|---|---|
| `GET /<tenant>/p/<id>/<width>.jpg` (or `.webp`) | A photo, cached for good: the id is a hash of the photo's content, so a photo never changes. |
| `POST /<tenant>/upload` | Stores a photo from the tenant's editor (multipart fields named `<width>.jpg` and `<width>.webp`, made in the browser) and answers its description: `{id, width, height, widths, formats}`. |
| `GET /<tenant>/f/<id>/<name>` | A file, cached for good: the id is the SHA-256 of its content. |
| `POST /<tenant>/files` | Stores one file (multipart field `file`, optional `name`, `label` such as "OPP-02 market report v3", `kept=true`) for a tenant with `files`, and answers `{id, name, url, type, size, label, kept}`. |
| `POST /_clean` | Deletes the photos and files each tenant no longer uses, at most once a day. Kept files are never deleted. |

An upload has to carry the editor's GitHub token
(`Authorization: Bearer …`), and it is stored only if that token can push to
the tenant's `repository`. The person who may change the site's content is
the one who may add its photos.

A service can upload with its GitHub App's installation token (`ghs_…`)
instead. Such a token can't say who its user is, so the check is different:
the app's installation must list the tenant's repository with push
(contents: write). The file is recorded as uploaded by `github-app`, and
the `for` field (the person the service uploads for) is kept with it. A
person's token can't set `for`.

Only the tenant's `origins` (and
`http://localhost`, for development) get CORS headers for uploads.

### Files

A tenant that has `files` in `tenants.json` can store files besides photos:

| `files` key | What |
|---|---|
| `types` | The extensions it takes, from pdf, pptx, docx, xlsx, csv, txt, png, jpg, jpeg, webp, gif, svg, cbor and json. |
| `max_bytes` | The largest file, 25 MB when not given (Pages takes at most 100 MB a request). |
| `kept` | `true` keeps every upload, as if each were sent with `kept=true`. |

A file is checked by its extension and, where the format has one, by its
first bytes (`%PDF-`, PNG, JPEG and so on; docx, pptx and xlsx are zip
archives; csv, txt and svg must be text, and an svg must contain an `<svg`
tag; a cbor file must be a CBOR map, as every publet object is, and a json
file must parse as JSON). It is served with its type, as an attachment for Office files, csv
and cbor, and with a sandboxing Content-Security-Policy, so an SVG's scripts
never run on this site. A file's address is a capability: anyone who has
it can read the file.

**Kept files** are uploaded with `kept=true`: the client documents that
went out. The clean-up never deletes them. Uploading the same file again
without `kept` doesn't unkeep it.

### The tenants

| Tenant | Site | Keeps |
|---|---|---|
| `visit-ee` | visit.ee | photos |
| `opportunity` | opportunity.sustenaut.eu | photos, and pdf, pptx, docx, png, jpg, svg, csv and xlsx files |
| `sources` | schryer/business-plan's sources corpus | papers (pdf) whose licence allows it, signed publet objects (cbor, named by their SHA-256 like any file) and their indexes (json); all kept, and with no `in_use` list nothing is ever cleaned |

### The clean-up

The clean-up runs nightly (`.github/workflows/clean.yml`). For each
tenant, it reads the photos the site uses from the tenant's `in_use`
address (`{"photos": ["<id>", …], "files": ["<id>", …]}`, which the site
writes) and deletes the others, but only once they are 30 days old. That way a photo
waiting in an open pull request survives. A tenant whose list can't be
read, or comes back empty while it has photos, is left alone, and so is a
tenant without `in_use`. Files are
treated the same way, except kept ones. A list without a `files` key never
has files deleted.

The clean-up needs no secret, so there is no token to keep or rotate. It
does only what the sites' own public lists say, and the service runs it at
most once every 20 hours, however often `/_clean` is called. Asking more
often gets `429`.

### Adding a site

Add it to `tenants.json`:

```json
"visit-ee": {
  "repository": "schryer/visit-ee",
  "origins": ["https://temp.schryer.eu", "https://visit.ee"],
  "in_use": "https://temp.schryer.eu/photos.json"
}
```

Add `"files": {"types": ["pdf", "png"], "max_bytes": 26214400}` for a site
that keeps files too, like `opportunity` (opportunity.sustenaut.eu).

## Working on it

```sh
npm ci
npm test        # node --test, with an in-memory bucket and GitHub answered locally
```

`npx wrangler pages dev public --r2 STORAGE` runs it locally with a local
bucket.

## Setting it up (once)

1. **The bucket.** Create an R2 bucket named `sustenaut-storage` in the
   Cloudflare account, either in the dashboard or with
   `npx wrangler r2 bucket create sustenaut-storage`.
2. **The Pages project and the name.** These come from the `storage` site in
   schryer/business-plan's `pubkit.json`, applied by its infra like
   maps.sustenaut.eu.
3. **The deploy's secrets.** In this repository's Actions settings, add the
   secret `CLOUDFLARE_GITHUB_API_TOKEN` (the same Pages-only token maps
   uses) and the variable `CLOUDFLARE_ACCOUNT_ID`. If the deploy says the
   token can't bind the bucket, give the token "Workers R2 Storage: Read"
   as well.
4. **Turn it on.** Set the repository variable `STORAGE_DEPLOY` to `on`.
   The next push to main deploys.
5. **Protect main.** Run `pubkit protect Sustenaut/storage` as a repository
   admin.
