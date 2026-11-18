# Data packages and trust

The app answers only from **knowledge packages**: official pages, cut into
short passages, in one SQLite file each. Maps come as **map areas**. Both
are built, signed and published in
[lychnion/lychnion-data](https://github.com/lychnion/lychnion-data) (see
"How packages are made" there).

How to use downloads, publishers and catalogs in the app:
[help/en/04-downloads.md](../help/en/04-downloads.md) and
[help/en/07-publishers.md](../help/en/07-publishers.md).

## What the app bundles

| Folder | What |
|---|---|
| `assets/packages/` | Knowledge packages `jp.bousai.core`, `jp.outdoor.hiking`, `intl.firstaid.basics` |
| `assets/maps/` | Evacuation sites for the Nishinomiya area |
| `assets/downloads/catalog.json` | The app's own copy of the download catalog |
| `assets/help/app.help.sqlite` | The app's help, built from `help/` by `tool/build_help.py` |

A newer download from the catalog replaces a bundled copy. To refresh the
bundled files, copy the built files from a `lychnion-data` checkout.

To compare answers with the model alone, without any package, run with
`--dart-define=BARE=true`.

## Signing and trust

Every guide, map and model has a record signed by its publisher. The app
checks the signature and every file's SHA-256 before it uses a file. So a
file may come from any server, a USB stick, a base or another phone.

- Lychnion's own key is built into the app.
- **Publishers:** a city or a club signs its own guides and maps with its
  own key. People add the publisher with a link or QR code
  (`lychnion://publisher?…`). Removing a publisher deletes its guides and
  maps.
- **Publish your own (desktop):** the app makes a signing key that stays
  on that computer and signs a guide or map file. A computer that is a
  base then serves it to phones.
- **Catalogs:** the app can follow other catalogs. It shows only items
  signed by Lychnion or by a publisher the user added.
- **Headless node:** [`packages/lychnion_node`](../packages/lychnion_node/README.md)
  is one program for a server or a small box. It fills a folder from one
  or more catalogs, keeps it current, and serves it like a base.

The code for records is in `packages/lychnion_format`, and for downloads
in `packages/lychnion_fetch` and `lib/download/`.

The full design, including what is still open (sync between nodes, a
publisher guide): [distribution.md](distribution.md). Version numbers of
data and formats: [versioning.md](versioning.md).
