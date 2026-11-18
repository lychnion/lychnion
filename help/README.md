# Help texts

The app's own help, in Japanese and English (lychnion#9). Drafts.

`tool/build_help.py` turns these files into a small knowledge package
(`assets/help/app.help.sqlite`) that ships with the app. People can read
it on the Help screen, or ask "How do I share with other phones?"
without internet and get an answer with "Lychnion help" as the source.
The same texts can later become the online docs.

## Layout

```text
help/ja/<nn>-<topic>.md    Japanese (the app's main language)
help/en/<nn>-<topic>.md    English, same topics and order
```

- One file per topic, the same file names in both languages.
- `# Title` is the topic; each `## Heading` is one short passage that
  answers one question. Keep passages short (2 to 5 sentences): they
  are what search finds and what an answer quotes.
- Name buttons and screens exactly as the app does (`lib/l10n/*.arb`),
  in 「」 in Japanese and in quotes in English.
- Say what to do, in order. No marketing, no promises the app can't keep.
- When a screen changes, change its help in the same commit.

## Topics

| # | Topic |
|---|---|
| 01 | First steps: what to download, and why |
| 02 | Asking questions: sources, safety lines, limits |
| 03 | The map: nearest site, hazards, walking routes |
| 04 | Downloads: models, guides, maps, updates, mobile data |
| 05 | Base: answers and data from a computer on the same Wi-Fi |
| 06 | Sharing with phones nearby |
| 07 | Publishers and catalogs |
| 08 | Privacy: what stays on this device |
| 09 | When something does not work |
