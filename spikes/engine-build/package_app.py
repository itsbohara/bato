#!/usr/bin/env python3
"""Package the built engine app as Bato.app: rename, rebrand, icon, ad-hoc sign, verify.

The packaged copy is made from out/Debug_GN_arm64/cefsimple.app and never touches it. Everything
lands under the SSD dist directory; nothing is installed and no browser state is read or created.
See spikes/engine-native-slot/PACKAGING-RESULTS.md for the identity, state and signing decisions.
"""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runtime  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SSD = Path('/Volumes/Mahesh/personal/bato-build')
BUILD_OUTPUT = SSD / 'source/chromium/src/out/Debug_GN_arm64'
BUILT_APP = BUILD_OUTPUT / 'cefsimple.app'
DIST = SSD / 'dist'
APP_NAME = 'Bato'
OLD_NAME = 'cefsimple'
OLD_BUNDLE_ID = 'org.cef.cefsimple'
BUNDLE_ID = 'com.itsbohara.bato'
COPYRIGHT = 'Bato is MIT licensed. Chromium and CEF components keep their own licenses.'
ICON_SOURCE = REPO / 'spikes/engine-build/packaging/make_icon.swift'
ICON_OVERRIDE = REPO / 'spikes/engine-build/packaging/Bato.icns'
USAGE_DESCRIPTIONS = {
    'NSCameraUsageDescription': 'A website you opened is asking to use the camera.',
    'NSMicrophoneUsageDescription': 'A website you opened is asking to use the microphone.',
    'NSLocationUsageDescription': 'A website you opened is asking for your location.',
    'NSBluetoothAlwaysUsageDescription': 'A website you opened is asking to connect to a Bluetooth device.',
}

# The packaged app keeps its data under ~/Library/Application Support/Bato and uses the real
# keychain. cefsimple_mac.mm accepts that exact Profiles location only without the mock keychain,
# and SSD runtime/profiles/ only with it, so default_arguments adds the mock flag for SSD paths.
APPLICATION_SUPPORT = Path.home() / 'Library/Application Support/Bato'
ALPHA_PROFILE = APPLICATION_SUPPORT / 'Profiles'
ALPHA_STATE = APPLICATION_SUPPORT / 'State'


def default_arguments(profile, state):
    mock_keychain = ['--use-mock-keychain'] if Path(profile).is_relative_to(SSD) else []
    return ['--use-native', *mock_keychain, f'--cache-path={profile}', '--url=about:blank',
            '--bato-native-slot', '--bato-native-reservation', '--bato-native-quit',
            f'--bato-workspace-state={state}']


def run(command, quiet=False, **kwargs):
    if quiet:
        kwargs.update(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return subprocess.run([str(part) for part in command], check=True, **kwargs)


def read_version():
    marketing = (REPO / 'VERSION').read_text().strip()
    build = subprocess.run(['git', 'rev-list', '--count', 'HEAD'], cwd=REPO, capture_output=True, text=True)
    return marketing, build.stdout.strip() if build.returncode == 0 else '0'


def load_plist(path):
    with path.open('rb') as handle:
        return plistlib.load(handle)


def store_plist(path, content):
    with path.open('wb') as handle:
        plistlib.dump(content, handle)


def build_icon(work, icon):
    if icon:
        return Path(icon)
    if ICON_OVERRIDE.is_file():
        return ICON_OVERRIDE
    iconset = work / 'Bato.iconset'
    shutil.rmtree(iconset, ignore_errors=True)
    env = dict(os.environ, TMPDIR=str(SSD / 'tmp'))
    run(['swift', ICON_SOURCE, iconset], env=env)
    icns = work / 'Bato.icns'
    run(['iconutil', '-c', 'icns', iconset, '-o', icns])
    return icns


def bundle_component_libraries(app):
    """The engine is a component build: the executables resolve libc++_chrome and ~500 sibling
    dylibs through @rpath, which reaches Contents/Frameworks inside the bundle but otherwise only
    the build output directory. APFS clones keep this on the SSD without duplicating 5 GB."""
    _, images = runtime.artifact_images(BUILD_OUTPUT)
    needed = [name for name in runtime.dependency_closure(images, BUILD_OUTPUT)
              if '/' not in name and name.endswith('.dylib')]
    frameworks = app / 'Contents/Frameworks'
    for name in needed:
        if not (frameworks / name).exists():
            run(['cp', '-c', BUILD_OUTPUT / name, frameworks / name])
    return len(needed)


def rename_components(app):
    """CEF finds helpers as '<main executable name> Helper (<kind>)', so every name changes together."""
    contents = app / 'Contents'
    (contents / 'MacOS' / OLD_NAME).rename(contents / 'MacOS' / APP_NAME)
    for helper in sorted((contents / 'Frameworks').glob(f'{OLD_NAME} Helper*.app')):
        new_name = helper.name.replace(OLD_NAME, APP_NAME, 1)[:-len('.app')]
        old_name = helper.name[:-len('.app')]
        (helper / 'Contents/MacOS' / old_name).rename(helper / 'Contents/MacOS' / new_name)
        plist_path = helper / 'Contents/Info.plist'
        plist = load_plist(plist_path)
        plist['CFBundleExecutable'] = new_name
        plist['CFBundleName'] = new_name
        plist['CFBundleDisplayName'] = new_name
        plist['CFBundleIdentifier'] = plist['CFBundleIdentifier'].replace(OLD_BUNDLE_ID, BUNDLE_ID, 1)
        plist['CFBundleShortVersionString'], plist['CFBundleVersion'] = VERSION
        store_plist(plist_path, plist)
        helper.rename(helper.parent / f'{new_name}.app')


def rebrand_main(app, icon, defaults):
    plist_path = app / 'Contents/Info.plist'
    plist = load_plist(plist_path)
    plist.update({
        'CFBundleExecutable': APP_NAME, 'CFBundleName': APP_NAME, 'CFBundleDisplayName': APP_NAME,
        'CFBundleIdentifier': BUNDLE_ID, 'CFBundleIconFile': 'Bato.icns',
        'CFBundleShortVersionString': VERSION[0], 'CFBundleVersion': VERSION[1],
        'LSApplicationCategoryType': 'public.app-category.productivity',
        'NSHumanReadableCopyright': COPYRIGHT,
        'BatoDefaultArguments': defaults,
    })
    plist.update(USAGE_DESCRIPTIONS)
    store_plist(plist_path, plist)
    resources = app / 'Contents/Resources'
    (resources / f'{OLD_NAME}.icns').unlink()
    shutil.copyfile(icon, resources / 'Bato.icns')
    shutil.copyfile(REPO / 'NOTICES.md', resources / 'NOTICES.md')
    (resources / 'English.lproj/InfoPlist.strings').write_text(
        f'CFBundleName = "{APP_NAME}";\nCFBundleDisplayName = "{APP_NAME}";\n'
        f'NSHumanReadableCopyright = "{COPYRIGHT}";\n')


def is_macho(path):
    with path.open('rb') as handle:
        return handle.read(4) in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe')


def is_bundle(path):
    return path.suffix in ('.app', '.framework')


def sign(app):
    """Inside-out ad-hoc signing: loose Mach-O files, then nested bundles deepest first, then the app.

    A bundle's own executable is covered by signing the bundle; framework Versions/Current and
    other symlinks are skipped so nothing is signed twice.
    """
    loose, bundles = [], []
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            continue
        if path.is_dir() and is_bundle(path):
            bundles.append(path)
        elif path.is_file() and is_macho(path):
            parent_bundle = next((p for p in path.parents if is_bundle(p)), None)
            main_executable = parent_bundle and (path.parent.name in ('MacOS',)
                                                  or path.parent.name == 'A' and path.parent.parent.name == 'Versions')
            if not main_executable:
                loose.append(path)
    for path in loose:
        run(['codesign', '--force', '-s', '-', path], quiet=True)
    for path in sorted((b for b in bundles if b != app), key=lambda b: len(b.parts), reverse=True):
        run(['codesign', '--force', '-s', '-', path], quiet=True)
    run(['codesign', '--force', '-s', '-', app], quiet=True)


def verify(app):
    report = {}
    strict = subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', app],
                            capture_output=True, text=True)
    report['codesign_verify'] = {'exit': strict.returncode, 'output': strict.stderr.strip().splitlines()[-2:]}
    gatekeeper = subprocess.run(['spctl', '-a', '-vv', app], capture_output=True, text=True)
    report['spctl'] = {'exit': gatekeeper.returncode, 'output': (gatekeeper.stdout + gatekeeper.stderr).strip(),
                       'expected': 'rejected: ad-hoc signature is not notarized'}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist', type=Path, default=DIST)
    parser.add_argument('--icon', type=Path, help='replacement .icns (otherwise packaging/Bato.icns, else generated)')
    parser.add_argument('--profile', type=Path, default=ALPHA_PROFILE, help='default engine Profile cache path')
    parser.add_argument('--state', type=Path, default=ALPHA_STATE, help='default Bato organization directory')
    args = parser.parse_args()
    if not BUILT_APP.is_dir():
        sys.exit(f'Built app missing: {BUILT_APP}')
    global VERSION
    VERSION = read_version()
    work = args.dist / 'work'
    work.mkdir(parents=True, exist_ok=True)
    icon = build_icon(work, args.icon)
    target = args.dist / f'{APP_NAME}.app'
    if target.exists():
        shutil.rmtree(target)
    run(['cp', '-cR', BUILT_APP, target])
    libraries = bundle_component_libraries(target)
    rename_components(target)
    rebrand_main(target, icon, default_arguments(args.profile, args.state))
    sign(target)
    report = verify(target)
    report.update({'app': str(target), 'component_libraries': libraries, 'bundle_id': BUNDLE_ID, 'version': VERSION[0], 'build': VERSION[1]})
    (args.dist / 'package-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return report['codesign_verify']['exit']


if __name__ == '__main__':
    sys.exit(main())
