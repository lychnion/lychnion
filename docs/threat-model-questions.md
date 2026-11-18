# Threat-model question bank

This is Lychnion's own bank of maintainer questions for the threat model at
the repository root ([threat-model.md](../threat-model.md)). The Alpha-Omega
`threat-model` skill ships a reference bank written for in-process
libraries. Lychnion is an app with an on-device language model, signed data
from many transports, a server on the local Wi-Fi, deep links and a headless
node, so it needs its own questions. The bank below covers those areas.

## How to use this file

1. When the model is revised, pick the questions below that the change
   touches. Wave 1 is always scope, intended use, configuration support and
   host side effects.
2. Ask one question at a time and frame it as a proposed answer ("we believe
   X — confirm or correct").
3. Record an answer as *(maintainer, YYYY-MM)* in the model, remove the item
   from §1.18, and regenerate `threat-model.yaml` and `threat-model.json`.
4. Keep the ruling here, so the next revision does not ask again.

## Questions by area

Each question names the model section it lands in. **R** marks a question
adapted from the skill's reference bank (its number in brackets).

### Scope and intended use (§1.2, §1.3)

- Which components ship from this repository and share one model: phone
  app, desktop app as a base, headless node, shared packages? (R 1, 2, 28)
- What does the app promise about an answer: only installed guides, sources
  shown, fixed safety line? What does it not promise? (R 3, 14)
- Which shipped code is dev-only (`lib/spike/`, `tool/`, dev flags)? (R 28)
- Is licence compliance (AGPL, the app store exception) a security property?

### The on-device model and answers (§1.7, §1.8, §1.11, §1.12)

- Is wrong or harmful wording from the model, with sources and safety line
  shown, a vulnerability or a content bug?
- Which publishers may supply the "official" safety line?
- Is text in a signed package that steers the model (prompt injection) in
  model? Does it matter whose package it is?
- What does a citation mark promise: that the passage was given to the
  model, or that it supports the sentence?
- Which models may be installed and loaded, and from whom? Is a GGUF file
  (with its chat template) treated as code?
- What must the app show when grounding fails (no index, no embedder)?
- Are package vectors, synonyms and trigger words trusted as shipped?
- Is there a limit on a question typed on the device?

### Data packages, catalogs and signing (§1.4, §1.7, §1.11, §1.12)

- Where is the Lychnion signing key kept, and is its compromise in model?
  Is there rotation or revocation?
- What may an added publisher do: which kinds, which ids, which file names?
- "Versions only go up": on which stores, and what happens after delete,
  publisher removal, reinstall or on a fresh node?
- Is freshness promised, or can an old but validly signed catalog hide an
  update (freeze, replay)? Which tier?
- Are files re-checked at load, or trusted after install? Are bundled
  files trusted by the app signature?
- Is a multi-file update all-or-nothing?
- May a followed catalog send the app to any host? May a base's catalog?
- Is a USB stick a trusted source?

### Key statements and backups (§1.10, §1.11, §1.12)

- Which keys do replacement and revocation statements cover: added
  publishers, the desktop's own publisher, the built-in Lychnion key, base
  keys?
- What may the holder of an old or stolen key do with statements, and is
  that in model?
- What does a key backup promise (passphrase, restore guards), and what does
  it leave to the operator?
- Can a carrier withhold statements, and what does that cost?

### Deep links and QR codes (§1.7, §1.10, §1.11)

- For each link kind (`base` and its older host `shelter`, `share`,
  `publisher`, `catalog`, and the legacy `fieldkit://` scheme), what may it
  do before and after the dialog?
- Does a link opened from a web page or message count as "checked in
  person", like a QR code scanned at the base?
- Is a fake QR code posted in person at a shelter in model?

### The base and the local Wi-Fi (§1.5, §1.10, §1.11, §1.12)

- Who is the attacker on the Wi-Fi, and what may they do?
- Is a pinned base's operator trusted for the content of facts and answers?
- On which interfaces may the base and Share nearby listen?
- Which per-request limits are promised? Is availability against a flooding
  device promised?
- Are questions, answers and the installed list confidential on the Wi-Fi?
- Is the browser page for phones without the app protected in transit?
- Is stripping a signature before a pinned base has signed once accepted?
- Are cross-site requests and DNS rebinding in model? Do bases have internet?
- Which facts may change the suggested site and route? Are time limits on
  facts promised? What does a fact signature prove?

### Privacy and storage (§1.5, §1.8, §1.11, §1.12)

- Where may questions, answers and position go? To a base only? To which
  hosts?
- May release builds write questions or answers to the system log?
- Is app data excluded from OS backups?
- Does any library (llama.cpp, bonsoir, geolocator) use the network on its
  own? (R 26)

### Headless node (§1.6, §1.7, §1.10)

- Which keys does a node trust, and who checks them?
- Is a catalog or file host that is not a publisher an attacker in scope?
  May it withhold, delay or serve old records?
- Is plain HTTP on a LAN supported? Is a reverse proxy required on the
  internet?
- May a node serve a folder it did not pull, such as a USB stick?
- Is the private-address filter a promise or defence in depth?

### Release, signing and CI (§1.3, §1.9)

- Who builds releases, where, and with which keys? Does CI hold secrets or
  produce shipped builds?
- Are the maintainers' accounts and build machines trusted?
- How are iOS, macOS and Windows builds signed?

### Coexistence (§1.1, appendix)

- How do `SECURITY.md` and the model share the work, and which wins? (R 39)

## Ruling record (2026-11-19)

The first model asked Q1 to Q20 one at a time, each with selectable
answers, against commit `6ee5dea`. After re-binding to `be565e8` it asked
Q32 and Q33 about the key statements that had landed in between, and then
Q21 to Q31, the questions the draft had left open. The maintainer chose the
proposed answer every time, and the model is accepted.

| Q | Question | Ruling |
| --- | --- | --- |
| Q1 | Scope | One model: phone app, desktop base, headless node, `lychnion_format`, `lychnion_fetch`. Out: `lychnion-data`, `lychnion-studio`, `lib/spike/`, `tool/`. |
| Q2 | What an answer promises | Only installed signed guides, sources shown, fixed safety line. Wording correctness is not promised; wrong advice with source and safety line is a content bug. Dropping either, or showing non-guide text, is a vulnerability. |
| Q3 | Dev flags | Every `--dart-define` flag and `DEV_MENU` tester builds are unsupported for users. |
| Q4 | `SECURITY.md` | Stays the reporting channel with a short summary; the model wins; this change links it. |
| Q5 | Adversaries at a base | Anyone on the Wi-Fi is in scope. A QR-pinned base's operator is trusted for content. Device control is out. |
| Q6 | Publishers and keys | The Lychnion key (1Password, never on a server or in CI) is the root; its theft is out of model; no rotation yet (key statements landed later, see Q32). Added publishers are trusted for content under their own name only; replacing Lychnion's or another publisher's items is a vulnerability. |
| Q7 | Releases | Maintainer accounts and build machines are trusted. CI ships nothing and holds no secrets. |
| Q8 | Licence | Not a security property. |
| Q9 | Headless node | Trusts the built-in key plus `--publisher` keys. A non-publisher host is in scope. LAN plain HTTP supported; a reverse proxy is required on the internet. Pull a stick, do not serve it. |
| Q10 | Link pinning | **Vulnerability:** only an in-person QR scan may give fact trust. |
| Q11 | Bind address | The base and Share nearby are for the local Wi-Fi or hotspot only; other interfaces are a vulnerability. |
| Q12 | Base availability | Per-request limits are promised; flooding from the Wi-Fi is disclaimed. |
| Q13 | Freshness | No-downgrade while installed is promised; freshness is disclaimed, tier security-critical. |
| Q14 | Models | Only Lychnion ships models. |
| Q15 | Safety lines | Only Lychnion's packages supply them. Prompt steering by a signed package is out of model. A citation means "passage given", not "answer right". |
| Q16 | Facts | Only verified facts change the suggested site or route; time limits are promised; a signature proves origin, not truth or authority. |
| Q17 | Privacy | Questions leave only to a connected base on the local network; position never leaves; release logging of questions is a vulnerability; OS backup is disclaimed. The privacy help needs the base case. |
| Q18 | Wi-Fi limits | Disclaimed: confidentiality on the Wi-Fi, browser-page integrity, signature stripping before the first signed answer, cross-site requests while bases are offline. |
| Q19 | Files after install | Trusted after install; a half-failed multi-file update is a correctness bug; parser defects go upstream. |
| Q20 | Side effects | The inventory in §1.5 is right, including the assumption that native libraries do not use the network. |
| Q21 | Fake QR code posted in person | Out of model: phones trust what is scanned in person, and staff control what is posted. A web link that pins a key stays in model (Q10). |
| Q22 | Node private-address filter | Defence in depth, tier correctness-only. Missing ranges such as `::` are bugs against it; catalog URL redirects are accepted. |
| Q23 | Node drops an incomplete record | A bug against no-downgrade, low severity (#75). |
| Q24 | Long questions on the device | Correctness only: input against the user's own device. |
| Q25 | The base computer's own Ask page | Claimed, correctness-only: answers to phones and to the computer never mix. |
| Q26 | Source link labels | Disclaimed false friend: the label is not the destination; links stay http and https only. |
| Q27 | The U+001F separator in signed facts | Fields never contain control characters; a signature that fits another split of the fields is a bug. |
| Q28 | 48-bit base key ids | A collision only denies service; disclaimed, correctness-only. |
| Q29 | Radio message reader | Unsupported until the app uses it. |
| Q30 | Code-only facts | Confirmed as written: the N/A matrix rows, the node's side effects (including client IPs in its log) and no vendored code. |
| Q31 | Deeply nested JSON | Claimed under client-response-limits: rejected without a crash or hang (#78). |
| Q32 | Lychnion's key and key statements | Statements for the built-in `lychnion` key are claimed and verified like any publisher's; theft of the key itself stays out of model. |
| Q33 | Old keys and backups | Claimed: a backup's key is readable only with the passphrase; restore never brings back a revoked or replaced key. Disclaimed: denial by an old-key holder, offline guessing of a weak passphrase, where the backup is kept. |

No question is open. The next revision continues at Q34.
