# Alpha gaps batch 2: results

Run 2026-11-08. Not committed. Real-host runs used the SSD test runtime (`runtime/ag2-state-v2`, copied from `sbs-state-v1`), `--use-mock-keychain`, wrappers `tmp/launch-ag2-v2.py`, `v3`, `v4` and quit through the app menu. `dist/Bato.app`, `~/Library/Application Support/Bato` and the real keychain were not touched. Helper scripts and window-cropped screenshots are in `tmp/ag2/` (SSD). Test fixtures: `spikes/fixtures/server.py` (18765) plus `tmp/ag2/server.py` (18767: `/dialogs` page with alert/confirm/prompt, a `target=_blank` link, a plain link, `window.open`; `/auth` Basic auth, user `bato`, password `secret`).

Note: wrapper `launch-ag2-v1.py` had a bad state path and briefly opened the polish agent's finished `runtime/sbs-state-v1`; it was quit cleanly (exit 0) after a few seconds, no actions taken. All later runs used `ag2-state-v2`.

## What changed

1. **Open Link in Peek (context menu).** No engine hook was needed: Chrome-style browsers already honour `CefContextMenuHandler`. `SimpleHandler` now implements `OnBeforeContextMenu`/`OnContextMenuCommand`, calling `BatoWorkspaceContextMenu`/`BatoWorkspaceContextMenuCommand` in `native_slot_client.mm`. For a link on a workspace page that Swift would accept as a Peek parent (`PeekLinkEligible`) the item "Open Link in Peek" is inserted after "Open Link in New Tab"; the command reuses `PeekLinkRequested` (same guards and deferral as Shift-click).
2. **Closed-tab history survives relaunch.** `ClosedTab`/`ClosedTabStack` are `Codable`; new `BatoPersistence/ClosedTabsStore.swift` writes `<state>/closed-tabs.json` (per Profile, newest 25, wrong-Profile tabs dropped on load, corrupt file set aside). `PageRuntime.closedTabsDidChange` saves after every change, `restoreClosedTabs` loads at launch and drops unknown Profiles and unreopenable URLs. Wired in `NativeWorkspaceController.init`.
3. **Essentials E2/E3.** E2 (footer picker out of sync) was written against the old footer picker; the footer is now the workspace pager dots plus the Profile button, both rendered from the one `BrowserState`. Rechecked on the host (see below). E3 (Create leaves the new workspace in the launch window) is NOT fixed: window creation is tied to creating the first page (`PendingWindow` in `native_slot_client.mm`), so an empty new Profile cannot get its own window without a new engine path for an anchor-less window. Left open, info severity.
4. **"Chromium" strings.** Engine: `Chromium` replaced by `Bato` in the message text (not `desc`, `<ex>`, `ChromiumOS`, `ChromiumUpdater`, copyright "The Chromium Authors") of `chromium_strings.grd`, `settings_chromium_strings.grdp`, `components_chromium_strings.grd`, `extensions_chromium_strings.grdp` and `new_or_sad_tab_strings.grdp` (sad tab "Restart Bato", accessibility window name "<page> - Bato - <Profile>", omnibox chip "Bato", about/restart/sign-in strings). Non-English translations keep their old text (their message IDs change, so they fall back to English). The keychain item name "Chromium Safe Storage" is a code constant and is unchanged.
5. **target=_blank links.** Real-host check found they opened a stock window outside the sidebar (the known M3 item). Fix: engine `CefBrowserInfoManager::CanCreateWindow` offers a new foreground/background tab with `opener_suppressed` to the client's `CefRequestHandler::OnOpenURLFromTab`; Bato's handler (`BatoWorkspaceOpenLinkInTab`, Swift export `BatoSwiftWorkspaceOpenLinkInTab` -> `openExternalURL`) opens a sidebar tab. Links with an opener and `window.open` with features are unchanged. A background-tab link also selects the new tab (no background-add path yet).

## Files

Engine patch (`engine.patch`, `manifest.json`: 8 -> 14 files): `cef/libcef/browser/browser_info_manager.cc`, `chrome/app/chromium_strings.grd`, `chrome/app/settings_chromium_strings.grdp`, `components/components_chromium_strings.grd`, `extensions/strings/extensions_chromium_strings.grdp`, `components/new_or_sad_tab_strings.grdp`.

Client (`client.patch`, `client.json`: 54 -> 55 files, 49 -> 50 mirrors): `client/native_slot_client.mm`, `client/native_slot_client.h`, `client/WorkspaceSlot.swift`, `client/compile_native_slot.py` (adds `ClosedTabsStore.swift`), staged `simple_handler.cc/.h` (context menu and `OnOpenURLFromTab`), staged `BUILD.gn` input, new mirror `app/Sources/BatoPersistence/ClosedTabsStore.swift`; the polish agent's UI files were restaged.

Swift app: `BatoCore/BrowserState.swift` (Codable, `ClosedTabStack(tabs:)`, `isValidPageURL`), `BatoRuntime/PageRuntime.swift`, `BatoPersistence/ClosedTabsStore.swift`, `BatoBrowserUI/NativeWorkspaceController.swift`; tests `ClosedTabsStoreTests.swift` (new), `ClosedTabRuntimeTests.swift` (2 added).

## Verification

Build/process: `native_slot.py check` 82 files; engine 14-file and client 55-file roundtrips verified; `test_patch.py` 4 passed; `cd app && swift test` 215 tests in 26 suites passed ; three `build --execute` rounds succeeded (logs `logs/ag2-build*.out`, `logs/build.log`).

| # | Check | Result |
| --- | --- | --- |
| 1 | Right-click a link: menu shows "Open Link in Peek" under "Open Link in New Tab" (`tmp/sbs-shots/ag2-open-in-peek-menu.png`); click it | PASS. Peek presented over the page with Open as Tab/Close in the sidebar (`ag2-open-in-peek.png`); Escape dismissed it. |
| 2 | Close two tabs, quit (exit 0), relaunch, Cmd-Shift-T | PASS. `closed-tabs.json` written on close; after relaunch the last closed tab ("Download History") came back at its position. |
| 3 | Strings | PASS. Omnibox chip "Bato", accessibility window name "prompt:xyz - Bato - Person 1". Sad-tab text not triggered on the host this run (source string verified in the grdp). |
| 4 | JS alert / confirm (Cancel) / prompt (typed text, OK) | PASS. Native-styled dialogs over the page, sidebar titles updated to `alert-done`, `confirm:false`, `prompt:xyz`. |
| 5 | HTTP Basic auth | PASS. "Sign in" dialog for `http://127.0.0.1:18767`; credentials accepted, page "auth-ok", Chrome's "Save password?" bubble appeared. (This ran in the stray window, see 6, but the dialog is the same engine path.) |
| 6 | `target=_blank` link | FAIL before fix: new stock window with tab strip (`native-slot-factory-refused`). PASS after fix (third build): sidebar tab. |
| 7 | Tab > Close Tabs to the Right | PASS when enabled: command 34 closed the tab below the selection. Defect: the menu item is disabled when the selected sidebar tab is the *last tab in Chrome's own strip* (creation order), not the sidebar's. |
| 8 | Tab > Group Tab | PASS. Consumed (`workspace-chrome-command` 99), no group or window created. |
| 9 | Popup `window.open` with features | Not re-run this batch (covered by MILESTONE3 #2, engine path unchanged). |

## After the final build

Wrapper `launch-ag2-v4.py`/`v5.py` (same state, exit receipts `logs/ag2-v4-exit.json`, `ag2-v5-exit.json`, both exit 0). `target=_blank` link click: PASS, a new "Bato compatibility fixtures" row appeared in the sidebar and was selected, no stock window (`tmp/sbs-shots/ag2-target-blank-sidebar-tab.png`). The tab survived relaunch. Another agent's cefsimple instance ran against the same binary at the same time, so windows were selected by pid.

Cropped Bato-window screenshots for the polish comparison (all `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/`):
- `after-sidebar-selected-row.png`
- `after-command-bar.png`
- `after-switcher-popover.png` (checkmark on Space 2 matches the pager dot, so E2 is not reproducible with the current UI)
- `after-settings-rail.png`
- also `ag2-open-in-peek-menu.png`, `ag2-open-in-peek.png`, `ag2-target-blank-sidebar-tab.png`

## Still open

- E3 (empty new Profile has no window until a page opens): needs an engine path creating an anchor window without a page.
- Close Tabs to the Right enablement follows Chrome's strip order, not the sidebar; needs an engine enable-state override.
- Background-tab links select the new tab.
- Basic auth and the dialogs were checked on loopback HTTP only; no real OAuth provider.
- Non-English strings still say Chromium.
