#!/usr/bin/env python3
"""GN-only Swift library action, scoped to the bounded SSD component output."""
from pathlib import Path
import subprocess
import sys


def main():
    source, output = (Path(value).resolve() for value in sys.argv[1:])
    tree = source.parents[3]
    expected_source = tree / 'cef/tests/cefsimple/NativeSlot.swift'
    expected_output = tree / 'out/Debug_GN_arm64/gen/cef/libBatoNativeSlot.dylib'
    if source != expected_source or output != expected_output:
        raise SystemExit('Refusing unexpected native-slot Swift source/output')
    output.parent.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    modules = output.parent / 'bato-modules'
    modules.mkdir(exist_ok=True)
    common = ['xcrun', 'swiftc', '-parse-as-library', '-target', 'arm64-apple-macos13.0',
              '-sdk', sdk, '-module-cache-path', str(output.parent / 'native-slot-module-cache'),
              '-I', str(modules)]
    objects = []
    for name, filenames in [('BatoCore', ['BrowserState.swift', 'CommandBar.swift', 'Essentials.swift', 'SettingsModel.swift', 'DefaultBrowser.swift',
                                        'DownloadsModel.swift', 'DownloadsController.swift', 'Archive.swift']),
                           ('BatoPersistence', ['OrganizationStore.swift', 'BackupStore.swift', 'SessionRecovery.swift']),
                           ('BatoRuntime', ['PageRuntime.swift', 'PeekSession.swift', 'EssentialsRuntime.swift']),
                           ('BatoImport', ['ArcSidebarParser.swift', 'ArcStaging.swift', 'ImportPlan.swift',
                                           'ArcSourceReader.swift', 'ImportTransaction.swift']),
                           ('BatoBlocking', ['BlockedCounters.swift', 'BlockingHostExports.swift', 'BlockingProfiles.swift', 'BlockingService.swift', 'BlockingSettings.swift', 'BlockingSettingsStore.swift', 'FilterListUpdater.swift', 'URLSessionListFetcher.swift', 'UBlockListsChoice.swift']),
                           ('BatoBrowserUI', ['NativeWorkspaceController.swift', 'CommandBarController.swift',
                                              'ArcImportController.swift', 'BlockingControls.swift',
                                              'SettingsWindowController.swift', 'SidebarStyle.swift', 'RecoveryController.swift',
                                              'DownloadsButton.swift', 'DownloadsPopover.swift', 'DownloadsSidebar.swift',
                                              'ArchiveController.swift', 'ArchiveSheet.swift', 'UBlockOffer.swift'])]:
        module_sources = [str(source.parent / 'bato' / name / filename) for filename in filenames]
        obj = modules / (name + '.o')
        subprocess.run(common + ['-swift-version', '6', '-whole-module-optimization',
                                 '-emit-object', '-emit-module', '-module-name', name,
                                 '-emit-module-path', str(modules / (name + '.swiftmodule')),
                                 *module_sources, '-o', str(obj)], check=True)
        objects.append(str(obj))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-emit-library',
                    '-module-name', 'BatoNativeSlot', '-target', 'arm64-apple-macos13.0',
                    '-sdk', sdk, '-module-cache-path', str(output.parent / 'native-slot-module-cache'),
                    '-Xlinker', '-install_name', '-Xlinker', '@rpath/libBatoNativeSlot.dylib',
                    '-I', str(modules), str(source), str(source.parent / 'WorkspaceSlot.swift'),
                    *objects, '-o', str(output)], check=True)


if __name__ == '__main__':
    main()
