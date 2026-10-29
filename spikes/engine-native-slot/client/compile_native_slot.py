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
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-emit-library',
                    '-module-name', 'BatoNativeSlot', '-target', 'arm64-apple-macos13.0',
                    '-sdk', sdk, '-module-cache-path', str(output.parent / 'native-slot-module-cache'),
                    '-Xlinker', '-install_name', '-Xlinker', '@rpath/libBatoNativeSlot.dylib',
                    str(source), '-o', str(output)], check=True)


if __name__ == '__main__':
    main()
