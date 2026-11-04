# Current facts (2026-11-05)

Facts that change during a disaster: a shelter is full, a road is blocked,
a warning is in force, water is handed out. They are kept apart from the
model and the knowledge packages, and the app never lets the model write
them. The app shows them as they are, with their age and source.

## What a fact is

| Field | Example |
|---|---|
| kind | S shelter status, R road blocked, W water point, A warning |
| subject | GSI site ID (共通ID), a point `lat,lon`, or a city name |
| value | `open` / `crowded` / `full` / `closed`, `blocked`, 「津波警報」 |
| observed / expires | every fact expires; expired facts are never shown |
| source | official (3), sensor (2), citizen (1), plus a name |

When two facts about the same thing disagree, the most trusted source
wins, then the newest. A citizen report is shown as 「住民の報告・未確認」 /
"resident report, unconfirmed".

Code: `lib/facts/`. Facts are stored in `facts.jsonl` in app support,
append only.

## Where they show

- **Answer:** the nearest site skips a shelter that is full or closed, and
  says why: 「市役所（11 m）は除外：満員（受け入れ停止）· 20分前 · 西宮市（テスト）· 公式」.
  Below it, a box 「最新の情報（AIの回答ではありません）」 lists warnings and
  blocked roads.
- **Map:** full or closed sites are grey; blocked roads have an orange
  marker; the same box sits above the site list; each site shows its status.

![Answer with a full shelter skipped](images/facts-answer.png)
![Map with current information](images/facts-map.png)

Demo run (made-up facts, marked 「テスト」 in their source):

```bash
flutter run -d macos --release ... --dart-define=DEMO_FACTS=true \
  --dart-define=MOCK_LOCATION=34.7376,135.3417 \
  "--dart-define=ASK=海の近くで強い揺れを感じました。どうすればいいですか？"
```

## Sharing

- **Shelter computer:** `GET /facts` returns all unexpired facts, so phones
  apply the same rules. A connected phone pulls them at once and then every
  minute.
- **Radio-sized format:** `GET /facts?compact=1` packs facts for slow links
  (LoRa, SMS). One shelter update is 16 bytes (`So|1b7|f|9ivw|3c`: kind+source,
  site number, status, minute, lifetime). 12 updates fit in one 190-byte
  message. Sites are numbered by their position in the map area's site list,
  so both sides need the same map version.

## Open

- No way to enter facts in the app yet; they come from the demo flag or a
  shelter computer. A shelter-side form and an official feed (e.g. city
  open data) are next.
- Facts are not signed. Anyone on the shelter Wi-Fi network could only read
  them, not write, but a future write path needs signatures.
- The answer shows the status of a skipped site, not yet the status of the
  suggested one (in the demo 市民会館 is 「混雑」, shown only on the map).
- The compact format is not yet sent over any radio.
