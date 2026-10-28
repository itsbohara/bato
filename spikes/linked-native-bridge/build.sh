#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache="$HOME/.cache/bato/linked-native-bridge"
mkdir -p "$cache"
if ! mkdir "$cache/build.lock" 2>/dev/null; then
  echo "Linked bridge build already running (or stale lock: $cache/build.lock)" >&2
  exit 1
fi
trap 'rmdir "$cache/build.lock"' EXIT HUP INT TERM
python3 "$here/prepare.py"
swiftc=$(xcrun --find swiftc)
swift_lib=$(CDPATH= cd -- "$(dirname -- "$swiftc")/../lib/swift/macosx" && pwd)
bridge="${BATO_LINK_NATIVE_BRIDGE:-ON}"
if [ "$bridge" != OFF ]; then
  xcrun swiftc -parse-as-library -emit-object -module-name BatoLinkedBridge \
    -target arm64-apple-macos13.0 "$here/NativeBridge.swift" -o "$cache/NativeBridge.o"
fi
cmake -S "$cache/source" -B "$cache/build" -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 -DUSE_SANDBOX=ON -DBATO_SWIFT_LIBRARY_DIR="$swift_lib" \
  -DBATO_LINK_NATIVE_BRIDGE="$bridge"
cmake --build "$cache/build" --target cefsimple --parallel 1
