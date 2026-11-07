#!/usr/bin/env python3
"""Loopback-only download fixture server (port 18768): small, slow, large and failing downloads."""
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
        elif route == "/large.bin":
            self.send_body("large-download.bin", bytes(48 * 1024 * 1024), 0)
        elif route == "/fail.bin":
            self.send_body("failing-download.bin", bytes(4 * 1024 * 1024), 0.02, cut_at=1024 * 1024)
        else:
            self.send_error(404)

    def send_body(self, name, body, delay, cut_at=None):
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            for start in range(0, len(body), CHUNK):
                if cut_at is not None and start >= cut_at:
                    self.connection.close()
                    return
                self.wfile.write(body[start:start + CHUNK])
                time.sleep(delay)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18768)
    args = parser.parse_args()
    with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
        server.serve_forever()
