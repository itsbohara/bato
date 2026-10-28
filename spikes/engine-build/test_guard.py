"""Exercise real process ownership/reserve behavior without using the SSD."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('bato_engine', Path(__file__).with_name('engine.py'))
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class ReserveGuardTest(unittest.TestCase):
    def test_initial_bookkeeping_failure_still_stops_child(self):
        for failure in ('state-write', 'print'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                children = []
                actual_popen = subprocess.Popen
                actual_write = Path.write_text
                first_write = True
                def spawn(*args, **kwargs):
                    child = actual_popen(*args, **kwargs)
                    children.append(child)
                    return child
                def write(path, *args, **kwargs):
                    nonlocal first_write
                    if path.name == 'run-state.json' and first_write:
                        first_write = False
                        raise OSError('initial state failure')
                    return actual_write(path, *args, **kwargs)
                with mock.patch.object(engine.subprocess, 'Popen', side_effect=spawn):
                    if failure == 'state-write':
                        with mock.patch.object(Path, 'write_text', write):
                            with self.assertRaisesRegex(OSError, 'initial state failure'):
                                engine.guarded_run([sys.executable, '-c', 'import time; time.sleep(20)'],
                                                   root, None, root / 'test.log', root,
                                                   reserve=20, free_fn=lambda: 100)
                    else:
                        with mock.patch.object(engine, 'print', create=True,
                                               side_effect=BrokenPipeError('initial print failure')):
                            with self.assertRaisesRegex(BrokenPipeError, 'initial print failure'):
                                engine.guarded_run([sys.executable, '-c', 'import time; time.sleep(20)'],
                                                   root, None, root / 'test.log', root,
                                                   reserve=20, free_fn=lambda: 100)
                self.assertEqual(len(children), 1)
                self.assertIsNotNone(children[0].poll())
                self.assertFalse(engine.group_alive(children[0].pid))

    def run_descendant_case(self, leader_exits):
        """A TERM-ignoring child must not escape cleanup when its leader exits."""
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(20)'],
                                     start_new_session=True)
        cleanup = engine.terminate_owned
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                ready = root / 'child-ready'
                child = ('import os,signal,time; from pathlib import Path; '
                         'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                         f'Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(20)')
                parent = ('import subprocess,sys,time; from pathlib import Path; '
                          f'subprocess.Popen([sys.executable,"-c",{child!r}]); '
                          f'\nwhile not Path({str(ready)!r}).exists(): time.sleep(.01)\n' +
                          ('sys.exit(0)' if leader_exits else 'time.sleep(20)'))
                free = (lambda: 100) if leader_exits else (lambda: 19 if ready.exists() else 100)
                with mock.patch.object(engine, 'terminate_owned',
                                       side_effect=lambda p: cleanup(p, term_timeout=.1, kill_timeout=2)):
                    if leader_exits:
                        engine.guarded_run([sys.executable, '-c', parent], root, None,
                                           root / 'test.log', root, reserve=20,
                                           interval=.02, free_fn=free)
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'files preserved'):
                            engine.guarded_run([sys.executable, '-c', parent], root, None,
                                               root / 'test.log', root, reserve=20,
                                               interval=.02, free_fn=free)
                child_pid = int(ready.read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)
                self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait()

    def test_term_ignoring_descendant_is_stopped(self):
        self.run_descendant_case(False)

    def test_exited_leader_does_not_skip_descendant_cleanup(self):
        self.run_descendant_case(True)

    def test_reserve_refuses_launch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            touched = root / 'should-not-exist'
            command = [sys.executable, '-c', f'open({str(touched)!r}, "w").close()']
            with self.assertRaisesRegex(RuntimeError, 'before child launch'):
                engine.guarded_run(command, root, None, root / 'test.log', root,
                                   reserve=20, free_fn=lambda: 19)
            self.assertFalse(touched.exists())

    def test_reserve_stops_owned_group_preserves_other_process(self):
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(20)'],
                                     start_new_session=True)
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                preserved = root / 'existing-data'
                preserved.write_text('keep')
                values = iter([100, 19])
                with self.assertRaisesRegex(RuntimeError, 'files preserved'):
                    engine.guarded_run([sys.executable, '-c', 'import time; time.sleep(20)'],
                                       root, None, root / 'test.log', root,
                                       reserve=20, interval=.02, free_fn=lambda: next(values))
                state = json.loads((root / 'run-state.json').read_text())
                self.assertTrue(state['stopped_for_disk_reserve'])
                self.assertFalse(state['running'])
                self.assertIsNotNone(state['exit_code'])
                self.assertIsNone(unrelated.poll())
                self.assertEqual(preserved.read_text(), 'keep')
        finally:
            unrelated.terminate()
            unrelated.wait()

    def test_success_records_exit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine.guarded_run([sys.executable, '-c', 'print("done")'], root, None,
                               root / 'test.log', root, reserve=20, interval=.02,
                               free_fn=lambda: 100)
            state = json.loads((root / 'run-state.json').read_text())
            self.assertEqual(state['exit_code'], 0)
            self.assertFalse(state['running'])
            self.assertIn('done', (root / 'test.log').read_text())


class ProvenanceTest(unittest.TestCase):
    def test_modified_automate_script_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / 'bootstrap/automate-git.py'
            script.parent.mkdir()
            script.write_text('print("reviewed")\n')
            digest = hashlib.sha256(script.read_bytes()).hexdigest()
            with mock.patch.dict(engine.LOCK, {'automate_sha256': digest}):
                engine.verify_automate(root)
                script.write_text('print("changed")\n')
                with self.assertRaisesRegex(RuntimeError, 'changed'):
                    engine.verify_automate(root)

    def test_partial_tree_with_version_never_runs_automate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            version = root / 'source/chromium/src/chrome/VERSION'
            version.parent.mkdir(parents=True)
            version.write_text('MAJOR=156\nMINOR=0\nBUILD=8078\nPATCH=48\n')
            (root / engine.MARKER).write_text(json.dumps(engine.LOCK))
            with mock.patch.object(sys, 'argv', ['engine.py', 'checkout', '--root', str(root), '--execute']), \
                    mock.patch.object(engine, 'preflight'), \
                    mock.patch.object(engine, 'verify_source'), \
                    mock.patch.object(engine, 'guarded_run') as run:
                with self.assertRaisesRegex(RuntimeError, 'successful pinned checkout marker'):
                    engine.main()
                run.assert_not_called()

    def test_dirty_pinned_tooling_is_preserved_and_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True,
                                               stderr=subprocess.DEVNULL).strip()
            git('init')
            git('remote', 'add', 'origin', 'https://example.invalid/tool.git')
            (root / 'tool.py').write_text('original\n')
            git('add', 'tool.py')
            git('-c', 'user.name=Bato fixture', '-c', 'user.email=bato@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '-m', 'fixture')
            revision = git('rev-parse', 'HEAD')
            engine.check_repo(root, revision, 'https://example.invalid/tool.git')
            (root / 'tool.py').write_text('local edit\n')
            with self.assertRaisesRegex(RuntimeError, 'edits preserved'):
                engine.check_repo(root, revision, 'https://example.invalid/tool.git')
            self.assertEqual((root / 'tool.py').read_text(), 'local edit\n')


if __name__ == '__main__':
    unittest.main()
