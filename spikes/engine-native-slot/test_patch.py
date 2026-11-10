"""Real overlay round-trip on copied exact targets; source checkout stays read-only."""
import importlib.util
import re
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

    def test_patch_installs_canonical_abi_with_definitions(self):
        header = (HERE / 'bato_native_slot.h').read_text()
        added = [line[1:] for line in (HERE / 'engine.patch').read_text().splitlines()
                 if line.startswith('+') and not line.startswith('+++')]
        installed = '\n'.join(added)
        self.assertIn(header.rstrip('\n'), installed)
        exports = re.findall(r'CEF_EXPORT\s+\w+\s+(bato_native_slot_\w+)\(', header)
        self.assertIn('bato_native_slot_peek_present_v1', exports)
        self.assertIn('bato_native_slot_register_peek_interaction_callbacks_v1', exports)
        self.assertEqual(len(exports), 25)
        self.assertIn('bato_native_slot_set_layout_v1', exports)
        self.assertIn('bato_native_slot_present_split_v2', exports)
        self.assertIn('bato_native_slot_register_split_layout_callbacks_v1', exports)
        for name in exports:
            self.assertRegex(installed, r'extern "C" CEF_EXPORT \w+ ' + name + r'\(')

    def test_compact_top_row_policy(self):
        added = '\n'.join(line[1:] for line in (HERE / 'engine.patch').read_text().splitlines()
                          if line.startswith('+') and not line.startswith('+++'))
        self.assertIn('sidebar_owns_tabs = cef::NativeSidebarOwnsTabs(&browser_view_.get())', added)
        self.assertIn('(sidebar_right ? 0 : reserved_width) + kNativeCardMargin', added)
        self.assertIn('cef::NativeTopToolbarWidthFor(original_area.width())', added)
        self.assertIn('Inset(gfx::Insets::TLBR(top_row, reserved_width, 0, 0))', added)
        self.assertIn('leading_exclusion.vertical_padding', added)
        self.assertIn('cef::NativeSidebarOwnsTabs(this) ? cef::NativeTopStripHeight(this) : 44', added)
        self.assertNotIn('Inset(gfx::Insets::TLBR(44, reserved_width', added)

    def test_split_pane_toolbar_policy(self):
        added = '\n'.join(line[1:] for line in (HERE / 'engine.patch').read_text().splitlines()
                          if line.startswith('+') and not line.startswith('+++'))
        self.assertIn('constexpr int kNativePaneToolbarHeight = 40;', added)
        self.assertIn('constexpr int kNativePaneGap = 10;', added)
        self.assertIn('sizes.resize = HasNativePaneToolbars()', added)
        self.assertIn('? kNativePaneGap', added)
        self.assertIn('start_rect.Inset(gfx::Insets::TLBR(kNativePaneToolbarHeight, 0, 0, 0))', added)
        self.assertIn('SetNativePaneChrome(HasNativePaneToolbars())', added)
        self.assertIn('multi_contents->IsInSplitView()', added)
        self.assertIn('split_tabs::SplitTabLayout::kStacked', added)
        self.assertIn('kNativeSplitButtonSlot', added)


if __name__ == '__main__':
    unittest.main()
