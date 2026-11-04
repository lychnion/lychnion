# Offline map: Nishinomiya area

Date: 2026-11-04. macOS (M4 Max), release build.

![Map tab: tsunami evacuation sites near 西宮市役所](images/map-nishinomiya-tsunami.png)

## What it does

- Base map from one local PMTiles file, no network: OpenStreetMap data via a
  Protomaps build, cut to eastern Kobe – Nishinomiya – western Osaka
  (bbox 135.20,34.66 to 135.48,34.88), zoom 0 to 15. **24 MB.**
- Evacuation sites from GSI (国土地理院): 1,613 指定緊急避難場所 (694 of them
  for tsunami) and 1,001 指定避難所 in the area. **392 KB** SQLite in the
  app's assets.
- Pick a hazard (tsunami, earthquake, flood, landslide, storm surge, large
  fire, inland flooding, volcano): the map shows the sites designated for it,
  and the list shows the five nearest with straight-line distance and compass
  direction. Shelters (指定避難所) are never offered as places to flee to.
- Location from the device GPS (works without network); `MOCK_LOCATION` for
  testing. Japanese or English labels follow the system language.
- The GSI usage notes are shown on the map screen, as the GSI terms require
  when the data is passed on.

## How to build the data

```bash
brew install pmtiles
python3 -I tool/build_map.py tool/maps/nishinomiya.json
```

Writes `assets/maps/jp.map.nishinomiya.sites.sqlite` and
`build/maps/jp.map.nishinomiya.pmtiles` (not in git). Another area is a new
manifest with its bbox and prefecture codes.

## Licences

| Data | Licence | What we do |
|---|---|---|
| GSI 指定緊急避難場所・指定避難所データ | 国土地理院コンテンツ利用規約 + usage notes (agreed on 2026-11-04 by Daniel) | Attribution and the notes in the app; marked as edited (area cut) |
| OpenStreetMap via Protomaps | ODbL 1.0 | Attribution on the map |

## Open points

- **No street or place names on the map yet.** The Protomaps theme needs
  label fonts; to check with vector_map_tiles (Japanese glyphs).
- **Old library versions.** The PMTiles plugin pins flutter_map 7 and
  vector_map_tiles 8; the newer betas conflict. Fine for the PoC, to revisit.
- **Distance is straight-line.** Routes would need a routing graph; a later
  step (Valhalla offline tiles or simpler).
- **Not yet linked with the assistant.** Next: when a question mentions
  evacuation (or the tsunami safety line fires), show the nearest site for
  that hazard under the answer.
- Data freshness: GSI updates often (Hyogo 2026-10-22, Osaka 2026-10-21 at
  download). The package should carry the date and the app should show it.
