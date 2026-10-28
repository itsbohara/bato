#!/usr/bin/env python3
"""Launch only the dedicated three-window synthetic context diagnostic."""
from pathlib import Path
import os
import subprocess

cache = Path.home() / '.cache/bato/profile-contexts'
app = cache / 'build/tests/cefsimple/Release/cefsimple.app/Contents/MacOS/cefsimple'
if not app.is_file():
    raise SystemExit('Build this context diagnostic first')
pid_file = cache / 'runtime.pid'
if pid_file.exists():
    try:
        os.kill(int(pid_file.read_text()), 0)
    except (ProcessLookupError, ValueError):
        pass
    else:
        raise SystemExit('Recorded context process still exists; close it before restarting')
environment = os.environ.copy()
environment.pop('DYLD_INSERT_LIBRARIES', None)
args = [str(app), '--use-native', '--use-mock-keychain',
        '--cache-path=' + str(cache / 'profiles'),
        '--force-renderer-accessibility', '--enable-logging=stderr']
with (cache / 'runtime.log').open('w') as output:
    process = subprocess.Popen(args, cwd=cache, env=environment,
                               stdout=output, stderr=subprocess.STDOUT,
                               start_new_session=True)
pid_file.write_text(str(process.pid))
print('Owned context diagnostic PID', process.pid)
print('Three synthetic windows: A1/A2 share a storage context; B requests isolation.')
print('Mock Keychain is test-only; these Profiles must never contain real secrets.')
