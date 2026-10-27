#!/bin/sh
set -eu
cache="$HOME/.cache/bato/cef-baseline"
version='156.0.14+g4fa4ab5+chromium-156.0.8078.48'
sample="${1:-cefclient}"
case "$sample" in
  cefclient) ;;
  cefsimple)
    script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    python3 "$script_dir/apply-cefsimple-profile.py"
    ;;
  *) echo 'usage: build.sh [cefclient|cefsimple]' >&2; exit 1 ;;
esac
cmake -S "$cache/cef_binary_${version}_macosarm64" -B "$cache/build" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DUSE_SANDBOX=ON
cmake --build "$cache/build" --target "$sample" --parallel 4
