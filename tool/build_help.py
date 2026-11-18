#!/usr/bin/env python3
"""Builds the app's own help into a knowledge package (lychnion#9).

    python3 -I tool/build_help.py [help] [assets/help/app.help.sqlite]

Reads help/ja/*.md and help/en/*.md (see help/README.md): each file is a
topic, each "## " section one passage. Japanese is the package language,
English goes into passage_texts, so answers read the passage in the
question's language. The two languages must have the same files and the
same number of sections in the same order.

The package has the tables of the other knowledge packages
(lychnion-data/tool/build_package.py), so the app reads it the same way,
but it ships inside the app and is searched only for questions about the
app (lib/knowledge/app_help.dart).
"""
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_URL = "https://github.com/lychnion/lychnion/blob/main/help/{lang}/{name}"


def read_topic(path):
    """(title, [(heading, text)]) of one Markdown file."""
    title, sections, heading, lines = None, [], None, []

    def flush():
        if heading is not None:
            text = "\n".join(lines).strip()
            if not text:
                sys.exit(f"{path}: section '{heading}' is empty")
            sections.append((heading, text))

    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# ") and title is None:
            title = line[2:].strip()
        elif line.startswith("## "):
            flush()
            heading, lines = line[3:].strip(), []
        elif heading is not None:
            lines.append(line)
    flush()
    if not title or not sections:
        sys.exit(f"{path}: needs a '# ' title and '## ' sections")
    return title, sections


def version(files):
    """App version plus a hash of the texts: the app caches search vectors
    per package version, so changed texts must change the version."""
    m = re.search(r"^version:\s*([0-9.]+)", (ROOT / "pubspec.yaml").read_text(), re.M)
    h = hashlib.sha256()
    for f in files:
        h.update(f.name.encode() + b"\0" + f.read_bytes())
    return f"{m.group(1) if m else '0'}+{h.hexdigest()[:8]}"


def main(src, out):
    ja_files = sorted((src / "ja").glob("*.md"))
    en_names = sorted(p.name for p in (src / "en").glob("*.md"))
    if [p.name for p in ja_files] != en_names:
        sys.exit("help/ja and help/en must have the same files")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    db = sqlite3.connect(out)
    db.executescript("""
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE sources(id TEXT PRIMARY KEY, title TEXT, publisher TEXT, url TEXT,
                             licence TEXT, licence_url TEXT, attribution TEXT,
                             region TEXT NOT NULL DEFAULT 'JP');
        CREATE TABLE passages(id INTEGER PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id),
                              heading TEXT, text TEXT NOT NULL,
                              original_heading TEXT, original TEXT);
        CREATE TABLE passage_texts(passage_id INTEGER NOT NULL, lang TEXT NOT NULL,
                                   heading TEXT, text TEXT NOT NULL,
                                   reviewed INTEGER NOT NULL DEFAULT 0,
                                   PRIMARY KEY(passage_id, lang));
        CREATE TABLE alerts(id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id),
                            text TEXT NOT NULL, match_all TEXT NOT NULL,
                            text_en TEXT, match_all_en TEXT);
    """)
    meta = {
        "id": "app.help", "title": "リクニオンのヘルプ", "language": "ja",
        "version": version(ja_files + sorted((src / "en").glob("*.md"))), "note": "", "translation": "",
        "name": json.dumps({"ja": "ヘルプ", "en": "Help"}, ensure_ascii=False),
        "notice": "{}", "suggestions": "{}", "synonyms": "{}", "area": "",
    }
    db.executemany("INSERT INTO meta VALUES(?,?)", meta.items())
    pid = 0
    topics = []
    for ja_path in ja_files:
        ja_title, ja = read_topic(ja_path)
        en_title, en = read_topic(src / "en" / ja_path.name)
        if len(ja) != len(en):
            sys.exit(f"{ja_path.name}: {len(ja)} sections in ja, {len(en)} in en")
        sid = "help-" + ja_path.stem
        topics.append({"id": sid, "ja": ja_title, "en": en_title})
        db.execute(
            "INSERT INTO sources VALUES(?,?,?,?,?,?,?,?)",
            (sid, f"ヘルプ：{ja_title} / Help: {en_title}", "Lychnion",
             SOURCE_URL.format(lang="ja", name=ja_path.name),
             "AGPL-3.0", "https://github.com/lychnion/lychnion/blob/main/LICENSE",
             "Lychnion", "JP"))
        for (jh, jt), (eh, et) in zip(ja, en):
            pid += 1
            db.execute("INSERT INTO passages VALUES(?,?,?,?,NULL,NULL)", (pid, sid, jh, jt))
            db.execute("INSERT INTO passage_texts VALUES(?,?,?,?,1)", (pid, "en", eh, et))
    # The help screen lists topics in this order, with these titles.
    db.execute("INSERT INTO meta VALUES('topics',?)", (json.dumps(topics, ensure_ascii=False),))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}: "
          f"{len(ja_files)} topics, {pid} passages")


if __name__ == "__main__":
    a = sys.argv[1:]
    main(Path(a[0]) if a else ROOT / "help",
         Path(a[1]) if len(a) > 1 else ROOT / "assets" / "help" / "app.help.sqlite")
