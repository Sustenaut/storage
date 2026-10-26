# storage

storage.sustenaut.eu keeps photos (and later other files) for the sites
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
| `POST /_clean` | Deletes the photos each tenant no longer uses, at most once a day. |

An upload has to carry the editor's GitHub token
(`Authorization: Bearer …`), and it is stored only if that token can push to
the tenant's `repository`. The person who may change the site's content is
the one who may add its photos. Only the tenant's `origins` (and
`http://localhost`, for development) get CORS headers for uploads.

The clean-up runs nightly (`.github/workflows/clean.yml`). For each
tenant, it reads the photos the site uses from the tenant's `in_use`
address (`{"photos": ["<id>", …]}`, which the site's build writes) and
deletes the others, but only once they are 30 days old. That way a photo
waiting in an open pull request survives. A tenant whose list can't be
read, or comes back empty while it has photos, is left alone.

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
5. **Protect main.** Run `pubkit protect schryer/storage` as a repository
   admin.
