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
| `GET /<tenant>/head/<name>` | The file a named head points at, with its hash as `ETag`, for a private tenant with `heads` (below). |
| `PUT /<tenant>/head/<name>` | Moves the head to a stored file. |
| `GET /<tenant>/head/<name>/log` | Where the head has pointed, newest first. |
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

A GitHub Actions job can upload with its OpenID Connect token instead,
when the tenant's `write` list names it (see "Private tenants" below for
how). That takes no secret at all.

Only the tenant's `origins` (and
`http://localhost`, for development) get CORS headers for uploads.

### Files

A tenant that has `files` in `tenants.json` can store files besides photos:

| `files` key | What |
|---|---|
| `types` | The extensions it takes, from pdf, pptx, docx, xlsx, csv, txt, png, jpg, jpeg, webp, gif, svg, cbor, json and gz. |
| `max_bytes` | The largest file, 25 MB when not given (Pages takes at most 100 MB a request). |
| `kept` | `true` keeps every upload, as if each were sent with `kept=true`. |

A file is checked by its extension and, where the format has one, by its
first bytes (`%PDF-`, PNG, JPEG and so on; docx, pptx and xlsx are zip
archives; csv, txt and svg must be text, and an svg must contain an `<svg`
tag; a cbor file must be a CBOR map, as every publet object is, and a json
file must parse as JSON, and a gz file must start as gzip does). It is served with its type, as an attachment for Office files, csv
and cbor, and with a sandboxing Content-Security-Policy, so an SVG's scripts
never run on this site. A public tenant's file address is a capability: anyone who has
it can read the file.

**Kept files** are uploaded with `kept=true`: the client documents that
went out. The clean-up never deletes them. Uploading the same file again
without `kept` doesn't unkeep it.

### The tenants

| Tenant | Site | Keeps |
|---|---|---|
| `visit-ee` | visit.ee | photos |
| `opportunity` | opportunity.sustenaut.eu | photos, and pdf, pptx, docx, png, jpg, svg, csv and xlsx files |
| `publications` (private) | pub.sustenaut.eu's publet objects | each publication release's `publication-0-objects.tar.gz`, uploaded by Sustenaut/business-plan's main and read by Sustenaut/pub-site; all kept |
| `release-sustenaut`, `release-schryer` (private) | the release control plane's board snapshots, one tenant per GitHub owner | json files, all kept, written by Sustenaut/release's main and read by the release app; a `board` head names the latest |
| `sources` | Sustenaut/business-plan's sources corpus | papers (pdf) whose licence allows it, signed publet objects (cbor, named by their SHA-256 like any file) and their indexes (json); all kept, and with no `in_use` list nothing is ever cleaned |

### Private tenants

A tenant with `"private": true` serves nothing to the public. Every read
and every write needs an OpenID Connect token (a JWT) whose **principal**
is on the tenant's lists:

| Key | Who |
|---|---|
| `read` | may read its photos and files |
| `write` | may upload, and read |

A principal is `github:<owner>/<repo>` (any ref) or
`github:<owner>/<repo>@<ref>` (only that ref, such as
`refs/heads/main`): a GitHub Actions job of that repository. `auth:<client>`, a
client of auth.sustenaut.eu, is ready in `src/jwt.js`, waiting for its
issuer to be turned on. Personal tokens and GitHub App tokens are never
taken by a private tenant, and it needs no `repository`.

`k8s:<namespace>/<account>` is a pod on the Sustenaut k3s server, by its
projected service-account token (below).

A token is taken only if it is RS256, from a trusted issuer (only
`https://token.actions.githubusercontent.com` for now), signed by a key in
that issuer's published key set, for the audience `storage.sustenaut.eu`,
and in date (a minute of clock skew allowed). The service fetches the key
sets itself and keeps them for ten minutes, so it holds no secret.

A private tenant's files are never cached: not by Cloudflare's cache, and
not by a browser (`Cache-Control: private, no-store`, `Vary: Authorization`).
Only the tenant's `origins` get CORS headers, never `*`. The clean-up
never touches a private tenant.

A public tenant can have a `write` list too: those workflows then upload
with their token, besides the editors' GitHub tokens.

In a workflow, ask GitHub for a token for this audience (the job needs
`permissions: id-token: write`), then send it like any other:

```sh
token=$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=storage.sustenaut.eu" | jq -r .value)
curl -fsS -H "Authorization: Bearer $token" -F file=@publication-0-objects.tar.gz \
  https://storage.sustenaut.eu/publications/files
```

### Pods on the k3s server

A pod uploads with a service-account token Kubernetes projects into it for
the audience `storage.sustenaut.eu`; no secret is stored anywhere. Its
principal is `k8s:<namespace>/<account>` (the opportunity site:
`k8s:opportunity/app`, in the `opportunity` tenant's `write`). The token
must name exactly `system:serviceaccount:<namespace>:<account>`, be for this
audience, unexpired, and signed by a key in `src/k8s.json`. The server's API
isn't public, so its keys are pinned there rather than fetched: k3s's issuer
name is the same in every cluster, and the key is what makes a token ours.

In the pod (business-plan's `opportunity-site/k8s/app.yaml`): a dedicated
service account with no RBAC bindings, `automountServiceAccountToken: false`,
and only a projected token volume (audience `storage.sustenaut.eu`,
`expirationSeconds: 600`), read from its file on each upload. It never goes
in an environment variable, an image, git or a log. This service logs
nothing of a request but errors.

**Revoking a pod's access:** take its principal out of the tenant's `write`
and deploy (immediate); delete the service account too
(`k3s kubectl -n <namespace> delete serviceaccount <account>`), which
invalidates its tokens on the server.

**Rotating the k3s signing key** (or a new server): put the new public keys in
`src/k8s.json` first, alongside the old, and deploy; then rotate
(`/var/lib/rancher/k3s/server/tls/service.key`, restart k3s); then remove the
old key. Read the keys with

```sh
ssh root@sustenaut k3s kubectl get --raw /openid/v1/jwks
```

The tests fail while `src/k8s.json` has no keys.

A file's id is its SHA-256, so a reader that knows the hash it wants also
knows the address: `/publications/f/<sha256>/<name>`.

### Named heads

A file here never changes, so nothing says which one is the latest. A private
tenant with `"heads": true` can keep names for that, such as `board`. Reading
needs the same token as reading a file, and moving one the same as uploading:

```sh
# Upload the file, then point the head at its id, the SHA-256 of its content.
curl -fsS -H "Authorization: Bearer $token" -F file=@board.json \
  https://storage.sustenaut.eu/release-sustenaut/files
curl -fsS -X PUT -H "Authorization: Bearer $token" -H "If-Match: \"$current\"" \
  -d "{\"hash\": \"$hash\"}" https://storage.sustenaut.eu/release-sustenaut/head/board
```

The `ETag` of `GET` or `HEAD /<tenant>/head/<name>` is the hash it points at,
quoted. `PUT` needs that hash in `If-Match`, or `If-None-Match: *` for a head
that has never moved, and answers `412` when the head points elsewhere, also if
another move got there first. So two writers can't overwrite each other: the
one that loses reads the head again. Moving a head to where it already points
changes nothing and adds nothing to the log.

`GET /<tenant>/head/<name>/log` answers
`{"name": "board", "log": [{"hash", "time", "principal"}, …]}`, newest first,
starting with where it points now. A head's files can't be deleted, because
the clean-up never touches a private tenant. A head can't be deleted either.

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
   Sustenaut/business-plan's `pubkit.json`, applied by its infra like
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
