#!/usr/bin/env python3
"""Ask the eval questions through the real Lychnion app on this Mac.

Usage:
  python3 tool/eval/run_mac.py --model ~/Work/Geonic/lychnion-models/gemma-4-E2B-it-Q4_0.gguf \
      --label mac-e2b [--out tool/eval/results/2026-11-19/mac-e2b.jsonl] [--define LLM_BACKEND=cpu]

Builds a release app under its own test app id (default com.lychnion.app.eval, set with
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER, no file is changed), so the live app's data is never
touched. The answer model and the search model are cloned (APFS, no extra space) into that test
app's Documents folder. The app asks all questions with the ASK flag and logs one
`LYCHNION {"event":"answer",...}` line per answer; this script only reads those lines, so it works
the same for any answer engine.

Writes one JSON line per answer (the app's own fields plus "qid"), after a first "meta" line.
"""
import argparse
import datetime
import json
import os
import platform
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.expanduser("~/Work/Geonic/lychnion-models")


def questions():
    """[(qid, lang, text)] in asking order: each topic in Japanese, then in English."""
    data = json.load(open(os.path.join(HERE, "questions.json"), encoding="utf-8"))
    out = []
    for t in data["topics"]:
        for lang in ("ja", "en"):
            q = t[lang]
            if "|" in q:
                sys.exit(f"question {t['topic']}-{lang} contains '|', which ASK uses to split")
            out.append((f"{t['topic']}-{lang}", lang, q))
    return out


def container_docs(app_id):
    return os.path.expanduser(f"~/Library/Containers/{app_id}/Data/Documents")


def build(app_id, defines):
    env = dict(os.environ, FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app_id)
    cmd = ["flutter", "build", "macos", "--release"] + [f"--dart-define={d}" for d in defines]
    print("building:", " ".join(c if len(c) < 80 else c[:77] + "..." for c in cmd), flush=True)
    subprocess.run(cmd, cwd=REPO, env=env, check=True, stdout=subprocess.DEVNULL)
    app = os.path.join(REPO, "build/macos/Build/Products/Release/Lychnion.app")
    exe = os.path.join(app, "Contents/MacOS/Lychnion")
    out = subprocess.run(["defaults", "read", os.path.join(app, "Contents/Info"),
                          "CFBundleIdentifier"], capture_output=True, text=True).stdout.strip()
    if out != app_id:
        sys.exit(f"built app has id {out!r}, not {app_id!r}: refusing to run on the live app data")
    return exe


def ensure_container(exe, app_id):
    """macOS makes the sandbox container on the first launch: start the app once if needed."""
    docs = container_docs(app_id)
    if os.path.isdir(docs):
        return docs
    print("first launch, to create the test app's container", flush=True)
    p = subprocess.Popen([exe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(120):
        if os.path.isdir(docs):
            break
        time.sleep(0.5)
    p.terminate()
    p.wait(timeout=20)
    if not os.path.isdir(docs):
        sys.exit(f"no container at {docs}")
    return docs


def clone_model(src, docs):
    """APFS clone (cp -c) into Documents/eval-models; returns the docs: path for the app."""
    dest_dir = os.path.join(docs, "eval-models")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(src))
    if not (os.path.exists(dest) and os.path.getsize(dest) == os.path.getsize(src)):
        subprocess.run(["cp", "-c", src, dest], check=True)
    return f"docs:eval-models/{os.path.basename(src)}"


def git(*args):
    return subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True).stdout.strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, help="answer model (.gguf)")
    ap.add_argument("--label", required=True, help="name in the results, e.g. mac-e2b")
    ap.add_argument("--embed", default=os.path.join(MODELS, "embeddinggemma-2-Q8_0.gguf"),
                    help="search model (.gguf); 'none' for keyword search only")
    ap.add_argument("--define", action="append", default=[], help="extra --dart-define, e.g. LLM_BACKEND=cpu")
    ap.add_argument("--app-id", default="com.lychnion.app.eval")
    ap.add_argument("--out", help="default: tool/eval/results/<date>/<label>.jsonl")
    ap.add_argument("--only", help="comma-separated topic names (for a quick check)")
    ap.add_argument("--timeout", type=int, default=3600, help="seconds for all answers")
    a = ap.parse_args()
    if a.app_id == "com.lychnion.app":
        sys.exit("use a test app id, never the live app's")
    model = os.path.expanduser(a.model)
    qs = questions()
    if a.only:
        keep = set(a.only.split(","))
        qs = [q for q in qs if q[0].rsplit("-", 1)[0] in keep]
    by_text = {text.strip(): (qid, lang) for qid, lang, text in qs}  # the app trims each question
    out = a.out or os.path.join(HERE, "results", datetime.date.today().isoformat(), f"{a.label}.jsonl")

    # The container must exist before the models can go in; the docs: paths are fixed, so build
    # with them first.
    docs = container_docs(a.app_id)
    model_path = f"docs:eval-models/{os.path.basename(model)}"
    defines = [f"GGUF_MODEL_PATH={model_path}", "ASK=" + "|".join(t for _, _, t in qs)]
    if a.embed != "none":
        defines.append(f"EMBED_MODEL_PATH=docs:eval-models/{os.path.basename(os.path.expanduser(a.embed))}")
    defines += a.define
    exe = build(a.app_id, defines)
    docs = ensure_container(exe, a.app_id)
    clone_model(model, docs)
    if a.embed != "none":
        clone_model(os.path.expanduser(a.embed), docs)

    meta = {
        "event": "meta", "label": a.label, "model": os.path.basename(model),
        "model_bytes": os.path.getsize(model),
        "embed": None if a.embed == "none" else os.path.basename(a.embed),
        "defines": a.define, "app_id": a.app_id, "commit": git("rev-parse", "HEAD"),
        "dirty": bool(git("status", "--porcelain", "--", "lib", "assets", "pubspec.lock")),
        "host": platform.platform(), "chip": subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip(),
        "started": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "questions": len(qs),
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    print(f"asking {len(qs)} questions with {meta['model']} -> {os.path.relpath(out, REPO)}", flush=True)
    answers, seen = [], set()
    p = subprocess.Popen([exe], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    watchdog = threading.Timer(a.timeout, p.kill)  # also ends a run that hangs without output
    watchdog.start()
    try:
        for line in p.stdout:
            i = line.find("LYCHNION {")
            if i < 0:
                continue
            try:
                ev = json.loads(line[i + len("LYCHNION "):])
            except json.JSONDecodeError:
                print(f"  skipped a broken log line: {line[:120]!r}", flush=True)
                continue
            if ev.get("event") == "load_failed":
                sys.exit(f"model did not load: {ev.get('error')}")
            if ev.get("event") != "answer":
                continue
            if ev.get("answered_by"):
                sys.exit(f"answered by the base {ev['answered_by']!r}, not this Mac: remove the base "
                         "from the test app's settings")
            qid, lang = by_text.get((ev.get("q") or "").strip(), (None, None))
            if qid is None or qid in seen:
                print(f"  ignored an answer to an unexpected or repeated question: {ev.get('q')!r}", flush=True)
                continue
            seen.add(qid)
            answers.append({"qid": qid, **ev})
            print(f"  {len(answers):2}/{len(qs)} {qid}: {ev.get('total_ms', 0) / 1000:.1f} s", flush=True)
            if len(seen) == len(qs):
                break
    finally:
        watchdog.cancel()
        p.terminate()
        try:
            p.wait(timeout=20)
        except subprocess.TimeoutExpired:
            p.kill()
    meta["finished"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(out, "w", encoding="utf-8") as f:
        for row in [meta] + answers:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    missing = len(qs) - len(answers)
    print(f"wrote {len(answers)} answers" + (f", {missing} MISSING" if missing else ""))
    if missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
