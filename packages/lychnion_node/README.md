# lychnion_node

A headless Lychnion node: a single program that serves Lychnion packages
and maps to the app and to other nodes, and keeps itself current. For
people who run a server or a small box; a city or a club can also use
the desktop app instead (docs/distribution.md).

It serves a folder with the same layout as every node:

```text
catalog.json             signed records, files listed by hash
blobs/sha256/<sha256>    every file, named by its SHA-256
```

Nothing on the node needs trust: the app checks every record's
signature and every file's hash. The node never holds a signing key.

## Commands

```sh
# fill (and later update) a folder from one or more catalogs
lychnion_node pull --into /srv/lychnion \
  --kind package --kind map \
  https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json

# also a city's catalog, signed with its key (from its lychnion://publisher link)
lychnion_node pull --into /srv/lychnion \
  --publisher jp.city.kobe=<public key> \
  https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json \
  https://bousai.example.jp/lychnion/catalog.json

# serve it (port 8642, as a base)
lychnion_node serve /srv/lychnion

# check signatures and hashes
lychnion_node check /srv/lychnion --publisher jp.city.kobe=<public key>
```

`pull` keeps only records signed by Lychnion (built in) or by a
publisher given with `--publisher`, fetches their files by hash
(resumable, from every address the catalog gives, mirrors included),
and writes `catalog.json`. Versions only go up; an id stays with the
publisher that has it in the folder; a record is listed only when all
its files are there, otherwise the version before stays. Files no
record lists any more are removed. `--kind` limits it to `package`,
`map` or `model` (models are gigabytes). Run it from cron to keep the
node current, for example every hour.

`pull` also reads a folder instead of an address, for example a USB
stick written by the desktop app ("Copy to a USB stick") or another
node's folder: `lychnion_node pull --into /srv/lychnion /media/stick`.
Every file is checked by its hash there too.

`serve` answers `GET`/`HEAD` for `/catalog.json` and
`/blobs/sha256/<hash>` (with Range, so downloads resume), and one line
at `/`; nothing else. It logs one line per request.

## Keeping itself current

Instead of cron:

```sh
# pull now, then every 30 minutes; after a failed run (no internet)
# again after 1, 2, 4 … minutes, so a short window is not missed
lychnion_node pull --into /srv/lychnion --every 30m --kind package --kind map \
  https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json

# or serve and pull in one process (one container)
lychnion_node serve /srv/lychnion --every 30m --kind package --kind map \
  --pull https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json
```

`--every` takes `30m`, `1h`, `2h30m` (at least a minute). After a run
that worked the next one comes after that time, give or take a tenth
(so many nodes do not ask at the same second). Ctrl-C or `docker stop`
ends it; a download in the middle resumes next time.

In the app, a node is a catalog to follow (Settings → Catalogs):
`http://<node>:8642/catalog.json`.

## Build

```sh
dart pub get
dart compile exe bin/lychnion_node.dart -o lychnion_node
```

Or as a container, from the repository root:

```sh
docker build -f packages/lychnion_node/Dockerfile -t lychnion-node .
docker run -d -v /srv/lychnion:/data -p 8642:8642 lychnion-node
docker run --rm -v /srv/lychnion:/data lychnion-node \
  pull --into /data --kind package \
  https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json

# one container that serves and keeps itself current
docker run -d --restart unless-stopped -v lychnion:/data -p 8642:8642 \
  lychnion-node serve /data --every 30m --kind package --kind map \
  --pull https://github.com/lychnion/lychnion-data/releases/latest/download/catalog.json
```

The image holds only the compiled program and its runtime files, and
runs as an unprivileged user (65534). A named volume is writable by it;
a host folder mounted at /data must be writable by user 65534 for
`pull`.

## Operating it

- `pull` takes a lock on the folder: a second run while one is still
  working (a long download) ends at once with exit code 75.
- Exit codes: 0 done, 1 something failed (the last good state stays),
  64 wrong arguments, 74 a file problem (disk full, permissions),
  75 another pull is running.
- Files of records from a publisher you no longer give with
  `--publisher` are kept, not deleted: the record is set aside in
  `.kept.json` (not served) and listed again once you give the key.
  It still holds its id.
- Addresses a catalog gives on private or local networks (also after
  a redirect, also written as `::ffff:a.b.c.d`) are skipped, unless the
  catalog itself is on such a network (a base). Names are looked up
  once per pull; a name that changes its address between the lookup
  and the download is not caught.
- `pull` checks sizes; `check` also checks every hash. Run `check` now
  and then to find a damaged disk.
- A record stays until a higher version replaces it; a publisher
  cannot withdraw a version from nodes yet (to be decided with step 5).
- `serve` takes at most 64 requests at a time and closes idle
  connections after 30 seconds. On the open internet, put it behind a
  reverse proxy (TLS, rate limits).

Licence: AGPL-3.0, as the app.
