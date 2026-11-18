#!/usr/bin/env python3
"""Builds the region lookup: which prefecture or state a position is in.

Source: Natural Earth 1:10m "Admin 1 – States, Provinces" (public domain),
https://www.naturalearthdata.com/ (download it yourself, unpack, and pass
the .shp path). Output: a small SQLite file with one row per region: its
ISO 3166-2 code (JP-28, US-CA), names, bounding box and outline.

The app uses it to rank sources tagged for the user's prefecture a little
higher (lib/knowledge/regions.dart). Positions never leave the device.

    python3 -I tool/build_regions.py <ne_10m_admin_1_states_provinces.shp> \
        assets/regions/regions.sqlite [--tolerance 0]

No third-party modules: reads the shapefile and dBase table directly.
"""
import argparse
import json
import math
import sqlite3
import struct
import sys
from pathlib import Path


def read_dbf(path):
    data = Path(path).read_bytes()
    n = struct.unpack('<I', data[4:8])[0]
    header_len, record_len = struct.unpack('<HH', data[8:12])
    fields = []
    pos = 32
    while data[pos] != 0x0D:
        name = data[pos:pos + 11].split(b'\0')[0].decode('ascii')
        size = data[pos + 16]
        fields.append((name, size))
        pos += 32
    rows = []
    for i in range(n):
        start = header_len + i * record_len
        rec = data[start:start + record_len]
        if rec[:1] == b'*':  # deleted
            rows.append(None)
            continue
        off = 1
        row = {}
        for name, size in fields:
            # dBase pads with spaces, and some files with zero bytes.
            row[name] = rec[off:off + size].decode('utf-8', 'replace').strip(' \x00')
            off += size
        rows.append(row)
    return rows


def read_shp(path):
    """Polygons as lists of rings, each ring a list of (lon, lat)."""
    data = Path(path).read_bytes()
    pos = 100
    shapes = []
    while pos < len(data):
        _, length = struct.unpack('>II', data[pos:pos + 8])
        content = data[pos + 8:pos + 8 + length * 2]
        pos += 8 + length * 2
        kind = struct.unpack('<i', content[:4])[0]
        if kind == 0:
            shapes.append([])
            continue
        if kind not in (5, 15, 25):
            raise SystemExit(f'unexpected shape type {kind}')
        nparts, npoints = struct.unpack('<ii', content[36:44])
        parts = list(struct.unpack(f'<{nparts}i', content[44:44 + 4 * nparts]))
        pts_off = 44 + 4 * nparts
        pts = [struct.unpack('<dd', content[pts_off + 16 * i:pts_off + 16 * i + 16])
               for i in range(npoints)]
        rings = [pts[a:b] for a, b in zip(parts, parts[1:] + [npoints])]
        shapes.append(rings)
    return shapes


def simplify(points, tol):
    """Douglas-Peucker on one ring (degrees)."""
    if len(points) < 4:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, best_i = 0.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            if norm == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / norm
            if d > best:
                best, best_i = d, i
        if best > tol and best_i > 0:
            keep[best_i] = True
            stack.append((a, best_i))
            stack.append((best_i, b))
    return [p for p, k in zip(points, keep) if k]


def _varint(n, out):
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def encode_rings(rings):
    """Compact outline: varint ring count; per ring a varint point count,
    then lon/lat in 1e-4 degrees (about 10 m) as zigzag varint deltas from
    the previous point (the first from 0). Decoded in regions.dart."""
    out = bytearray()
    _varint(len(rings), out)
    for r in rings:
        _varint(len(r), out)
        px = py = 0
        for lon, lat in r:
            x, y = round(lon * 1e4), round(lat * 1e4)
            for d in (x - px, y - py):
                _varint((d << 1) ^ (d >> 63), out)
            px, py = x, y
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('shp')
    ap.add_argument('out')
    ap.add_argument('--tolerance', type=float, default=0,
                    help='simplification in degrees (0.01 ≈ 1 km); default 0 '
                         'keeps every point (the 1:10m source is coarse '
                         'already, and the file stays about 5 MB)')
    args = ap.parse_args()
    shp = Path(args.shp)
    rows = read_dbf(shp.with_suffix('.dbf'))
    shapes = read_shp(shp)
    if len(rows) != len(shapes):
        raise SystemExit(f'{len(rows)} records but {len(shapes)} shapes')
    version = (shp.parent / (shp.stem + '.VERSION.txt'))
    version = version.read_text().strip() if version.exists() else '?'

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    db = sqlite3.connect(out)
    db.executescript('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE regions (
            code TEXT PRIMARY KEY,   -- ISO 3166-2, e.g. JP-28
            country TEXT NOT NULL,   -- ISO 3166-1 alpha-2, e.g. JP
            name_en TEXT NOT NULL,
            name_ja TEXT,
            min_lon REAL, min_lat REAL, max_lon REAL, max_lat REAL,
            rings BLOB NOT NULL      -- see encode_rings
        );
    ''')
    kept = skipped = points = 0
    for row, rings in zip(rows, shapes):
        if row is None or not rings:
            skipped += 1
            continue
        code = row.get('iso_3166_2', '')
        country = row.get('iso_a2', '')
        # Codes ending in '~' are Natural Earth placeholders for regions
        # without an ISO code (e.g. Hong Kong districts): kept, they still
        # match at country level. Rows without a country are left out.
        if not code or '-' not in code or country in ('', '-1', '-99'):
            skipped += 1
            continue
        flat = []
        lons, lats = [], []
        for ring in rings:
            r = simplify(ring, args.tolerance)
            if len(r) < 4:
                # Small islands vanish when simplified: keep them as they are.
                r = ring
            if len(r) < 4:
                continue
            flat.append(r)
            lons += [p[0] for p in r]
            lats += [p[1] for p in r]
        if not flat:
            skipped += 1
            continue
        points += sum(len(r) for r in flat)
        db.execute(
            'INSERT OR REPLACE INTO regions VALUES (?,?,?,?,?,?,?,?,?)',
            (code, country, row.get('name_en') or row.get('name', ''),
             row.get('name_ja') or None, min(lons), min(lats), max(lons),
             max(lats), encode_rings(flat)))
        kept += 1
    meta = {
        'id': 'world.regions.admin1',
        'title': 'Prefectures and states (Natural Earth admin-1)',
        'source': 'Natural Earth 1:10m Admin 1 – States, Provinces',
        'source_version': version,
        'source_url': 'https://www.naturalearthdata.com/downloads/10m-cultural-vectors/',
        'licence': 'Public domain (Natural Earth)',
        'tolerance_deg': str(args.tolerance),
    }
    db.executemany('INSERT INTO meta VALUES (?,?)', meta.items())
    db.commit()
    db.execute('VACUUM')
    db.close()
    print(json.dumps({'regions': kept, 'skipped': skipped, 'points': points,
                      'bytes': out.stat().st_size}))


if __name__ == '__main__':
    sys.exit(main())
