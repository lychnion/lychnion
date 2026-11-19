# Lychnion (offline AI helper): proof of concept plan

> **Dated plan.** Kept as written. Since 2026-11-18 the repo is public
> and the code is under the AGPLv3 (see the [README](../README.md#licence)).

Draft 2026-11-02, updated 2026-11-05. PoC built: private repo
`lychnion/lychnion` (Apache 2.0; named Lychnion since
2026-11-17). Results in section 7.

"Bousai LLM" is now only the name of the disaster package. The app gets a
more general name because it also targets hikers, backcountry skiers and
hunters. See section 0.

## 0. Name

Idea: one general app name, packages named by use ("<Name>: Bousai",
"<Name>: Mountain"). No "survival" in the name.

Quick check, 2026-11-02 (domains via registry RDAP/whois, App Store Japan
search). Trademarks not checked yet (J-PlatPat, classes 9 and 42).

| Candidate | Domains (.app .com .org .ai .jp) | App Store Japan | Verdict |
|---|---|---|---|
| Mamori (守り) | all taken | **"MAMORI 防災"** exists (evacuation app, updated 2026-11-01), plus 5 other "Mamori" apps and MAMORIO (lost-item tags) | Drop: direct clash in the same category |
| Tomoshibi (灯) | only **tomoshibi.ai** free | "ともしび" lamp app, study timer, therapy journal; none in disaster or outdoor | Possible |
| Shirube (しるべ) | all taken | **"しるべ"** offline direction-to-point app (Navigation, 2020); a photo app "SHIRUBE" | Weak: same idea (offline navigation), old but live |
| Sonae (備え) | all taken | "+ Sonae" (Sonae, a large Portuguese retail group); "備えメモ" family disaster notebook | Drop: big existing brand, leans to disaster only |
| Field Guide | only **fieldguide.jp** free | Many "… Field Guide" apps (fauna, mushrooms, farming) | Generic: hard to own or find, fine as a subtitle |

Later candidate (2026-11-02): **Koko AI** (ここ, "here": everything you need
is here on your device).

- Free domains: kokoai.jp, koko-ai.jp, koko-ai.app, kokoai.dev. Taken:
  koko.ai/.com/.app/.jp, kokoai.com/.app/.ai.
- Same name in use: "Koko AI" anime AI-companion app; Koko, a US AI
  mental-health service; "KoKo - Safe AI for Kids" (US App Store); "Koko"
  Korean-learning app (JP App Store). US trademark KOKO LIVE (class 9) owned
  by KOKO AI, INC. None in disaster or outdoor.
- Other meanings: 個々 (each person, fine), Koko the signing gorilla
  (friendly), Finnish "whole", Hawaiian "blood".
- Verdict: possible, but crowded and hard to find in search. Japanese
  trademark (J-PlatPat) not checked.

Also checked: **Coco AI** (2026-11-02): cocoai.jp and coco-ai.jp taken in
2026, "CocoAI" and "Coco：AI健康コーチ" in the JP App Store, big brands
(CoCo壱番屋, Pixar "Coco"), Spanish "el Coco" = bogeyman. Drop.

**Pocket AI** (2026-11-04): free pocketai.jp, pocket-ai.jp, pocket-ai.app;
pocketai.com/.app/.ai and pocket.ai taken. At least six App Store apps with
the same or almost the same name, most of them offline LLM chat apps
("Pocket AI - No Internet", "Pocket AI: Pocket Offline AI", "PocketPal AI",
"pocket - ローカルAIチャットボット"). Drop as the main name: same category,
impossible to stand out. Fine as a descriptive subtitle.

Also ruled out: "GPT" in the name (OpenAI brand rules, App Store
rejections, suggests a cloud service), bous.ai (taken 2023), bousai.ai
(taken 2026-10-16). "offlaine": .com and .app taken, .ai and .jp free.

**Shiritai / shirit.ai** (2026-11-04): blocked. Japanese trademark
登録7034984 "SHIRITAI", readings シリタイ / シリットエイアイ ("Shirit AI") /
シリット, classes 35 and 42 (42 covers software and online services), owner
HELATH株式会社, filed 2025-07-23, registered 2026-04-10, live
(https://www.j-platpat.inpit.go.jp/c1801/TR/JP-2025-083519/40/ja). Also a
free browser extension "Shiritai 知りたい" (shiritai.app). shirit.ai itself
is unregistered, but using it would clash with that trademark.
**Kikitai**: kikit.ai is a Japanese survey service "キキタイ？" since 2018.

**Moyai** (2026-11-04): blocked. 株式会社MOYAI holds "MOYAI" (登録6148595,
classes 9 and 42, 2019) and "moYaI" (登録6898543, 2024). moyai.ai is an AI
agent monitoring product; BerriAI/moyai is an active AI coding agent; all
domains taken. Also the NPO もやい (poverty support) holds 舫∞もやい.
**Musubi** (2026-11-04): blocked. KAKEHASHI holds many "Musubi" marks in
classes 42/44 and "Pocket Musubi" in class 9 (pharmacy and medication
software, close to our first-aid content); 掬びAI (ムスビエイアイ, PTS,
classes 9/42, 2025); MUSVI (ムスビ, classes 38/42). All domains taken;
musubi-tuner is a well-known AI fine-tuning tool.

**Lifeline** (2026-11-04): drop. 61 Japanese marks for ライフライン, many in
classes 9/42 (日本ライフライン, 喜界瓦斯 "Life Line" in 9/41/42, ぴあ, ...);
"Lifeline" game series by 3 Minute Games (stranded person you guide by
text) fills the App Store; in Japanese ライフライン means utilities
(power, water, gas). All domains taken.
**Bowline** (2026-11-04): possible. No Japanese mark for BOWLINE / ボーライン /
ボウライン (only "Rainbow Line" marks and a similar-sounding BAURAIN). No
App Store app. Domains all taken (.com, .app, .org, .dev, .net, .io, .ai
2025, .jp 2025-12 via onamae privacy, no site). GitHub: old deprecated
maccman/bowline. Weak points: few Japanese know the word (they say もやい結び),
and English readers may say "bow-line" or think of bowling.

Decision (2026-11-04): leave "AI" and "GPT" out of the name. Use a neutral
code name for the repo and the code during the PoC. Choose the public name
once the app works and it is clear what it does best. The public name only
lives in the store listing, app title and website, so changing it later is
cheap.

Next: pick one or two, check J-PlatPat and Google Play, then consider
compound forms (for example "Tomoshibi Guide", or a name with a free
`.app`/`.jp`). Repo name follows the app name.

Goal: an offline AI helper for disaster preparedness in Japan. One Flutter
codebase for iOS, Android, macOS and Windows. Open source. Every answer cites
its sources. Personal goal: learn how offline AI works end to end.

## 1. What exists today

| | SEER | CrowChat | Survival LLM |
|---|---|---|---|
| Maker | LIBRA | Versefactory.AI | anonymous dev, brangus.io |
| Price | ¥2,980 once | Free | Free |
| Source | Closed | Closed | MIT |
| Platforms | iOS/iPadOS 18+ (A12+). Mac listed but "not tested" | iOS 15+. Android "in preparation" | macOS (Apple Silicon), Windows x64. No phone |
| Model | Gemma, picked by device. 0.9 to 2.4 GB download | 1B / 2B / 9B by RAM, 0.8 to 5.9 GB | 8B to very large. 6 to 80 GB |
| Answers | Generated, cites the one bundled book | Mostly a curated, pre-written Q&A set, cites source | Generated from RAG, cites articles with highlights |
| Knowledge | One book ("ネットが死んだ日", 190k chars), GSI evacuation sites | GSI evacuation sites (~99,000), GSI tiles, hazard map portal, P2P地震情報, own Q&A based on 東京防災, JMA, FDMA, MHLW | Wikipedia, WikiMed, MedlinePlus, CDC, Ready.gov, military manuals, wikiHow, iFixit; user can add own files |
| Maps | Nearest sites by GPS, no map tiles mentioned | Offline map areas, hazard overlays (hazard check needs network) | None |
| Device to device | No | Not on the site (P2P地震情報 is only a data feed) | No |
| Other | First aid flows, emergency mode, stock calculator, family plan, voice in/out | Recent quake/tsunami info (only from last online fetch) | Memory notes, two library sizes, unsigned installers |

Gaps the PoC can fill:

- **Open and inspectable.** Only Survival LLM is open, and it is desktop only.
- **Phone and desktop from one codebase.** Nobody has both.
- **Swappable knowledge.** All three ship one fixed library. Nobody offers
  packages for a use case (hunting, backcountry, hiking).
- **Licence shown per source.** Only Survival LLM does this.
- **Facts with an expiry.** CrowChat shows "last fetched" quake data, but
  nobody models time, source and expiry, and nobody shares updates between
  devices.
- **Japanese RAG, not canned answers.** CrowChat avoids generation for safety.
  We can keep generation but make it quote retrieved text.

## 2. On-device LLM in Flutter

| Option | iOS | Android | macOS | Windows | Notes |
|---|---|---|---|---|---|
| **flutter_edge_ai** (was flutter_gemma), MIT | yes | yes | yes (14+) | yes (x64) | One Dart API over several engines below. Has embeddings and a RAG add-on (sqlite-vec). Active, but young and fast-moving |
| ↳ LiteRT-LM (`.litertlm`) | yes, Metal | yes, GPU/NPU | yes | yes | Google's current runtime. Best for Gemma. Fewer models converted |
| ↳ llama.cpp (`.gguf`) | yes (16.4+) | yes | yes | yes | Any GGUF model (Qwen, Sarashina, LFM, ...). Most model choice |
| ↳ MediaPipe LLM (`.task`) | CPU only | yes | no | no | Upstream says maintenance only. Skip |
| MLC LLM | yes | yes | yes | partly | No maintained Flutter binding. Would need our own FFI. Skip for PoC |
| Own FFI to llama.cpp | yes | yes | yes | yes | Fallback if the package breaks. More work, full control |

**Pick:** flutter_edge_ai with the llama.cpp engine first (widest model
choice for Japanese), LiteRT-LM as a second engine to compare speed with
Gemma 4. Keep the LLM behind one small interface so we can switch to our own
FFI later.

### Models (Japanese, 2 to 4B)

| Model | Size | Licence | Note |
|---|---|---|---|
| Gemma 4 E2B | 2.3B effective, 2.8 GB Q4_0 (measured) | Apache 2.0 | Spike 1 model. Fast on Mac; ~4.5 GB RAM on Android |
| Gemma 4 E4B | 4.5B effective | Apache 2.0 | Desktop / high-end phone |
| Qwen3.5-4B | 4B | Apache 2.0 (check card) | Top under-10B on one Japanese leaderboard (Qualiteg, Sep 2026) |
| LFM2.5-1.2B-JP | 1.2B | LFM licence (check terms) | Very small fallback for old phones |
| Sarashina2.2 3B / TinySwallow 1.5B | | check | Japanese-made, test if time allows |

Embeddings for search: **Ruri v3 30m or 70m** (Apache 2.0, Japanese,
small), or EmbeddingGemma (supported by flutter_edge_ai out of the box).

The PoC includes a small test set (about 30 Japanese questions with known
answers from the packages) to compare models on real devices: answer quality,
citation correctness, time to first token, RAM.

## 3. Architecture

```
┌──────────── Flutter app (iOS / Android / macOS / Windows) ────────────┐
│  Chat UI ─ citations ─ map view ─ package manager ─ "current facts"   │
│                                                                        │
│  Retriever ── SQLite + FTS5 (keyword) + sqlite-vec (vectors)           │
│     │            ▲                                                     │
│     ▼            │ installed packages                                  │
│  Prompt builder ─┘   (top 4-6 chunks, each with source id)             │
│     │                                                                  │
│     ▼                                                                  │
│  LLM interface ── flutter_edge_ai (llama.cpp / LiteRT-LM)              │
│                                                                        │
│  Facts store: {fact, time, source, expires_at} (built, see §7)         │
│  Map: flutter_map + PMTiles (offline vector tiles)                     │
└────────────────────────────────────────────────────────────────────────┘
```

- **Hybrid search.** Japanese keyword search (FTS5 with a bigram or
  morphological tokenizer) plus vector search. Keyword search catches place
  names and exact terms that small embedders miss.
- **Answers must cite.** The prompt gives numbered chunks. The app checks each
  `[n]` in the answer points to a given chunk and shows the source text and
  licence under the answer. If nothing relevant is found, the app says so
  instead of letting the model guess.
- **Safety lines are not generated.** "Call 119", "go to higher ground now"
  and similar come from fixed text in the package, shown above the model
  answer.

### Knowledge packages

A package is one file (SQLite) with chunks, embeddings, sources and licence
metadata, plus a small manifest:

```json
{
  "id": "jp.bousai.core",
  "version": "2026.11.0",
  "language": "ja",
  "embedding_model": "ruri-v3-70m",
  "sources": [
    {"id": "gsi-hinanbasho", "title": "指定緊急避難場所データ",
     "publisher": "国土地理院", "licence": "国土地理院コンテンツ利用規約",
     "attribution": "出典：国土地理院", "retrieved": "2026-11-01"}
  ]
}
```

A small build tool (Python or Dart CLI) turns source documents into a
package. Packages are downloaded once over Wi-Fi, or copied from another
device or a USB stick.

### Offline maps and location

- `flutter_map` + PMTiles works on all four platforms (pure Dart).
  MapLibre's Flutter plugin does not cover desktop well.
- Base map: a Japan or per-prefecture PMTiles extract of OpenStreetMap
  (ODbL, attribution needed), or GSI vector tiles (国土地理院コンテンツ利用規約).
- Evacuation sites from GSI as a point layer. "Nearest sites by hazard type"
  works on GPS alone, no network.
- Hazard overlays (flood, landslide) are raster tiles from the hazard map
  portal. Size per prefecture is the open question. Optional in the PoC.

## 4. Sources and licences

Status: ✅ fine with attribution, ⚠️ needs a check or permission, ❌ not usable
as is.

### Bousai package (`jp.bousai.core`)

| Source | Licence | Status |
|---|---|---|
| GSI 指定緊急避難場所・指定避難所データ (CSV/GeoJSON) | 国土地理院コンテンツ利用規約 (CC BY 4.0 compatible) | ✅ cite "出典：国土地理院". Data only covers municipalities that agreed to publish |
| 内閣府 防災情報, 消防庁 (FDMA) guides, 気象庁 (JMA) explanations, 厚労省 | 政府標準利用規約 2.0 (CC BY 4.0 compatible) | ✅ but check each page: third-party images and some pamphlets are excluded |
| 消防庁 応急手当 (first aid) materials | 政府標準利用規約 | ✅ check per document |
| 東京防災 (Tokyo Metropolitan Government) | No open licence found | ⚠️ ask 東京都総合防災部. CrowChat only "based on" it |
| Municipal open data (shelters, hazard info) | Often CC BY 4.0, varies | ⚠️ per municipality |
| 日本赤十字社 first aid, JRC 蘇生ガイドライン | Copyright | ❌ link only, or ask |
| Wikipedia JA (selected articles) | CC BY-SA 4.0 | ✅ but share-alike: keep it in its own package |

### Outdoor packages

| Package | Sources | Status |
|---|---|---|
| Hiking (`jp.outdoor.hiking`) | 警察庁 山岳遭難の概況 (prevention part), 気象庁 lightning / thunderstorm / volcano pages, 環境省 熱中症, 厚労省 SFTS Q&A, 林野庁 ticks and hornets | ✅ First version built in the app (2026-11-18): 10 sources, 50 passages, PDL1.0. Gaps: hypothermia, マムシ (no national page with reuse terms); 夏山登山の警告文 waits for licence check. ⚠️ 日本山岳ガイド協会 and mountain-hut info need permission |
| Backcountry ski / snowboard (`jp.outdoor.backcountry`) | 気象庁 snow and weather explanations, 防災科研 (NIED) avalanche material | ⚠️ NIED terms per item. 日本雪崩ネットワーク (JAN) bulletins are copyright, ask them, they are the key source |
| Hunting (`jp.outdoor.hunting`) | 環境省 鳥獣保護管理 pages, hunting law (e-Gov 法令, free to use), 熊/猪 safety | ✅ law and ministry pages. ❌ 狩猟読本 (大日本猟友会) is copyright |

Rule for every package: no source goes in without a licence entry in the
manifest. The app shows it under each citation.

### Sources from abroad

Agreed 2026-11-18. Much survival knowledge is the same everywhere
(hypothermia, frostbite, wound care, avalanche rescue basics), so foreign
sources may fill gaps where Japan has no usable source.

- **Universal topics only:** the body, first aid, physics (lightning,
  snow). Not species (マムシ, ツキノワグマ), laws, services or emergency
  numbers; such lines are dropped when the package is built.
- **Every source has a region** (ISO 3166: `JP`, `JP-13`, `GB`, `US`), in
  the manifest (`"region"` per source, or for the whole package; default
  `JP`).
- **Local first, nothing dropped.** All packages are searched together and
  relevance decides; a more local source only gets a small nudge (3 % per
  level) when passages are about equally relevant. A small local package
  adds to the general ones, it never hides them.
- **The model combines them.** When a foreign passage is among the
  sources, the prompt says: combine all sources, follow the Japanese one
  where they disagree, take no phone numbers, laws or services from
  foreign sources.
- **Labelled:** 「海外の資料（英国）」 next to the source.
- **Translated when the package is built, never on the phone.** The phone
  model turned "snug but not too tight" (snakebite bandage) into
  「しっかりと縛って」. So foreign passages get a translation once, stored in
  `lychnion-data/packages/translations/<id>.<lang>.json` (reviewed by a person
  before release), and the package keeps the original next to it: Japanese
  questions use the translation, English ones the original, and the
  sources sheet shows 「Lychnionによる翻訳（公式の訳ではありません）」 with the
  original one tap away.
- **Every package in more languages, made at build time** (decided
  2026-11-18): each passage can carry its text per language
  (`lychnion-data/tool/add_translations.py`, table `passage_texts`), so the phone model
  reads passages in the question's language and never translates. Japanese
  and English first; publishers could add more (Spanish, Chinese, …) later.
  For that the app also needs language detection beyond ja/en, its own
  texts, and safety lines and notices per language.
- **First foreign package:** `intl.firstaid.basics` (2026-11-18), US Army
  ATP 4-02.11 (bites, snakebite, ticks, heat, altitude) and TC 21-3 (cold
  injuries), public domain; sources picked with the vetted list of the
  Survival LLM project. Left out: rabies (Japan has none), US species
  identification, 911, and the jellyfish advice (looks outdated).
- **Licences:** the data licence is independent of the app's (AGPL). For
  the general packages, sources that allow any reuse with credit: PDL1.0,
  CC BY, UK Open Government Licence, US federal public domain. Sources
  with NC (non-commercial) or SA (share-alike) terms only in a package of
  their own, so the others stay free to pass on.

## 5. PoC scope

**In (about 4 to 6 weeks of part-time work):**

1. Flutter app that runs on macOS and Android first, then iOS and Windows.
2. Chat with one local model (Gemma 4 E2B via llama.cpp), streaming answers.
3. One package: `jp.bousai.core`, small (GSI evacuation sites + ~50 pages of
   FDMA/内閣府/JMA guidance).
4. Hybrid search and checked citations.
5. Map with offline tiles for one prefecture and nearest evacuation sites.
6. Test set and a one-page result: which model, which device, how fast, how
   often citations are right.

**Out for now, later steps:**

- Outdoor packages (build one after the core works, probably hiking).
- ~~Current facts store~~ (done 2026-11-05, see §7).
- Sharing packages and facts between devices: Wi-Fi/Bluetooth nearby sync,
  then Meshtastic over BLE (Idea 5). Facts must be small and signed.
- Shelter / local-government desktop features (several users, printing).
- Voice input and output.

### Steps

1. Spike: Flutter + flutter_edge_ai runs Gemma 4 E2B on a Mac and an
   Android phone. Measure speed and RAM. (Decides if the package is good
   enough or we need own FFI.)
2. Package builder: GSI CSV + a few gov HTML pages → SQLite package.
3. Retrieval + prompt + citation check, tested from the command line first.
4. App UI: chat, citations, package list.
5. Map and nearest sites.
6. Test set run on 3 to 4 devices, write up results.

## 6. Open questions for Daniel (answered 2026-11-04)

- Code: private repo, first on Daniel's GitHub account, since 2026-11-17
  in the `lychnion` org (`lychnion/lychnion`), Apache 2.0.
- Platforms: tested on a Mac, an iPad Air 5, a Pixel 5a and the iPhone
  simulator (as of 2026-11-05).
- Sources: clearly open ones only for the PoC (PDL1.0 government pages, GSI).
  東京都 and 日本雪崩ネットワーク not contacted.
- Language: Japanese and English from the start.

## 7. Results (updated 2026-11-05, evening)

Details in the repo: `docs/spike-1-results.md` to `docs/spike-6-results.md`,
`docs/map-results.md`, `docs/device-results.md`, `docs/shelter-results.md`,
`docs/download-results.md` and `docs/facts-results.md`.

| Step | Result |
|---|---|
| 1. Model on device | Gemma 4 E2B (Q4_0, 2.65 GB) via flutter_edge_ai + llama.cpp. Mac M4 Max: ~115 tokens/s. |
| 1. Bare model, 8 safety questions | 2 dangerous (tsunami: "wait for TV/radio"; avalanche: no beacon), 1 wrong number (water). |
| 2. Answers from sources | Package of official pages (PDL1.0), citation check, fixed safety lines quoted word for word. Tsunami and water fixed. |
| 3. Vector search, English | EmbeddingGemma 2 (310 MB, multilingual). English questions translated to Japanese before search. |
| 4. Near-topic answers | Volcano page added; a yes/no self-check with the 2B model did not work; "partly covered" label instead. |
| 5. Desktop model | Gemma 4 E4B (4.6 GB): better answers, 68 tokens/s, 5.2 GB. For the desktop / shelter version. Still not a reliable judge. |
| 6. Bears, getting lost | 政府広報オンライン articles (plain text, PDL1.0), two more safety lines. 37 questions: **28 / 28 covered answered from the right source, 9 / 9 uncovered refused.** |
| Map | Nishinomiya: 24 MB offline map (OSM/Protomaps), 2,614 GSI sites. Nearest site per hazard; answers link to the map. |
| iPad Air 5 (M1, 8 GB) | Full app offline: ~22 tokens/s, answers in 2 to 9 s, ~2 GB memory, same results as the Mac. |
| Pixel 5a (2021, 6 GB) | Same quality, but CPU only: median 48 s per answer; memory borderline. Reading less (2 short passages) gets ~29 s at a small quality cost. |
| Small phone models | Qwen3-1.7B 20 / 23, LFM2.5-1.2B-JP 14 / 23; both computed the family water amount wrong (12 L instead of 36 L). |
| Shelter computer | Desktop app answers phones on the local network (E4B). Pixel 5a without a model: answer in 2.5 s instead of 48 s. Office Wi-Fi blocked device-to-device traffic (client isolation): a shelter needs its own hotspot or a network that allows it. |
| Downloads | Models (Hugging Face), package and map area (public `lychnion/lychnion-data` releases) downloaded in the app with resume and SHA-256 check. Pixel 5a: everything downloaded, then airplane mode: cited answer and offline map work. |
| GSI data gap | 西宮市 and 尼崎市 mark no emergency site for earthquakes (神戸市 marks all). The app now warns when the user's city has no site for the hazard and points to the city's hazard map. |
| Current facts | Shelter status, blocked roads, water points and warnings, each with time, source (official / sensor / resident) and expiry, kept apart from the model. The most trusted source wins, then the newest; expired facts are never shown. Full or closed shelters are skipped when suggesting where to go. Shown as 「最新の情報（AIの回答ではありません）」 with age and source. |
| Facts entry | Staff enter facts on the shelter computer's map (status per site, long press for a road or water point, warnings per city), with a lifetime and source; "解除する" clears a fact. Phones pull them every minute. |
| Radio-sized facts | Compact format for LoRa / Meshtastic: one shelter update is 16 bytes, 12 updates fit in one 190-byte message. Not yet sent over a radio. |
| Shelter QR code | The shelter computer shows a QR code; the phone camera opens Lychnion, which asks before it connects. Address can also be typed. Tested Mac → iPhone simulator. |
| Signed facts | Official facts are signed (Ed25519) by the device that enters them; phones trust a shelter's key through its QR code. Unsigned "official" facts count as resident reports. Radio: one signature per message, 6 signed updates per 200 bytes. |
| Walking routes | Distances and minutes along roads and paths (OpenStreetMap walking graph, 10.4 MB for the Nishinomiya area), the route drawn on the map, sites sorted by walking distance, blocked roads avoided. Search 19 ms on the simulator. For tsunami, GSI ground heights: routes keep to higher ground, each site shows its height above sea level, a route that dips 2 m or more is flagged. Small effect in flat Nishinomiya (routes 0–6 % longer, dips slightly lower). |
| Tsunami inundation area | Official expected inundation (国土数値情報 A40, CC BY 4.0) on every road point. In tsunami mode the map says whether you are inside (with expected depth) and draws the way out of the area; routes avoid deep areas; each site shows its expected flooding. The areas are drawn on the map, coloured by depth (1.5 MB of tiles). |
| Second area: Kushimoto | 串本町 (Kii peninsula, steep coast): the same tools build it in under a minute, 3 MB in all. There the tsunami route matters: from the town centre (3–5 m expected) the way out leads uphill in 391 m (about 7 min); in flat Nishinomiya it is 910 m and stays low. |
| App design | Redesigned for demos: chat-style Ask screen with suggested questions and a status label, full-screen map with a sliding panel, Settings with language (device / 日本語 / English) and downloads. |
| iPhone simulator | Runs the full app (CPU). Needed one build fix for Xcode 27. |

Lessons:

- The bare model is fast enough on recent devices but must not answer
  safety questions alone.
- A citation is only as good as the source text. OCR of two-column PDFs
  inverted advice twice (bears: "drop your bag and run", "don't make
  noise"); that source is disabled. Use plain-text sources only.
- Content beats cleverness: missing official pages caused the bad answers;
  adding them fixed volcano, bears and getting lost.
- Fixed safety lines carry the critical action even when the small model's
  own answer is weak.
- Recent phones and tablets run the app well; older Android phones need GPU
  support or a shelter computer that answers over local Wi-Fi (shown working).
- Official open data has gaps too (missing earthquake designations): the app
  must say when it cannot find a proper site, not silently send people to the
  next city.

Still open: Android GPU, an official
facts feed with city keys, key revocation, sending facts over a radio mesh (Idea 5), QR test
with a real phone camera, iOS test of the downloads, public name.

## Sources

- SEER App Store page: https://apps.apple.com/jp/app/seer-%E3%82%AA%E3%83%95%E3%83%A9%E3%82%A4%E3%83%B3%E7%94%9F%E5%AD%98%E6%88%A6%E7%95%A5ai/id6804414258
- CrowChat: https://crowchat.ai/
- Survival LLM: https://www.brangus.io/survival-llm
- flutter_edge_ai: https://pub.dev/packages/flutter_edge_ai
- Japanese LLM ranking (Qualiteg, Sep 2026): https://journal.qualiteg.com/llm-ranking-2026/
- LFM2.5-1.2B-JP: https://gigazine.net/gsc_news/en/20260107-lfm2-5-on-device-ai/
- Ruri v3: https://huggingface.co/cl-nagoya/ruri-v3-70m
- GSI evacuation site data: https://www.gsi.go.jp/bousaichiri/hinanbasho.html

Not verified first-hand: Gemma 4 and Qwen3.5 licences (from secondary
sources), exact GSI and NIED terms pages, Survival LLM's GitHub URL (the site
links are placeholders).
