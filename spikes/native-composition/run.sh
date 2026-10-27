#!/bin/sh
set -eu
if [ "$#" -lt 1 ]; then
  printf '%s\n' 'Usage: run.sh /absolute/path/to/cefclient [CEF arguments...]' >&2
  exit 2
fi
probe_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cef_executable=$1
shift
if [ ! -x "$cef_executable" ]; then
  printf '%s\n' 'CEF executable must exist and be executable.' >&2
  exit 2
fi
probe_output="${BATO_PROBE_OUTPUT:-$HOME/.cache/bato/native-composition}"
probe_library=$("$probe_dir/build.sh")
# This directory is deliberately separate from any real browser Profile.
mkdir -p "$probe_output/profile"
export BATO_NATIVE_PROBE=1
export BATO_NATIVE_PROBE_AUTOTEST=1
export DYLD_INSERT_LIBRARIES="$probe_library${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
exec "$cef_executable" --use-views --cache-path="$probe_output/profile" --enable-logging=stderr "$@"
