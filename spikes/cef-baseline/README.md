# Pinned CEF baseline experiment

This is an engine feasibility harness, not the Bato application or a selected production foundation. It launches the stock CEF Chrome-style sample with disposable test Profiles. See [RESULTS.md](RESULTS.md) for evidence and limits.

Prerequisites: Apple Silicon macOS, selected Xcode, CMake, Python 3.12+, and Node.js with the global WebSocket API (22+). Downloads/builds/Profiles stay under `$HOME/.cache/bato/cef-baseline`.

```sh
python3 spikes/cef-baseline/prepare.py --standard
sh spikes/cef-baseline/build.sh
python3 spikes/cef-baseline/launch.py --built --profile profile-a
```

The downloader pins CEF156/Chromium156 and verifies the published SHA1 before extraction; RESULTS records locally computed SHA256 values too. `--standard` adds the source sample and headers, not a Chromium checkout. The `cefclient` target compiles the sample and C++ wrapper against the distributed framework with sandbox integration enabled.

The launcher refuses to start while its recorded process exists. Close the previous spike before switching Profiles. `--profile` accepts only the two disposable cache directories; never point this harness at real browser data. `--extension /absolute/unpacked/path` may be repeated for developer loading. This is not proof of end-user/store installation or extension update support. `--probe-library` accepts the separate native-composition diagnostic dylib; it is deliberately not a production integration.

The debug endpoint binds to loopback port9223, which must be unused. Treat this as a test-only debugging capability; close the sample when finished. To inspect an already-open diagnostic page without opening or navigating tabs:

```sh
node spikes/cef-baseline/cdp.mjs 'chrome://extensions/' 'document.title'
```

Do not run multiple UI-driving agents against this window. Coordinate tab changes, popups, and relaunches through the primary agent. Do not commit cached runtime data or downloaded extension packages.

## Full native Chrome-window diagnostic

For the separate built-in split experiment, compile the small `cefsimple` sample from the same distribution. The build script applies the bounded disposable-Profile mapping patch because stock cefsimple does not read the sample’s `--cache-path` switch:

```sh
sh spikes/cef-baseline/build.sh cefsimple
python3 spikes/cef-baseline/launch.py --built --sample cefsimple --native --profile profile-a
```

Add the same developer `--extension` paths as needed, and coordinate with the UI owner before closing/relaunching the current spike. This launches Chrome-owned native browser chrome; it is not a Swift-owned Bato window. The patch changes sample Profile plumbing only. CEF’s license for upstream sample material is preserved in [CEF-LICENSE.txt](CEF-LICENSE.txt).
