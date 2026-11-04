# Spike 5: bigger desktop model (Gemma 4 E4B)

Date: 2026-11-05. MacBook Pro M4 Max. Same app, package and 35 questions as
spike 4. Gemma 4 E4B: `gemma-4-E4B-it-Q4_0.gguf` from
`ggml-org/gemma-4-E4B-it-GGUF` (4.6 GB, Apache 2.0, SHA-256 checked).
Raw results: `spike-results/macos-e4b*.json`, `macos-e2b-no-bear-source.json`.

## E4B vs E2B

| | E2B (2.65 GB) | E4B (4.6 GB) |
|---|---|---|
| Covered, answered from the right source | 23 / 23 | 22 / 23 |
| Uncovered, refused | 10 / 12 | 10 / 12 |
| With the yes/no check: covered / uncovered | 15 / 23, 12 / 12 | 20 / 23, 11 / 12 |
| Speed (Mac) | 113 tokens/s | 68 tokens/s |
| Whole answer (median) | 0.7 s | 1.4 s |
| App memory | 3.4 GB | 5.2 GB |

- **E4B writes better answers.** English avalanche question: "immediately
  search using an avalanche beacon, then dig them out" (E2B answered from the
  victim's view). "10 things for the shelter": a real list from the sources
  (E2B: "no list in the sources").
- **E4B is a much better judge**, but still refuses two good answers with
  the check on. The check stays off.
- One new miss: volcano alert level 3 answered "no answer in the sources"
  (E2B said the sources have no specific actions for level 3).
- For a desktop or shelter computer E4B is worth it: 1.4 s per answer and
  5 GB of memory are fine there. For phones E2B stays the choice.

## Bear source removed

E4B answered the bear question with 「大きな音や声を出してクマを誘引しないこと」
("do not make loud noises"). The official advice is the opposite: make noise
where you cannot see far. The cause is the OCR of the 環境省 PDF again: page
6 also has two columns, and its lines are interleaved
(「…注意しまし」「識して大きな音や声を出しましょう」「…クマを誘引する可能性」).
E2B had made the same inversion in spike 3 (「大きな音や声を出さないようにする」).

The source is now disabled in the manifest (`"disabled": "…reason…"`), and
the bear questions count as not covered. Result with E2B on the new package
(96 passages, vectors shipped): **22 / 22 covered, 12 / 13 uncovered**; both
bear questions now answer "no answer in the sources". The only remaining miss
is getting lost in the mountains.

Rule for packages, confirmed twice: no OCR text from multi-column layouts.
Bears need a checked text source.

## Next

- Desktop / shelter version with E4B, serving phones over local Wi-Fi.
- Checked bear and hiking sources.
