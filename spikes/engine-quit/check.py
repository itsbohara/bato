#!/usr/bin/env python3
"""Read-only pin/hash and patch checks for the bounded native Quit experiment."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = Path('/Volumes/Mahesh/personal/bato-build/source/chromium/src/cef')
PATHS = {
    'libcef/browser/chrome/browser_util.h',
    'libcef/browser/chrome/chrome_browser_host_impl.cc',
    'libcef/browser/chrome/chrome_browser_delegate.cc',
    'libcef/browser/chrome/chrome_content_browser_client_cef_mac.mm',
    'tests/cefsimple/simple_handler.h',
    'tests/cefsimple/simple_handler.cc',
    'tests/cefsimple/cefsimple_mac.mm',
}

STARTUP_PATHS = {
    'chrome/browser/chrome_browser_main_mac.mm',
    'chrome/browser/chrome_browser_application_mac.mm',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load_manifest(directory=HERE):
    manifest = json.loads((directory / 'manifest.json').read_text())
    lock = json.loads((HERE.parent / 'engine-build/lock.json').read_text())
    if manifest.get('schema') != 1 or manifest.get('cef_revision') != lock['cef_revision']:
        raise RuntimeError('Quit manifest does not match pinned CEF')
    files = manifest.get('files', [])
    if len(files) != len(PATHS) or {item.get('path') for item in files} != PATHS:
        raise RuntimeError('Unexpected Quit patch target paths')
    for item in files:
        for key in ('original_sha256', 'patched_sha256'):
            if not re.fullmatch('[a-f0-9]{64}', item.get(key, '')):
                raise RuntimeError('Malformed Quit source hash')
        if item['original_sha256'] == item['patched_sha256']:
            raise RuntimeError('Quit target must change')
    sample = next(item for item in files if item['path'] == lock['sample_path'])
    if sample['original_sha256'] != lock['sample_patched_sha256']:
        raise RuntimeError('Quit sample must build on the existing runtime/storage guard')
    patch = directory / 'quit.patch'
    if digest(patch.read_bytes()) != manifest.get('patch_sha256'):
        raise RuntimeError('Quit patch hash differs')
    return manifest, patch


def load_startup_manifest(directory=HERE):
    manifest = json.loads((directory / 'startup.json').read_text())
    lock = json.loads((HERE.parent / 'engine-build/lock.json').read_text())
    if manifest.get('schema') != 1 or manifest.get('chromium_commit') != lock['chromium_commit']:
        raise RuntimeError('Quit startup manifest does not match pinned Chromium')
    files = manifest.get('files', [])
    if len(files) != len(STARTUP_PATHS) or {item.get('path') for item in files} != STARTUP_PATHS:
        raise RuntimeError('Unexpected Quit startup target paths')
    for item in files:
        for key in ('original_sha256', 'patched_sha256'):
            if not re.fullmatch('[a-f0-9]{64}', item.get(key, '')):
                raise RuntimeError('Malformed Quit startup source hash')
        if item['original_sha256'] == item['patched_sha256']:
            raise RuntimeError('Quit startup target must change')
    patch = directory / 'startup.patch'
    if digest(patch.read_bytes()) != manifest.get('patch_sha256'):
        raise RuntimeError('Quit startup patch hash differs')
    return manifest, patch


def inspect_files(source, manifest):
    source = source.resolve()
    states = set()
    for item in manifest['files']:
        target = source / item['path']
        if target.is_symlink() or not target.resolve().is_relative_to(source):
            raise RuntimeError('Quit target escapes source: ' + item['path'])
        actual = digest(target.read_bytes())
        if actual == item['original_sha256']:
            states.add('original')
        elif actual == item['patched_sha256']:
            states.add('patched')
        else:
            raise RuntimeError('Quit source hash differs: ' + item['path'])
    if len(states) != 1:
        raise RuntimeError('Quit patch is partially applied; preserve and inspect source')
    return states.pop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source = args.source.resolve()
    manifest, patch = load_manifest()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if revision != manifest['cef_revision']:
        raise RuntimeError('Unexpected embedded CEF revision')
    startup, startup_patch = load_startup_manifest()
    chromium = source.parent
    chromium_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=chromium, text=True).strip()
    if chromium_revision != startup['chromium_commit']:
        raise RuntimeError('Unexpected Chromium revision')
    states = [inspect_files(source, manifest), inspect_files(chromium, startup)]
    if len(set(states)) != 1:
        raise RuntimeError('Quit CEF/startup patches are partially applied; preserve and inspect source')
    command = ['git', 'apply'] + (['--reverse'] if states[0] == 'patched' else [])
    subprocess.run(command + ['--check', str(patch)], cwd=source, check=True)
    subprocess.run(command + ['--check', str(startup_patch)], cwd=chromium, check=True)
    print(json.dumps({'source_state': states[0], 'cef_files': len(manifest['files']),
                      'chromium_files': len(startup['files']),
                      'patch_check': 'passed', 'mutations': False}))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
