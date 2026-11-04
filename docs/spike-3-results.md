# Spike 3: vector search, cut-off, Japanese and English

Date: 2026-11-04. MacBook Pro M4 Max. Chat model Gemma 4 E2B Q4_0 (as before).
New: EmbeddingGemma 2 (Q8_0, 310 MB, Apache 2.0, multilingual) for vector
search through flutter_edge_ai's llama.cpp backend, hybrid ranking, a
relevance cut-off, and English questions. 28 test questions
([lib/spike/eval_questions.dart](../lib/spike/eval_questions.dart)):
14 Japanese and 6 English questions the package covers, 8 it does not.
Raw results: `spike-results/macos-spike3-*.json`.

## How it works now

1. Passages are embedded once on the device (97 passages: 2.5 to 3 s on the
   Mac) and cached per package version.
2. English questions are first translated into Japanese by the chat model,
   because the package is Japanese and Japanese-to-Japanese search works much
   better than English-to-Japanese.
3. Ranking: vector similarity and bigram keyword score, merged by reciprocal
   rank fusion. Keyword search only for Japanese text.
4. Cut-off: passages below cosine 0.70 are never given to the model. If none
   are left, the app says "no source" without calling the model.
5. The model's own "no answer in the sources" reply is the second gate.
6. The tsunami safety line now has English trigger words and an English
   translation, shown with the official Japanese text and marked as our
   translation.

## Results (final run, cut-off 0.70)

| Group | Good | Notes |
|---|---|---|
| Japanese, covered (14) | 13 | Paraphrases work (飲み水, 部屋の中, 車を運転していて). Miss: "10 things for the shelter" answered "no list in the sources". |
| English, covered (6) | 5 | Earthquake, tsunami (with safety line), water, bleeding, evacuation site vs shelter are right and cited. Miss: avalanche answered from the victim's view ("escape to the edge"), not the rescuer's. |
| Not covered (8) | 5 | Heatstroke, mamushi, typhoon windows, snake bite (en), day-hike packing (en): "no source". Misses: hiking without signal (cites a snow passage, says call 110), bear encounter (gives prevention tips instead of "no source"), volcano (generic advice). |

Retrieval alone (first run): the right source was first for all 16 Japanese
covered questions.

## What we learned

- **Vector search fixes paraphrases** without synonym lists. Japanese
  retrieval is now reliable on this test set.
- **Cross-language search is weak; translating the question first is a cheap
  fix.** English answers went from 0 of 6 usable to 5 of 6. Cost: one short
  extra model call (about 0.3 s on the Mac).
- **Page leftovers hurt.** Link lists ("災害関連X") and video captions
  matched English words and outranked real content. The builder now drops
  them; every new source needs this check.
- **A similarity cut-off alone cannot separate "covered" from "not
  covered".** Near topics score high (bear prevention vs bear encounter: 0.83;
  volcano vs general evacuation advice: 0.72), while covered English
  questions scored as low as 0.60 before translation. The cut-off is a cheap
  first filter; the model's refusal is the real gate, and it still lets
  near-topic answers through.
- **Near-topic answers are the remaining risk.** They are cited and sound
  right but answer a slightly different question. Ideas: ask the model to
  first say whether the passages answer the question (yes/no), or show
  "related information, not a direct answer" in the UI.

## Next

1. "Does this answer the question?" check before generating (or a separate
   short call), and a UI label for related-but-not-direct answers.
2. Fill the package gaps (hiking, bear encounter, volcano is a 首相官邸 page
   too: funka.html).
3. Real phone test, now with both models (about 3.2 GB of model files).
4. Grow the test set as the packages grow; keep it bilingual.
