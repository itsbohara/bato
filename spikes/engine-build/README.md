# Guarded external-SSD engine experiment

The user authorized `/Volumes/Mahesh/personal` for Bato engine work on 2026-10-28. This scaffold uses only its dedicated `bato-build/` child. The application repository stays at its existing location; unrelated Personal-folder files are not inspected or changed.

**Checkout completed on 2026-10-28:** the pinned automate command exited0 and its completion marker was verified. Configuration applied116 upstream CEF patches (one platform patch skipped), then stopped because depot_tools’ separate Python shim was not initialized. The explicit bootstrap repair completed without updating tooling. Configuration retry generated36640 targets from5030 files, both local patches applied, and the two-job ARM64 component compilation is now running. No completed engine build or native-reservation runtime result exists. The current prebuilt-engine experiments are independent.

## Exact configuration

[`lock.json`](lock.json) pins CEF revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`, its Chromium compatibility tag `156.0.8078.48` and resolved commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`, the reviewed CEF automate script SHA256 and a resolved official depot_tools commit. `prepare` fetched only the pinned small depot_tools and CEF checkouts, verified their remote/HEAD values and hashed the automate script. It did not invoke gclient or fetch Chromium dependencies. Tracked edits to those tool checkouts are preserved and rejected; their HEAD values alone are insufficient provenance.

The pinned automate script would normally inject mutable `siso_version: latest` into a new gclient configuration. This scaffold instead precreates and verifies the exact configuration using the version from the pinned [Chromium DEPS](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/DEPS): `git_revision:c574896b272b40aac6e44c228ee0b471ea7e3d7d`. The upstream script retains that existing configuration. Its source is not modified. The complete bootstrap script hash is checked again immediately before execution; source HEAD/origin and version are checked afterward.

This is one native ARM64 **Debug component** developer configuration, `Debug_GN_arm64`, with `symbol_level=0`, local Xcode and remote execution off. Exact pinned CEF `tools/gn_args.py` supports `GN_OUT_CONFIGS`, so only this configuration is generated. Only `cefsimple` is compiled; no Release configuration, distribution packaging or PGO-profile download is requested. This is not an official or redistributable artifact. A component build can depend on sibling dylibs in the output tree; it must not be dropped into the existing binary-distribution app as though it were a stand-alone replacement framework.

## Capacity and toolchain

Observed preflight: mounted writable APFS USB SSD, approximately167GiB free,16GiB RAM, Apple Silicon, Xcode26.3/macOS SDK26.2. The [pinned developer guide](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/docs/master_build_quick_start.md#mac-os-x-setup) specifies16GB RAM (32GB+ recommended) and150GB free for a Debug developer build. The separate [automated artifact guide](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/docs/automated_build_setup.md#macos-configuration) specifies200GB; that production packaging path is not selected.

Initial preparation and the first checkout require at least150,000,000,000 free bytes **plus** the20GiB reserve. Subsequent stages require the20GiB reserve rather than requiring the initial budget again after sources occupy disk. At the observed capacity, that leaves only about7–8GiB beyond developer-minimum-plus-reserve: sufficient to attempt a bounded development checkout, not a guarantee that the complete build fits. Every expensive child is stopped if the volume falls below the reserve. No unrelated data is deleted to free space.

The exact Chromium [SDK override](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/build/config/mac/mac_sdk_overrides.gni) sets `mac_sdk_min="15"`; installed26.2 clears that check. The [official SDK](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/build/config/mac/mac_sdk.gni) is26.5. Passing the minimum does not prove that every source compiles with the older26.2 SDK. An SDK/API error must be reported; this script does not weaken official-build checks or install/change Xcode.

## Commands

Run from the application repository:

```sh
python3 spikes/engine-build/engine.py preflight
python3 spikes/engine-build/engine.py prepare

# Initialize gn’s pinned Python interpreter without updating depot_tools Git.
python3 spikes/engine-build/engine.py bootstrap
python3 spikes/engine-build/engine.py bootstrap --execute

# Print the exact expensive command, then explicitly execute it when reviewed.
python3 spikes/engine-build/engine.py checkout
python3 spikes/engine-build/engine.py checkout --execute

# Apply upstream CEF configuration/patches and generate one GN directory first.
python3 spikes/engine-build/engine.py configure --execute
python3 spikes/engine-build/engine.py patch --execute
python3 spikes/engine-build/engine.py build --execute
python3 spikes/engine-build/engine.py status
```

`checkout` runs the pinned official automate script with the exact CEF/Chromium refs, `--no-chromium-history`, `--no-build`, `--no-distrib`, and update suppression for already pinned CEF/depot_tools. **No-build still fetches Chromium dependencies and runs Chromium hooks.** It is a large stage, not a metadata check. No force-clean, reset or clean flag is added. The official initial sync may replace its generated initial `src/out` directory; this wrapper refuses checkout updates when tracked local source changes exist. After applying the Bato patch, use configure/build directly instead of rerunning checkout.

`bootstrap` invokes only the pinned `bootstrap_python3` function with Bash failure propagation. Its tracked manifest and resolved package versions install the interpreter inside SSD depot_tools and create `python3_bin_reldir.txt`. It does not update the tooling repository or run the broader `ensure_bootstrap` gsutil/pylint initialization. It uses the same preflight, provenance checks, workspace lock, scoped caches and process-group/disk-reserve guard as expensive stages, with preview unless `--execute` is supplied. Afterward it checks tooling provenance again and refuses a missing or non-executable interpreter, or a marker resolving outside depot_tools. No global environment setting is changed.

`configure` runs pinned CEF's `gclient_hook.py`, which generates CEF wrappers, applies upstream CEF patches and creates GN files. `patch` then checks/applies the [reservation sketch](../engine-reservation/README.md) against the resulting source, treating an already applied identical patch as success. Upstream CEF patches may change its target: a failed apply is a review point, never a reason to force or silently adapt it. `build` validates the generated ARM64 Debug/component/symbol settings and both patches, then invokes `autoninja -j 2` for `cefsimple` only.

The same patch stage applies [`sample-runtime.patch`](sample-runtime.patch) **only to embedded `src/cef`**, leaving the pinned tooling checkout unchanged. Exact before/after SHA256 values protect its zero-context diff. It maps explicit `--cache-path` into CEF settings as the baseline guard does, requires `--use-mock-keychain`, canonicalizes the path and refuses anything outside `/Volumes/Mahesh/personal/bato-build/runtime/profiles/` or a missing workspace marker. It also routes sample termination to the known CEF handler rather than assuming Chromium's current application delegate implements the sample selector. Build refuses a missing/changed guard. Its apply/hash and syntax-only Objective-C++ checks passed against pinned headers; the full GN build and runtime are still untested. No launch command is provided before that build succeeds.

## Guard and preservation

The root must be the canonical authorized path on the mounted APFS volume, on a different device from the internal root filesystem. The script checks a workspace marker, exact tooling revisions and source version. It does not modify the user's HOME, shell startup files, global PATH or system configuration. Child environment scopes depot_tools PATH, configurable CIPD/vpython/XDG/ccache caches and TMPDIR to the SSD. Host Xcode and unavoidable OS-managed caches remain system-managed.

The coordinator also verified that global Git `cache.cachepath` is unset on this host. Recheck that if the host configuration changes: depot_tools can consult it before environment overrides. Do not create a full-history Git mirror merely to relocate a cache for this no-history experiment.

`logs/run-state.json` records the owned command/PID and its phase log. A nonblocking workspace lock prevents concurrent wrapper commands, and stale running/cleanup-error groups block another run. The reserve monitor checks every five seconds and sends TERM, then KILL if needed, to the **whole process group it created**; it checks remaining group members even after the original leader exits. SIGINT/TERM/HUP also stop that owned group. All checkout/build files are preserved.

`checkout-complete.json` is written only after the initial complete automate command exits0 and source/version/dependency-manifest checks pass. Existing `src` without that marker is rejected even if `chrome/VERSION` already exists: automate's no-history path could otherwise skip an interrupted sync/hooks and falsely report completion. Configure/patch/build also require a matching completion marker. A partial checkout needs explicit manual recovery after inspecting the exact failed phase, including dependency sync and hooks; then the coordinator must review its completion metadata. The wrapper neither deletes the partial tree nor offers an automatic bypass/adoption switch. A version file alone is never a completion claim.

No browser is launched by these stages, and no Profile, Keychain, extension or private artifact is copied to the SSD. Later runtime checks must use dedicated synthetic Profiles and the same mock-Keychain policy on every restart. Engine build success alone would not pass the native hosting/extension foundation gate.

Read [process lifecycle](PROCESS-LIFECYCLE.md) before stopping the current build: Siso deliberately uses separate helper/action groups, and the wrapper independently verifies only its initial group. After a disk/error/cancel stop, explicitly inspect owned worker survivors before accepting cleanup or launching another stage.

After successful compilation, [runtime handoff](RUNTIME.md) describes the read-only artifact/dependency checker and fixed control/reservation launch previews. The checker cannot launch the sample and refuses an active build. Actual source-built runtime acceptance remains pending.

## Verification

```sh
python3 -m unittest discover -s spikes/engine-build -p 'test_*.py'
```

Twelve tests passed. Bootstrap tests verify the pinned command, scoped environment without global mutation, preview behavior and refusal to launch after a provenance failure. They start disposable Python processes, force a simulated low-space transition, stop a TERM-ignoring descendant even when its leader has already exited, preserve an unrelated process/file and record a completed normal run. Initial state-write/print failures also stop the child while preserving the original error. Provenance tests reject changed bootstrap source and dirty pinned tooling, and ensure a partial tree containing a valid VERSION never invokes automate. Preflight passes against the actual mounted SSD. No test starts Chromium checkout or compilation.
