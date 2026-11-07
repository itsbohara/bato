# Packaging results (milestone 5)

Run 2026-11-07. Plan: PACKAGING-PLAN.md. Not committed. Nothing was run against real user data, and the system default browser was not touched.

## What exists

- `python3 spikes/engine-build/package_app.py` copies `out/Debug_GN_arm64/cefsimple.app` to `SSD/dist/Bato.app` (6.0 GB apparent, APFS clones), renames and rebrands it, signs it ad hoc and verifies it. Report: `SSD/dist/package-report.json`. About 80 s.
- `python3 spikes/engine-build/run_bato.py [url] [--state DIR --profile DIR]` opens the packaged app through LaunchServices. Without options it starts the alpha state (below). It was only exercised for argument validation; the alpha state was not launched on purpose.
- `VERSION` (0.1.0) is the single version source. `CFBundleVersion` is the commit count (169 at packaging time).
- `spikes/engine-build/packaging/make_icon.swift` draws the placeholder icon (deep teal rounded tile with a white rounded "B", no resemblance to Arc, Dia or Chrome). Drop a finished `Bato.icns` at `spikes/engine-build/packaging/Bato.icns` or pass `--icon` to replace it.

## Results

| # | Item | Result |
| --- | --- | --- |
| 1 | Identity | PASS. `com.itsbohara.bato`, name/display name `Bato`, executable `Bato`, helpers `Bato Helper (...)` with `com.itsbohara.bato.helper[.alerts\|.renderer]`. Dock/app-switcher show Bato; the menu bar title is Bato. Menu items now read About Bato, Hide Bato, Quit Bato, Your Bato, Bato Help (`MenuBranding`, rewritten at install and whenever a menu opens). Window titles still end in " - Chromium" (Chromium product string; needs a resource change in the engine) and the dev-only File item "Bato Quit application" is still present. Added camera, microphone, location and Bluetooth usage descriptions so a permission request cannot abort the app. |
| 2 | Icon | PASS (placeholder). `iconutil` builds the .icns from ten generated sizes. |
| 3 | Promos | PASS with a caveat. Workspace mode adds `--no-default-browser-check` and disables 79 enabled-by-default desktop `IPH_*` features including `IPH_HighEfficiencyMode` ("Make Chromium faster"). Confirmed the list reaches helper processes (`ps`). On a fresh Profile (`profiles/pkg-fresh-v1`, state `pkg-state-v3`) no bubble, infobar or sign-in/sync prompt appeared in about two minutes of AX inspection. The unsuppressed baseline was not recaptured, so this shows absence, not a before/after. What's New only runs with Google branding. A new IPH added by a later Chromium needs its name added to `kSuppressedPromoFeatures`. |
| 4 | Signing | `codesign --verify --deep --strict` exit 0 ("valid on disk", "satisfies its Designated Requirement"). `spctl -a -vv`: rejected, exit 3, as expected for ad hoc. |
| 5 | LaunchServices cold launch | PASS. `open -a dist/Bato.app 'http://127.0.0.1:18765/permissions.html?pkg-open=2' --args <test flags>` with Bato not running started the app and the link became a tracked row (`lastURL` in the fresh state's `organization.json`, v5 and v6). `--args` works with the packaged app. Quit via the "Quit Bato" menu item exited cleanly (process gone, organization byte-identical before and after quit). `open --stdout/--stderr` fails with LaunchServices error -10810 here, so LaunchServices runs have no log file; direct runs (v2, v3) have one. |
| Direct runs | v2, v3 | Packaged binary exec'd with test flags, mock keychain, fresh state copy: start, menu check, "Quit Bato" exit 0 and exactly one `cef-shutdown-complete` (v3, `logs/pkg-v3-exit.json`). |

## State, keychain, migration

- The engine guard is unchanged: cache path must be under `SSD/runtime/profiles/` and `--use-mock-keychain` is required. So the packaged app's alpha state is `SSD/runtime/alpha-state` plus `SSD/runtime/profiles/alpha-v1` (baked into the Info.plist `BatoDefaultArguments` by `package_app.py --state/--profile`). The app needs the SSD mounted and `SSD/.bato-engine-workspace.json` present.
- No path changed, so no migration. The bundle id change does not move browser data (the path is explicit). Only per-bundle-id macOS state starts empty: user defaults, TCC grants, notification settings and any default-browser registration (not set; Bato is not the default browser).
- Future move to `~/Library/Application Support/Bato`: relax the guard in `cefsimple_mac.mm`, decide the production Keychain item (Chromium stores "Chromium Safe Storage"), copy `alpha-state` and `profiles/alpha-v1` into place while Bato is not running, and keep the old directories until a clean launch.
- Mock keychain: unchanged, still mandatory.

## Things to know

- **First launch prompts.** The unsigned-identity app triggers two macOS prompts that I did not answer: "Bato would like to access files on a removable volume" (it runs from the SSD) and notification permission requests from "Bato" and "Bato Helper (Alerts)". Allow the first, decide on the second. Because the signature is ad hoc (identity is the code hash), a repackage may ask again. A stable self-signed local certificate would fix that and is a small follow-up.
- **Not relocatable.** The component build makes the bundle depend on the cloned dylibs it contains; copying it elsewhere duplicates 6 GB and still needs the SSD for state.
- **`BatoDefaultArguments` safety.** Defaults apply only when the command line has no `--bato-workspace-state` and no `--cache-path`. While testing I once ran `open -a dist/Bato.app --args --version` and later `--args --use-native` without a Profile, which started the packaged app on the alpha paths (they did not exist before). It created only seed data (a 484-byte `organization.json`, a 23 MB fresh Profile), quit cleanly, and I deleted `runtime/alpha-state` and `runtime/profiles/alpha-v1`. That is why the client now skips the defaults when `--cache-path` is present.
- **Screenshots.** Two region captures taken while looking for the Bato window also showed unrelated desktop windows (the window was hidden behind a macOS prompt). Both files were deleted immediately and no further screen captures were taken; the rest of the checks used accessibility snapshots.
- **Tests.** `python3 -m unittest` in `spikes/engine-build` passes. In `spikes/engine-native-slot`, `test_patch.py` fails one case (`len(exports)` is 20, expected 16), which also fails without these changes.

## Process record

`native_slot.py check`: 74 files. Client patch: 53 files, 48 mirrors, round trip verified (`cefsimple_mac.mm` and `WorkspaceSlot.swift` changed). `app/tools/dev.py test`: 167 XCTest + 198 Swift Testing, 0 failures (`logs/pkg-swift-tests.log`). Two `build --execute` rounds, both successful; last segment `logs/pkg-build-segment.log`. Wrappers `tmp/launch-pkg-v1.py` (dyld failure before the component libraries were bundled, exit -6, no app started), `v2`..`v6`, states `runtime/pkg-state-v1..v6`, logs `logs/pkg-v*`. Latest clean direct exit receipt: `logs/pkg-v3-exit.json`.

## Open

1. Developer ID signing, notarization, hardened runtime and an updater are untouched.
2. Window titles and omnibox chips still say Chromium.
3. Notices bundle (`CEF-LICENSE.txt` and friends) is not shipped inside the app.
4. A release (non-component) engine build would make the bundle self-contained and much smaller.
5. The packaged default launch (no flags) was verified only on the alpha paths I then removed and on a test-defaults package I removed; re-verify once after the user's first real launch.
