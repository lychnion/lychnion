# Real device test: iPad Air (5th generation)

Date: 2026-11-04. iPad Air 5 (Apple M1, 8 GB), iPadOS, release build signed
with a free Apple ID (personal team). Same app and data as spike 4:
Gemma 4 E2B Q4_0 (2.65 GB), EmbeddingGemma 2 Q8_0 (296 MB), Bousai package,
Nishinomiya map (25 MB), cut-off 0.70, no relevance check.
Raw results: [spike-results/ipad-air5-m1-spike4.json](spike-results/ipad-air5-m1-spike4.json).

| | iPad Air 5 (M1, 8 GB) | MacBook Pro M4 Max |
|---|---|---|
| Engine | GPU (Metal) | GPU (Metal) |
| Model load | 14 s first time, 4.2 s after | 1.5 to 4.5 s |
| Speed | about 22 tokens/s (15 to 24) | about 115 tokens/s |
| First token (prompt with 4 passages) | median 2.1 s, max 4.2 s | 0.15 to 0.5 s |
| Whole answer | median 3.5 s, max 9.1 s | 1 to 2 s |
| App memory | about 1.9 to 2.6 GB | 1.6 to 3 GB |
| 35 test questions | 23 / 23 covered, 10 / 12 uncovered | same |

33 of 35 answers were word for word the same as on the Mac. The full run of
35 questions took about 2.5 minutes. The map (vector mode, with labels) and
the link from answers to the nearest evacuation site work the same as on the
Mac.

![Tsunami answer on the iPad](images/ipad-tsunami-answer.png)

![Offline map on the iPad](images/ipad-map.png)

## What this means

- **A recent iPhone or iPad runs the full app.** Answers take a few seconds,
  which is fine for this use. The 8 GB M1 is roughly what current iPhone Pro
  models have; older or smaller iPhones still need testing.
- **Most of the waiting is reading the sources, not writing.** The first
  token waits for the model to read about 1,000 tokens of passages. Shorter
  passages, or fewer of them, would make answers start sooner.
- **Memory is fine on 8 GB:** about 2 GB for both models, well below the
  emulator's 4.5 GB (iOS maps the model file instead of copying it).

## Setup notes

- Free Apple ID: "Extended Virtual Addressing" cannot be signed with a
  personal team, so only "Increased Memory Limit" is set. Apps signed this way
  stop working after 7 days and must be reinstalled.
- Models and map are copied over the cable into the app's Documents folder:
  `xcrun devicectl device copy to --domain-type appDataContainer
  --domain-identifier dev.fieldkit.fieldkit`. The app accepts `docs:` paths
  for this (`lib/util/paths.dart`).
- iOS release builds do not show the app's log in `devicectl --console`;
  the test writes its results and screenshots to Documents, copied back with
  `xcrun devicectl device copy from`.

## Next

- Pixel 5a (2021, 6 GB): the low end, probably needs a smaller model.
- Download of models and packages inside the app (now copied by cable).

# Pixel 5a (2021, 6 GB, Android 14)

Date: 2026-11-05. Same app and data, Gemma 4 E2B Q4_0 + EmbeddingGemma 2,
CPU only (llama.cpp picks the CPU on Android). Raw results:
[spike-results/pixel5a-gemma4-e2b.json](spike-results/pixel5a-gemma4-e2b.json).

| | Pixel 5a (6 GB) | iPad Air 5 (M1) | Mac M4 Max |
|---|---|---|---|
| Engine | CPU | GPU | GPU |
| Model load | 12 to 14 s | 4 to 14 s | 1.5 to 4.5 s |
| Writing speed | about 5.5 tokens/s | about 22 | about 115 |
| Reading the sources (first token) | median 44 s, max 130 s | median 2.1 s | 0.15 to 0.5 s |
| Whole answer | **median 48 s, max 2.5 min** | median 3.5 s | 1 to 2 s |
| App memory | 2.0 to 2.4 GB | about 2 GB | 1.6 to 3 GB |
| 35 test questions | 22 / 23 covered, 10 / 12 uncovered | 23 / 23, 10 / 12 | 23 / 23, 10 / 12 |

- **Quality holds, speed does not.** The answers are as good as on the
  Mac (16 of 35 word for word the same; the only new miss is the English
  avalanche question, answered "no answer in the sources"). But nearly a
  minute per answer is too slow for an emergency.
- **The bottleneck is reading, not writing.** On the CPU the model reads
  the question and four passages (about 400 to 1,000 tokens) at well under
  50 tokens/s. Fewer and shorter passages would help more than a faster
  writer.
- **Memory is borderline.** Android closes most other apps (Gmail, Chrome,
  Slack, Settings) to make room, and kills fieldkit itself as soon as
  another app comes to the front. The model then has to load again.
- Embedding the 108 passages the first time took 133 s (cached afterwards).
  A package should ship with its vectors, so phones never do this.
- Speed dropped during the run (first answers about 25 to 40 s, later up to
  2.5 min), most likely because the phone got warm and slowed down.

## What this means for older phones

Small models are faster but lost quality on the Mac (Qwen3-1.7B 20 / 23,
LFM2.5-1.2B-JP 14 / 23) and both computed the family water amount wrong
(12 L instead of 36 L). So for phones like the Pixel 5a the options are:

1. Same model, less to read: two shorter passages instead of four, and
   vectors shipped in the package.
2. A smaller model plus more fixed safety lines, so the critical answers do
   not depend on the model.
3. Use the phone as a client: the desktop version at a shelter answers
   phones nearby over local Wi-Fi (as in the Idea 4 desktop version).

## Setup notes (Android)

- Release builds keep their private folder closed to adb. Models are pushed
  to the app's folder on shared storage, `Android/data/<package>/files`
  (`docs:` paths). The app has to create that folder itself first; if adb
  creates it, the app cannot see the files.
- The test turns on "Stay awake while charging" over adb during the run and
  restores it afterwards (`settings put global stay_on_while_plugged_in`).
