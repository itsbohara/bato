#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache="$HOME/.cache/bato/profile-contexts"
mkdir -p "$cache"
if ! mkdir "$cache/build.lock" 2>/dev/null; then
  echo "Context build active or stale lock: $cache/build.lock" >&2
  exit 1
fi
trap 'rmdir "$cache/build.lock"' EXIT HUP INT TERM
python3 "$here/prepare.py"
cmake -S "$cache/source" -B "$cache/build" -DCMAKE_BUILD_TYPE=Release \
  -DPROJECT_ARCH=arm64 -DUSE_SANDBOX=ON
cmake --build "$cache/build" --target cefsimple --parallel 1
