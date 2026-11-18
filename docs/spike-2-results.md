# Spike 2: answers from official sources, with citations

Date: 2026-11-04. Same model and questions as spike 1 (Gemma 4 E2B Q4_0,
MacBook Pro M4 Max). New: a small Bousai package, keyword search, a prompt
that allows only the given passages, a citation check, and fixed safety
lines. Raw results: [spike-results/](spike-results/) (`*-grounded*.json`).

## How it works

1. `lychnion-data/tool/build_package.py` turns a manifest
   ([lychnion-data/packages/jp.bousai.core.json](../tool/packages/jp.bousai.core.json))
   into one SQLite file: 109 passages from 7 government sources, 356 KB.
   All sources use PDL1.0 (CC BY 4.0 compatible). PDFs with a broken text
   layer go through macOS OCR.
2. Fixed safety lines ("alerts") are quoted word for word from a source; the
   build fails if the quote is not in the source. One so far: tsunami.
3. The app searches the package (character bigrams, BM25, small synonym list),
   gives the model the top 4 passages with numbers, and asks it to answer only
   from them and cite `[n]`.
4. The app checks the citations: every `[n]` must point to a passage it gave
   the model. If nothing relevant is found, the model is not called and the
   app says so.

## Results

| Question | Spike 1 (model alone) | Spike 2 (with package) |
|---|---|---|
| Earthquake, at home | OK | **OK**, cited (首相官邸 地震) |
| Strong shaking near the sea | **Dangerous** (wait for TV/radio) | **Fixed**: safety line on top, answer "leave the coast, go as high as possible", cited |
| Water for 4 people, 3 days | **Wrong** (9 L) | Correct but incomplete: "3 L per person per day for 3 days", no total |
| 10 things for the shelter | OK (from memory) | Honest: "the sources have no list of 10", points to the emergency bag |
| Lost while hiking, no signal | Weak | Weak: cites a snow-mountain passage ("call 110/119 by radio or phone"); no real source in the package |
| Bear encounter | Mixed | Run 1: **dangerous** (see below). Run 2, after the fix: vague but safe |
| Avalanche, buried partner | **Wrong** (no beacon) | Cited the right passage, but gave step 3 (mark the spots) as the first step; the source starts with "keep watching the person" |
| Heavy bleeding | OK | **OK**, cited (消防庁 止血法) |

Every answer had valid citations; no made-up passage numbers. The answers are
shorter and stick to the sources. Speed: first token 150 to 520 ms (longer
prompts than spike 1), about 115 tokens/s.

## What we learned

- **Retrieval plus fixed safety lines fixed the worst failure** (tsunami)
  and the wrong number (water). The model stopped adding facts from memory.
- **A citation is only as good as the source text.** In run 1 the bear
  answer listed "don't" items as things to do ("drop your bag and run",
  "don't use bear spray"). Cause: OCR of a two-column do / don't table mixed
  the columns. The citation check passed, because the garbled passage was
  really there. Fix for now: skip that page; the package lists it as a gap.
  Rule for packages: tables and multi-column layouts need a checked text
  version, not raw OCR.
- **Keyword search misses paraphrases** (飲み水 vs 飲料水, 家の中 vs 屋内).
  A synonym list fixed the test questions, but this does not scale; vector
  search (e.g. Ruri v3) is the next step.
- **Weak matches should not count as a source.** The hiking question pulled
  one loosely related snow passage and got a confident answer. Needs a better
  relevance cut-off, or a check that the passage really answers the question.
- **Small models summarise unevenly.** Avalanche: right passage, wrong
  "first" step. Showing the cited passage under the answer (the app does
  this) lets the user read the source directly.

## Next

1. Vector search with a small Japanese embedder, combined with keyword search.
2. Better relevance cut-off; test questions that the package does not cover.
3. A checked bear source and a hiking source (prefectural police pages need a
   licence check each).
4. More fixed safety lines (avalanche: keep watching, then beacon search;
   bleeding: direct pressure, call 119).
5. Real phone test.
