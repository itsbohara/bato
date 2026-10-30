#!/usr/bin/env python3
"""Guarded overlay for the bounded native-slot experiment; no checkout/configure."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import engine
import runtime

ARTIFACTS = engine.HERE.parent / 'engine-native-slot'
REPOSITORY = engine.HERE.parent.parent
RESERVATION_PATH = 'chrome/browser/ui/views/frame/layout/browser_view_layout_delegate_impl.cc'
RESERVATION_BASE_SHA = '1332ecbaa3bb52f617dec0265b28b743039ef8fcdcdbc231d5f4a7bc6a42ff15'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def load_layers(source):
    layers, seen = [], set()
    for name in ('engine', 'client'):
        manifest_path = ARTIFACTS / ('manifest.json' if name == 'engine' else 'client.json')
        manifest = json.loads(manifest_path.read_text())
        patch = ARTIFACTS / (name + '.patch')
        if (manifest.get('schema') != 1 or
                manifest.get('cef_revision') != engine.LOCK['cef_revision'] or
                manifest.get('chromium_commit') != engine.LOCK['chromium_commit'] or
                digest(patch) != manifest.get('patch_sha256')):
            raise RuntimeError('Native slot manifest/patch provenance differs: ' + name)
        entries = []
        for original in manifest.get('files', []):
            entry = dict(original)
            path = Path(entry['path'])
            if (entry.get('root') not in ('cef', 'chromium') or path.is_absolute() or
                    '..' in path.parts or not path.parts):
                raise RuntimeError('Unsafe native slot target')
            relative = Path('cef') / path if entry['root'] == 'cef' else path
            target = source / relative
            if (target.is_symlink() or not target.resolve().is_relative_to(source.resolve()) or
                    str(relative) in seen):
                raise RuntimeError('Duplicate or escaping native slot target')
            seen.add(str(relative))
            for key in ('original_sha256', 'patched_sha256'):
                value = entry.get(key)
                if key == 'original_sha256' and value is None:
                    continue
                if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value):
                    raise RuntimeError('Invalid native slot source hash')
            entry.update(relative=str(relative), target=target)
            entries.append(entry)
        # Swift application sources are staged into the pinned engine tree.
        # Refuse stale copies rather than silently compiling an older sidebar.
        for repository_path, target_path in manifest.get('source_mirrors', {}).items():
            original = REPOSITORY / repository_path
            relative = Path(repository_path)
            target = next((e for e in entries if e['path'] == target_path and e['root'] == 'cef'), None)
            if (relative.is_absolute() or '..' in relative.parts or
                    not original.resolve().is_relative_to(REPOSITORY.resolve()) or
                    target is None or digest(original) != target['patched_sha256']):
                raise RuntimeError('Native slot staged source differs: ' + repository_path)
        # All patches use Chromium-relative paths, even for embedded CEF files.
        headers = re.findall(r'^(?:--- a/|\+\+\+ b/)(.+)$', patch.read_text(), re.M)
        if not entries or set(headers) != {entry['relative'] for entry in entries}:
            raise RuntimeError('Native slot patch targets differ from manifest')
        layers.append((entries, patch))
    return layers


def protected_base(root):
    cef, quit_files, _ = engine.quit_patch_entries(root)
    source, startup_files, _ = engine.quit_startup_entries(root)
    protected = {str((cef / e['path']).relative_to(source)): e['patched_sha256'] for e in quit_files}
    protected.update({e['path']: e['patched_sha256'] for e in startup_files})
    helper, _ = engine.helper_packaging_paths(root)
    protected[str(helper.relative_to(source))] = engine.HELPER_PACKAGING['patched_sha256']
    protected[RESERVATION_PATH] = RESERVATION_BASE_SHA
    return protected


def inspect(root, layers):
    source = engine.source_paths(root)[0]
    entries = [e for files, _ in layers for e in files]
    by_path = {e['relative']: e for e in entries}
    states = set()
    for e in entries:
        actual = digest(e['target'])
        if actual == e['original_sha256']:
            states.add('original')
        elif actual == e['patched_sha256']:
            states.add('patched')
        else:
            raise RuntimeError('Native slot source changed; preserving: ' + e['relative'])
    if len(states) != 1:
        raise RuntimeError('Native slot is partially applied; preserving all files')
    state = states.pop()
    for relative, expected in protected_base(root).items():
        overlay = by_path.get(relative)
        if overlay:
            if overlay['original_sha256'] != expected:
                raise RuntimeError('Native slot does not preserve reviewed base: ' + relative)
            expected = overlay['patched_sha256'] if state == 'patched' else expected
        if digest(source / relative) != expected:
            raise RuntimeError('Reviewed base changed: ' + relative)
    return state


def apply(root, layers):
    state = inspect(root, layers)
    if state == 'patched':
        print('Native slot overlay already applied')
        return
    source = engine.source_paths(root)[0]
    # No writes until both independent patches pass their dry-run.
    for _, patch in layers:
        subprocess.run(['git', 'apply', '--check', str(patch)], cwd=source, check=True)
    for _, patch in layers:
        subprocess.run(['git', 'apply', str(patch)], cwd=source, check=True)
    if inspect(root, layers) != 'patched':
        raise RuntimeError('Native slot final hash verification failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('check', 'patch', 'build', 'artifacts'))
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    root = engine.DEFAULT_ROOT
    engine.preflight(root)
    engine.require_marker(root)
    with (root / 'run.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        engine.require_idle(root)
        engine.verify_source(root)
        engine.require_checkout(root)
        source = engine.source_paths(root)[0]
        layers = load_layers(source)
        state = inspect(root, layers)
        if args.phase == 'check':
            print(json.dumps({'source_state': state, 'files': sum(len(f) for f, _ in layers)}))
        elif args.phase == 'patch':
            if args.execute:
                apply(root, layers)
            else:
                print('Preview only; use --execute to apply verified native slot patches')
        else:
            if state != 'patched':
                raise RuntimeError('Native slot overlay is not applied')
            output = source / 'out' / engine.LOCK['configuration']
            runtime.require_configuration(output)
            command, cwd = engine.stage_command('build', root)
            if args.phase == 'build':
                print(json.dumps({'command': command, 'execute': args.execute}), flush=True)
                if args.execute:
                    engine.guarded_run(command, cwd, engine.environment(root),
                                       root / 'logs/build.log', root, engine.LOCK['reserve_bytes'])
            else:
                runtime.require_build(root)
                _, images = runtime.artifact_images(output)
                closure = runtime.dependency_closure(images, output)
                print(json.dumps({'checked_images': len(closure), 'launch': False}))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
