# Lychnion docs

Pages for people who build, test or run Lychnion. For how to use the
app, see the user help in [help/](../help/README.md).

## Developing

- [Development](development.md): requirements, run, test, repository
  layout, app assets.
- [Dev flags](dev-flags.md): every `--dart-define` flag.
- [Release builds](release-builds.md): Android builds and signing.
- [Releasing](releasing.md): checklist for an app release.
- [Versions](versioning.md): app, data and format numbers.

## Data and distribution

- [Data packages and trust](data-packages.md): what the app bundles, how
  signing works, publishers and catalogs.
- [Distribution design](distribution.md): the full design for publishers,
  catalogs, nodes and sync.
- [Base](base.md): a computer that serves phones on the same Wi-Fi.
- [Base map and map data](base-map-design.md): proposal for one base map,
  offline areas by cell, tile schema, terrain and map data types.

## Security

- [Threat model](../threat-model.md): the security contract, with
  `threat-model.yaml` and `threat-model.json` beside it.
- [Threat-model questions](threat-model-questions.md): the questions asked
  of the maintainers and their answers.
- [Threat-model notes](threat-model-notes.md): how the model was made, and
  candidate issues.

## Help texts

- [help/README.md](../help/README.md): how the help is written, in
  Japanese and English, and how it becomes the app's built-in help.

## Research notes

Results from the prototype, oldest first. They are dated records: they
describe the app as it was then and are not updated.

- [Plan](poc-plan.md): the original proof-of-concept plan.
- [Spike 1](spike-1-results.md): Gemma 4 E2B runs on the device through
  flutter_edge_ai and llama.cpp.
- [Spike 2](spike-2-results.md): answers only from official sources,
  with checked citations and fixed safety lines.
- [Spike 3](spike-3-results.md): vector search (EmbeddingGemma 2), a
  relevance cut-off, Japanese and English.
- [Spike 4](spike-4-results.md): near-topic questions; a yes/no
  self-check did not work with the 2B model.
- [Spike 5](spike-5-results.md): Gemma 4 E4B for desktop (better
  answers, half the speed).
- [Spike 6](spike-6-results.md): checked sources for bears and getting
  lost.
- [Base (shelter computer)](shelter-results.md): the desktop app answers
  phones on the local network.
- [Real devices](device-results.md): iPad Air 5, Pixel 5a and the iPhone
  simulator.
- [Offline map](map-results.md): evacuation sites, walking routes,
  tsunami areas.
- [Downloads](download-results.md): models, packages and maps downloaded
  in the app.
- [Current facts](facts-results.md): shelter status, closed roads and
  warnings, apart from the AI.

Raw results are in [spike-results/](spike-results/), screenshots in
[images/](images/).
