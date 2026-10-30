"""Overlay mutation/provenance tests on disposable source files only."""
import difflib
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import native_slot as slot


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


class NativeSlotTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = slot.engine.source_paths(self.root)[0]
        self.artifacts = self.root / 'artifacts'
        self.artifacts.mkdir()
        self.files = [('chrome/a.cc', 'before\n', 'after\n'),
                      ('cef/new.h', None, 'new header\n')]
        for name, (relative, before, after) in zip(('engine', 'client'), self.files):
            target = self.source / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if before is not None:
                target.write_text(before)
            patch = ''.join(difflib.unified_diff(
                before.splitlines(True) if before else [], after.splitlines(True),
                fromfile='a/' + relative if before else '/dev/null', tofile='b/' + relative))
            (self.artifacts / (name + '.patch')).write_text(patch)
            manifest = dict(schema=1, cef_revision=slot.engine.LOCK['cef_revision'],
                chromium_commit=slot.engine.LOCK['chromium_commit'], patch_sha256=sha(patch),
                files=[dict(root='cef' if relative.startswith('cef/') else 'chromium',
                    path=relative.removeprefix('cef/'), original_sha256=sha(before) if before else None,
                    patched_sha256=sha(after))])
            path = self.artifacts / ('manifest.json' if name == 'engine' else 'client.json')
            path.write_text(json.dumps(manifest))
        patcher = mock.patch.object(slot, 'ARTIFACTS', self.artifacts)
        patcher.start()
        self.addCleanup(patcher.stop)
        protected = mock.patch.object(slot, 'protected_base', return_value={'chrome/a.cc': sha('before\n')})
        protected.start()
        self.addCleanup(protected.stop)

    def test_real_two_patch_apply_and_idempotence_preserve_unrelated(self):
        unrelated = self.source / 'unrelated'
        unrelated.write_text('keep')
        layers = slot.load_layers(self.source)
        self.assertEqual(slot.inspect(self.root, layers), 'original')
        slot.apply(self.root, layers)
        self.assertEqual(slot.inspect(self.root, layers), 'patched')
        with mock.patch.object(slot.subprocess, 'run') as run:
            slot.apply(self.root, layers)
            run.assert_not_called()
        self.assertEqual(unrelated.read_text(), 'keep')

    def test_new_file_collision_and_mixed_state_preserved(self):
        target = self.source / 'cef/new.h'
        target.write_text('unrelated existing header')
        layers = slot.load_layers(self.source)
        with self.assertRaisesRegex(RuntimeError, 'source changed'):
            slot.apply(self.root, layers)
        self.assertEqual((self.source / 'chrome/a.cc').read_text(), 'before\n')
        target.write_text('new header\n')
        with self.assertRaisesRegex(RuntimeError, 'partially applied'):
            slot.apply(self.root, layers)
        self.assertEqual(target.read_text(), 'new header\n')

    def test_staged_repository_source_drift_is_refused(self):
        repository = self.root / 'repository'
        repository.mkdir()
        original = repository / 'Page.swift'
        original.write_text('new header\n')
        manifest_path = self.artifacts / 'client.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['source_mirrors'] = {'Page.swift': 'new.h'}
        manifest_path.write_text(json.dumps(manifest))
        with mock.patch.object(slot, 'REPOSITORY', repository):
            slot.load_layers(self.source)
            original.write_text('newer application source\n')
            with self.assertRaisesRegex(RuntimeError, 'staged source differs'):
                slot.load_layers(self.source)
        self.assertFalse((self.source / 'cef/new.h').exists())

    def test_tampered_patch_and_escaping_target_refused(self):
        patch = self.artifacts / 'engine.patch'
        patch.write_text(patch.read_text() + 'tampered')
        with self.assertRaisesRegex(RuntimeError, 'provenance'):
            slot.load_layers(self.source)
        manifest_path = self.artifacts / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['patch_sha256'] = slot.digest(patch)
        manifest['files'][0]['path'] = '../escape'
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(RuntimeError, 'Unsafe'):
            slot.load_layers(self.source)

    def test_base_chain_mismatch_refused_before_any_mutation(self):
        layers = slot.load_layers(self.source)
        with mock.patch.object(slot, 'protected_base', return_value={'chrome/a.cc': '0' * 64}):
            with self.assertRaisesRegex(RuntimeError, 'preserve reviewed base'):
                slot.apply(self.root, layers)
        self.assertFalse((self.source / 'cef/new.h').exists())

    def test_second_dry_run_failure_leaves_first_file_unchanged(self):
        layers = slot.load_layers(self.source)
        calls = 0
        real_run = slot.subprocess.run
        def run(command, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise slot.subprocess.CalledProcessError(1, command)
            return real_run(command, **kwargs)
        with mock.patch.object(slot.subprocess, 'run', side_effect=run):
            with self.assertRaises(slot.subprocess.CalledProcessError):
                slot.apply(self.root, layers)
        self.assertEqual((self.source / 'chrome/a.cc').read_text(), 'before\n')
        self.assertFalse((self.source / 'cef/new.h').exists())


if __name__ == '__main__':
    unittest.main()
