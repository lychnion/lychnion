# Dev flags

Flags for testing, set at build time with `--dart-define`:

```bash
flutter run -d macos --dart-define=MIN_COS=0.75 --dart-define=START_TAB=2
```

All are optional. Normal users never need them. The source of truth is
the comment at the top of [lib/main.dart](../lib/main.dart).

## Models and answers

| Flag | Example | What it does |
|---|---|---|
| `GGUF_MODEL_PATH` | `/path/model.gguf` | Load this answer model on start. `docs:…` means a file in the app's Documents folder. |
| `GGUF_MODEL_URL` | `https://…/model.gguf` | Download this answer model on start. |
| `EMBED_MODEL_PATH` | `/path/embed.gguf` | Load this search model on start. |
| `LLM_BACKEND` | `cpu` or `gpu` | Which processor runs the answer model. Unset: the engine decides. |
| `BARE` | `true` | No knowledge packages: the model answers alone. For comparison only. |
| `MIN_COS` | `0.75` | Relevance cut-off for search. Default `0.70`. |
| `TOP_K` | `2` | Passages per answer. Default `4`. |
| `RELEVANCE_CHECK` | `true` | Ask the model a yes/no question before answering (spike 4; did not help). |

## Downloads

| Flag | Example | What it does |
|---|---|---|
| `CATALOG_URL` | `https://…/catalog.json` | Use this download catalog instead of the built-in one. |
| `DOWNLOAD_BASE_URL` | `http://127.0.0.1:8765/` | Base for relative file URLs in the catalog (see [development.md](development.md#downloads-from-a-local-server)). |
| `AUTO_DOWNLOAD` | `id1,id2` | Download (or check) these catalog items on start, in order. `!id` downloads again. |

## Map and position

| Flag | Example | What it does |
|---|---|---|
| `MAP_PMTILES_PATH` | `/path/area.pmtiles` | Use this offline base map. |
| `MOCK_LOCATION` | `34.7376,135.3417` | A fixed position instead of GPS. |
| `MAP_THEME_LOG` | `true` | Log map style problems to the console. |

## Base and current information

| Flag | Example | What it does |
|---|---|---|
| `SHELTER_SERVER` | `true` | Turn on the base at start, whatever the setting says (desktop). |
| `SHELTER_NAME` | `南小学校` | The base's name shown on phones, with `SHELTER_SERVER`. |
| `SHELTER_URL` | `http://192.168.1.20:8642` | Phone: ask this base first. |
| `FACTS_EDIT` | `true` | Allow entering current information on the map. On with `SHELTER_SERVER`. |
| `DEMO_FACTS` | `true` | Add made-up current information (test data). Needs a map area. |

## Scripted tests and screenshots

| Flag | Example | What it does |
|---|---|---|
| `AUTO_BENCH` | `true` | Run the eight test questions after the model loads. |
| `ASK` | `'q1\|q2'` | Ask these questions after loading, then save screenshots of the answers and the map. |
| `START_TAB` | `2` | Open on this tab (1: conversations, 2: map). |
| `SCREENSHOT_AFTER_S` | `20` | Save a PNG of the app to Documents after this many seconds. |
| `DEV_MENU` | `true` | Show the Developer menu in release builds (see [release-builds.md](release-builds.md)). |
