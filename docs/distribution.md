# Distribution: apps and data packages

Design note, 2026-11-18. Status: steps 1, 2, 3 and 7 built; storage,
node sync and publishing extended the same day.
Not over-engineered on purpose: every step below works on its own.

## The situation we design for

**Ideal:** people install the app and its packages while they have
internet, and keep them up to date before anything happens. Outdoor users
(hiking, skiing, sailing) mostly do this.

**Realistic, for disasters:**

- People hear about the app only after something happened, for example at
  a shelter.
- People who installed it long ago never updated the packages.
- New information appears during the emergency: new official guidance, a
  local map, closed roads, shelter status.
- Internet is down or comes back only now and then.
- Local governments set up their own distribution on site, often on an
  ordinary notebook PC, sometimes on prepared hardware.

So the data has to move over **whatever connection exists**: internet,
the shelter's local Wi-Fi, a USB stick, later phone to phone. And every
copy, from wherever it came, must be **provably genuine and current**.

## Principles

1. **Trust the signature, not the source.** A package is trusted because
   its publisher signed it, not because of the server, stick or phone it
   came from. Then any transport is fine.
2. **Content is addressed by its hash** (SHA-256, as in today's catalog).
   A file either matches or is thrown away.
3. **Versions only go up.** A device never accepts an older version of
   something it has (no rollback to outdated or tampered data).
4. **Packages are data, never code.** SQLite, PMTiles, JSON. The app
   opens only files whose signature and hash it has checked.
5. **Small steps.** Each step below is useful alone. P2P networks are a
   possible later transport, not a foundation.

## Building blocks

### Publishers and keys

Every publisher has an Ed25519 key pair: Lychnion for the general
packages, and for example a city for its local packages. The app ships
with the Lychnion public key. Other publishers' keys are added by the
user, for example by scanning the shelter's QR code, which already carries
the shelter computer's key (`ShelterQrCard`, `lib/facts/signing.dart`).

### Package records

For each package version, the publisher signs a small record:

```json
{
  "id": "jp.outdoor.hiking",
  "version": "2026.11.1",
  "publisher": "lychnion",
  "title": {"ja": "登山（基本）", "en": "Hiking (basics)"},
  "licence": "PDL1.0; sources listed in the package",
  "files": [{"name": "jp.outdoor.hiking.sqlite", "size": 401408, "sha256": "…"}],
  "signed": "2026-11-18T09:00:00+09:00",
  "signature": "…"
}
```

A record stays valid wherever it is copied. A catalog is then just a list
of records, so a node can carry packages of several publishers **without
re-signing them**.

### Node

A node is anything that serves records and files to apps. It does three
things:

1. **Serves** its catalog (a list of signed records) and the files, over
   plain HTTP: on the internet, or on a local network without internet.
2. **Syncs** the catalogs it follows (for example Lychnion's general and
   topical packages, or a neighbouring city's), whenever it has internet.
   It copies the records unchanged, so their signatures stay valid.
3. **Publishes** its own packages, signed with its own key.

No Git or GitHub needed. A node is meant to be run by a city's staff or a
club, so it comes in forms they can operate:

- **The Lychnion desktop app** (macOS, Windows): a "share packages" switch
  turns any notebook PC into a node, for example the shelter computer.
  Following catalogs and adding own packages happen in the app.
- **A headless node** for a server or a small box: the same Dart code as a
  single program (`dart compile exe`) or a container. For people who
  operate servers.
- **A static folder.** A node can export its catalog and files as plain
  files, to put on any web host or a USB stick. GitHub Pages works too,
  for those who already use GitHub, but it is one option, not a
  requirement.

The signing key stays on the machine that publishes the node's own
packages (or on a separate machine), never in a shared folder or
repository.

```mermaid
flowchart LR
  L["Lychnion node<br/>general and topical packages"] -->|sync when online| C["City node<br/>+ local packages"]
  C -->|sync, or copy on a stick| S["Shelter notebook PC<br/>desktop app as node"]
  S -->|local Wi-Fi, no internet| P1["Phones with the app"]
  S -->|web page| P2["Phones without the app"]
  L -->|internet| P1
  C -->|internet| P1
```

Open question: how a city makes its own package without our Python build
tools (for example from its own web pages or PDFs, in the desktop app).

### What phones do

Phones do not join any network of nodes. They fetch records and files
directly: from a catalog over the internet when they can, from the shelter
computer when they are on its Wi-Fi. They check the signature and hash,
keep the newest version, and the app loads it.

### Storage: files by hash, any server

GitHub release files are where Lychnion's packages start, not what the
system depends on: maps for all of Japan reach many gigabytes, and other
publishers (cities, clubs) need their own place.

- Every node keeps files under the same layout, `blobs/sha256/<hash>`, and
  a signed record lists its files by hash. A phone or node can fetch a
  file from **any** node it can reach and knows by the hash that it is the
  right one.
- So the host does not matter: GitHub, an object store without download
  fees (for example Cloudflare R2), a city's web server, the shelter
  laptop, a USB stick.

How it works (built 2026-11-18, step 3):

- **Catalog, format 2.** `records` (signed), `base`, `urls` (file hash →
  one address, for files that are not next to the catalog, like the
  models on Hugging Face), and `mirrors`: nodes that keep files by hash.
  Mirrors are in the catalog, not in the signed records, so adding or
  removing a mirror needs no new version. They need no signature: the
  hash in the signed record decides whether a file is right. Apps from
  before step 3 ignore `mirrors`; `urls` keeps one address (a string) per
  file for them.

  ```json
  {
    "format": 2,
    "base": "https://github.com/lychnion/lychnion-data/releases/download/2026.11.4/",
    "records": ["…"],
    "urls": {"8e30…": "https://huggingface.co/…/gemma-4-E2B-it-Q4_0.gguf"},
    "mirrors": ["https://mirror.example.org/lychnion/"]
  }
  ```

- **The app** tries every address of a file in turn: a shelter's first
  (local Wi-Fi), then the file's own address (`urls`, or `base` and the
  file name), then `<mirror>/blobs/sha256/<hash>` on each mirror. When one
  is unreachable, answers with an HTTP error or the connection drops, it
  goes on with the next one **from the byte where it stopped** (the part
  file belongs to the hash, not to a server). When a finished file has
  the wrong hash, it starts again from the next address. A shelter's
  catalog adds its addresses in front; the internet ones stay as
  fallback.
- **Static node.** `dart run tool/records.dart export CATALOG --out DIR
  FOLDER…` writes `catalog.json` and every file it finds (checked against
  the signed records) as `blobs/sha256/<hash>`, for a USB stick or any
  web host. Files it does not have keep their address from the source
  catalog. `tool/records.dart catalog --mirror URL` adds mirrors to a
  catalog.
- The shelter computer serves the same layout
  (`/blobs/sha256/<hash>`, see step 2).
- No second host for Lychnion's own files yet: GitHub releases name files,
  not hashes, so they stay the files' own addresses. A mirror (for example
  R2) is a later decision.

### Sync between nodes

- A node follows publishers (their keys and catalogs) and keeps their
  records and files. Records keep their publisher's signature, so any
  node can carry anyone's packages: a city mirrors Lychnion's, Lychnion
  may mirror a city's. Every extra node is one more place to get the data
  from.
- Nodes sync whenever any connection exists: mobile data on one phone,
  satellite, the hours when the network is back, or a USB stick carried
  between places. The newest signed version wins; versions only go up.
- Finding nodes without a central server: a short built-in list of known
  nodes (first start), the shelter's QR code, and discovery on the local
  Wi-Fi.

### Updates during a disaster

A city signs a new version of its local package on its node (new shelter
information, a local map). It spreads to the shelter laptops as soon as
they have any connection, and phones on a shelter's Wi-Fi get it there.
Current facts (shelter status, closed roads) already travel the same way,
signed, from shelter computers.

### Publishing your own packages

Cities and others need two things:

- **A guide:** what makes a good package (clear scope; every source with a
  licence; a notice saying what it is not for), translations and their
  review, and the signing key (kept offline, with a plan for replacing it).
- **A tool:** a "package studio" in the desktop app (and the same as a
  command line for developers) that turns web pages, PDFs and shelter
  lists into a package, checks licences, translates with a larger model
  and marks the texts for human review, signs, and publishes to the
  publisher's node.
- **Import from your own website:** a city points the studio at its own
  web pages (disaster pages, shelter lists, hazard maps) and gets a draft
  package. The city owns that content, so it decides itself what may be
  published, with no licence questions; nothing is published without its
  review and signature. Built from the tools we already have
  (`tool/build_package.py`, `tool/add_translations.py`,
  `tool/pdf_sections.py`).

### Open: whom to trust

The app has Lychnion's key built in; other keys are added by QR code at a
shelter. Lychnion could also vouch for known city keys with a signed
list, so people do not have to judge keys themselves. To decide later.

## Security

| Risk | Answer |
|---|---|
| Fake or changed package | Signature of a trusted publisher on the record, SHA-256 of every file |
| Old package replayed as new | Versions only go up; the app refuses older ones |
| Stolen node key | Each key signs only its publisher's packages; Lychnion's key is not on any node. Key rotation and revocation: a later step |
| Bad or slow mirror | Mirrors are unsigned on purpose: a file from one must match the signed hash, or it is thrown away and the next address is tried. A bad mirror costs time, not safety |
| Malicious file content | Packages are data; opened read-only, only after the checks; size limits |
| Wrong publisher trusted | Keys are added only by an explicit action (QR at the shelter), shown with the publisher's name; the user can remove them |
| Licence problems | Every source has a licence entry; each package carries its licences and attributions |

A threat model for nodes (Alpha-Omega style) should come with step 3.

## Steps

1. **Signed records** (built 2026-11-18). Sign the records of the Lychnion packages in
   `lychnion-data` and make the app check them. Bundled packages stay as
   they are; downloads and updates must be signed.
2. **Shelter computer serves packages** (built 2026-11-18, turned on
   with a switch in Settings). The desktop app serves its
   records and files on the local network; phones connected to it update
   from it without internet. (Phones already talk to it for answers.)
3. **Files by hash, several mirrors** (built 2026-11-18). The
   `blobs/sha256/` layout on every node, mirrors in the catalog, the app
   fetching from any address it knows and going on from the next one
   when one fails. See "Storage" above.
4. **Nodes for others.** Following catalogs and publishing own packages
   in the desktop app, plus the headless node. A city or a club runs one
   without Git or a server background; phones trust its key by QR.
5. **Sync between nodes**, including updates during a disaster.
6. **Publisher guide and package studio.**
7. **On-site help.** A web page served by the shelter computer, so phones
   without the app (all iPhones without it, since iOS installs apps only
   from the App Store) can ask questions in the browser (built
   2026-11-18, see `docs/shelter-results.md`). Next: open the page by
   itself when a phone joins the shelter Wi-Fi (lychnion#3). A "shelter kit":
   one folder or stick with the desktop app, all packages and maps, and
   the Android app file.

## Later, if needed

- **Updates flowing up.** When internet comes back, even briefly, a
  shelter computer sends its new local information (shelter status,
  closed roads, already signed as facts) to its city's node, and pulls
  updates. The node then also holds the most recent updates.
- **Peer to peer.** Hypercore (key-addressed, signed append-only logs,
  Holepunch) fits "keep it current from any peer" well; IPFS gives content
  addressing, with IPNS for updates. Both need internet-reachable servers
  to find peers, and neither has a usable Flutter implementation today.
  Because records are signed and files hash-addressed, either can be added
  later as one more transport without changing the format. Most useful
  between nodes, not on phones.
- **Phone to phone** (Wi-Fi Direct, Bluetooth), using the same records.
- **Several catalogs in the app** with priorities, and key revocation.

## Apps

Separate topic, notes for later:

- Stores: App Store and Google Play under the app store exception
  (`LICENSE-APPSTORE-EXCEPTION.md`); F-Droid fits the AGPL.
- On site: Android can install the app file from the shelter kit; iOS
  cannot, hence the web page in step 7.
- Desktop (shelter computer): macOS and Windows builds as GitHub release
  files; who signs and publishes them is still open.
- The source repository must be public before the app reaches anyone
  outside the team (AGPL).
