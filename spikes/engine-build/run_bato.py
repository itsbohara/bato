#!/usr/bin/env python3
"""Open the packaged Bato.app through LaunchServices.

With no options the app starts on its alpha state (the paths package_app.py wrote into its
Info.plist: SSD runtime/alpha-state and runtime/profiles/alpha-v1). Test runs must name both a
state directory and a Profile cache so they never touch the alpha state.
"""
import argparse
import subprocess
import sys
from pathlib import Path

SSD = Path('/Volumes/Mahesh/personal/bato-build')
APP = SSD / 'dist/Bato.app'
NAMESPACE = SSD / 'runtime'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', nargs='?', help='web link to open in the running or starting app')
    parser.add_argument('--state', type=Path, help='test organization directory under SSD runtime/')
    parser.add_argument('--profile', type=Path, help='test Profile cache under SSD runtime/profiles/')
    args = parser.parse_args()
    if not (SSD / '.bato-engine-workspace.json').is_file() or not APP.is_dir():
        sys.exit(f'Mount the SSD and run package_app.py first: {APP}')
    command = ['open', '-a', str(APP)]
    if args.url:
        command.append(args.url)
    if args.state or args.profile:
        if not (args.state and args.profile):
            sys.exit('Test launches need both --state and --profile')
        for path in (args.state, args.profile):
            if not path.resolve().is_relative_to(NAMESPACE):
                sys.exit(f'{path} is outside {NAMESPACE}')
        command += ['--args', '--use-native', '--use-mock-keychain', f'--cache-path={args.profile.resolve()}',
                    '--url=about:blank', '--bato-native-slot', '--bato-native-reservation', '--bato-native-quit',
                    f'--bato-workspace-state={args.state.resolve()}']
    return subprocess.run(command).returncode


if __name__ == '__main__':
    sys.exit(main())
