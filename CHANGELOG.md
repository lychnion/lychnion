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
  safety line from an official source: the official text word for word,
  or our translation (not official) when the source is in another
  language, with the official text one tap away. Answer models to
  download: Gemma 4 E2B for phones, E4B for computers. Search with
  EmbeddingGemma 2. All on the device. On Android, Gemma 4 E2B also comes
  as a LiteRT-LM model that answers about twice as fast (Google's engine,
  on the CPU, Android 11 or newer); the app uses it when it is installed,
  unless another answer model was picked, and falls back to the GGUF
  model if it cannot load it. Computers and
  iPhones keep llama.cpp.
- **Offline maps** for two areas to download: Nishinomiya and Kushimoto.
  Evacuation sites per hazard, tsunami inundation areas by depth, and
  walking routes; tsunami routes keep to higher ground. The evacuation
  sites for Nishinomiya come with the app. The nearest site is on Home.
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
- **Back up, replace and revoke a publisher key** (desktop,
  [#41](https://github.com/lychnion/lychnion/issues/41)). A backup file
  protected by a passphrase, and restore from it. Replacing a key: the old
  key signs the new one, and phones that trust the old key accept the new
  one. Revoking a stolen key: phones stop using it and what it signed, and
  add the publisher's new link. Phones learn of both from catalogs, USB
  sticks, a base and phones nearby, also offline; the headless node
  passes them on.
- **Headless node** (`packages/lychnion_node`): serves, mirrors and keeps
  catalogs current on a server.
- **Guide files** (`packages/lychnion_guide`): the tables, writing a guide
  and checking that the app can open it, shared with lychnion-studio. The
  desktop app runs the same check before it signs a guide.
- **Help inside the app**, in Japanese and English, readable and
  searchable without the AI; the AI also answers questions about the app.
- **Settings and About:** language, region, mobile data, sharing on the
  local network, app and data versions.
- Signed Android release builds (`tool/build_release.sh`).
- CI (format, analyze, test) and Dependabot.

### Changed

- New name and brand: Lychnion (リクニオン). IDs are `com.lychnion.app`
  and `lychnion://`.
- Base QR codes say `lychnion://base?…` (was `lychnion://shelter?…`,
  still read). A base's default name is "Lychnion base".
- Licence: GNU AGPL 3.0 with an app store exception. Versions up to
  commit `064f50a` were published under Apache 2.0.
- Built with Flutter 3.50 (Dart 3.14). Material and Cupertino widgets
  now come from the `material_ui` and `cupertino_ui` packages. sqlite3
  3.9 and newer native build tools.
- The data tools moved to
  [lychnion-data](https://github.com/lychnion/lychnion-data). Bundled
  data is from its release 2026.11.5.

### Security

- A fact dated more than 30 minutes in the future, living longer than 3
  days, or expiring more than 3 days from now is refused and never
  current. Before, one fact dated 2099 won its topic for years, and a
  "cleared" one hid it. A fact dated a little ahead (clocks differ) is
  accepted, but until its time comes it loses to every report that is
  not; one that only looks ahead after the device's clock was set back
  is hidden, not deleted. A device whose clock is more than 30 minutes
  behind refuses fresh facts, so set the clock on phones without network
  time (#70).
- Only confirmed facts change the suggested evacuation site and the
  walking route. A resident report, or an "official" fact whose
  signature does not check out (anyone on a base's Wi-Fi can send one),
  is still shown with its "unconfirmed" label, but no longer makes the
  app steer away from a shelter, route around a road or switch to a
  warning's hazard (#69).
- The AI model never answers alone. When the guides or the search model
  fail to load after the model is up, the question bar turns off (unless
  a base answers) and the screen says the guides could not be loaded;
  before, the model answered by itself, with no sources and no safety
  line (#65). A reload (after a download, or a publisher removed) drops
  the guides loaded before, so a failed reload does not go on answering
  from the old set; questions asked meanwhile get the explanation when
  nothing can answer them.
- Release builds no longer write questions, answers, the sources that
  matched or the region to the system log (logcat on Android), and log
  errors only by their type; timings are still logged. The `LOG_ANSWERS`
  define (and `ASK`, `AUTO_BENCH`, which the eval reads) logs them in a
  release build for development (#71).
- A base address must be on the local network: a private IPv4 address,
  a link-local or private IPv6 address, a `.local` name, or loopback
  (debug builds and desktops only), on a port from 1 to 65535. A link or
  a typed address naming an internet host is refused, so a web page can
  no longer send a phone's questions to a server on the internet; a base
  saved that way by an older build is forgotten. The privacy help now
  says that questions go to a connected base (#72).
- Only Lychnion publishes models. A publisher the user added can bring
  guides and maps, but its model records are refused in catalogs, on USB
  sticks, from bases and by nodes when they pull, and a model of theirs
  installed by an older build is never loaded or picked as the chat or
  search model. A model's file is parsed by native code and its text is
  what answers (#67). Such an older install is not listed in Downloads;
  removing that publisher in Settings → Publishers deletes it and frees
  the space.
- Lychnion's ids and file names are reserved even before they are
  installed: the bundled packages, the bundled catalog and Lychnion's
  items in every catalog of Lychnion's the app has checked. An added
  publisher can no longer install a package, map or model under one of
  them, from a USB stick, a followed catalog or a base. A copy installed
  that way before is not used; Lychnion's own update replaces it,
  whatever version the copy claims, and removes the copy's files that no
  other item lists (#68). Deleting an item never removes a file another
  installed item lists. The headless node does not reserve ids yet.
- Only packages signed by Lychnion supply the fixed official safety line
  above an answer. A package from a publisher the user added is still
  searched and quoted with its source, but its safety lines are left out.
  A copy of a built-in Lychnion package installed from an added
  publisher is not used: the app answers from Lychnion's own. An empty
  trigger word no longer matches every question (#66).
- The base and Share nearby listen only on the device's private
  addresses on interfaces with a known Wi-Fi, hotspot, tethering or
  wired name, the addresses the screen shows, and follow them as the
  network changes. Before, they listened on every interface: a desktop
  base on its upstream network or the internet, a sharing phone on
  mobile data (#64). A computer on two private networks still listens on
  both.
- The app installs only package records signed by Lychnion or by a
  publisher the user added, checks every file's size and SHA-256, and
  never installs an older version.
- Facts from a base are trusted only after the user compared the base's
  code with its screen. A `lychnion://base` link, which a web page or a
  message can open too, only connects and pins the key; before, one tap
  on any such link made the base's facts official (#63). Settings lists
  the trusted bases with their codes and can remove them; the name from
  a link is cleaned and capped like publisher names. Answers from a base
  whose code was not compared carry the "not checked" note. Bases trusted
  before this version stay trusted: check the list in Settings → "Base".
- A base limits what each phone can send and how long it may hold a
  connection, and its errors don't show file paths. Phones limit what
  they accept from a base.
- An answer from a base that was not connected by its QR code says so.
- Base answers are signed. A phone that scanned the base's QR code sends
  a new random value with each question, and the base signs its answer
  together with it and the question as received. The phone refuses an
  answer that was changed, signed by another key, sent before, or made
  for a changed question, and answers itself. An answer from an older
  base without a signature says so; once a base has signed, the phone
  refuses unsigned answers from it. The QR code of a base that signs
  says so, so the phone refuses unsigned answers from the first one.
  When the phone refuses a base's answer, its own answer says so. The
  page for phones without the app stays unsigned.
- A phone keeps at most 5,000 facts and drops expired ones.
- A base stops an answer when the phone that asked has left.
- From a base or a phone nearby, the app downloads only files on that
  device, never from other addresses its catalog names or redirects to.

### Formats

Catalog `format: 2` (with an optional `keys` list), signed record
`format: 1`, key statement `format: 1`, key backup `format: 1`, base
protocol `v: 1`. Older builds ignore `keys`: they do not accept a
replacement key or honour a revocation.

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
- Questions and answers on the base Wi-Fi are not encrypted, and a base
  found on the Wi-Fi without its QR code is not checked
  ([#36](https://github.com/lychnion/lychnion/issues/36)).

[Unreleased]: https://github.com/lychnion/lychnion/commits/main
