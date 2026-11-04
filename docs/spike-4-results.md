# Spike 4: near-topic answers

Date: 2026-11-04. Same setup as spike 3 (Gemma 4 E2B Q4_0, EmbeddingGemma 2,
cut-off 0.70, MacBook Pro M4 Max). 35 test questions: 23 the package covers,
12 it does not, 5 of them new "near-topic" ones (earthquake insurance, fridge
food in a power cut, pets at shelters, making river water safe, fire
extinguisher). Raw results: `spike-results/macos-spike4-*.json`.

Problem from spike 3: for questions next to a covered topic (bear encounter
vs bear prevention, getting lost vs snow-mountain advice) the app gave cited
but off-target answers instead of "no source".

## What we tried

1. **Close the gap with content:** added the 首相官邸 volcano page (PDL1.0).
   Volcano questions are now covered and answered with citations.
2. **Yes/no relevance check before answering** (`RELEVANCE_CHECK=true`): a
   short extra call asks the model whether the passages answer the question;
   if not, the app shows the related passages without a generated answer.
3. **Gap admission label:** if the answer itself says something is not in the
   sources (「…の記載はありません」, "the sources do not mention…"), the app
   labels it "only partly covered by the sources".

## Results

| Setup | Covered answered from the right source | Uncovered refused |
|---|---|---|
| No check (spike 3 setup + volcano page) | **23 / 23** | 10 / 12 |
| Strict yes/no check ("direct answer?") | 15 / 23 | **12 / 12** |
| Softer yes/no check ("different situation?") | 17 / 23 | 10 / 12 |

All five new near-topic questions were refused already without the check:
the 0.70 cut-off or the model's own "no answer in the sources" handled them.
The two misses without the check are the same as in spike 3: bear encounter
and lost while hiking.

The strict check refused good answers (water amount, avalanche rescue, "is a
tsunami only one wave", volcano alert level 3). The softer one still refused
several of those and let bear and hiking through again. Extra time per
answer: about 0.3 s.

The gap admission label fired on the bear answer (all runs), the hiking
answer (one of two runs), the "10 things for the shelter" answer (really
partial) and the volcano level 3 answer.

## What we learned

- **A 2B model is a poor judge of its own sources.** The yes/no check is not
  reliable in either direction, so it stays off. A larger model on desktop
  (Gemma 4 E4B) might judge better; not tested.
- **Content beats cleverness.** Adding one official page fixed the volcano
  case completely. The remaining misses are topics the package should cover
  (bear encounter, getting lost in the mountains).
- **Honest labels are cheap.** The model often says itself when the sources
  do not cover part of the question; surfacing that as a warning costs
  nothing and catches the near-topic cases at least some of the time.
- Current state for the 35 questions: 23 / 23 covered answered from the right
  source, 10 / 12 uncovered refused, the 2 others answered with citations and
  (usually) the "partly covered" warning.

## Next

- Cover bear encounter and getting lost with checked sources (prefectural
  police and 環境省 pages, with a licence check each).
- Try Gemma 4 E4B as the desktop model, including as a judge.
- Keep growing the test set with each new package.
