#!/usr/bin/env python3
"""Read-only post-build checks and launch preview; never launches the sample."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import engine

FRAMEWORK = 'Chromium Embedded Framework'
HELPERS = ('', ' (Renderer)', ' (GPU)', ' (Alerts)')
FIXTURE = 'http://127.0.0.1:18765/login.html'
SYSTEM_PREFIXES = ('/System/Library/', '/usr/lib/')


def require_build(root):
    state = json.loads((root / 'logs/run-state.json').read_text())
    command, _ = engine.stage_command('build', root)
    if (state.get('phase_log') != 'build.log' or state.get('command') != command or
            state.get('running') is not False or state.get('exit_code') != 0 or
            not isinstance(state.get('finished'), (int, float)) or
            state.get('cleanup_error') or state.get('stopped_for_disk_reserve')):
        raise RuntimeError('No completed successful exact engine build; inspect build.log')
    engine.require_idle(root)


def require_configuration(output):
    # Parse assignments exactly; substring checks could accept commented settings.
    values = {}
    for line in (output / 'args.gn').read_text().splitlines():
        match = re.fullmatch(r'\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*=\s*([^#]+?)\s*(?:#.*)?', line)
        if match:
            if match[1] in values:
                raise RuntimeError('Duplicate GN setting: ' + match[1])
            values[match[1]] = match[2].strip()
    expected = {'is_component_build': 'true', 'is_debug': 'true',
                'target_cpu': '"arm64"', 'symbol_level': '0',
                'use_remoteexec': 'false', 'use_system_xcode': 'true'}
    for key, value in expected.items():
        if values.get(key) != value:
            raise RuntimeError('Unexpected generated GN setting: ' + key)


def require_patches(root):
    source, cef = engine.source_paths(root)
    if hashlib.sha256((cef / engine.LOCK['sample_path']).read_bytes()).hexdigest() != engine.LOCK['sample_patched_sha256']:
        raise RuntimeError('Dedicated mock-Profile/sample termination guard changed or missing')
    patch = engine.HERE.parent / 'engine-reservation/native-reservation.patch'
    if subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=source,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        raise RuntimeError('Reservation source patch changed or missing')


def load_commands(text):
    """Extract dyld paths without matching LC_ID_DYLIB (the image's own name)."""
    dependencies, rpaths = [], []
    for block in text.split('Load command ')[1:]:
        command = re.search(r'^\s*cmd (\S+)\s*$', block, re.M)
        if not command:
            continue
        if command[1] == 'LC_RPATH':
            path = re.search(r'^\s*path (.+) \(offset \d+\)\s*$', block, re.M)
            if path:
                rpaths.append(path[1])
        elif command[1] in ('LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB', 'LC_REEXPORT_DYLIB',
                            'LC_LOAD_UPWARD_DYLIB', 'LC_LAZY_LOAD_DYLIB'):
            name = re.search(r'^\s*name (.+) \(offset \d+\)\s*$', block, re.M)
            if name:
                dependencies.append(name[1])
    return dependencies, rpaths


def expand_path(value, image, executable):
    for token, base in (('@loader_path', image.parent), ('@executable_path', executable.parent)):
        if value == token or value.startswith(token + '/'):
            return (base / value[len(token):].lstrip('/')).resolve()
    if value.startswith('/'):
        return Path(value).resolve()
    raise RuntimeError('Unsupported relative dyld path: ' + value)


def dependency_closure(images, output, inspect=None):
    """Resolve required non-system images in place; never invokes their code.

    Weak loads are checked conservatively too. A missing weak image is a review
    point rather than an automatically ignored dependency. System shared-cache
    libraries need not exist as ordinary filesystem files.
    """
    output = output.resolve()
    inspect = inspect or (lambda path: engine.command_output(['otool', '-l', str(path)]))
    checked = set()
    for executable, initial_images in images:
        pending = [(image, ()) for image in initial_images]
        seen = set()
        while pending:
            image, inherited = pending.pop()
            image = image.resolve()
            context = (image, inherited)
            if context in seen:
                continue
            seen.add(context)
            if not image.is_relative_to(output) or not image.is_file():
                raise RuntimeError('Missing or external component image: ' + str(image))
            if engine.command_output(['lipo', '-archs', str(image)]) != 'arm64':
                raise RuntimeError('Expected ARM64-only image: ' + str(image))
            dependencies, raw_rpaths = load_commands(inspect(image))
            rpaths = tuple(dict.fromkeys(
                tuple(expand_path(path, image, executable) for path in raw_rpaths) + inherited))
            for name in dependencies:
                if name.startswith(SYSTEM_PREFIXES):
                    continue
                if name.startswith('@rpath/'):
                    suffix = name[len('@rpath/'):]
                    candidate = next(((base / suffix).resolve() for base in rpaths
                                      if (base / suffix).is_file()), None)
                    if candidate is None:
                        raise RuntimeError('Unresolved component dependency: ' + name)
                else:
                    candidate = expand_path(name, image, executable)
                if not candidate.is_relative_to(output):
                    raise RuntimeError('Dependency escapes component output: ' + str(candidate))
                pending.append((candidate, rpaths))
            checked.add(image)
    return sorted(str(path.relative_to(output)) for path in checked)


def artifact_images(output):
    app = output / 'cefsimple.app'
    main = app / 'Contents/MacOS/cefsimple'
    framework = app / 'Contents/Frameworks' / (FRAMEWORK + '.framework') / 'Versions/A' / FRAMEWORK
    roots = [(main, (main, framework))]
    for suffix in HELPERS:
        name = 'cefsimple Helper' + suffix
        helper = app / 'Contents/Frameworks' / (name + '.app') / 'Contents/MacOS' / name
        roots.append((helper, (helper, framework)))
    for executable, _ in roots:
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise RuntimeError('Missing executable component sample/helper: ' + str(executable))
    # These runtime-loaded graphics libraries are not necessarily LC_LOAD_DYLIBs.
    libraries = framework.parent / 'Libraries'
    names = ['libvk_swiftshader.dylib', 'libvulkan.dylib', 'libcef_sandbox.dylib']
    # ANGLE is static by default in this pin. Only require separate dylibs when
    # GN actually selected CEF's conditional bundle target.
    graph = (output / 'build.ninja').read_text()
    if re.search(r'^build cef_framework_angle_binaries: phony ', graph, re.M):
        names += ['libEGL.dylib', 'libGLESv2.dylib']
    dynamic = tuple(libraries / name for name in names)
    roots.append((main, dynamic))
    return main, roots


def fresh_profile(root, reservation):
    profile = root / 'runtime/profiles' / ('reservation-mock-v1' if reservation else 'control-mock-v1')
    if profile.resolve() != profile:
        raise RuntimeError('Refusing symlinked test Profile path')
    if profile.exists() and (not profile.is_dir() or any(profile.iterdir())):
        raise RuntimeError('Test Profile already contains data; inspect provider history before reuse')
    return profile


def preview(root, reservation=False):
    engine.preflight(root)
    engine.require_marker(root)
    # Existing wrapper creates this lock during prepare; r+ does not create it.
    with (root / 'run.lock').open('r') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Engine workspace command is active; wait for the build to finish') from None
        require_build(root)
        engine.require_checkout(root)
        engine.verify_source(root)
        require_patches(root)
        output = engine.source_paths(root)[0] / 'out' / engine.LOCK['configuration']
        require_configuration(output)
        executable, images = artifact_images(output)
        dependencies = dependency_closure(images, output)
        profile = fresh_profile(root, reservation)
        command = [str(executable), '--use-native', '--use-mock-keychain',
                   '--cache-path=' + str(profile), '--url=' + FIXTURE]
        if reservation:
            command.append('--bato-native-reservation')
        return {'mode': 'preview-only', 'cwd': str(output), 'command': command,
                'fresh_test_profile': str(profile), 'checked_images': dependencies,
                'notice': 'No process launched or Profile created. UI acceptance is still required.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reservation', action='store_true', help='Preview the opt-in reservation case')
    args = parser.parse_args()
    print(json.dumps(preview(engine.DEFAULT_ROOT, args.reservation), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
