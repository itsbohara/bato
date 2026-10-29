"""Hash-locked multi-file patch behavior; no real engine tree is changed."""
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('quit_engine', Path(__file__).with_name('engine.py'))
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class QuitPatchTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cef = engine.source_paths(self.root)[1]
        self.patch_dir = self.root / 'reviewed-patch'
        self.patch_dir.mkdir()
        self.files = {'tests/cefsimple/cefsimple_mac.mm': ('guard retained\n', 'guard retained\nquit opt-in\n'),
                      'libcef/quit.cc': ('original dispatch\n', 'reviewed dispatch\n')}
        entries, patches = [], []
        for name, (before, after) in self.files.items():
            target = self.cef / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(before)
            entries.append(dict(path=name, original_sha256=digest(before), patched_sha256=digest(after)))
            patches.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                               fromfile='a/' + name, tofile='b/' + name))
        patch = ''.join(patches)
        (self.patch_dir / 'quit.patch').write_text(patch)
        self.manifest = dict(schema=1, cef_revision=engine.LOCK['cef_revision'],
                             patch_sha256=digest(patch), files=entries)
        self.save_manifest()
        startup_entries, startup_patches = [], []
        for startup_path in ('chrome/browser/chrome_browser_main_mac.mm',
                             'chrome/browser/chrome_browser_application_mac.mm'):
            target = engine.source_paths(self.root)[0] / startup_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('startup before\n')
            startup_entries.append(dict(path=startup_path,
                original_sha256=digest('startup before\n'), patched_sha256=digest('startup after\n')))
            startup_patches.extend(difflib.unified_diff(['startup before\n'], ['startup after\n'],
                fromfile='a/' + startup_path, tofile='b/' + startup_path))
        self.startup_target = target
        startup_patch = ''.join(startup_patches)
        (self.patch_dir / 'startup.patch').write_text(startup_patch)
        (self.patch_dir / 'startup.json').write_text(json.dumps(dict(
            schema=1, chromium_commit=engine.LOCK['chromium_commit'], files=startup_entries,
            patch_sha256=digest(startup_patch))))
        self.directory_patch = mock.patch.object(engine, 'QUIT_DIR', self.patch_dir)
        self.directory_patch.start()
        self.addCleanup(self.directory_patch.stop)
        self.lock_patch = mock.patch.dict(engine.LOCK, sample_patched_sha256=digest('guard retained\n'))
        self.lock_patch.start()
        self.addCleanup(self.lock_patch.stop)

    def save_manifest(self):
        (self.patch_dir / 'manifest.json').write_text(json.dumps(self.manifest))

    def test_real_apply_is_idempotent_and_preserves_unrelated_file(self):
        unrelated = self.cef / 'unrelated'
        unrelated.write_text('keep')
        engine.patch_quit(self.root)
        engine.require_quit_patch(self.root)
        with mock.patch.object(engine.subprocess, 'run') as run:
            engine.patch_quit(self.root)
            run.assert_not_called()
        self.assertEqual(unrelated.read_text(), 'keep')
        self.assertEqual(self.startup_target.read_text(), 'startup after\n')
        for name, (_, after) in self.files.items():
            self.assertEqual((self.cef / name).read_text(), after)

    def test_tampered_patch_is_refused_without_mutation(self):
        with (self.patch_dir / 'quit.patch').open('a') as patch:
            patch.write('unreviewed')
        with self.assertRaisesRegex(RuntimeError, 'provenance'):
            engine.patch_quit(self.root)
        for name, (before, _) in self.files.items():
            self.assertEqual((self.cef / name).read_text(), before)

    def test_partial_or_changed_tree_is_preserved_and_refused(self):
        sample = self.cef / engine.LOCK['sample_path']
        sample.write_text(self.files[engine.LOCK['sample_path']][1])
        with self.assertRaisesRegex(RuntimeError, 'partially patched'):
            engine.patch_quit(self.root)
        self.assertEqual((self.cef / 'libcef/quit.cc').read_text(), 'original dispatch\n')
        with self.assertRaisesRegex(RuntimeError, 'missing or changed'):
            engine.require_quit_patch(self.root)

    def test_escaping_target_and_missing_original_guard_are_refused(self):
        self.manifest['files'][1]['path'] = '../outside'
        self.save_manifest()
        with self.assertRaisesRegex(RuntimeError, 'escapes'):
            engine.patch_quit(self.root)
        self.manifest['files'][1]['path'] = 'libcef/quit.cc'
        self.manifest['files'][0]['original_sha256'] = '0' * 64
        self.save_manifest()
        with self.assertRaisesRegex(RuntimeError, 'runtime guard'):
            engine.patch_quit(self.root)

    def test_tampered_or_partial_startup_refuses_before_cef_mutation(self):
        self.startup_target.write_text('startup after\n')
        with self.assertRaisesRegex(RuntimeError, 'partially patched'):
            engine.patch_quit(self.root)
        for name, (before, _) in self.files.items():
            self.assertEqual((self.cef / name).read_text(), before)
        self.startup_target.write_text('startup before\n')
        with (self.patch_dir / 'startup.patch').open('a') as patch:
            patch.write('unreviewed')
        with self.assertRaisesRegex(RuntimeError, 'provenance'):
            engine.patch_quit(self.root)


if __name__ == '__main__':
    unittest.main()
