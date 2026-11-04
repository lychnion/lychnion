# Spike 6: checked sources for bears and getting lost

Date: 2026-11-05. Gemma 4 E2B, same app; 37 test questions (2 new English
ones). Raw results: `spike-results/macos-e2b-spike6.json`.

## Sources added

Both from 政府広報オンライン, PDL1.0 (`https://www.gov-online.go.jp/tos/`),
plain web text, no OCR:

| Source | Written with | Covers |
|---|---|---|
| 「クマに出会わないために。知っておきたい対策」 (2026-09-10) | 環境省 | Avoiding bears; what to do when you meet one (do / never do), bear spray, defensive position |
| 「山の事故を防ごう！登山を楽しむために知っておきたい安全対策」 (updated 2025-10-28) | 警察庁 | Planning, equipment, getting lost (go back, wait at an open place or ridge), calling for help |

The site refuses scripted downloads, so the article text was read in a
browser and saved as a snapshot in `tool/packages/snapshots/` (article text
only, no graphs, photos or link lists). The builder reads snapshots for
sources that set `"snapshot"`. Attribution follows the site's rule:
「出典：政府広報オンライン「…」（URL）を加工して作成」.

Two new fixed safety lines, quoted word for word (the build checks this):

- Bear: 「クマに出会ってしまったら、クマを見ながら静かにゆっくり移動することが基本です。」
- Lost: 「もし、道に迷ってしまったら、そのまま下山をするのではなく、元の道に引き返すようにしましょう。」

Each has Japanese and English trigger words and a marked English translation.

## Results

| | Spike 5 (bear source off) | Spike 6 |
|---|---|---|
| Covered, answered from the right source | 22 / 22 | **28 / 28** |
| Not covered, refused | 12 / 13 | **9 / 9** |

(The day-hike packing question moved to "covered": the mountain article
lists clothing and equipment. Run before relabelling: 27 / 27 and 9 / 10.)

- Bear encounter, Japanese and English: safety line on top, then "move
  slowly while watching the bear; never shout, throw things, run or drop
  your bag", cited.
- Lost while hiking, English: "do not keep going down, go back; if you
  cannot reach the trail, wait at an open place or ridge", cited. The
  Japanese answer itself drifts to maps and GPS, but the safety line above
  it gives the key action.
- No more near-topic misses in this test set.

## Lessons

- Look for the plain-text version first. 政府広報オンライン often has the
  same official guidance as a PDF, written as a web page with clear lists.
- Safety lines carry the critical action even when the small model's own
  answer is weak.
