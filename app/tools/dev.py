#!/usr/bin/env python3
"""Build/test the native organization preview with output confined to the SSD."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path('/Volumes/Mahesh/personal/bato-build/alpha-swift')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['test', 'build', 'run'])
    parser.add_argument('--output-root', type=Path, default=DEFAULT_ROOT)
    parser.add_argument('--state-directory', type=Path)
    args = parser.parse_args()
    root = args.output_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(root).free < 2 * 1024**3:
        parser.error('At least 2 GiB free is required for this small Swift package.')
    env = os.environ.copy()
    for name in ['module-cache', 'cache', 'tmp']:
        (root / name).mkdir(exist_ok=True)
    env['CLANG_MODULE_CACHE_PATH'] = str(root / 'module-cache')
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(root / 'module-cache')
    env['TMPDIR'] = str(root / 'tmp')
    common = ['--package-path', str(PACKAGE), '--scratch-path', str(root / 'build'),
              '--cache-path', str(root / 'cache')]
    subprocess.run(['swift', 'test' if args.command == 'test' else 'build',
                    *common, '--jobs', '2'], env=env, check=True)
    if args.command == 'test':
        return
    binary_dir = Path(subprocess.check_output(
        ['swift', 'build', *common, '--show-bin-path'], env=env, text=True).strip())
    bundle = root / 'Bato Shell Preview.app'
    contents = bundle / 'Contents'
    executable_dir = contents / 'MacOS'
    executable_dir.mkdir(parents=True, exist_ok=True)
    executable = executable_dir / 'BatoShell'
    shutil.copy2(binary_dir / 'BatoShell', executable)
    with (contents / 'Info.plist').open('wb') as handle:
        plistlib.dump({
            'CFBundleIdentifier': 'org.bato.shell-preview',
            'CFBundleName': 'Bato Shell Preview',
            'CFBundleDisplayName': 'Bato Shell Preview',
            'CFBundleExecutable': 'BatoShell',
            'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.0',
            'CFBundleVersion': '1',
            'LSMinimumSystemVersion': '15.0',
            'NSPrincipalClass': 'NSApplication',
            'NSHighResolutionCapable': True,
        }, handle)
    subprocess.run(['codesign', '--force', '--sign', '-', str(bundle)], check=True)
    print(bundle, flush=True)
    if args.command == 'run':
        command = [str(executable)]
        if args.state_directory:
            command += ['--state-directory', str(args.state_directory.resolve())]
        # A synchronous owned process: normal app Quit returns its actual status.
        raise SystemExit(subprocess.call(command, env=env, cwd=root))


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
