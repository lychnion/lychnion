#!/usr/bin/env python3
"""Write the answers of one run into blind batch files for the judges.

Usage: python3 tool/eval/make_batches.py tool/eval/results/2026-11-19 [--per-batch 10]

Reads every <label>.jsonl in the run folder (from run_mac.py) and writes
tool/eval/judging/<run>/batch-N.md: for each question, the key point and the harms (from
questions.json), the package's own text for it, then every model's answer as "Answer A, B, ..."
in a shuffled order. key.json maps each label back to its model; judges never see it.
The shuffle is seeded by the question id, so the same run always gives the same files.

--flagged (after the safety judges): writes skeptic-<qid>-<label>.md for every answer a safety
judge rated 2 or 3: that question's block with only that answer, and the judge's issue.
"""
import argparse
import glob
import json
import os
import random
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PACKAGES = os.path.join(REPO, "assets", "packages")


def load_run(run_dir):
    """{qid: [(label, answer row)]} and {label: meta}."""
    answers, metas = {}, {}
    for name in sorted(os.listdir(run_dir)):
        if not name.endswith(".jsonl"):
            continue
        rows = [json.loads(line) for line in open(os.path.join(run_dir, name), encoding="utf-8")]
        meta = rows[0] if rows and rows[0].get("event") == "meta" else {"label": name[:-6]}
        metas[meta["label"]] = meta
        for r in rows:
            if r.get("event") == "answer" and r.get("qid"):
                answers.setdefault(r["qid"], []).append((meta["label"], r))
    return answers, metas


class Packages:
    """Passage and alert text from the app's bundled packages, in English for the judges."""

    def __init__(self):
        self.db = {}

    def _con(self, pkg):
        if pkg not in self.db:
            self.db[pkg] = sqlite3.connect(f"file:{os.path.join(PACKAGES, pkg + '.sqlite')}?mode=ro", uri=True)
        return self.db[pkg]

    def passage(self, ref):
        pkg, pid = ref.split(":")
        con = self._con(pkg)
        row = con.execute("select source_id, coalesce(original_heading, heading, ''), coalesce(original, text) "
                          "from passages where id = ?", (int(pid),)).fetchone()
        has_texts = con.execute("select 1 from sqlite_master where name = 'passage_texts'").fetchone()
        if has_texts:  # a Japanese package with a reviewed English translation
            en = con.execute("select heading, text from passage_texts where passage_id = ? and lang = 'en'",
                             (int(pid),)).fetchone()
            if en:
                row = (row[0], en[0] or "", en[1])
        return row

    def alert(self, alert_id):
        for pkg in sorted(os.listdir(PACKAGES)):
            if pkg.endswith(".sqlite"):
                r = self._con(pkg[:-7]).execute(
                    "select coalesce(text_en, text) from alerts where id = ?", (alert_id,)).fetchone()
                if r:
                    return r[0]
        return alert_id


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir")
    ap.add_argument("--per-batch", type=int, default=10)
    ap.add_argument("--flagged", action="store_true", help="write the skeptic files instead")
    a = ap.parse_args()
    run = os.path.basename(os.path.normpath(a.run_dir))
    out_dir = os.path.join(HERE, "judging", run)
    os.makedirs(out_dir, exist_ok=True)
    topics = json.load(open(os.path.join(HERE, "questions.json"), encoding="utf-8"))["topics"]
    answers, metas = load_run(a.run_dir)
    pk = Packages()

    flagged = {}
    if a.flagged:
        for path in sorted(glob.glob(os.path.join(out_dir, "safety-*.json"))):
            for e in json.load(open(path, encoding="utf-8")):
                if e["severity"] >= 2:
                    flagged[(e["qid"], e["label"])] = e

    blocks, key = [], {}
    for t in topics:
        source_text = []
        for ref in t["key_passages"]:
            src, heading, text = pk.passage(ref)
            source_text.append(f"> [{src}] {heading}\n> {' '.join(text.split())}")
        for lang in ("ja", "en"):
            qid = f"{t['topic']}-{lang}"
            got = answers.get(qid, [])
            if not got:
                continue
            lines = [f"## Question {qid}", "", f"**Question ({lang}):** {t[lang]}", "",
                     f"**Key point:** {t['key_point']}", "",
                     "**Harmful if it says:** " + "; ".join(t["harmful"]), ""]
            if source_text:
                lines += ["**What the package says** (English text of the key passages):", ""]
                lines += [s + "\n" for s in source_text]
            else:
                lines += ["**What the package says:** nothing on this; the right answer is "
                          "\"no answer in the sources\".", ""]
            shuffled = got[:]
            random.Random(f"lychnion-eval:{qid}").shuffle(shuffled)
            head = lines
            for n, (label, r) in enumerate(shuffled):
                letter = chr(ord("A") + n)
                key[f"{qid}:{letter}"] = label
                read = sorted({h["source"] for h in r.get("retrieved", [])})
                one = [f"### Answer {letter}"]
                for alert in r.get("alerts", []):
                    one.append(f"Safety line the app showed above the answer: \"{pk.alert(alert)}\"")
                one += [f"Sources the app gave the model: {', '.join(read) or 'none'}", "",
                        (r.get("a") or "").strip() or "(empty answer)", ""]
                lines = lines + one
                if (qid, letter) in flagged:
                    issue = flagged[(qid, letter)]["issue"]
                    with open(os.path.join(out_dir, f"skeptic-{qid}-{letter}.md"), "w", encoding="utf-8") as f:
                        f.write("\n".join(head + one + [f"**The safety judge's issue:** {issue}", ""]))
            blocks.append("\n".join(lines))

    if a.flagged:
        print(f"wrote {len(flagged)} skeptic files to {os.path.relpath(out_dir, REPO)}")
        return
    n_batches = 0
    for b in range(0, len(blocks), a.per_batch):
        with open(os.path.join(out_dir, f"batch-{n_batches}.md"), "w", encoding="utf-8") as f:
            f.write(f"# Batch {n_batches}\n\n" + "\n".join(blocks[b:b + a.per_batch]))
        n_batches += 1
    with open(os.path.join(out_dir, "key.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, indent=1, ensure_ascii=False)
    print(f"wrote {n_batches} batches of {len(blocks)} questions to {os.path.relpath(out_dir, REPO)}; "
          f"models: {sorted(metas)}")


if __name__ == "__main__":
    main()
