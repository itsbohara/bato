#!/usr/bin/env python3
"""Explicit, guarded CEF developer-build stages on Bato's external SSD.

prepare fetches only small tooling/CEF checkouts. bootstrap/checkout/configure/patch/build
print their command until --execute is supplied. No cleanup or force flags.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import urllib.request

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / 'lock.json').read_text())
HELPER_PACKAGING = json.loads((HERE / 'helper-packaging.json').read_text())
DEFAULT_ROOT = Path('/Volumes/Mahesh/personal/bato-build')
MARKER = '.bato-engine-workspace.json'
CHECKOUT_MARKER = 'checkout-complete.json'


def command_output(command, cwd=None):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def preflight(root, initial=False):
    """Refuse an unmounted/internal replacement path before creating files."""
    root = root.absolute()
    if root != root.resolve() or any(c.isspace() for c in str(root)):
        raise RuntimeError('Build root must be canonical and contain no spaces')
    personal = Path('/Volumes/Mahesh/personal')
    if root != personal / 'bato-build':
        raise RuntimeError('Only the authorized personal/bato-build root is allowed')
    if not personal.is_dir():
        raise RuntimeError('Authorized SSD Personal folder is not mounted')
    info = plistlib.loads(subprocess.check_output(['diskutil', 'info', '-plist', '/Volumes/Mahesh']))
    if (info.get('MountPoint') != '/Volumes/Mahesh' or
            info.get('FilesystemType') != 'apfs' or not info.get('Writable')):
        raise RuntimeError('Expected mounted APFS SSD at /Volumes/Mahesh')
    if personal.stat().st_dev == Path('/').stat().st_dev:
        raise RuntimeError('Refusing internal-disk fallback')
    if not os.access(personal, os.W_OK):
        raise RuntimeError('SSD Personal folder is not writable')
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise RuntimeError('This experiment requires native Apple Silicon macOS')
    memory = int(command_output(['sysctl', '-n', 'hw.memsize']))
    if memory < 16 * 1024**3:
        raise RuntimeError('CEF developer minimum is 16 GiB RAM')
    sdk = command_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'])
    if tuple(int(p) for p in sdk.split('.')) < (15,):
        raise RuntimeError('Pinned Chromium SDK minimum is 15')
    free = shutil.disk_usage(personal).free
    minimum = (LOCK['initial_free_bytes'] + LOCK['reserve_bytes']) if initial else LOCK['reserve_bytes']
    if free < minimum:
        raise RuntimeError(f'Insufficient free space: {free} bytes; need {minimum}')
    return {'root': str(root), 'free_bytes': free, 'memory_bytes': memory,
            'sdk': sdk, 'official_sdk': '26.5', 'filesystem': 'apfs',
            'configuration': LOCK['configuration'], 'reserve_bytes': LOCK['reserve_bytes']}


def require_marker(root):
    marker = root / MARKER
    if not marker.is_file() or json.loads(marker.read_text()) != LOCK:
        raise RuntimeError('Workspace marker/pins missing or changed; run prepare')


def pins_digest():
    return hashlib.sha256(json.dumps(LOCK, sort_keys=True).encode()).hexdigest()


def gclient_contents():
    solution = {'managed': False, 'name': 'src',
                'url': LOCK['chromium_url'] + '@' + LOCK['chromium_revision'].split('/')[-1],
                'custom_vars': {'checkout_pgo_profiles': False, 'source_tarball': False,
                                'siso_version': LOCK['siso_version']},
                'custom_deps': {}, 'deps_file': 'DEPS', 'safesync_url': ''}
    return 'solutions = ' + repr([solution]) + '\n'


def verify_automate(root):
    path = root / 'bootstrap/automate-git.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != LOCK['automate_sha256']:
        raise RuntimeError('Pinned automate script changed; refusing execution')


def require_checkout(root):
    path = root / CHECKOUT_MARKER
    if not path.is_file() or json.loads(path.read_text()).get('pins_sha256') != pins_digest():
        raise RuntimeError('No successful pinned checkout marker; inspect partial sync logs before manual recovery')


def require_idle(root):
    state = root / 'logs/run-state.json'
    if state.is_file():
        record = json.loads(state.read_text())
        if (record.get('running') or record.get('cleanup_error')) and group_alive(record['pid']):
            raise RuntimeError('Previous owned group still exists; inspect run-state before resuming')


def environment(root):
    env = os.environ.copy()
    # Do not alter HOME, the user's shell configuration, or global tool settings.
    for key in ('GIT_CACHE_PATH', 'GN_ARGUMENTS', 'GN_DEFINES', 'GN_OUT_CONFIGS',
                'CEF_ENABLE_AMD64', 'CEF_ENABLE_ARM64'):
        env.pop(key, None)
    env.update(PATH=str(root / 'depot_tools') + os.pathsep + env.get('PATH', ''),
               DEPOT_TOOLS_UPDATE='0', DEPOT_TOOLS_METRICS='0',
               CIPD_CACHE_DIR=str(root / 'cache/cipd'),
               VPYTHON_VIRTUALENV_ROOT=str(root / 'cache/vpython'),
               XDG_CACHE_HOME=str(root / 'cache/xdg'),
               CCACHE_DIR=str(root / 'cache/ccache'),
               TMPDIR=str(root / 'tmp') + '/',
               GN_DEFINES=LOCK['gn_defines'], GN_OUT_CONFIGS=LOCK['configuration'])
    return env


def group_alive(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Darwin can report EPERM for a group whose last member is becoming
        # a zombie. Treat it as present until reaping confirms disappearance.
        return True


def terminate_owned(process, term_timeout=10, kill_timeout=5):
    """Stop our entire new-session group, even if its leader has exited.

    A descendant can ignore TERM or outlive the leader. Waiting/reaping only
    the Popen object does not establish that gclient/ninja's group is gone.
    """
    group = process.pid
    process.poll()
    if not group_alive(group):
        process.wait()
        return
    try:
        os.killpg(group, signal.SIGTERM)
    except ProcessLookupError:
        process.wait()
        return
    except PermissionError:
        pass
    deadline = time.monotonic() + term_timeout
    while time.monotonic() < deadline:
        process.poll()
        if not group_alive(group):
            break
        time.sleep(.02)
    if group_alive(group):
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    try:
        process.wait(timeout=kill_timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError('Owned group leader did not exit after KILL')
    deadline = time.monotonic() + kill_timeout
    while group_alive(group) and time.monotonic() < deadline:
        time.sleep(.02)
    if group_alive(group):
        raise RuntimeError('Owned process group remains after KILL; inspect run-state before resuming')


def guarded_run(command, cwd, env, log_path, volume, reserve, interval=5, free_fn=None):
    free_fn = free_fn or (lambda: shutil.disk_usage(volume).free)
    if free_fn() < reserve:
        raise RuntimeError('Disk reserve reached before child launch')
    state = log_path.parent / 'run-state.json'
    with log_path.open('a') as log:
        process = None
        record = {'phase_log': log_path.name, 'command': command,
                  'started': time.time(), 'running': True}
        try:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            record['pid'] = process.pid
            state.write_text(json.dumps(record, indent=2) + '\n')
            print(json.dumps({'pid': process.pid, 'log': str(log_path)}), flush=True)
            while process.poll() is None:
                if free_fn() < reserve:
                    terminate_owned(process)
                    record['stopped_for_disk_reserve'] = True
                    raise RuntimeError('Stopped owned command at disk reserve; files preserved')
                try:
                    process.wait(timeout=interval)
                except subprocess.TimeoutExpired:
                    pass
            if process.returncode:
                raise subprocess.CalledProcessError(process.returncode, command)
        finally:
            if process is not None:
                try:
                    terminate_owned(process)
                except RuntimeError as error:
                    record['cleanup_error'] = str(error)
                    raise
                finally:
                    record.update(running=False, exit_code=process.returncode, finished=time.time())
                    state.write_text(json.dumps(record, indent=2) + '\n')


def check_repo(path, revision, url):
    if not (path / '.git').is_dir():
        raise RuntimeError(f'Missing managed Git checkout: {path}')
    if command_output(['git', 'remote', 'get-url', 'origin'], path) != url:
        raise RuntimeError(f'Unexpected remote: {path}')
    if command_output(['git', 'rev-parse', 'HEAD'], path) != revision:
        raise RuntimeError(f'Unexpected revision: {path}')
    if command_output(['git', 'status', '--porcelain', '--untracked-files=no'], path):
        raise RuntimeError(f'Tracked tooling/source edits preserved; refusing: {path}')


def small_checkout(root, name, url, revision, env):
    target = root / name
    if target.exists():
        check_repo(target, revision, url)
        return
    target.mkdir(parents=True)
    commands = [['git', 'init', str(target)],
                ['git', '-C', str(target), 'remote', 'add', 'origin', url],
                ['git', '-C', str(target), 'fetch', '--depth=1', '--no-tags', 'origin', revision],
                ['git', '-C', str(target), 'checkout', '--detach', 'FETCH_HEAD']]
    for command in commands:
        guarded_run(command, root, env, root / 'logs/prepare.log', root,
                    LOCK['reserve_bytes'])
    check_repo(target, revision, url)


def prepare(root):
    report = preflight(root, initial=True)
    root.mkdir(exist_ok=True)
    marker = root / MARKER
    if marker.exists() and json.loads(marker.read_text()) != LOCK:
        raise RuntimeError('Existing workspace has different pins; preserving it')
    marker.write_text(json.dumps(LOCK, indent=2) + '\n')
    for child in ('bootstrap', 'logs', 'tmp', 'cache/cipd', 'cache/vpython', 'cache/xdg', 'cache/ccache'):
        (root / child).mkdir(parents=True, exist_ok=True)
    automate = root / 'bootstrap/automate-git.py'
    if not automate.exists():
        with urllib.request.urlopen(LOCK['automate_url'], timeout=30) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != LOCK['automate_sha256']:
            raise RuntimeError('Pinned automate source mismatch')
        automate.write_bytes(data)
    if hashlib.sha256(automate.read_bytes()).hexdigest() != LOCK['automate_sha256']:
        raise RuntimeError('Existing automate source differs; preserving it')
    env = environment(root)
    small_checkout(root, 'depot_tools', LOCK['depot_tools_url'], LOCK['depot_tools_revision'], env)
    (root / 'source').mkdir(exist_ok=True)
    small_checkout(root, 'source/cef', LOCK['cef_url'], LOCK['cef_revision'], env)
    chromium = root / 'source/chromium'
    chromium.mkdir(exist_ok=True)
    config = chromium / '.gclient'
    if config.exists() and config.read_text() != gclient_contents():
        raise RuntimeError('Existing .gclient differs; preserving it')
    config.write_text(gclient_contents())
    (root / 'preflight.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


def source_paths(root):
    source = root / 'source/chromium/src'
    return source, source / 'cef'


def stage_command(phase, root):
    source, cef = source_paths(root)
    if phase == 'bootstrap':
        # Initialize only the Python shim required by gn. Unlike the broad
        # ensure_bootstrap script, this does not also bootstrap gsutil/pylint.
        # -e prevents the function's final cd from hiding a CIPD failure.
        return ['/bin/bash', '-e', '-c',
                'source "$1/bootstrap_python3"; bootstrap_python3',
                'bato-bootstrap', str(root / 'depot_tools')], root / 'depot_tools'
    if phase == 'checkout':
        return [sys.executable, str(root / 'bootstrap/automate-git.py'),
                '--download-dir=' + str(root / 'source'),
                '--depot-tools-dir=' + str(root / 'depot_tools'),
                '--branch=' + LOCK['cef_branch'], '--checkout=' + LOCK['cef_revision'],
                '--chromium-checkout=' + LOCK['chromium_revision'], '--arm64-build',
                '--no-chromium-history', '--no-depot-tools-update', '--no-cef-update',
                '--no-build', '--no-distrib'], root
    if phase == 'configure':
        return [sys.executable, str(cef / 'tools/gclient_hook.py')], cef
    if phase == 'build':
        return [str(root / 'depot_tools/autoninja'), '-C',
                'out/' + LOCK['configuration'], '-j', '2', 'cefsimple'], source
    raise RuntimeError('Unknown command phase')


def verify_source(root):
    source, cef = source_paths(root)
    check_repo(root / 'depot_tools', LOCK['depot_tools_revision'], LOCK['depot_tools_url'])
    check_repo(root / 'source/cef', LOCK['cef_revision'], LOCK['cef_url'])
    config = root / 'source/chromium/.gclient'
    if not config.is_file() or config.read_text() != gclient_contents():
        raise RuntimeError('Pinned gclient configuration changed or missing')
    verify_automate(root)
    if source.exists():
        version = source / 'chrome/VERSION'
        if not version.is_file():
            raise RuntimeError('Partial source checkout: inspect logs and resume gclient sync; no cleanup performed')
        numbers = dict(line.split('=', 1) for line in version.read_text().splitlines() if '=' in line)
        if '.'.join(numbers[k] for k in ('MAJOR', 'MINOR', 'BUILD', 'PATCH')) != '156.0.8078.48':
            raise RuntimeError('Unexpected Chromium source version')
        if command_output(['git', 'rev-parse', 'HEAD'], source) != LOCK['chromium_commit']:
            raise RuntimeError('Unexpected Chromium HEAD commit')
        if command_output(['git', 'remote', 'get-url', 'origin'], source) != LOCK['chromium_url']:
            raise RuntimeError('Unexpected Chromium origin')
        if cef.exists() and command_output(['git', 'rev-parse', 'HEAD'], cef) != LOCK['cef_revision']:
            raise RuntimeError('Unexpected embedded CEF revision')


def helper_packaging_paths(root):
    if (HELPER_PACKAGING.get('schema') != 1 or
            HELPER_PACKAGING.get('cef_revision') != LOCK['cef_revision'] or
            HELPER_PACKAGING.get('path') != 'BUILD.gn'):
        raise RuntimeError('Helper packaging manifest does not match pinned CEF')
    patch = HERE / 'helper-packaging.patch'
    if hashlib.sha256(patch.read_bytes()).hexdigest() != HELPER_PACKAGING['patch_sha256']:
        raise RuntimeError('Helper packaging patch changed')
    return source_paths(root)[1] / 'BUILD.gn', patch


def require_helper_packaging(root):
    target, _ = helper_packaging_paths(root)
    if hashlib.sha256(target.read_bytes()).hexdigest() != HELPER_PACKAGING['patched_sha256']:
        raise RuntimeError('Required Aperitif-named helper packaging is missing or changed; run patch stage')


def patch_helper_packaging(root):
    target, patch = helper_packaging_paths(root)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest == HELPER_PACKAGING['patched_sha256']:
        print('Aperitif-named helper packaging already applied')
        return
    if digest != HELPER_PACKAGING['original_sha256']:
        raise RuntimeError('Embedded CEF build definitions differ; refusing helper packaging patch')
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=target.parent, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=target.parent, check=True)
    require_helper_packaging(root)


def patch_source(root, execute):
    source, cef = source_paths(root)
    patch = HERE.parent / 'engine-reservation/native-reservation.patch'
    command = ['git', 'apply', '--check', str(patch)]
    print(json.dumps({'cwd': str(source), 'command': command, 'apply': execute}))
    if execute:
        # A previously applied identical patch is an idempotent success.
        reverse = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)],
                                 cwd=source, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if reverse.returncode == 0:
            print('Reservation patch already applied')
        else:
            subprocess.run(command, cwd=source, check=True)
            subprocess.run(['git', 'apply', str(patch)], cwd=source, check=True)
        sample = cef / LOCK['sample_path']
        digest = hashlib.sha256(sample.read_bytes()).hexdigest()
        if digest == LOCK['sample_patched_sha256']:
            print('Dedicated test-Profile/termination guard already applied')
        elif digest == LOCK['sample_original_sha256']:
            sample_patch = HERE / 'sample-runtime.patch'
            subprocess.run(['git', 'apply', '--unidiff-zero', '--check', str(sample_patch)],
                           cwd=cef, check=True)
            subprocess.run(['git', 'apply', '--unidiff-zero', str(sample_patch)],
                           cwd=cef, check=True)
            if hashlib.sha256(sample.read_bytes()).hexdigest() != LOCK['sample_patched_sha256']:
                raise RuntimeError('Sample runtime guard patch hash mismatch')
        else:
            raise RuntimeError('Embedded sample source differs; refusing runtime guard patch')
        patch_helper_packaging(root)


def main():
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['preflight', 'prepare', 'bootstrap', 'checkout', 'configure', 'patch', 'build', 'status'])
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    parser.add_argument('--execute', action='store_true', help='Execute bootstrap/checkout/configure/patch/build stage')
    args = parser.parse_args()
    root = args.root.absolute()
    if args.phase == 'preflight':
        print(json.dumps(preflight(root, initial=True), indent=2))
        return
    if args.phase == 'status':
        preflight(root)
        path = root / 'logs/run-state.json'
        print(path.read_text() if path.exists() else 'No managed command has run')
        return
    initial_checkout = args.phase == 'checkout' and not source_paths(root)[0].exists()
    preflight(root, initial=args.phase == 'prepare' or initial_checkout)
    if args.phase != 'prepare':
        require_marker(root)
    root.mkdir(exist_ok=True)
    with (root / 'run.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        require_idle(root)
        if args.phase == 'prepare':
            prepare(root)
            return
        verify_source(root)
        if args.phase not in ('checkout', 'bootstrap'):
            require_checkout(root)
        elif args.phase == 'checkout' and source_paths(root)[0].exists():
            # automate's no-history mode can skip sync/hooks for an existing
            # partial src tree even when chrome/VERSION is already present.
            require_checkout(root)
        if args.phase == 'patch':
            patch_source(root, args.execute)
            return
        command, cwd = stage_command(args.phase, root)
        print(json.dumps({'phase': args.phase, 'cwd': str(cwd), 'command': command,
                          'gn_defines': LOCK['gn_defines'], 'execute': args.execute}), flush=True)
        if not args.execute:
            return
        if args.phase == 'checkout':
            source, _ = source_paths(root)
            if source.exists() and command_output(['git', 'status', '--porcelain', '--untracked-files=no'], source):
                raise RuntimeError('Source has local changes; refusing update/revert. Use configure/build directly')
            verify_automate(root)
        if args.phase == 'build':
            require_helper_packaging(root)
            sample = source_paths(root)[1] / LOCK['sample_path']
            if hashlib.sha256(sample.read_bytes()).hexdigest() != LOCK['sample_patched_sha256']:
                raise RuntimeError('Dedicated test-Profile/runtime guard is missing; run patch stage')
            reservation = HERE.parent / 'engine-reservation/native-reservation.patch'
            if subprocess.run(['git', 'apply', '--reverse', '--check', str(reservation)],
                              cwd=source_paths(root)[0], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode:
                raise RuntimeError('Reservation patch is missing or changed; run/review patch stage')
            args_file = source_paths(root)[0] / 'out' / LOCK['configuration'] / 'args.gn'
            contents = args_file.read_text()
            for expected in ('is_component_build=true', 'is_debug=true', 'target_cpu="arm64"', 'symbol_level=0'):
                if expected not in contents.replace(' ', ''):
                    raise RuntimeError('Generated build configuration differs: ' + expected)
        guarded_run(command, cwd, environment(root), root / ('logs/' + args.phase + '.log'),
                    root, LOCK['reserve_bytes'])
        if args.phase == 'bootstrap':
            check_repo(root / 'depot_tools', LOCK['depot_tools_revision'], LOCK['depot_tools_url'])
            depot = root / 'depot_tools'
            marker = depot / 'python3_bin_reldir.txt'
            if not marker.is_file():
                raise RuntimeError('Python bootstrap exited without its interpreter marker')
            relative = Path(marker.read_text().strip())
            interpreter = (depot / relative / 'python3').resolve()
            if relative.is_absolute() or not interpreter.is_relative_to(depot.resolve()) or not os.access(interpreter, os.X_OK):
                raise RuntimeError('Python bootstrap interpreter is missing or outside pinned tooling')
        if args.phase == 'checkout':
            verify_source(root)
            if not (root / 'source/chromium/.gclient_entries').is_file() or not source_paths(root)[1].is_dir():
                raise RuntimeError('Checkout command exited but dependency manifest/embedded CEF is absent')
            (root / CHECKOUT_MARKER).write_text(json.dumps({'pins_sha256': pins_digest(),
                                                          'command_exit_code': 0,
                                                          'completed': time.time()}, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, BlockingIOError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    except KeyboardInterrupt:
        print('Interrupted; owned command stopped and files preserved', file=sys.stderr)
        raise SystemExit(130)
