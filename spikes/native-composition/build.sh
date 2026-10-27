#!/bin/sh
set -eu
probe_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
probe_output="${BATO_PROBE_OUTPUT:-$HOME/.cache/bato/native-composition}"
mkdir -p "$probe_output"
xcrun clang -fobjc-arc -fblocks -c "$probe_dir/bootstrap.m" -o "$probe_output/bootstrap.o"
xcrun swiftc -emit-library -module-name BatoNativeProbe -framework AppKit \
  "$probe_dir/Probe.swift" "$probe_output/bootstrap.o" -o "$probe_output/libBatoNativeProbe.dylib"
printf '%s\n' "$probe_output/libBatoNativeProbe.dylib"
