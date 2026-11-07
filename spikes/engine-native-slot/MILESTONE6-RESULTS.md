# Milestone 6 results: packaged app for personal daily use

Run 2026-11-07. Plan: MILESTONE6-PLAN.md. Not committed. The real data location (`~/Library/Application Support/Bato`) was never created or launched against, and the real keychain was never touched; every run used a mimic tree under the SSD and `--use-mock-keychain`.

## What changed

- **Data location.** `package_app.py` now bakes `~/Library/Application Support/Bato/State` (organization, preferences, backups, blocking settings) and `.../Bato/Profiles` (Chromium user-data root) into `BatoDefaultArguments`, without `--use-mock-keychain`. Passing SSD paths still bakes the mock flag. `run_bato.py` needs `--real` (or `--state` plus `--profile`) so a bare run cannot open real data by accident; `--app` selects another bundle.
- **Guard (`cefsimple_mac.mm`, `BatoProfileStorageAllowed`).** Mock keychain: cache path must be under `SSD/runtime/profiles/` and the SSD marker must exist (unchanged). No mock keychain: cache path must be exactly `$HOME/Library/Application Support/Bato/Profiles` or below. Everything else, including the real path with the mock flag, is refused (exit 1 before any storage is touched). Checked with a standalone compile of the function (12 cases: real path, child, mock+real, `ProfilesX`, `State`, `..` escape, Chrome and Chromium data dirs, SSD mimic, SSD non-profiles, `/tmp`) and with three probes of the packaged binary (real path + mock, SSD path without mock, Chrome's data dir): each printed "Bato engine refuses this storage location or keychain mode", nothing created.
- **Keychain.** Without the mock flag Chromium's os_crypt uses the login keychain item **"Chromium Safe Storage"** (the string in this engine build; there is no separate "Bato Safe Storage" because the product name is Chromium). Not exercised.
- **Window titles.** `WindowTitleBranding` (WorkspaceSlot.swift) observes each window's `title` and drops a trailing " - Chromium" (bare "Chromium" becomes "Bato"). On the host, `NSWindow` titles (Window menu, CGWindow names, `agent-desktop list-windows`) read "[::1]", "Settings", "about:blank" with no suffix. Not fixed: the accessibility window name that System Events and VoiceOver read is still "<page> - Chromium" (for example "Settings - Chromium - Person 1"); it comes from Chromium's views layer, not `NSWindow.title`. It is also unproven that the observer was needed, since no unpatched build was compared.
- **Dev menu item.** "Bato Quit application" and its action are gone from File (File menu listed: New Tab ... Print Using System Dialog, no extra item). "Quit Bato" is the only quit and exited 0 each time.
- **Notices.** `package_app.py` copies `NOTICES.md` into `Bato.app/Contents/Resources`. Settings > About "View Notices" opened that bundled copy.
- **Registered** the Swift batch agent's `AppPreferencesStore.swift` (client.json mirrors and files, compile script, staged BUILD.gn).

## Real-host results (packaged app, mimic data location)

| # | Check | Result |
| --- | --- | --- |
| 1 | Launch with **no flags** (`tmp/launch-m6-v2.py`): Info.plist defaults pointed at `runtime/profiles/m6-home/Library/Application Support/Bato/{State,Profiles}` (path with a space) | PASS. Browser and helpers ran with `--user-data-dir=.../Application Support/Bato/Profiles`; State and Profiles created under the mimic root; no `refused`/`mismatch`; quit exit 0, one `cef-shutdown-complete`. |
| 2 | Renderer crash, active tab "Permissions fixture" | PASS with Chromium's sad tab. Killing only renderer helpers whose command line carried the mimic `--user-data-dir` (first kills hit spare/other-tab processes with no visible effect; the kill that hit the tab) showed "Can't open this page", Error code 9, a Reload button (`logs/m6-shots/crash-3.png`). The sidebar row stayed and stayed selected; the organization's page list (42 entries, titles and URLs) was identical before and after (`logs/m6-v2-pre-crash.json`); clicking Reload restored the page (`crash-4.png`). No crash loop. Wording still says "Restart Chromium". |
| 3 | Engine crash (`kill -9` of wrapper-owned browser pid 56345, command line checked, `logs/m6-v3-kill.json`) | PASS. Relaunch (v4) showed the existing recovery sheet "Bato didn't quit properly last time" (Restore Session / Keep Current) before pages loaded, no automatic relaunch or loop; Keep Current, then quit exit 0 (v4), clean relaunch with no sheet (v5, exit 0). |
| 4 | File menu / titles | PASS as described above. |

### Swift batch checks (coordinator request)

| Check | Result |
| --- | --- |
| Settings > General search engine change persists | PASS. Changed DuckDuckGo to Bing (physical click on the popup, AX press on the menu item); `State/preferences.json` held `{"searchProvider": "bing"}`, still Bing after the kill-9 recovery relaunch (v4) and after a clean relaunch (v5). |
| Command bar uses it | PASS. The command bar footer picker reads "Bing" in v3 and v5 (a search was not submitted, to avoid network traffic). |
| Delete Workspace confirm | PASS. A new "Workspace 7" in Personal; Workspace actions > Delete Workspace... showed "Delete the workspace "Workspace 7"? This removes the workspace's 0 pin and tabs and 0 archived tabs ..." with Delete Workspace (default Cancel). Confirming removed it and selection returned to Personal; the organization's workspace list went back to six. |
| Last workspace refusal | PASS (by disabling). In the Clients Profile, which has one workspace, the Delete Workspace menu item is disabled. |
| Settings > About | PASS. "Bato, Version 0.1.0 (173). Released under the MIT License." View Notices opened `Bato.app/Contents/Resources/NOTICES.md` in the default editor. |

Settings sidebar panes still need a physical click (`mouse-click --headed --xy`); AX presses do not switch panes (known from M4).

## First real launch (step by step)

Do this once, with the SSD mounted. Nothing below has been run by the agent.

1. Quit any test Bato that is running (Bato > Quit Bato). Make sure `/Volumes/Mahesh/personal/bato-build/dist/Bato.app` exists (`python3 spikes/engine-build/package_app.py` rebuilds it from the last engine build, about 80 s).
2. Optional safety copy: if `~/Library/Application Support/Bato` already exists for any reason, move it aside; the first launch is meant to start on empty data.
3. Launch: double-click `dist/Bato.app` in Finder, or `open /Volumes/Mahesh/personal/bato-build/dist/Bato.app`, or `python3 spikes/engine-build/run_bato.py --real`. (Never pass `--state`/`--profile` for real use.)
4. macOS prompts, answer as follows:
   - **Files on a removable volume** (the app runs from the SSD): Allow.
   - **Keychain, once, shortly after the first page or login field loads:** "Bato wants to use your confidential information stored in "Chromium Safe Storage" in your keychain." Enter your login password and choose **Always Allow** (Allow works too but asks every launch). This item is created by this first run; any other Chromium-based app that already created "Chromium Safe Storage" shares it, which is harmless. Because the app is ad-hoc signed, every repackage changes its identity and macOS asks again once.
   - **Notifications** from "Bato" / "Bato Helper (Alerts)": your choice; Deny is fine for now.
5. A fresh, empty organization starts (one Profile, one workspace). Bring in Arc data with Settings > Import (or the workspace "..." menu > Import from Arc...) after quitting Arc; the import writes a pre-import snapshot.
6. Data now lives in `~/Library/Application Support/Bato/State` (organization.json, preferences.json, backups/, blocking/) and `~/Library/Application Support/Bato/Profiles` (cookies, logins, history, extensions). Back up the whole `Bato` folder with Bato quit.
7. Quit with Cmd-Q or Bato > Quit Bato. After a crash or force quit the next launch shows the recovery sheet (Keep Current is almost always right).
8. If something is badly wrong, quit and move `~/Library/Application Support/Bato` aside; nothing else holds Bato data. The keychain item can be deleted in Keychain Access ("Chromium Safe Storage") only if no other Chromium app needs it.

Expected limits: the app needs the SSD mounted to launch (component build, 6 GB bundle); it is not the system default browser; it cannot be updated by itself.

## Also known

- Sad tab and error pages say "Chromium" ("Restart Chromium"); engine strings.
- Accessibility window title keeps " - Chromium" (see above).
- Repackaging resets the keychain "Always Allow" and macOS permission grants (ad-hoc identity).
- The default (no-flags) launch of the *real* package was verified only by reading its Info.plist and by the guard probes above; the no-flags launch itself was verified on the mimic package (removed afterwards, `dist-m6test`).

## Process record

`native_slot.py check`: 75 files; client patch 54 files, 49 mirrors, round trip verified; `test_patch.py` 4 passed (the former 16-versus-20 exports failure no longer occurs); `app/` `swift test` 173 XCTest + 208 Swift Testing, 0 failures (`logs/m6-swift-tests.log`); `python3 -m unittest` in `spikes/engine-build` passed. One failed `build --execute` round (my edit of `cefsimple_mac.mm` broke the Objective-C delegate; rebuilt from the committed client patch with the edits reapplied), then a successful round, segment `logs/m6-build-segment.log`. Wrappers `tmp/launch-m6-v1.py` (pre-change package baseline; crash kills there hit non-visible processes) to `v5`; receipts `logs/m6-v1..v5-exit.json` (v3 is -9 with `logs/m6-v3-kill.json`; every other exit 0). Screenshots (window crops only) in `logs/m6-shots/`. Test tree `runtime/profiles/m6-home` and `runtime/m6-state-v1`.
