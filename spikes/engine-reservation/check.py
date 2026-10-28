#!/usr/bin/env python3
"""Fetch four pinned source texts, verify decoded SHA256 and dry-run patch.

Does not create a Chromium checkout, change an installed engine or compile code.
Only a temporary directory receives source text; it is removed on completion.
"""
from pathlib import Path, PurePosixPath
import base64
import hashlib
import json
import subprocess
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
lock = json.loads((HERE / 'sources-lock.json').read_text())
expected_prefix = ('https://chromium.googlesource.com/chromium/src/+/refs/tags/'
                   + lock['chromium_version'] + '/')
with tempfile.TemporaryDirectory(prefix='bato-reservation-review-') as temporary:
    root = Path(temporary)
    for entry in lock['files']:
        path = PurePosixPath(entry['path'])
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit('Unsafe source path in lock')
        if entry['url'] != expected_prefix + str(path) + '?format=TEXT':
            raise SystemExit('Source URL differs from pinned tag/path')
        with urllib.request.urlopen(entry['url'], timeout=30) as response:
            raw = response.read()
        decoded = base64.b64decode(raw)
        if (hashlib.sha256(decoded).hexdigest() != entry['sha256_decoded']
                or len(decoded) != entry['bytes_decoded']):
            raise SystemExit('Pinned source mismatch: ' + str(path))
        destination = root.joinpath(*path.parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(decoded)
    subprocess.run(['git', 'apply', '--check', str(HERE / 'native-reservation.patch')],
                   cwd=root, check=True)
print('Four pinned source hashes matched; patch dry-run passed. Not compiled.')
