#!/usr/bin/env python3
"""Read-only check of exact engine native-slot overlay; never applies to checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = Path('/Volumes/Mahesh/personal/bato-build/source/chromium/src')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(directory=HERE):
    manifest = json.loads((directory / 'manifest.json').read_text())
    lock = json.loads((HERE.parent / 'engine-build/lock.json').read_text())
    patch = directory / 'engine.patch'
    if (manifest.get('schema') != 1 or manifest.get('cef_revision') != lock['cef_revision'] or
            manifest.get('chromium_commit') != lock['chromium_commit'] or
            manifest.get('patch_sha256') != digest(patch.read_bytes())):
        raise RuntimeError('Native-slot engine provenance mismatch')
    paths = set()
    for item in manifest['files']:
        relative = Path(item['path'])
        if item['root'] not in ('cef', 'chromium') or relative.is_absolute() or '..' in relative.parts:
            raise RuntimeError('Native-slot target escape')
        name = str(Path('cef') / relative) if item['root'] == 'cef' else str(relative)
        if name in paths:
            raise RuntimeError('Duplicate native-slot engine target')
        paths.add(name)
        if item['original_sha256'] is None and name != 'cef/include/internal/bato_native_slot.h':
            raise RuntimeError('Unexpected new native-slot engine target')
    return manifest, patch


def relative(item):
    return Path('cef') / item['path'] if item['root'] == 'cef' else Path(item['path'])


def inspect(source, manifest):
    source = source.resolve()
    states = set()
    for item in manifest['files']:
        target = source / relative(item)
        if target.is_symlink() or not target.resolve().is_relative_to(source):
            raise RuntimeError('Native-slot target escape')
        actual = digest(target.read_bytes()) if target.exists() else None
        if actual == item['original_sha256']:
            states.add('original')
        elif actual == item['patched_sha256']:
            states.add('patched')
        else:
            raise RuntimeError('Native-slot target differs: ' + str(relative(item)))
    if len(states) != 1:
        raise RuntimeError('Native-slot engine partially applied')
    return states.pop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    source = parser.parse_args().source.resolve()
    manifest, patch = load()
    for directory, revision in ((source, manifest['chromium_commit']),
                                (source / 'cef', manifest['cef_revision'])):
        actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=directory, text=True).strip()
        if actual != revision:
            raise RuntimeError('Native-slot checkout revision mismatch')
    state = inspect(source, manifest)
    command = ['git', 'apply'] + (['--reverse'] if state == 'patched' else [])
    subprocess.run(command + ['--check', str(patch)], cwd=source, check=True)
    print(json.dumps(dict(state=state, files=len(manifest['files']), patch_check='passed', mutations=False)))


if __name__ == '__main__':
    main()
