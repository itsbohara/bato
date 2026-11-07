# Milestone 6 plan: packaged app ready for personal daily use

Goal: the packaged `Bato.app` can be launched by its owner against real data, with the SSD only needed to host the app bundle. Nothing in this milestone creates or launches the real data location; all verification uses a location shaped the same under the SSD.

## Decisions

1. **Data location.** Organization state at `~/Library/Application Support/Bato/State`; Chromium user-data (cache) root at `~/Library/Application Support/Bato/Profiles`. `package_app.py` bakes these into `BatoDefaultArguments` by default; `--state/--profile` still bake a test location.
2. **Guard (cefsimple_mac.mm).** Two accepted namespaces. The SSD test namespace (`SSD/runtime/profiles/` plus the SSD marker file) keeps requiring `--use-mock-keychain`. The real namespace is exactly `$HOME/Library/Application Support/Bato/Profiles` (and below), resolved through symlinks, and does not take the mock keychain: a launch there with `--use-mock-keychain` is refused so real data never sits under the mock key. Test launches keep SSD paths; the Application Support layout (a directory with a space in `Application Support/Bato/{State,Profiles}`) is exercised by a mimic tree under `SSD/runtime/profiles/`.
3. **Keychain.** Without `--use-mock-keychain` Chromium's os_crypt uses the login keychain item for the engine's product name. Not exercised by tests.
4. **Window titles.** Chromium formats titles from a resource string ("$1 - Chromium"). Changing it means an engine resource rebuild; instead the client observes each window's `title` (KVO) and drops the trailing " - Chromium" (a bare "Chromium" becomes "Bato").
5. **Dev-only menu item.** The File item "Bato Quit application" and its action are removed; "Quit Bato" is the only quit.
6. **Renderer crash.** Baseline first: kill a fixture tab's renderer in the current package and see what Chromium's sad tab does and whether the organization keeps the entry. Add a Bato state only if the baseline fails the criteria (entry tracked, Reload works, no crash loop).
7. **Engine crash.** Existing recovery (session marker, sheet, no auto relaunch) is the DESIGN path; re-verify only that it still works when launched from the packaged app (kill -9 of the test browser pid).

## Verification

RESUME process: mirrors, stage, regenerate, `native_slot.py check`, `test_patch.py`, `swift test` (`logs/m6-swift-tests.log`), `build --execute` (`logs/m6-build-segment.log`), `package_app.py`, then wrappers `tmp/launch-m6-v1.py`.. against the packaged binary with mock keychain, test paths and receipt guard; quit through "Quit Bato".
