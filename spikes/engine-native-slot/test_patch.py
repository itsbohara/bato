"""Real overlay round-trip on copied exact targets; source checkout stays read-only."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('slot_check', HERE / 'check.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class NativeSlotPatchTest(unittest.TestCase):
    def test_tampered_artifact_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copyfile(HERE / 'manifest.json', root / 'manifest.json')
            (root / 'engine.patch').write_bytes((HERE / 'engine.patch').read_bytes() + b'changed\n')
            with self.assertRaisesRegex(RuntimeError, 'provenance'):
                check.load(root)

    @unittest.skipUnless(check.DEFAULT_SOURCE.is_dir(), 'pinned source unavailable')
    def test_real_round_trip_and_partial_refusal(self):
        manifest, patch = check.load()
        check.inspect(check.DEFAULT_SOURCE, manifest)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for item in manifest['files']:
                relative = check.relative(item)
                source = check.DEFAULT_SOURCE / relative
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if source.exists():
                    shutil.copyfile(source, target)
            if check.inspect(root, manifest) == 'patched':
                subprocess.run(['git', 'apply', '--reverse', str(patch)], cwd=root, check=True)
            original = {check.relative(item): (root / check.relative(item)).read_bytes()
                        if (root / check.relative(item)).exists() else None for item in manifest['files']}
            subprocess.run(['git', 'apply', str(patch)], cwd=root, check=True)
            self.assertEqual(check.inspect(root, manifest), 'patched')
            new_header = root / 'cef/include/internal/bato_native_slot.h'
            new_header.unlink()
            with self.assertRaisesRegex(RuntimeError, 'partially'):
                check.inspect(root, manifest)
            new_header.write_bytes((HERE / 'bato_native_slot.h').read_bytes())
            subprocess.run(['git', 'apply', '--reverse', str(patch)], cwd=root, check=True)
            self.assertEqual(check.inspect(root, manifest), 'original')
            for relative, before in original.items():
                target = root / relative
                self.assertEqual(target.read_bytes() if target.exists() else None, before)


if __name__ == '__main__':
    unittest.main()
