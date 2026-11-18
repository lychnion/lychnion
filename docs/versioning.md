# Versions

Decided 2026-11-18. The app and the data change at different speeds, so
they are numbered differently.

## The app: semantic versions

`MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`, for example `0.2.0+5`.
Releases are tagged `v0.2.0` on `lychnion/lychnion`.

- **0.x while Lychnion is a prototype.** A change that breaks something
  for users or for other nodes raises the minor version (0.2 → 0.3); fixes
  raise the patch (0.2.0 → 0.2.1).
- **1.0.0** is the first public release in the App Store and Google Play.
  After that: major for breaking changes, minor for new features, patch
  for fixes.
- **`+BUILD`** is a counter that only goes up, one step for every build
  sent to a store or to testers. The stores require it (Android
  `versionCode`, iOS build number). It is not part of the version people
  see.
- Phones and computers (the base) share one version.
- No app release has been made yet: the first one is `v0.1.0`.

## Data: calendar versions

Knowledge packages, maps and models keep `YYYY.MM.N`, for example
`2026.11.3`: the third version in November 2026. Releases of
`lychnion-data` use the same form (`2026.11.4`).

- Content changes on its own schedule (a new official page, a city
  update), independent of app releases.
- "Newer date, newer version" is what updates rely on: the app replaces a
  package only with a higher version (`compareVersions` in
  `packages/lychnion_format/lib/src/record.dart`), never a lower one.
- A package version says nothing about which app can read it; the
  formats below do.

## Formats: what connects the two

Each file format and protocol has its own small number. The app knows
which ones it reads; data says which one it uses.

| What | Number today | Where |
|---|---|---|
| Catalog | `format: 2` | `lib/download/catalog.dart` |
| Signed record | `format: 1` | `packages/lychnion_format/lib/src/record.dart` |
| Base protocol (phones ↔ base) | `v: 1` | `lib/shelter/shelter_protocol.dart` |

Rules:

- **Adding a field** that older apps can ignore keeps the number. Example:
  an optional `area` in records.
- **Changing what a field means**, or a field older apps must understand,
  raises the number. Publishers then offer the old and the new format side
  by side until old apps are rare.
- **Old apps skip what they can't read:** a record with an unknown format
  or an item of an unknown kind is left out of the list, the rest of the
  catalog still works (`Catalog.parse`). A catalog with an unknown format is
  not read at all, so the catalog number changes only when there is no
  other way.
- An app release that starts reading a new format says so in its release
  notes.
