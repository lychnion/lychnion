#!/usr/bin/env python3
"""Builds a knowledge package (one SQLite file) from a JSON manifest.

    python3 -I tool/build_package.py tool/packages/jp.bousai.core.json [--max-chars N]

Downloads each source once into build/package-cache/ (or reads a saved text
snapshot, for sites that refuse scripted downloads), extracts the text
(HTML, Word .doc via macOS textutil, PDF via tool/pdf2txt.swift), splits it
into short passages and writes assets/packages/<id>.sqlite.

Every fixed safety line ("alert") must appear word for word in its source,
otherwise the build fails.
"""
import json
import re
import sqlite3
import subprocess
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "package-cache"
OUT = ROOT / "assets" / "packages"
MAX_CHARS = 420

# Page furniture on kantei.go.jp and similar sites, not content.
DROP_LINES = {"子項目を開閉", "この記事で伝えたいトピックス", "関連リンク", "ページの先頭へ", "印刷"}


class _Text(HTMLParser):
    BLOCK = {"p", "li", "div", "tr", "br", "td", "th", "dd", "dt"}
    HEAD = {"h1", "h2", "h3", "h4"}
    SKIP = {"script", "style", "nav", "header", "footer", "noscript"}

    def __init__(self):
        super().__init__()
        self.out, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag in self.HEAD:
            self.out.append("\n## ")
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in self.HEAD:
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)


def fetch(src, manifest_dir):
    if src.get("snapshot"):
        # Text saved from a browser for sites that refuse scripted downloads.
        return manifest_dir / src["snapshot"]
    ext = Path(src["url"].split("?")[0]).suffix or ".html"
    path = CACHE / f"{src['id']}{ext}"
    if not path.exists():
        req = urllib.request.Request(src["url"], headers={"User-Agent": "lychnion-package-builder"})
        with urllib.request.urlopen(req, timeout=60) as r:
            path.write_bytes(r.read())
    return path


def extract(path):
    if path.suffix in (".html", ".htm"):
        p = _Text()
        p.feed(path.read_bytes().decode("utf-8", "replace"))
        return "".join(p.out)
    if path.suffix == ".txt":
        return path.read_text(encoding="utf-8")
    if path.suffix == ".doc":
        return subprocess.run(["textutil", "-convert", "txt", "-stdout", str(path)],
                              check=True, capture_output=True, text=True).stdout
    if path.suffix == ".pdf":
        text = subprocess.run(["swift", str(ROOT / "tool" / "pdf2txt.swift"), str(path)],
                              check=True, capture_output=True, text=True).stdout
        if _japanese_ratio(text) < 0.3:
            # Broken font encoding: read the rendered pages instead.
            print(f"{path.name}: text layer unreadable, using OCR")
            text = subprocess.run(["swift", str(ROOT / "tool" / "pdf_ocr.swift"), str(path)],
                                  check=True, capture_output=True, text=True).stdout
        return text
    raise ValueError(f"unsupported file type: {path}")


def _japanese_ratio(text):
    chars = [c for c in text if not c.isspace()]
    if not chars:
        return 0.0
    jp = sum(1 for c in chars if "぀" <= c <= "ヿ" or "一" <= c <= "鿿")
    return jp / len(chars)


def clean_lines(text):
    lines = []
    for raw in text.splitlines():
        line = re.sub(r"[ \t　]+", " ", raw).strip()
        if not line or line in DROP_LINES or line == "##":
            continue
        lines.append(line)
    return lines


def passages(lines, max_chars=MAX_CHARS):
    """Groups lines into passages of up to MAX_CHARS, each with its heading."""
    heading, buf, out = "", [], []

    def flush():
        if buf:
            out.append((heading, "\n".join(buf)))
            buf.clear()

    for line in lines:
        if line.startswith("## "):
            flush()
            heading = line[3:].strip()
            continue
        if buf and sum(len(b) for b in buf) + len(line) > max_chars:
            flush()
        buf.append(line)
    flush()
    # Very short passages (menus, captions) carry no usable guidance.
    return [(h, t) for h, t in out if len(t) >= 25]


def squash(s):
    return re.sub(r"\s+", "", s)


def main(manifest_path, max_chars=MAX_CHARS):
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    if max_chars != MAX_CHARS:
        # A different cut is a different package: vectors cached per version.
        manifest["version"] += f"+c{max_chars}"
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    texts, rows = {}, []
    manifest["sources"] = [s for s in manifest["sources"] if not s.get("disabled")]
    for src in manifest["sources"]:
        text = extract(fetch(src, Path(manifest_path).parent))
        texts[src["id"]] = squash(text)
        # e.g. cover, contents and link-list sections, and video captions
        skip = set(src.get("skip_headings", [])) | set(manifest.get("skip_headings_all", []))
        drop = manifest.get("drop_lines_containing", [])
        lines = [l for l in clean_lines(text) if not any(d in l for d in drop)]
        ps = [(h, t) for h, t in passages(lines, max_chars) if h not in skip]
        if not ps:
            sys.exit(f"no text extracted from {src['id']}")
        rows += [(src["id"], h, t) for h, t in ps]
        print(f"{src['id']}: {len(ps)} passages")

    for alert in manifest.get("alerts", []):
        # Each sentence of a fixed safety line must be in the source as written.
        for sentence in filter(None, alert["text"].split("。")):
            if squash(sentence) not in texts[alert["source"]]:
                sys.exit(f"alert {alert['id']}: not found in {alert['source']}: {sentence}")

    out = OUT / f"{manifest['id']}.sqlite"
    out.unlink(missing_ok=True)
    db = sqlite3.connect(out)
    db.executescript("""
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE sources(id TEXT PRIMARY KEY, title TEXT, publisher TEXT, url TEXT,
                             licence TEXT, licence_url TEXT, attribution TEXT);
        CREATE TABLE passages(id INTEGER PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id),
                              heading TEXT, text TEXT NOT NULL);
        CREATE VIRTUAL TABLE passages_fts USING fts5(heading, text, content='passages',
                              content_rowid='id', tokenize='trigram');
        CREATE TABLE alerts(id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id),
                            text TEXT NOT NULL, match_all TEXT NOT NULL,
                            text_en TEXT, match_all_en TEXT);
    """)
    for k in ("id", "title", "language", "version", "note"):
        db.execute("INSERT INTO meta VALUES(?,?)", (k, manifest.get(k, "")))
    db.execute("INSERT INTO meta VALUES('gaps',?)", (json.dumps(manifest.get("gaps", []), ensure_ascii=False),))
    # Query expansion for keyword search, until vector search is added.
    db.execute("INSERT INTO meta VALUES('synonyms',?)", (json.dumps(manifest.get("synonyms", {}), ensure_ascii=False),))
    db.executemany("INSERT INTO sources VALUES(:id,:title,:publisher,:url,:licence,:licence_url,:attribution)",
                   [{k: s.get(k) for k in ("id", "title", "publisher", "url", "licence", "licence_url", "attribution")}
                    for s in manifest["sources"]])
    db.executemany("INSERT INTO passages(source_id,heading,text) VALUES(?,?,?)", rows)
    db.execute("INSERT INTO passages_fts(passages_fts) VALUES('rebuild')")
    # text_en is our translation, shown next to the official Japanese text.
    db.executemany("INSERT INTO alerts VALUES(?,?,?,?,?,?)",
                   [(a["id"], a["source"], a["text"], json.dumps(a["all"], ensure_ascii=False),
                     a.get("text_en"), json.dumps(a.get("all_en", []), ensure_ascii=False))
                    for a in manifest.get("alerts", [])])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {out.relative_to(ROOT)}: {len(rows)} passages, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    args = sys.argv[1:]
    chars = MAX_CHARS
    if "--max-chars" in args:
        i = args.index("--max-chars")
        chars = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    main(args[0], chars)
