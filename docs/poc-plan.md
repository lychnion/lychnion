# Offline AI helper (name open): proof of concept plan

Draft, 2026-11-02. Nothing built yet. No repository created.

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
│  Facts store (later): {fact, time, source, expires_at}                 │
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
| Hiking (`jp.outdoor.hiking`) | 環境省 / 林野庁 guidance, 警察庁 山岳遭難 stats, 環境省 クマ出没対応 manuals, OSM trails | ✅ gov terms / ODbL. ⚠️ 日本山岳ガイド協会 and mountain-hut info need permission |
| Backcountry ski / snowboard (`jp.outdoor.backcountry`) | 気象庁 snow and weather explanations, 防災科研 (NIED) avalanche material | ⚠️ NIED terms per item. 日本雪崩ネットワーク (JAN) bulletins are copyright, ask them, they are the key source |
| Hunting (`jp.outdoor.hunting`) | 環境省 鳥獣保護管理 pages, hunting law (e-Gov 法令, free to use), 熊/猪 safety | ✅ law and ministry pages. ❌ 狩猟読本 (大日本猟友会) is copyright |

Rule for every package: no source goes in without a licence entry in the
manifest. The app shows it under each citation.

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
- Current facts store `{fact, time, source, expires_at}` with "expired" shown
  in the UI.
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

## 6. Open questions for Daniel

- Where should the code live? (new repo, which org, licence: MIT or
  Apache 2.0?)
- Start with macOS + Android, or iPhone first?
- OK to contact 東京都 and 日本雪崩ネットワーク about reuse, or keep to
  clearly open sources for the PoC?
- Japanese UI only, or Japanese + English from the start (helps visitors and
  the grant text)?

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
