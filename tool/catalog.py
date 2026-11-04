#!/usr/bin/env python3
"""Updates size and sha256 of catalog entries from local files.

Usage:
  python3 -I tool/catalog.py assets/downloads/catalog.json FILE...

For each FILE, the catalog file entry with the same name gets its size and
SHA-256. Run it after tool/build_package.py, tool/add_vectors.py or
tool/build_map.py, bump the item's "version", then upload the files next
to the catalog. Models are not touched (their checksums come from the
Hugging Face LFS oid, see docs/download-results.md).
"""
import hashlib
import json
import os
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    catalog_path, files = sys.argv[1], sys.argv[2:]
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)
    by_name = {
        fe["name"]: fe for item in catalog["items"] for fe in item["files"]
    }
    for path in files:
        name = os.path.basename(path)
        entry = by_name.get(name)
        if entry is None:
            sys.exit(f"{name}: not in the catalog")
        entry["size"] = os.path.getsize(path)
        entry["sha256"] = sha256(path)
        print(f"{name}: {entry['size']} bytes, {entry['sha256']}")
    with open(catalog_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
