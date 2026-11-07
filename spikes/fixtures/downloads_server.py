#!/usr/bin/env python3
"""Loopback-only download fixture server (port 18768): small, slow, large, failing (resumable) and
dangerous-type downloads."""
import argparse
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHUNK = 64 * 1024


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/small.txt":
            self.send_body("small-download.txt", b"bato small download fixture\n", 0)
        elif route == "/slow.bin":
            self.send_body("slow-download.bin", bytes(8 * 1024 * 1024), 0.12)
        elif route == "/slower.bin":
            self.send_body("slower-download.bin", bytes(24 * 1024 * 1024), 0.12)
        elif route == "/large.bin":
            self.send_body("large-download.bin", bytes(48 * 1024 * 1024), 0)
        elif route == "/fail.bin":
            # Cut after 1 MB, but only until /fail-ok.bin is requested; then a resume or retry completes.
            cut = None if self.server.fail_ok else 1024 * 1024
            self.send_body("failing-download.bin", bytes(4 * 1024 * 1024), 0.02, cut_at=cut)
        elif route == "/fail-ok":
            self.server.fail_ok = True
            self.send_body("ok.txt", b"retries now succeed\n", 0)
        elif route == "/fail-reset":
            self.server.fail_ok = False
            self.send_body("reset.txt", b"failures cut again\n", 0)
        elif route.startswith("/danger."):
            self.send_body("bato-danger" + route[route.index("."):], b"#!/bin/sh\necho bato fixture\n", 0)
        else:
            self.send_error(404)

    def send_body(self, name, body, delay, cut_at=None):
        start_at = 0
        range_header = self.headers.get("Range", "")
        if range_header.startswith("bytes=") and range_header.endswith("-"):
            start_at = int(range_header[6:-1])
            cut_at = None
        self.send_response(206 if start_at else 200)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Last-Modified", "Sat, 01 Nov 2025 00:00:00 GMT")
        self.send_header("ETag", '"bato-fixture-' + name + '"')
        if start_at:
            self.send_header("Content-Range", f"bytes {start_at}-{len(body) - 1}/{len(body)}")
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Content-Length", str(len(body) - start_at))
        self.end_headers()
        try:
            for start in range(start_at, len(body), CHUNK):
                if cut_at is not None and start >= cut_at:
                    self.connection.close()
                    return
                self.wfile.write(body[start:start + CHUNK])
                time.sleep(delay)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        if self.server.verbose:
            print(self.address_string(), self.headers.get("Range", "-"), format % args, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18768)
    parser.add_argument("--verbose", action="store_true", help="log requests with their Range header")
    args = parser.parse_args()
    with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
        server.verbose = args.verbose
        server.fail_ok = False
        server.serve_forever()
