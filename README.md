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
part of the bucket. [`openapi.json`](openapi.json) describes every route, its tokens,
its answers and its errors (always `{"error": "..."}`), and `tests/openapi.test.js` fails
when it and the code disagree. The JavaScript and Python clients are generated from it
in [integrations](https://github.com/Sustenaut/integrations), on its `Caller`.

| Request | What it does |
|---|---|
| `GET /<tenant>/p/<id>/<width>.jpg` (or `.webp`) | A photo, cached for good: the id is a hash of the photo's content, so a photo never changes. |
| `POST /<tenant>/upload` | Stores a photo from the tenant's editor (multipart fields named `<width>.jpg` and `<width>.webp`, made in the browser) and answers its description: `{id, width, height, widths, formats}`. |
| `GET /<tenant>/f/<id>/<name>` | A file, cached for good: the id is the SHA-256 of its content. |
| `POST /<tenant>/files` | Stores one file (multipart field `file`, optional `name`, `label` such as "OPP-02 market report v3", `subject` such as a card's id, `kept=true`) for a tenant with `files`, and answers `{id, name, url, type, size, label, subject, kept}`. |
| `GET /<tenant>/head/<name>` | The file a named head points at, with its hash as `ETag`, for a private tenant with `heads` (below). |
| `PUT /<tenant>/head/<name>` | Moves the head to a stored file. |
| `GET /<tenant>/head/<name>/log` | Where the head has pointed, newest first. |
| `PUT /<tenant>/<inbox\|batches\|rejected>/...` | Stores a file in a buffer, for a private tenant with `inbox` (below). |
| `GET /<tenant>/<inbox\|batches\|rejected>/...` | Reads one. |
| `DELETE /<tenant>/<inbox\|batches\|rejected>/...` | Deletes one, for a principal on the tenant's `delete` list. |
| `GET /<tenant>/list?prefix=inbox/` | Lists a buffer's files in name order, up to 1,000 at a time, with a `cursor` for the next page. |
| `GET /<tenant>/list?prefix=f/` | Lists a private tenant's files, for its readers, the same way: each one's `name`, `id`, `url`, `size`, `uploaded` and `metadata` (`label`, `kept`, `by`, `for`, `subject`, as its upload gave them). A public tenant is never listed. |
| `POST /_clean` | Deletes the photos and files each tenant no longer uses, at most once a day. Kept files are never deleted. |

An upload has to carry the editor's GitHub token
(`Authorization: Bearer …`), and it is stored only if that token can push to
the tenant's `repository`. The person who may change the site's content is
the one who may add its photos.

The check is integrations' `Caller` (`@sustenaut/integrations`, pinned to a release
tag), as `github.repo-ops` `check-push`: a 10-second timeout, one try, and a record of
each call in this service's call-log buffer, `calls-storage`, through integrations' call-log
Durable Object (the `CALL_LOG` binding), which writes a file every two minutes, even an idle
one. GitHub's yes is kept for a minute (in memory, by a hash of the token and
repository), so an upload of many sizes or files asks GitHub once; a
revoked push permission can therefore still upload for up to a minute. A
no is never kept. GitHub not answering within 10 seconds, or failing, is a
503, to try again, not a 403.

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
| `types` | The extensions it takes, from pdf, pptx, docx, xlsx, csv, txt, png, jpg, jpeg, webp, gif, svg, cbor, json, gz, avro, whl and zip. |
| `max_bytes` | The largest file, 25 MB when not given (Pages takes at most 100 MB a request). |
| `kept` | `true` keeps every upload, as if each were sent with `kept=true`. |

A file is checked by its extension and, where the format has one, by its
first bytes (`%PDF-`, PNG, JPEG and so on; docx, pptx, xlsx and whl are zip
archives; csv, txt and svg must be text, and an svg must contain an `<svg`
tag; a cbor file must be a CBOR map, as every publet object is, and a json
file must parse as JSON, a gz file must start as gzip does, and an avro file as Avro does). It is served with its type, as an attachment for Office files, csv
and cbor, and with a sandboxing Content-Security-Policy, so an SVG's scripts
never run on this site. A public tenant's file address is a capability: anyone who has
it can read the file.

A private tenant's readers can list its files (`GET /<tenant>/list?prefix=f/`, with
`limit` and `cursor`; `f/<id>/` narrows it to one id). An upload's `subject` (up to 200
characters, like `label`) comes back in the listing's `metadata`, so a site can find the
files about one thing, such as a card, without keeping a table of its own. A public
tenant is never listed: its addresses stay the only way to its files.

**Kept files** are uploaded with `kept=true`: the client documents that
went out. The clean-up never deletes them. Uploading the same file again
without `kept` doesn't unkeep it.

### The tenants

| Tenant | Site | Keeps |
|---|---|---|
| `visit-ee` | visit.ee | photos |
| `opportunity` (private) | opportunity.sustenaut.eu | photos, and pdf, pptx, docx, png, jpg, svg, csv and xlsx files |
| `publications` (private) | pub.sustenaut.eu's publet objects | each publication release's `publication-0-objects.tar.gz`, uploaded by Sustenaut/business-plan's main and read by Sustenaut/pub-site and Sustenaut/estimate; all kept |
| `pdc` | pub.sustenaut.eu's copy of the PDC's signed objects (cbor) and their reading data (json), public like the PDC's own repository; all kept, written by Sustenaut/pub-site's main | a CID is a file's SHA-256, so each is at an address worked out from its CID |
| `release-sustenaut`, `release-schryer` (private) | the release control plane's board snapshots, one tenant per GitHub owner | json files, all kept, written by each owner's release-controlplane main, and each read by its own owner's deployment alone (`k8s:release/app`, `k8s:release-schryer/app`); a `board` head names the latest |
| `plane` (private) | the operating plane's shared state | json files of at most 1 MiB, all kept, written and read by the main branch of each of Sustenaut's observability, notifier, integrations, release-controlplane, opportunity-site, notebooks and auth (`github:Sustenaut/<repo>@refs/heads/main`); named heads point at the latest of each. Its pods' own identities (`k8s:plane/app`) come later. |
| `calls-integrations`, `calls-visit-ee`, `calls-opportunity-site`, `calls-business-plan`, `calls-storage`, `calls-release-controlplane`, `calls-notifier` (private) | the integrations call log's buffers, one tenant per consuming project (see Buffers below): written by the services that make the calls, loaded and deleted by its ingest pod alone. `calls-storage` is this service's own: integrations' call-log Durable Object writes it, from the records this service sends it. `calls-release-controlplane` is written by both owners' release-controlplane deployments (`k8s:release/app`, `k8s:release-schryer/app`). |
| `signals` (private) | Sustenaut/observability's signals, a buffer (see Buffers below) | written by observability's evaluator (`k8s:observability/evaluator`), loaded into BigQuery and deleted by the integrations ingest pod alone (`k8s:integrations/ingest`) |
| `notifier` (private) | Sustenaut/notifier's state: which signals it has posted | small json files, written and read by the notifier's pod alone (`k8s:notifier/app`); a `posted` head names the latest, moved with `If-Match` so two runs can't both win. It writes a new file only when it has posted something. |
| `facts` (private) | Sustenaut/business-plan's facts registry | its signed publet objects (cbor), all kept; uploaded by its editors from their own machines and read by business-plan's main |
| `sources` (private, its pdfs public) | Sustenaut/business-plan's sources corpus | papers (pdf) whose licence allows it, which come from elsewhere and stay public at the addresses signed records name; signed publet objects (cbor, named by their SHA-256 like any file) and their indexes (json); all kept, never cleaned; read by business-plan's main (the review site's image build) |
| `pypi` | the PyPI files the requirements locks pin, copied by the mirror workflow, served as a simple repository index (see The mirror below) | whl, gz and zip files, public, all kept, never cleaned; written by Sustenaut/storage's main alone |
| `terraform` | the Terraform providers CI uses, copied from their registries by the mirror workflow, served by Terraform's network mirror protocol (see The mirror below) | zip files, public, all kept, never cleaned; written by Sustenaut/storage's main alone |
| `wheels` | the wheels of Sustenaut's public releases, copied from GitHub by this repository's own mirror workflow (see The mirror below) | whl files, public, all kept, never cleaned; written by Sustenaut/storage's main alone |

### Buffers

A private tenant with `"inbox": true` also holds files waiting to be taken: the
integrations service's call logs, written by each sender and loaded and deleted by its
ingest pod. So what's in the buffer is what's still to do, and nothing needs to remember a
place in it.

| Folder | Holds |
|---|---|
| `inbox/<table>/<date>/` | Avro files waiting to load |
| `batches/` | json: which files the current load has |
| `rejected/<table>/<date>/` | Avro files that couldn't load, for a person |

A file is named by its sender and is checked as Avro or JSON, up to 50 MB. Sending a name
again replaces the file, which is how a sender retries, as the name holds a hash of its
content. Anyone on `read` or `write` may read and list; `write` may also store. Only a
principal on the tenant's `delete` list may delete, by OpenID Connect token. Unlike a
`file`, a buffer's file isn't cached and has no `kept`: the clean-up leaves private tenants
alone, so a file stays until it is deleted.

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
issuer to be turned on. Personal tokens and GitHub App tokens are not taken by a private tenant,
and it needs no `repository`, unless it says `"editors": true`: then a GitHub
token that may push to its `repository` may read and write it too, checked
with GitHub (and kept a minute, as above). `sources`, `facts`, `publications` and `opportunity` do, because people upload
from their own machines (`make sources-upload` and the like), where no workflow
token exists. Nothing is public until an explicit publishing step puts it
somewhere public, with one exception: `"public_types"` lists file types of a
private tenant that anyone may read, cached like a public tenant's. `sources`
lists `pdf`: the raw papers come from elsewhere, and its signed source records
name their addresses.

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

### Google service accounts

A Cloud Run service, or anything else running as a Google service account, asks its
metadata server for an identity token for the audience `storage.sustenaut.eu`, with
`format=full` so the token carries its address:

```
http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=storage.sustenaut.eu&format=full
```

with the header `Metadata-Flavor: Google`. No secret is stored anywhere. Its principal is
`gcp:<address>`, such as `gcp:plan@sustenaut.iam.gserviceaccount.com`. The token must be
signed by one of Google's keys and be for this audience and in date. It must also say
its address is verified, and that address must be a service account's. Any Google
account can ask for a token for this audience, so only the exact addresses in a
tenant's lists count. A `gcp:` entry matches only itself, never by its part after `@`.

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

### The mirror

When GitHub's release downloads fail, as they did on 2026-11-09 with 504s,
every CI run that installs one of our wheels fails with them. So storage
keeps a copy of each, and installs fall back to it.

`.github/workflows/mirror.yml` runs hourly. `mirror/wheels.sh` lists the
releases of every public repository of the owners in `mirror/sources.json`
and copies each attached wheel into the `wheels` tenant, skipping the ones
already there. A file here is named by its SHA-256, the same hash a lock
pins, so a lock line alone gives the fallback address:

```
https://github.com/Sustenaut/pubkit/releases/download/v0.31.3/pubkit-0.31.3-py3-none-any.whl --hash=sha256:adb0…
https://storage.sustenaut.eu/wheels/f/adb0…/pubkit-0.31.3-py3-none-any.whl
```

Storage only has to be there, never trusted: pip and uv still check the
hash. The workflow writes with its own OpenID Connect token on main, so no
package's release changes and no secret is kept. A wheel released less than
an hour ago may not be copied yet; run the workflow by hand to copy it now.
`DRY_RUN=1 mirror/wheels.sh` lists what a run would copy.

**The locks.** `mirror/locks.sh` fetches every `.terraform.lock.hcl` and
`requirements*.lock` at the default branch of the repositories the mirror
may read, and the next two copy what they pin. With the
`sustenaut-storage-mirror` GitHub App (`apps/sustenaut-storage-mirror.json`,
contents: read; its id and key are `MIRROR_APP_ID` and `MIRROR_APP_KEY`
here, sent by `./with-secrets ./pubkit app-secrets`), those are the
repositories its installation reaches, the private ones included. Without
it, they are the owners' public repositories. `scripts/go-live-mirror-app.sh`
makes the app and sets it up.

**Terraform providers.** `mirror/terraform.sh` copies each provider and
version the locks pin into the `terraform` tenant, for each platform
`mirror/sources.json` lists (CI's `linux_amd64`).

**PyPI packages.** `mirror/pypi.sh` copies the files the requirements locks
pin by name and version into the `pypi` tenant. A lock pins every
platform's wheel, so only the ones CI and our machines install are copied:
pure wheels, CPython 3.12 to 3.14 (or abi3) on manylinux x86_64, or the
sdist of a pin with none of those. A tenant with `"simple": true` serves a
[simple repository index](https://peps.python.org/pep-0503/) of its files
at `/<tenant>/simple/<project>/`, each link carrying its SHA-256, so pip
can install from it:

```sh
pip install --require-hashes --index-url https://storage.sustenaut.eu/pypi/simple/ -r tests/requirements.lock
```

A file is uploaded with its project's normalized name (PEP 503) as its
`subject`, and its name must start with that name and a version.

A tenant with `"providers": true` serves Terraform's
[provider network mirror protocol](https://developer.hashicorp.com/terraform/internals/provider-network-mirror-protocol)
from its archives: `GET /terraform/<hostname>/<namespace>/<type>/index.json`
lists the versions here, and `.../<version>.json` each platform's archive
with its `zh:` hash, which is the archive's SHA-256 and so its id here.
An archive is uploaded named as its release names it
(`terraform-provider-<type>_<version>_<os>_<arch>.zip`), with its
provider's address as its `subject`. A Terraform CLI configuration that
uses it:

```hcl
provider_installation {
  network_mirror { url = "https://storage.sustenaut.eu/terraform/" }
}
```

Terraform checks each archive against the module's lock, so here too
storage only has to be there.

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
npm run dev     # wrangler pages dev, with a local bucket
```

wrangler is a devDependency pinned at the version estimate pins, and
`package-lock.json` locks it, so every machine and the deploy (`npm run
deploy`) run the same wrangler; move it in both repositories together.

## Setting it up (once)

1. **The bucket.** Create an R2 bucket named `sustenaut-storage` in the
   Cloudflare account, either in the dashboard or with
   `npx --no-install wrangler r2 bucket create sustenaut-storage` after `npm ci`.
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
