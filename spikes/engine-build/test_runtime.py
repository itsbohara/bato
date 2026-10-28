"""Read-only runtime-plan failure gates; no engine or browser is launched."""
import importlib.util
import fcntl
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('bato_runtime', HERE / 'runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeGateTest(unittest.TestCase):
    def test_build_gate_rejects_running_failed_or_wrong_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'logs').mkdir()
            command, _ = runtime.engine.stage_command('build', root)
            good = dict(phase_log='build.log', command=command, running=False,
                        exit_code=0, finished=2, started=1)
            for change in ({'running': True}, {'exit_code': 1}, {'phase_log': 'configure.log'},
                           {'command': ['cefsimple']}, {'cleanup_error': 'group alive'},
                           {'stopped_for_disk_reserve': True}, {'finished': None}):
                with self.subTest(change=change):
                    (root / 'logs/run-state.json').write_text(json.dumps(good | change))
                    with self.assertRaisesRegex(RuntimeError, 'successful exact engine build'):
                        runtime.require_build(root)
            (root / 'logs/run-state.json').write_text(json.dumps(good))
            runtime.require_build(root)

    def test_gn_comments_do_not_satisfy_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve()
            settings = ('is_component_build=true\nis_debug=true\ntarget_cpu="arm64"\n'
                        'symbol_level=0\nuse_remoteexec=false\nuse_system_xcode=true\n')
            (output / 'args.gn').write_text(settings)
            runtime.require_configuration(output)
            (output / 'args.gn').write_text(settings.replace('target_cpu=', '# target_cpu='))
            with self.assertRaisesRegex(RuntimeError, 'target_cpu'):
                runtime.require_configuration(output)
            (output / 'args.gn').write_text(settings + 'target_cpu="x64"\n')
            with self.assertRaisesRegex(RuntimeError, 'Duplicate'):
                runtime.require_configuration(output)

    def test_dependency_resolution_and_missing_or_external_library(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve()
            main, library = output / 'app/main', output / 'libunit.dylib'
            main.parent.mkdir()
            main.touch()
            library.touch()
            main_load = ('Load command 0\n cmd LC_RPATH\n path @loader_path/.. (offset 12)\n'
                         'Load command 1\n cmd LC_LOAD_DYLIB\n name @rpath/libunit.dylib (offset 24)\n'
                         'Load command 2\n cmd LC_LOAD_DYLIB\n name /usr/lib/libSystem.B.dylib (offset 24)\n')
            with mock.patch.object(runtime.engine, 'command_output', return_value='arm64'):
                inspected = lambda path: main_load if path == main else ''
                checked = runtime.dependency_closure([(main, (main,))], output, inspect=inspected)
                self.assertEqual(checked, ['app/main', 'libunit.dylib'])
                library.unlink()
                with self.assertRaisesRegex(RuntimeError, 'Unresolved'):
                    runtime.dependency_closure([(main, (main,))], output, inspect=inspected)
                external = output.parent / ('outside-' + output.name)
                external.touch()
                try:
                    library.symlink_to(external)
                    with self.assertRaisesRegex(RuntimeError, 'escapes'):
                        runtime.dependency_closure([(main, (main,))], output, inspect=inspected)
                finally:
                    external.unlink()

    def test_wrong_architecture_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve()
            main = output / 'main'
            main.touch()
            with mock.patch.object(runtime.engine, 'command_output', return_value='x86_64'):
                with self.assertRaisesRegex(RuntimeError, 'ARM64-only'):
                    runtime.dependency_closure([(main, (main,))], output, inspect=lambda _: '')

    def test_profile_must_be_fresh_and_not_symlinked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            profile = runtime.fresh_profile(root, False)
            profile.mkdir(parents=True)
            self.assertEqual(runtime.fresh_profile(root, False), profile)
            (profile / 'unknown-provider-data').touch()
            with self.assertRaisesRegex(RuntimeError, 'already contains data'):
                runtime.fresh_profile(root, False)
            reserved = root / 'runtime/profiles/reservation-mock-v1'
            reserved.symlink_to(profile, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, 'symlinked'):
                runtime.fresh_profile(root, True)

    def test_artifacts_follow_selected_angle_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve()
            app = output / 'cefsimple.app'
            main = app / 'Contents/MacOS/cefsimple'
            main.parent.mkdir(parents=True)
            main.touch()
            main.chmod(0o700)
            for suffix in runtime.HELPERS:
                name = 'cefsimple Helper' + suffix
                helper = app / 'Contents/Frameworks' / (name + '.app') / 'Contents/MacOS' / name
                helper.parent.mkdir(parents=True)
                helper.touch()
                helper.chmod(0o700)
            graph = output / 'build.ninja'
            graph.write_text('')
            _, roots = runtime.artifact_images(output)
            self.assertEqual({p.name for p in roots[-1][1]},
                             {'libvulkan.dylib', 'libvk_swiftshader.dylib', 'libcef_sandbox.dylib'})
            graph.write_text('build cef_framework_angle_binaries: phony phony/cef/cef_framework_angle_binaries\n')
            _, roots = runtime.artifact_images(output)
            self.assertEqual({p.name for p in roots[-1][1]},
                             {'libvulkan.dylib', 'libvk_swiftshader.dylib', 'libcef_sandbox.dylib',
                              'libEGL.dylib', 'libGLESv2.dylib'})

    def test_active_workspace_lock_refuses_before_artifact_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'run.lock').touch()
            with (root / 'run.lock').open('r') as lock, \
                    mock.patch.object(runtime.engine, 'preflight'), \
                    mock.patch.object(runtime.engine, 'require_marker'), \
                    mock.patch.object(runtime, 'require_build') as build:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(RuntimeError, 'workspace command is active'):
                    runtime.preview(root)
                build.assert_not_called()

    def test_preview_has_only_fixed_flags_and_no_writes_or_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'run.lock').touch()
            output = root / 'source/chromium/src/out' / runtime.engine.LOCK['configuration']
            executable = output / 'cefsimple.app/Contents/MacOS/cefsimple'
            with mock.patch.object(runtime.engine, 'preflight'), \
                    mock.patch.object(runtime.engine, 'require_marker'), \
                    mock.patch.object(runtime, 'require_build'), \
                    mock.patch.object(runtime.engine, 'require_checkout'), \
                    mock.patch.object(runtime.engine, 'verify_source'), \
                    mock.patch.object(runtime, 'require_patches'), \
                    mock.patch.object(runtime, 'require_configuration'), \
                    mock.patch.object(runtime, 'artifact_images', return_value=(executable, [])), \
                    mock.patch.object(runtime, 'dependency_closure', return_value=[]), \
                    mock.patch.object(runtime.subprocess, 'Popen') as launch:
                before = list(root.rglob('*'))
                control, reserved = runtime.preview(root), runtime.preview(root, True)
                self.assertEqual(before, list(root.rglob('*')))
                self.assertNotIn('--bato-native-reservation', control['command'])
                self.assertIn('--bato-native-reservation', reserved['command'])
                self.assertNotEqual(control['fresh_test_profile'], reserved['fresh_test_profile'])
                self.assertEqual(control['command'][1:3], ['--use-native', '--use-mock-keychain'])
                self.assertIn('--url=http://127.0.0.1:18765/login.html', control['command'])
                self.assertFalse(any('remote-debugging' in flag for flag in control['command']))
                launch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
