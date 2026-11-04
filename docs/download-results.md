# Downloads inside the app

Date: 2026-11-05. macOS (M4 Max), release build. Android and iOS not tested
yet.

Models, knowledge packages and map areas can now be downloaded in the app
(**Downloads** tab, ダウンロード). Before, they were copied over the cable
(`docs:` paths) or bundled.

![Downloads tab while a model is being checked](images/macos-downloads.png)

## What it does

- One list for all three kinds, with size, version, licence, progress,
  speed and time left. Japanese or English follows the system language.
- **Resume:** files go to `<name>.part`; after a lost connection, a crash or
  "Stop", the download continues with an HTTP Range request. The part is
  hashed again first, so the final check covers the whole file.
- **Checksum:** every file is checked against its SHA-256 before it gets its
  real name. Models use the Hugging Face LFS oid (from
  `https://huggingface.co/api/models/<repo>/tree/main`, field `lfs.oid`). A
  damaged file is deleted and the user is told to download again.
- **Only checked files are used:** a verified download gets a record
  `<id>.installed.json`. Loaders only use files with a record, at the
  recorded size. Files already there without a record (copied by cable or
  picked with "Load GGUF file") show **Check file**, which hashes and adopts
  them without downloading again.
- **Delete** removes the files, any partial download and the record. The
  package falls back to the copy built into the app.
- **Wi-Fi only** is on by default: on mobile data alone the download does not
  start. Files of 1 GB or more ask first and say how much space they need.
- **One writer per file:** the part file is locked, so a second app window
  (desktop) cannot write the same file; it shows "already downloading".
- After a download, the app uses it at once: the chat model loads (the first
  one installed, or the one picked with **Use this model**), the search
  model switches on vector search (cut-off 0.70), the map tab opens the map
  area, a package update reloads the answers.

Storage (app support folder, the same folders as before):

| Kind | Folder | Before |
|---|---|---|
| Models | `models/` | same folder ("Load GGUF file" copied here) |
| Packages | `packages/` | bundled copy was written here; now goes to `bundled/packages/` |
| Map areas | `maps/` | pmtiles copied by cable; sites copied from assets (now `bundled/maps/`) |
| Settings, cached catalog | `downloads/` | – |

## Catalog

`assets/downloads/catalog.json` lists the items (id, kind, title ja/en,
version, licence, note, files with name, size, sha256, url). The app can
fetch a newer catalog from the URL in its `refresh` field (or the dev flag
`CATALOG_URL`) and keeps the last one it got; a higher package version then
shows **Update**. Relative file URLs resolve against `base` (or the
catalog's own URL, or `DOWNLOAD_BASE_URL`).

Models point to Hugging Face. **Package and map files have no public URL
yet** (`base` is empty), so those two items show "no download source yet"
and the app uses the bundled package. A private GitHub repo cannot serve
them: release assets of a private repo need a token.

After rebuilding a package or map:

```bash
python3 -I tool/catalog.py assets/downloads/catalog.json assets/packages/jp.bousai.core.sqlite
```

then bump the item's `version` and upload the file next to the catalog.

## Test on macOS

Package and map from a local server (`tool/serve_downloads.py`, Range
support), models from Hugging Face. Driven by the dev flag
`AUTO_DOWNLOAD=id,…` (a leading `!` downloads even if a matching file is
already there).

| Step | Result |
|---|---|
| Package (922 KB), map area (26.6 MB, 2 files) | 0.06 s and 0.2 s, checked |
| EmbeddingGemma 2 Q8_0 from Hugging Face (310 MB) | 9.2 s (about 34 MB/s), checked |
| Gemma 4 E2B Q4_0 (2.84 GB): app killed (`kill -9`) at 919 MB | part kept |
| Second app instance started during the download | refused ("already downloading"), part untouched |
| App started again | resumed at byte 919,048,768, finished and checked in 61 s |
| Gemma 4 E4B (4.6 GB) already on disk, no record | **Check file**: hashed in 21 s, adopted |
| After the downloads | E2B loaded from the download (GPU), tsunami question answered with sources, map from the downloaded files |
| Network use after the downloads | none (`lsof -i` on the app: no connections) |

![Map tab opened from the downloaded map area](images/macos-map-downloaded.png)

Seen once, not reproduced: in one run with several app instances killed
just before, the Downloads tab screenshot showed only the loading spinner.
Three later release runs showed the list normally.

## Tests

`test/download_test.dart` (11 tests): download and verify; resume after a
dropped connection (checks the Range header); Range kept across a redirect
(Hugging Face redirects to its CDN); server ignoring Range; wrong checksum;
a part of another version is not resumed; stop keeps the part; the bundled
catalog matches the bundled package; URL resolution; install records,
chat model choice, Wi-Fi setting default.

## Open

- **Hosting for packages and maps** (decision needed): a public static URL,
  e.g. a public Hugging Face dataset repo, Cloudflare R2, or releases of a
  public GitHub repo.
- Android (Pixel 5a) and iOS not tested yet. Hashing runs on the main
  isolate; about 200 MB/s on the Mac, a phone will be slower (the UI stays
  usable, but checking 2.8 GB may take a minute).
- iOS: downloads stop when the app goes to the background (resume works on
  return). Model files should be excluded from iCloud backup.
- No free-space check before starting; a full disk shows "not enough free
  space" when writing fails.
- The old "Download model" field on phones (`fromNetwork`) is still there;
  it can go once the Downloads tab is tested on phones.
