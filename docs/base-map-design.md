# Base map and map data: design

Design note, 2026-11-23. Status: proposal, nothing built yet.

Lychnion provides one base map for all of Japan, online by default.
Users make any area available offline by drawing a box on the map.
Other map layers stay data packages, published by whoever owns the data.

## Summary

- **The base map is ours:** one vector tile set covering Japan first,
  maybe the world later, with several styles drawn from it.
- **Offline areas snap to a fixed grid of cells** (z10, about 32 km
  across). Overlapping areas share cells, so nothing downloads twice,
  and an update fetches only the cells that changed.
- **Tile schema: OpenMapTiles.** Geolonia Maps and OSM Japan both use
  it, so their tiles can serve as alternative base maps.
- **Terrain follows Mapterhorn:** Terrarium encoding, lossless WebP,
  512 px tiles, in PMTiles.
- **Map data packages** declare one of four content types, each with an
  existing encoding. No new Lychnion file format.
- **Cells are signed like everything else:** a signed manifest lists
  every cell's SHA-256, so cells may come from any server, a base or a
  USB stick ([distribution.md](distribution.md)).

## Today

The prototype ([map-results.md](map-results.md)) ships each map area as
one signed item, for example `jp.map.nishinomiya`:

- a PMTiles base map cut to the area (OpenStreetMap through a Protomaps
  v4 build, zoom 0–15, 24 MB),
- evacuation sites, a walking graph with heights from GSI elevation
  tiles, and tsunami inundation drawn as coloured raster tiles
  (`inundation.mbtiles`).

The app draws it with flutter_map 7, vector_map_tiles 8 and
vector_tile_renderer 5 (`lib/map/offline_theme.dart`).

This works for one area, but people do not think in administrative
areas:

- Someone near a city border needs two areas and downloads the shared
  edge twice.
- A hike or a trip rarely matches a municipality.
- Each area has its own update cycle, so neighbouring areas drift apart.

## Base map model

The map is a stack of tile sets, each downloaded and updated on its own.

| Layer | Provided by | Online | Offline |
| --- | --- | --- | --- |
| Overview, Japan z0–9 | Lychnion | Bundled | Always on the device |
| Base map, z10–14 (overzoomed beyond) | Lychnion, or an alternative provider | Yes | Lychnion tiles only, by cell |
| Terrain (DEM) | Lychnion, Mapterhorn-compatible | Yes | By cell |
| Outdoor overlay (trails, huts, springs) | Lychnion | Yes | By cell |
| Map data packages | Their publishers | If the publisher hosts it | By package, or by cell for large ones |

For the user:

1. The app opens with the bundled overview, so there is a map with no
   network.
2. Online, base map, terrain and overlays stream in like any web map.
3. To go offline, the user draws a box (or picks "this view"). The app
   shows the download size, then fetches the cells the box touches.
4. Offline areas appear as a list with their size and data date.
   Deleting one frees only cells no other area uses.

Evacuation sites and walking graphs stay per-area items as today. They
are small, and the routing needs the whole graph of an area.

## Offline download cells

The user draws any box, but downloads happen in fixed cells. Fixed cells
make deduplication, caching, signing and updates simple.

**Cell grid**

- A cell is one web-mercator tile at zoom 10 with all its child tiles
  down to zoom 14: 1 + 4 + 16 + 64 + 256 = 341 tiles. At Tokyo's
  latitude a cell is about 32 km × 32 km.
- Vector tiles stop at zoom 14, because a z14 tile already holds the
  full detail (positions to about half a metre). The app draws z14 data
  sharply at zoom 18 and beyond (overzoom). So there is no growth to
  z18 as with raster tiles.
- z8 cells (about 128 km) were considered and rejected: every download
  and update would be 16 times larger.
- Cells are static PMTiles files on a CDN, built ahead of time. No
  extract per request.

**On the device**

- One tile store per tile set (base map, terrain, overlay), not one
  file per area.
- An offline area is a record: its box, its name, the cell ids it
  covers.
- Each cell has a reference count. Overlapping areas share cells;
  deleting an area removes only cells nobody else uses.

**Signing and updates**

- Each build publishes a manifest: build version, and per cell its id,
  SHA-256 and size. Lychnion signs the manifest like any other record.
- The app checks the signature and each cell's hash, so a base or a
  phone may pass cells on, as with every other file.
- An update compares hashes and downloads only the cells that changed,
  in the background, ideally on Wi-Fi. Versions only go up.
- Cells of different builds can meet at a border (a road ends at the
  edge). That is acceptable for most data; an area can also be updated
  in one go.
- The app shows each area's data date: in an emergency people need to
  know how old the map is.

## Tile schema

The base map uses the [OpenMapTiles](https://github.com/openmaptiles/openmaptiles)
schema. It is the one schema shared by the Japanese sources we could
swap in and by most commercial providers.

| Source | Schema | Notes |
| --- | --- | --- |
| Geolonia Maps | OpenMapTiles, plus Japan-specific layers | The public [`basic-v2` style](https://github.com/geolonia/cdn.geolonia.com) uses OpenMapTiles layers, plus a few extra ones (farmland plots, for example). |
| OSM Japan (`tile.openstreetmap.jp`) | OpenMapTiles | [osm-bright-ja and other styles](https://github.com/osmfj/tileserver-gl-site); also a `planet.pmtiles`. |
| GSI `experimental_bvmap`, `optimal_bvmap` | GSI's own (feature codes) | Both still trials. Not a base map schema for us. |
| PLATEAU | CityGML; 3D Tiles and MVT for some cities | No common building schema. Fits as map data packages. |
| MapTiler | Planet v4 (since November 2025) | Grew out of OpenMapTiles; v4 compatibility with OpenMapTiles 3.x styles not checked. |
| Stadia, OpenFreeMap | OpenMapTiles-compatible | |
| openstreetmap.org, VersaTiles | Shortbread | Growing worldwide; no Japanese provider uses it. |
| Protomaps | Own schema (v4) | What the prototype uses today. No paid providers. |

What OpenMapTiles commits us to:

- **Attribution:** the schema is licensed CC-BY 4.0, so the map shows
  "© OpenMapTiles" next to the OpenStreetMap credit.
- **A pinned version** (3.16 is the latest release), and styles that
  tolerate missing fields and different maximum zooms.
- **Outdoor detail goes in an overlay.** OpenMapTiles has peaks, paths
  and some trail attributes. Difficulty (`sac_scale`), huts, springs and
  similar go into a separate outdoor overlay, so the base map stays
  plain OpenMapTiles and can be swapped.
- **Labels** from `name:ja` and `name:latin`, as Geolonia and OSM Japan
  do.
- **Moving off Protomaps:** `lib/map/offline_theme.dart` has to be
  rewritten for OpenMapTiles layers, together with the renderer change
  below.

Shortbread is the alternative to watch. Choosing it now would rule out
Geolonia and OSM Japan tiles as alternatives.

## Terrain and 3D

Terrain uses the same format as [Mapterhorn](https://mapterhorn.com),
so we can take Japan from it, merge with it, or swap it in.

**Mapterhorn**

- Open global terrain tiles; code under BSD-3.
- Terrarium encoding, WebP, 512 px tiles, web mercator.
- `planet.pmtiles` holds z0–12; z13 and up comes as one PMTiles file per
  z6 tile, up to about z17.
- Japan uses GSI's DEM at 1 m, 5 m and 10 m. Attribution is per source
  ([attribution.json](https://download.mapterhorn.com/attribution.json)).
- `pmtiles extract` and `pmtiles merge` work on it.

**Rules**

- Terrain = Terrarium, lossless WebP, 512 px, PMTiles.
- First choice: take Japan from Mapterhorn instead of building our own.
- Do not ship GSI's PNG elevation tiles as they are. Their encoding
  wraps negative heights and has its own no-data value, which common
  renderers do not decode. Re-encode first. (Reading them at build time,
  as the walking graph does, is fine.)
- Terrain zoom sets terrain size, because terrain stays raster. A 512 px
  tile has about 16 m pixels at z12, 8 m at z13, 4 m at z14 near Tokyo.
  GSI's 5 m and 10 m data gains little beyond z13–14.

**Why elevation stays a regular grid**

Other forms exist, but a grid fits terrain best:

- A grid stores only heights; positions follow from the pixel. Point
  formats (LAS, Point Cloud PNG) store x, y and z for every point, about
  three times the data for the same surface.
- Triangle meshes (Cesium quantized-mesh) save space on flat ground, but
  need their own renderer and tooling.
- Contour lines are drawn from the grid and lose the values between
  lines, so they are an output, not a store.

**Renderer**

The prototype uses vector_map_tiles 8 with vector_map_tiles_pmtiles,
which pins flutter_map 7. Its author now calls vector_map_tiles
"minimally maintained" and works on mapigrade instead. So the renderer
has to change anyway. Candidates (from their docs, 2026-11-23, not yet
tested here):

| Plugin | How it draws | Platforms | Terrain | Notes |
| --- | --- | --- | --- | --- |
| [flutter_map_vector_tiles](https://pub.dev/packages/flutter_map_vector_tiles) 2.12 | Pure Dart, in flutter_map ≥ 8.2 | Android, iOS, macOS, Windows, Linux, web | Hillshade from Terrarium, Mapbox or custom DEM | PMTiles local and remote (gzip tiles only); MBTiles via a companion package; style glyphs, CJK from the system font; fill-extrusion buildings |
| [mapigrade](https://github.com/greensopinion/mapigrade) | MapLibre Native into a texture, flutter_map layers on top | Android (API 29+), iOS and macOS on arm64 | Not documented | Pre-1.0; no Windows or Linux |
| vector_map_tiles 10 beta | Flutter GPU | Needs Flutter's main channel | Hillshade, DEM contours (beta) | Not for production yet |
| MapLibre Native through a platform view | Native map | Android, iOS | Full, including 3D | Leaves flutter_map |

flutter_map_vector_tiles fits best: it keeps flutter_map, runs on the
Windows and Linux computers a base may run on, and draws hillshade from
the Terrarium tiles this note proposes. mapigrade is worth watching but
does not run on Windows or Linux yet.

**Point clouds**

[Point Cloud PNG](https://gbank.gsj.jp/seamless/pcpng/1.0.1/) (点群PNG),
by AIST's Geological Survey of Japan, stores point clouds as lossless PNG
or WebP tiles in `{z}/{x}/{y}` form, and so fits PMTiles. It suits raw
LiDAR (buildings, trees, point classes), not the terrain surface. It
fits as a map data package type once its tools have a public licence.

## Map data packages

A map data package declares one of four content types. Each uses an
existing encoding in PMTiles; the only Lychnion part is a small metadata
block.

| Content type | Encoding | Examples |
| --- | --- | --- |
| `vector` | MVT in PMTiles | Shelters, POIs, routes, boundaries, hazard zones as polygons |
| `elevation` | Terrarium, lossless WebP or PNG, in PMTiles | DEM, water surface height |
| `grid` | Lossless WebP or PNG with scale, offset and nodata, in PMTiles | Flood depth, tsunami inundation depth, landslide class, population per 250 m mesh, land cover class |
| `pointcloud` | Point Cloud PNG in PMTiles | LiDAR scans |

**Why `grid` matters**

Today the inundation tiles are coloured pictures
(`lychnion-data/tool/build_inundation_tiles.py`), and Japan's hazard map
portal serves its rasters the same way, so the values are lost. Storing
the value (flood depth in centimetres, for example) gives:

- **Restyling:** our own colour scales, readable in dark mode and for
  colour-blind users.
- **A cheap offline point query:** "how deep would the water be here?"
  is one pixel read, not a polygon test. A fast, reliable fact for the
  assistant, even on the Pixel 5a.

**Metadata block** (in the PMTiles metadata)

- `content_type`: one of the four above.
- `schema` (vector): layer names and fields, or a published schema.
- `encoding` (grid): channels used, `scale`, `offset`, `nodata`, unit.
- `classes` (grid with classes): value → label, Japanese and English.
- `base_map`: the OpenMapTiles version the package expects to draw on
  (a package may ship its own style layers), so a base map update
  cannot break it silently.
- `cells` (optional): the cell grid, when a large package allows partial
  downloads.
- Attribution, licence, source date, build date.

**Rules**

- Lossless only. Lossy WebP or JPEG corrupts the values.
- 8-bit channels limit precision; choose the scale per data set. Two
  channels at 1 cm steps cover 655 m, plenty for flood depth.
- Always define nodata.
- Publishers decide a package's extent, as today.
- If a common encoding appears for grids, packages adopt it without
  changing the app's model.

## Alternative base map providers

Because the styles target OpenMapTiles, an alternative provider is a
tile URL and a key, not a new style. A provider entry declares:

- tile URL or TileJSON, and how the key is passed,
- schema and version, maximum zoom, label languages,
- attribution,
- whether offline caching is allowed.

Limits:

- Most paid providers forbid bulk offline caching, so alternatives are
  online only. Offline cells always come from the Lychnion build.
- The outdoor overlay, terrain and map data packages stay on top,
  whatever the base map is.
- Extra layers of a provider show only in styles that know them.

Candidates: Geolonia Maps, OSM Japan, MapTiler, Stadia, OpenFreeMap.

## Build and hosting

```text
OpenStreetMap ──▶ Planetiler (OpenMapTiles profile) ──┐
OpenStreetMap ──▶ Planetiler (outdoor profile) ───────┤
Mapterhorn ─────▶ pmtiles extract ────────────────────┼──▶ cells + signed manifest ──▶ CDN ──▶ app
Publishers ─────▶ lychnion-data tools ────────────────┘        (static PMTiles)

PostGIS ────────▶ Martin (tiles on request) ──────────────────────────────────────────────▶ app (online only)
```

- **Planetiler** builds the base map with its default OpenMapTiles
  profile, and the outdoor overlay with a custom profile. All of Japan
  builds in minutes; a planet build needs a large machine.
- **Terrain** comes from Mapterhorn with `pmtiles extract`, cut to cells.
- **Cells and manifest** are static files behind a CDN (Cloudflare R2
  charges no egress). Nothing to scale.
- **Martin** (a tile server from the MapLibre project) serves tiles from
  PostGIS on request. Only for layers that change often or live in a
  database. Building OpenMapTiles through Martin would need the full
  PostGIS import toolchain, which Planetiler avoids.

## Phasing

Each phase works on its own.

1. **Japan online:** OpenMapTiles base map on a CDN, the bundled
   overview, one or two styles, the move to flutter_map 8 and
   flutter_map_vector_tiles.
2. **Offline areas:** box selection, cell download, shared cells with
   reference counts, signed manifest, area list with size and date.
3. **Updates:** background updates of changed cells.
4. **Outdoor:** outdoor overlay, outdoor style, terrain and contours
   (after the renderer test).
5. **Map data package types:** metadata block, `grid` reader with point
   query, inundation depth as the first `grid` package.
6. **Alternative providers:** Geolonia Maps and OSM Japan first.
7. **Global:** planet build, same cells and manifest.

## Risks and open questions

Risks:

- **We become a tile host.** Static files keep it simple, but people
  will rely on uptime in emergencies. The bundled overview and offline
  cells are the fallback.
- **Hotlinking.** Other apps may use our public tiles. Accept it, or add
  a light key.
- **Attribution and terms:** OpenStreetMap (ODbL), OpenMapTiles
  (CC-BY 4.0), GSI terms and Mapterhorn's per-source attribution must
  all show in the app.
- **Version seams** between cells of different builds.

Open questions:

- [ ] Renderer: test flutter_map_vector_tiles on the Pixel 5a with an
  OpenMapTiles style, Japanese labels and Terrarium hillshade.
- [ ] Contours: draw from the DEM on the device, or keep pre-built
  contour tiles?
- [ ] Are Geolonia's OpenStreetMap tiles updated on a schedule we can
  rely on as an alternative?
- [ ] Does MapTiler Planet v4 still work with OpenMapTiles 3.x styles?
- [ ] Which OpenMapTiles version do OSM Japan's tiles use?
- [ ] Mapterhorn's exact WebP settings (lossless assumed).
- [ ] Terrain cells: Mapterhorn's z6 files are large; re-cut to z10?
- [ ] Point Cloud PNG: public licence of the spec and tools.

## Sources

Checked 2026-11-23.

- [OSM Japan tile server](https://wiki.openstreetmap.org/wiki/Japan/OSMFJ_Tileserver),
  [osmfj/tileserver-gl-site](https://github.com/osmfj/tileserver-gl-site)
- [Geolonia `basic-v2` style](https://github.com/geolonia/cdn.geolonia.com),
  [Geolonia maps-core](https://github.com/geolonia/maps-core)
- [GSI experimental_bvmap](https://github.com/gsi-cyberjapan/gsimaps-vector-experiment),
  [GSI optimal_bvmap](https://github.com/gsi-cyberjapan/optimal_bvmap),
  [GSI elevation tile encoding](https://maps.gsi.go.jp/development/demtile.html)
- [PLATEAU data formats](https://www.mlit.go.jp/plateau/learning/tpc03-1/)
- [Mapterhorn data access](https://mapterhorn.com/data-access),
  [Mapterhorn code](https://github.com/mapterhorn/mapterhorn)
- [OpenMapTiles](https://github.com/openmaptiles/openmaptiles),
  [MapTiler Planet v4](https://docs.maptiler.com/schema/planet-v4/),
  [VersaTiles](https://docs.versatiles.org/basics/versatiles.html),
  [vector tiles on openstreetmap.org](https://community.openstreetmap.org/t/vector-tiles-are-deployed-on-openstreetmap-org/133008),
  [Protomaps basemaps](https://github.com/protomaps/basemaps)
- [Point Cloud PNG 1.0.1](https://gbank.gsj.jp/seamless/pcpng/1.0.1/)
