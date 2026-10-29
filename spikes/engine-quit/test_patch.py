"""Real patch round-trip in a temporary copy; never changes the source checkout."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('quit_check', HERE / 'check.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class QuitPatchTest(unittest.TestCase):
    def test_modified_patch_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copyfile(HERE / 'manifest.json', root / 'manifest.json')
            (root / 'quit.patch').write_bytes((HERE / 'quit.patch').read_bytes() + b'changed\n')
            with self.assertRaisesRegex(RuntimeError, 'patch hash differs'):
                check.load_manifest(root)
            shutil.copyfile(HERE / 'startup.json', root / 'startup.json')
            (root / 'startup.patch').write_bytes((HERE / 'startup.patch').read_bytes() + b'changed\n')
            with self.assertRaisesRegex(RuntimeError, 'patch hash differs'):
                check.load_startup_manifest(root)

    @unittest.skipUnless(check.DEFAULT_SOURCE.is_dir(), 'pinned external source checkout unavailable')
    def test_real_patch_round_trip_and_partial_or_changed_source_refusal(self):
        for source, (manifest, patch) in (
                (check.DEFAULT_SOURCE, check.load_manifest()),
                (check.DEFAULT_SOURCE.parent, check.load_startup_manifest())):
            with self.subTest(source=source):
                self.round_trip(source, manifest, patch)

    def round_trip(self, source, manifest, patch):
        check.inspect_files(source, manifest)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for item in manifest['files']:
                target = root / item['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / item['path'], target)
            if check.inspect_files(root, manifest) == 'patched':
                subprocess.run(['git', 'apply', '--reverse', str(patch)], cwd=root, check=True)
            self.assertEqual(check.inspect_files(root, manifest), 'original')
            original = {item['path']: (root / item['path']).read_bytes() for item in manifest['files']}
            subprocess.run(['git', 'apply', '--check', str(patch)], cwd=root, check=True)
            subprocess.run(['git', 'apply', str(patch)], cwd=root, check=True)
            self.assertEqual(check.inspect_files(root, manifest), 'patched')
            subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=root, check=True)
            first = manifest['files'][0]['path']
            patched = (root / first).read_bytes()
            (root / first).write_bytes(original[first])
            with self.assertRaisesRegex(RuntimeError, 'partially applied'):
                check.inspect_files(root, manifest)
            (root / first).write_bytes(patched)
            subprocess.run(['git', 'apply', '--reverse', str(patch)], cwd=root, check=True)
            self.assertEqual(check.inspect_files(root, manifest), 'original')
            for name, data in original.items():
                self.assertEqual((root / name).read_bytes(), data)
            (root / first).write_bytes(original[first] + b'changed\n')
            with self.assertRaisesRegex(RuntimeError, 'source hash differs'):
                check.inspect_files(root, manifest)


if __name__ == '__main__':
    unittest.main()
