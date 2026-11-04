#!/usr/bin/env python3
"""Serves a folder over HTTP with Range support, for testing downloads.

Usage:
  python3 -I tool/serve_downloads.py FOLDER [PORT] [--slow KBPS]

Put catalog.json and the package/map files in FOLDER, then run the app with
  --dart-define=CATALOG_URL=http://<this-mac>:PORT/catalog.json
(or DOWNLOAD_BASE_URL=http://<this-mac>:PORT/ to keep the bundled catalog).
--slow limits the speed so stopping and resuming can be tried by hand.
Not for production: no TLS, serves anything in FOLDER.
"""
import http.server
import os
import re
import sys
import time

ROOT = None
SLOW = 0  # bytes per second, 0 = no limit


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def do_GET(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().do_GET()
        size = os.path.getsize(path)
        start = 0
        m = re.match(r"bytes=(\d+)-$", self.headers.get("Range", ""))
        if m:
            start = int(m.group(1))
            if start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{size - 1}/{size}")
        else:
            self.send_response(200)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Length", str(size - start))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            chunk = 64 * 1024
            while True:
                data = f.read(chunk)
                if not data:
                    break
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    return
                if SLOW:
                    time.sleep(len(data) / SLOW)


def main():
    global ROOT, SLOW
    args = sys.argv[1:]
    if "--slow" in args:
        i = args.index("--slow")
        SLOW = int(args[i + 1]) * 1000
        del args[i : i + 2]
    if not args:
        sys.exit(__doc__)
    ROOT = os.path.abspath(args[0])
    port = int(args[1]) if len(args) > 1 else 8765
    print(f"Serving {ROOT} on port {port}")
    http.server.ThreadingHTTPServer(("", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
