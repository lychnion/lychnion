#!/usr/bin/env python3
"""Builds the offline walking graph for one map area.

    python3 -m venv build/route-venv && build/route-venv/bin/pip install osmium
    build/route-venv/bin/python -I tool/build_routes.py tool/maps/nishinomiya.json

Reads the OpenStreetMap extract named in the manifest ("routes.source",
downloaded once to build/map-cache/), keeps the ways people can walk on
inside the area's bbox, and writes build/maps/<id>.routes.bin (not in git).

File format (little endian, read by lib/map/route_graph.dart):

    header   'FKRG', u32 version=1, u32 nodes, u32 edges
    lat      i32[nodes]   degrees * 1e6
    lon      i32[nodes]
    offsets  u32[nodes+1] edges of node i are offsets[i] .. offsets[i+1]-1
    targets  u32[edges]
    lengths  u16[edges]   decimetres
    (padding to 4 bytes)

Every edge is stored in both directions (one-way streets do not apply to
people on foot). Nodes are sorted by a 0.001° grid, so each grid cell is
one run of nodes. Small pieces of road not connected to the rest (under
MIN_PART nodes) are dropped, so a position never snaps onto them.
"""
import json
import math
import struct
import sys
import urllib.request
from array import array
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "map-cache"
OUT = ROOT / "build" / "maps"

# Ways people can walk on. Motorways and their ramps are left out.
WALK = {
    "trunk", "trunk_link", "primary", "primary_link", "secondary",
    "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "living_street", "service", "pedestrian", "footway",
    "path", "steps", "track", "cycleway", "road", "bridleway",
}
NO = {"no", "private"}
MIN_PART = 200


def fetch(url, name):
    path = CACHE / name
    if not path.exists():
        print(f"downloading {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "fieldkit-route-builder"})
        with urllib.request.urlopen(req, timeout=600) as r, open(path, "wb") as f:
            while chunk := r.read(1 << 20):
                f.write(chunk)
    return path


def walkable(tags):
    hw = tags.get("highway")
    if hw not in WALK:
        return False
    if tags.get("foot") in NO or tags.get("motorroad") == "yes":
        return False
    if tags.get("access") in NO and tags.get("foot") not in {"yes", "designated", "permissive"}:
        return False
    if tags.get("area") == "yes" and hw != "pedestrian":
        return False
    return True


def dist(a, b):
    """Metres between two (lat, lon) points (haversine)."""
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


class Ways(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.w, self.s, self.e, self.n = bbox
        self.loc = {}      # osm node id -> (lat, lon)
        self.pairs = set()  # undirected (a, b) osm node ids, a < b

    def way(self, w):
        if not walkable(w.tags):
            return
        prev = None
        for nd in w.nodes:
            if not nd.location.valid():
                prev = None
                continue
            lat, lon = nd.location.lat, nd.location.lon
            inside = self.s <= lat <= self.n and self.w <= lon <= self.e
            if not inside:
                prev = None
                continue
            self.loc[nd.ref] = (lat, lon)
            if prev is not None and prev != nd.ref:
                self.pairs.add((min(prev, nd.ref), max(prev, nd.ref)))
            prev = nd.ref


def parts(n, adj):
    """Connected parts as lists of node indexes."""
    seen = bytearray(n)
    out = []
    for start in range(n):
        if seen[start]:
            continue
        seen[start] = 1
        stack, part = [start], []
        while stack:
            v = stack.pop()
            part.append(v)
            for u in adj[v]:
                if not seen[u]:
                    seen[u] = 1
                    stack.append(u)
        out.append(part)
    return out


def main(manifest_path):
    m = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    src = m["routes"]["source"]
    pbf = fetch(src, src.rsplit("/", 1)[1])

    h = Ways(m["bbox"])
    h.apply_file(str(pbf), locations=True, idx="flex_mem")
    print(f"{len(h.loc)} nodes, {len(h.pairs)} segments in bbox")

    ids = list(h.loc)
    index = {osm: i for i, osm in enumerate(ids)}
    adj = [[] for _ in ids]
    for a, b in h.pairs:
        ia, ib = index[a], index[b]
        adj[ia].append(ib)
        adj[ib].append(ia)

    keep = [p for p in parts(len(ids), adj) if len(p) >= MIN_PART]
    kept = sorted(v for p in keep for v in p)
    print(f"kept {len(kept)} nodes in {len(keep)} parts (dropped {len(ids) - len(kept)})")

    # Sort by a 0.001° grid (about 110 x 90 m), row by row: each grid cell
    # is one run of nodes, which the app uses to find the nearest node.
    def cell(v):
        lat, lon = h.loc[ids[v]]
        return (round(lat * 1e6) // 1000, round(lon * 1e6) // 1000)

    kept.sort(key=cell)
    new = {v: i for i, v in enumerate(kept)}

    lat = array("i", (round(h.loc[ids[v]][0] * 1e6) for v in kept))
    lon = array("i", (round(h.loc[ids[v]][1] * 1e6) for v in kept))
    offsets, targets, lengths = array("I", [0]), array("I"), array("H")
    for v in kept:
        p = h.loc[ids[v]]
        for u in sorted(adj[v], key=lambda u: new[u]):
            targets.append(new[u])
            lengths.append(min(65535, max(1, round(dist(p, h.loc[ids[u]]) * 10))))
        offsets.append(len(targets))

    out = OUT / f"{m['id']}.routes.bin"
    with open(out, "wb") as f:
        f.write(b"FKRG" + struct.pack("<III", 1, len(kept), len(targets)))
        for a in (lat, lon, offsets, targets, lengths):
            if sys.byteorder != "little":
                a.byteswap()
            f.write(a.tobytes())
        f.write(b"\0" * (-f.tell() % 4))
    km = sum(lengths) / 10 / 1000 / 2
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB, {len(kept)} nodes, {km:.0f} km of ways)")


if __name__ == "__main__":
    main(sys.argv[1])
