#!/usr/bin/env python3
"""Fetch pinned CEF binaries into a disposable cache, never a Chromium source tree."""
import argparse
import hashlib
import json
import tarfile
import urllib.parse
import urllib.request
from pathlib import Path

VERSION = '156.0.14+g4fa4ab5+chromium-156.0.8078.48'
ARTIFACTS = {
    'client': ('_client', 'a80906135c78d90a564e022989084d741ab1cd9d'),
    'standard': ('', 'dd97a0bf9f25686b135858ea809780dfb9b57006'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--standard', action='store_true', help='Also fetch source sample/headers for compilation')
args = parser.parse_args()
cache = Path.home() / '.cache/bato/cef-baseline'
cache.mkdir(parents=True, exist_ok=True)
for kind in (['client', 'standard'] if args.standard else ['client']):
    suffix, expected = ARTIFACTS[kind]
    basename = f'cef_binary_{VERSION}_macosarm64{suffix}'
    archive = cache / (basename + '.tar.bz2')
    url = 'https://cef-builds.spotifycdn.com/' + urllib.parse.quote(archive.name)
    if not archive.exists():
        partial = archive.with_suffix('.partial')
        with urllib.request.urlopen(url) as source, partial.open('wb') as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
        partial.replace(archive)
    sha1, sha256 = hashlib.sha1(), hashlib.sha256()
    with archive.open('rb') as source:
        while chunk := source.read(1024 * 1024):
            sha1.update(chunk)
            sha256.update(chunk)
    if sha1.hexdigest() != expected:
        raise RuntimeError(f'Upstream SHA1 mismatch for {archive}; refuse to extract')
    destination = cache / basename
    if not (destination / '.bato-extracted').exists():
        with tarfile.open(archive) as source:
            source.extractall(cache, filter='data')
        (destination / '.bato-extracted').touch()
    print(json.dumps({'kind': kind, 'version': VERSION, 'url': url, 'sha1': sha1.hexdigest(), 'sha256': sha256.hexdigest(), 'directory': str(destination)}))
