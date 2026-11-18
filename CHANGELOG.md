# Changelog

All notable changes to the Lychnion app. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); version numbers
follow [docs/versioning.md](docs/versioning.md). Data packages and maps
have their own releases in
[lychnion-data](https://github.com/lychnion/lychnion-data/releases).

## [Unreleased]

Planned as **0.1.0**, the first tagged version. It is a prototype: not in
the App Store or Google Play yet, the data is for testing, and nothing
here should be relied on alone in an emergency. Source only; build it as
[docs/development.md](docs/development.md) describes.

### Added

- **Offline answers with sources.** Japanese or English questions are
  answered from installed guides (official pages). Answers cite their
  sources and the app checks the citation numbers; an answer without a
  valid citation is shown with a warning. When a question matches a
  hazard in a guide (for example a tsunami), the answer starts with a
  safety line quoted word for word from an official source. Answer
  models to download: Gemma 4 E2B for phones, E4B for computers. Search
  with EmbeddingGemma 2. All on the device.
- **Offline maps** for two areas: Nishinomiya (bundled) and Kushimoto
  (download). Evacuation sites per hazard, tsunami inundation areas by
  depth, and walking routes; tsunami routes keep to higher ground. The
  nearest site is on Home.
- **Home, Ask and Map tabs.** Saved conversations, first steps, a guided
  tour, and a first-start notice on what the app can and cannot do.
- **Downloads.** Models, guides and maps from catalogs of signed package
  records, with resume, SHA-256 checks, several mirrors, updates and
  filters. Each item shows its area; the user's region (detected offline
  or picked in Settings) comes first.
- **Base (ベース).** A computer with the desktop app answers phones on the
  same Wi-Fi, shows current information (shelter status, closed roads,
  warnings) and passes on guides, maps and models. Phones connect by QR
  code or find the base on the Wi-Fi; phones without the app use a web
  page.
- **Phone to phone.** Share downloads with a phone nearby on the same
  Wi-Fi or a phone's hotspot, without internet.
- **USB stick (desktop).** The desktop app copies downloads to and from a
  USB stick. Phones cannot read a stick yet.
- **Short internet windows.** Catalogs refresh when a connection comes
  back and every 30 minutes. A computer with the desktop app can keep
  every guide and map current for the phones nearby.
- **Publishers and catalogs.** A city or a club can sign and publish its
  own guides and maps; people add the publisher by link or QR code and
  can follow its catalog. The desktop app can make its own key and
  publish.
- **Headless node** (`packages/lychnion_node`): serves, mirrors and keeps
  catalogs current on a server.
- **Help inside the app**, in Japanese and English, readable and
  searchable without the AI; the AI also answers questions about the app.
- **Settings and About:** language, region, mobile data, sharing on the
  local network, app and data versions.
- Signed Android release builds (`tool/build_release.sh`).
- CI (format, analyze, test) and Dependabot.

### Changed

- New name and brand: Lychnion (リクニオン), formerly the code name
  fieldkit. IDs are now `com.lychnion.app` and `lychnion://`; old
  `fieldkit://` QR codes still work.
- Licence: GNU AGPL 3.0 with an app store exception. Versions up to
  commit `064f50a` were published under Apache 2.0.
- The data tools moved to
  [lychnion-data](https://github.com/lychnion/lychnion-data). Bundled
  data is from its release 2026.11.5.

### Security

- The app installs only package records signed by Lychnion or by a
  publisher the user added, checks every file's size and SHA-256, and
  never installs an older version.
- Facts from a base are trusted only after its QR code was scanned.

### Formats

Catalog `format: 2`, signed record `format: 1`, base protocol `v: 1`.

### Known gaps

- Sync between nodes is not finished (distribution step 5), and there is
  no publisher guide or package studio yet (step 6).
- Help links on each screen
  ([#9](https://github.com/lychnion/lychnion/issues/9)).
- Opening the base page by itself on a shelter Wi-Fi
  ([#3](https://github.com/lychnion/lychnion/issues/3)), several phones
  at one base ([#5](https://github.com/lychnion/lychnion/issues/5)),
  Android Nearby ([#6](https://github.com/lychnion/lychnion/issues/6)).
- On phones without a fast GPU, answers are slow (Pixel 5a: about 48 s).

[Unreleased]: https://github.com/lychnion/lychnion/commits/main
