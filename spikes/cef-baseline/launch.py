#!/usr/bin/env python3
"""Launch only the pinned stock client with a disposable cache Profile."""
import argparse
import json
import os
import subprocess
from pathlib import Path
VERSION = '156.0.14+g4fa4ab5+chromium-156.0.8078.48'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--extension', action='append', default=[], type=Path)
parser.add_argument('--probe-library', type=Path)
parser.add_argument('--url', default='chrome://extensions')
parser.add_argument('--sample', default='cefclient', choices=['cefclient','cefsimple'])
parser.add_argument('--native', action='store_true', help='Use Chrome native window instead of Views hosting')
parser.add_argument('--built', action='store_true', help='Launch source-built stock cefclient instead of prebuilt client')
parser.add_argument('--profile', default='profile-a', choices=['profile-a', 'profile-b'])
args = parser.parse_args()
cache = Path.home() / '.cache/bato/cef-baseline'
pid_file = cache / 'baseline.pid'
if pid_file.exists():
    try:
        os.kill(int(pid_file.read_text()), 0)
    except (ProcessLookupError, ValueError):
        pass
    else:
        raise SystemExit('A recorded spike process is still running; close it before relaunching.')
if args.sample == 'cefsimple' and not args.built:
    raise SystemExit('cefsimple requires --built')
app = (cache / f'build/tests/{args.sample}/Release/{args.sample}.app/Contents/MacOS/{args.sample}') if args.built else (cache / f'cef_binary_{VERSION}_macosarm64_client/Release/cefclient.app/Contents/MacOS/cefclient')
if not app.is_file():
    raise SystemExit('Run prepare.py first')
command = [str(app), ('--use-native' if args.native else '--use-views'), '--cache-path=' + str(cache / args.profile), '--remote-debugging-port=9223', '--remote-debugging-address=127.0.0.1', '--force-renderer-accessibility', '--url=' + args.url, '--enable-logging=stderr']
if args.extension:
    for extension in args.extension:
        if not (extension / 'manifest.json').is_file():
            raise SystemExit(f'Missing extension manifest: {extension}')
    command.append('--load-extension=' + ','.join(str(p.resolve()) for p in args.extension))
environment = os.environ.copy()
if args.probe_library:
    if not args.probe_library.is_file():
        raise SystemExit('Missing native probe library')
    environment.update(BATO_NATIVE_PROBE='1', BATO_NATIVE_PROBE_AUTOTEST='1', DYLD_INSERT_LIBRARIES=str(args.probe_library.resolve()))
with (cache / 'baseline.log').open('w') as output:
    process = subprocess.Popen(command, cwd=cache, env=environment, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
(cache / 'baseline.pid').write_text(str(process.pid))
(cache / 'launch-args.json').write_text(json.dumps(command, indent=2))
print(f'PID {process.pid}; logs in {cache}/baseline.log; close the previous spike before relaunching.')
