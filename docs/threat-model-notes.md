# Threat-model notes

Working notes for [threat-model.md](../threat-model.md): how the first
version was made, and the candidate issues found on the way. The model
itself describes the contract; this file lists defects and follow-ups. The
sixteen that break a claimed property are filed as #63 to #78; the
hardening and documentation items are not filed.

## How the first version was made (2026-11-19)

- Bound to commit `be565e8` on `main`. The draft was first written against
  `6ee5dea`; thirteen commits landed meanwhile (key statements and backups,
  the catalog document, `lychnion://base` links, the `s=1` QR flag,
  `packages/lychnion_guide`). A read-only drift check found the claims and
  citations they changed, and two more questions (Q32, Q33) settled the new
  key features.
- Alpha-Omega `threat-model` plugin 1.2.1 at commit `192fd60`, full flow:
  recon, surface pass, interview, authoring, backtest, sidecar.
- The surface pass ran as four read-only sub-agents: the base and the local
  network; records, catalogs, downloads and publishing; the headless node
  with CI and release; answers, facts, deep links and privacy.
- Thirty-three maintainer questions, asked one at a time
  ([threat-model-questions.md](threat-model-questions.md)). All are
  answered, so the model is accepted.
- Validator (`tests/harness/validate_model.py` of the plugin): 92 checks
  pass for prose, YAML and JSON; one warning that the prose is longer than
  the 7,000-word guideline. The plugin's citation check covers C, Python, JS
  and similar files only, so the Dart, Kotlin and shell citations were
  checked with a separate script: every `file:line` points at a code line.
- Backtest: 41 items, 15 with a real history (13 fixed security commits, 2
  open items of issue 36), 26 synthesized. Every fixed item routes `VALID`.
  The routing table is producer-side and not committed (`.threat-model/` is
  ignored).

To regenerate the companions after editing the prose: rebuild
`threat-model.yaml` from the prose tables, run the plugin's `export_json.py`,
then its validator with `--json-report`. The small script that builds the
YAML from the tables is not in this repository yet (a follow-up).

## Candidate issues

"Confirmed" means the code path was read; "suspected" means it was not
proven. The property is the §1.11 claim each one breaks.

### Break a claimed property

1. **A web link pins a base key** ([#63](https://github.com/lychnion/lychnion/issues/63)) (confirmed, `key-consent`). Any
   `lychnion://shelter?…&key=` link, also from a web page or message on
   Android, pins its key after one "Connect"
   (`lib/app/incoming_links.dart:67`, `lib/base/base_checks.dart:47`). This
   holds for the new `lychnion://base` host too. The dialog does not show
   the key, the link's name is not cleaned (`lib/base/base_link.dart:64`),
   and trusted base keys cannot be removed. *Fixed in
   [#86](https://github.com/lychnion/lychnion/pull/86): links only pin
   the key; the user compares a code to trust it.*
2. **The base and Share nearby listen on every interface** ([#64](https://github.com/lychnion/lychnion/issues/64)) (confirmed,
   `lan-only-exposure`): `lib/base/base_server.dart:167` binds
   `anyIPv4`, including a desktop's upstream network and a phone's mobile
   data. *Fixed in [#87](https://github.com/lychnion/lychnion/pull/87):
   they listen only on local-network addresses
   (`lib/base/lan_sockets.dart`).*
3. **Bare-model answers without a warning** ([#65](https://github.com/lychnion/lychnion/issues/65)) (confirmed path, trigger
   suspected, `grounded-answer-presentation`). If the embedder or index
   fails after the model loaded, the question bar stays on and the warning
   is drawn only when `grounded` is true (`lib/ask/ask_page.dart:587`).
   *Fixed for #65: the phone answers by itself only with the model and
   the guides loaded (`answersOnDevice`); otherwise the bar is off, and a
   question that still gets through says the guides are missing.*
4. **Any package supplies "official" safety lines** ([#66](https://github.com/lychnion/lychnion/issues/66)) (confirmed,
   `safety-line-lychnion-only`): alerts of every installed package match
   (`lib/knowledge/grounded_answer.dart:253`), and an empty trigger word
   matches every question (`lib/knowledge/knowledge_package.dart:132`).
   *Fixed for #66: only packages signed by a built-in publisher keep
   their alerts, an added publisher's copy of a bundled id is not loaded,
   and an empty trigger word matches nothing. Still trusted: the safety
   lines in a paired base's answers, as the base sends them (a base runs
   this code, but an older base build does not filter).*
5. **Added publishers can ship models** ([#67](https://github.com/lychnion/lychnion/issues/67)) (confirmed, `models-lychnion-only`):
   any record kind is accepted (`lib/download/catalog.dart:186`), and with
   no model picked the first one in sort order becomes active
   (`lib/download/download_store.dart:563`). *Fixed for #67: `model`
   records only from built-in publishers (`mayPublishKind`), in the app
   and on nodes; older installs of others' models are never loaded.*
6. **A USB stick can squat a Lychnion id** ([#68](https://github.com/lychnion/lychnion/issues/68)) (confirmed, `publisher-namespace`):
   a stick record from an added publisher for a bundled or not yet installed
   Lychnion id is installed and then used, because the owner check sees only
   installed markers (`lib/download/stick.dart:313` calls
   `lib/download/download_store.dart:371`), and the installed copy then
   wins over the bundled one (`lib/download/download_store.dart:581`).
   *Fixed in the app for #68: Lychnion's ids and file names are reserved
   (`DownloadStore.reserve`, `reserveFrom`, `isReservedFor`), also when
   not installed; copies installed before are not used, and Lychnion's
   own replaces them. The headless node does not reserve ids yet.*
7. **Unconfirmed facts steer the map** ([#69](https://github.com/lychnion/lychnion/issues/69)) (confirmed,
   `unverified-facts-not-acted-on`): `lib/map/map_state.dart:59` and
   `lib/map/map_state.dart:174` use facts whatever their trust, and
   `lib/map/map_screen.dart:251` skips avoided sites. *Fixed for #69:
   `avoid`, `blockedPoints` and `warningHazard` use confirmed facts only.*
8. **Facts from the future win** ([#70](https://github.com/lychnion/lychnion/issues/70)) (confirmed, `fact-time-bounds`): no cap on
   `observedAt` or `expiresAt` (`lib/facts/fact_store.dart:275`).
   *Fixed for #70 (the line above is how it was): `FactStore.inTimeBounds`
   (30 minutes skew, 3 days lifetime) on arrival and when choosing; a
   fact dated after now ranks below every one that is not, until its
   time comes.*
9. **Questions and answers in the release log** ([#71](https://github.com/lychnion/lychnion/issues/71)) (confirmed, `device-egress`):
   `lib/ask/ask_page.dart:164` (`debugPrint`); each logged answer carries
   its question. Base answers are logged at `lib/ask/ask_page.dart:316`,
   the phone's own at `lib/ask/ask_page.dart:384`, and the region at
   `lib/ask/ask_page.dart:363`. *Fixed for #71: release builds leave
   them out (`loggable` in `lib/app/dev_flags.dart`) unless `LOG_ANSWERS`,
   `ASK` or `AUTO_BENCH` is set.*
10. **A base may be any host** ([#72](https://github.com/lychnion/lychnion/issues/72)) (confirmed, `device-egress`):
    `lib/base/base_link.dart:88` accepts public hosts, and Android allows
    cleartext to every host. `help/en/08-privacy.md` also needs the base
    case. *Fixed for #72: `BaseLink.normalize` accepts only local-network
    hosts (`isLocalHost`); the privacy help names the base case.
    Cleartext stays allowed on Android, which cannot limit it by address
    range; the app checks the host instead.*
11. **The LAN redirect guard misses ranges** ([#73](https://github.com/lychnion/lychnion/issues/73)) (confirmed,
    `lan-device-same-origin`): `packages/lychnion_fetch/lib/src/downloader.dart:421`
    lacks 100.64/10, which discovery accepts, and plain hostnames.
    *Fixed for #73: one definition (`isPrivateIPv4Address` in
    lychnion_fetch) for discovery and the guard; plain names count as
    local.*
12. **Node address filter gaps** ([#74](https://github.com/lychnion/lychnion/issues/74)) (confirmed, `node-private-address-filter`): `::` and some special ranges are not private
    (`packages/lychnion_node/lib/src/pull.dart:282`); catalog redirects are
    not filtered. *Fixed for #74: `isNonPublicAddress` covers them, and
    `fetchCatalogText(allowAddress:)` checks each catalog redirect.*
13. **Node forgets a version when a record is dropped** ([#75](https://github.com/lychnion/lychnion/issues/75)) (confirmed, `no-downgrade-installed`): `packages/lychnion_node/lib/src/pull.dart:196` drops a record whose
    current and new versions are incomplete, and the next pull accepts an
    older one. *Fixed for #75: such a record is set aside in `.kept.json`
    with its files, so its version still blocks older ones.*
14. **Windows file names ending in a dot** ([#76](https://github.com/lychnion/lychnion/issues/76)) (suspected, `publisher-namespace`):
    `packages/lychnion_format/lib/src/record.dart:128` allows a trailing dot
    and device names such as `NUL`; Windows may map `x.sqlite.` onto
    another publisher's `x.sqlite`.
15. **App-help words skip safety lines** ([#77](https://github.com/lychnion/lychnion/issues/77)) (suspected,
    `safety-line-lychnion-only`): a safety question containing a word such
    as 「ベース」, 「共有」, "offline" or "settings" may take the help path
    (`lib/knowledge/grounded_answer.dart:242`).

16a. **Nested key statements may abort a node pull** ([#78](https://github.com/lychnion/lychnion/issues/78)) (suspected, `client-response-limits`):
    `relevantStatements` canonicalises each `keys` entry before any shape
    check and catches only `FormatException`
    (`packages/lychnion_format/lib/src/key_statement.dart:328`); on the node
    the call is outside the parse `try`
    (`packages/lychnion_node/lib/src/pull.dart:139`).

### Breaks a correctness-only property (not filed)

16b. **Answers on the base computer can mix** (`answers-never-mix`, Q25):
    phones and the computer's own Ask page share one chat with no lock; a
    new chat closes the shared one (`lib/llm/local_llm.dart:106`), and a
    phone that leaves stops the shared session (`lib/llm/local_llm.dart:160`).

### Hardening and correctness

16. A multi-file network update is not all-or-nothing
    (`lib/download/download_manager.dart:864`); the stick path is.
17. Node downloads have no overall deadline; a trickling host holds the pull
    and its folder lock (`packages/lychnion_fetch/lib/src/downloader.dart:301`).
    Disclaimed (§1.12 `download-time-and-disk`), but a deadline would help.
18. `.copy` leftovers after a node crash are never removed. (The node's
    catalog size cap is fixed at `be565e8`: it keeps the old catalog and
    reports.)
19. The base re-reads every install marker per `/catalog.json` request
    (`lib/base/base_library.dart:28`); `Range: bytes=<size>-` returns an
    inverted `Content-Range`; file handles may run short under a download
    flood.
20. The vector cache file name uses the package id unchecked
    (`lib/knowledge/hybrid_retriever.dart:56`).
21. Package vectors are used without normalising
    (`lib/knowledge/hybrid_retriever.dart:153`).
22. Fact signing joins fields with U+001F without escaping (Q27); 48-bit key
    ids are overwritten on collision (Q28); a saved fact without `v_ok`
    loads as verified (`lib/facts/fact_store.dart:115`).
23. Source links allow `http` and hide the address behind the label (Q26).
24. The cached main catalog's unsigned `refresh` field becomes the next
    refresh source (`lib/download/download_manager.dart:655`).
25. `tool/build_release.sh` cleans up with `rm -P`, which exists only on
    macOS; a `DEV_MENU=true` build is signed with the production upload key.
26. CI does not run `dart pub get --enforce-lockfile`, tests the node on SDK
    3.12.2 while the image uses 3.13.6, and never builds the image.
27. Repository settings: `main` has no branch protection or ruleset, and
    secret scanning is off.

28a. "Revoke a lost key from a backup" stores a revocation for any
    publisher name in a self-consistent backup, and a base then serves it;
    phones keep it only for a key they trust
    (`lib/publish/key_actions.dart:282`).
28b. A base whose records alone exceed 2 MB throws when building its
    catalog (`lib/base/base_library.dart:37`); not traced further.

### Documentation out of date

28. `docs/distribution.md` says only the QR code pins a base key; links do
    too (see 1).
29. `docs/facts-results.md` "Signed facts" and the comment in
    `lib/app/settings.dart` still say a typed address is trusted on first
    connect; the code no longer does that.
30. `lib/facts/compact_codec.dart` says "Not signed yet"; signed packing
    exists.
31. `help/en/08-privacy.md` says questions never leave the device; they go
    to a connected base. *Fixed for #72: the help (en/ja) names the base.*
32. `docs/distribution.md` "Security" still says key rotation and
    revocation are "a later step", and the roadmap lists key revocation;
    both now exist for publisher keys, Lychnion's included (Q32).
    `lib/download/publisher_list.dart:28` says Lychnion's key cannot be
    replaced; statements can replace it.
33. `docs/distribution.md` "Revoke" says items are dropped "as when a
    publisher is removed"; removal deletes files, revocation does not.
34. `packages/lychnion_node/README.md` says a publisher cannot withdraw a
    version from nodes yet; revoking a key now sets aside what it signed.
35. `help/en/07-publishers.md` mentions only "keep a copy of the key
    offline"; nothing on backup, replacement or revocation.
