# Browser command ownership: results

Run 2026-11-07. Plan and audit: COMMANDS-PLAN.md. Not committed.

## Changes

- Engine (`engine.patch`, manifest 17 files, `test_patch.py` 4 tests OK): offers to `cef_delegate()->HandleCommand` at `chrome::NewWindow`, `SelectNextTab`, `SelectPreviousTab`, `SelectLastTab` (`browser_commands.cc`), `RestoreTab` (`browser_tab_restorer.cc`), and in `browser_actions.cc` the Cmd-1..8, `kActionNewTab` and `kActionCloseTab` lambdas. Not in `chrome::SelectNumberedTab` (CEF's `OnSetFocus` calls it).
- Client: `BatoWorkspaceChromeCommand` maps New Window to the command bar and adds commands 8 (reopen), 9/10 (next/previous), 21-29 (page by position). It logs every received id as `workspace-chrome-command`.
- Swift: `ClosedTab`/`ClosedTabStack` and position/adjacency helpers in `BrowserState`; per-Profile closed-tab stack and `reopenClosedTab`/`selectAdjacentEntry`/`selectEntry(forShortcut:)` in `PageRuntime`; three small methods in `NativeWorkspaceController`. New tests: `ClosedTabTests` (6), `ClosedTabRuntimeTests` (4).
- Fixtures: `spikes/fixtures/www/commands.html`, `commands.js`, `commands-popup.html` (find text, file input, window.open popup with postMessage, navigation type readout). Cert fixture is a throwaway HTTPS server on 127.0.0.1:18767 (`tmp/cert-fixture.py`, self-signed).

## Process

- `native_slot.py check` passed (56 files); `swift test` passed (157 Swift Testing tests plus XCTest, 0 failures; `logs/commands-swift-tests.log`).
- Two `build --execute` runs (first: all chord hooks; second: New Tab/Close Tab action hooks after the real-host run found them). Both finished successfully; `logs/commands-build-segment.log` holds both segments. siso reused its daemon, so no new `offline mode` boundary was printed; the segments start after the previous (F1) segment.
- Real host: `tmp/launch-commands-v1.py` (first build) and `launch-commands-v2.py` (second), `--use-mock-keychain`, receipt guard `logs/recovery-v7-exit.json` then `logs/commands-v1-exit.json`, fresh states `runtime/commands-state-v{1,2}` seeded from `runtime/recovery-state-v1` (`tmp/seed-commands-state.py`). Quit through "Quit Chromium" only; `logs/commands-v{1,2}-exit.json` exit code 0; lifecycle markers `native-slot-detached`, `profile-contexts-released` x2, `cef-shutdown-complete`, `slot-client-detached`; no `profile-*-refused/mismatch`. Chords are real System Events keystrokes with Bato verified frontmost first (`tmp/cmd-key.sh`); menu items by accessibility press (`tmp/cmd-menu.sh`); page clicks by physical click. Screenshots in `logs/commands-shots/`.

## Results

"Hook" = the command reached `OnChromeCommand` (log id in brackets).

| # | Check | Result |
| --- | --- | --- |
| 1 | Ctrl-Tab / Ctrl-Shift-Tab (v1, v2) | PASS. Next/previous in sidebar order with wrap ([34016], [34017]); the window title and `activeEntryID` follow. |
| 2 | Cmd-1..8, Cmd-9 (v1, v2) | PASS. Cmd-3 = third Favorite, Cmd-6 = first temporary tab, Cmd-9 = last row ([34020], [34023], [34026]). Order is Favorites, pins, tabs. |
| 3 | Cmd-Opt-Right/Left, Shift-Cmd-]/[ (v1) | PASS, same commands as Ctrl-Tab. |
| 4 | Tab > Select Next Tab menu (v1) | PASS, wraps to the first Favorite. |
| 5 | Shift-Cmd-T, close two tabs then reopen twice (v1) | PASS. Newest first (one, then three), each at its old index, selected and loaded; organization JSON updated; still one window, no Chromium tab. Reopen with an empty stack is a no-op that Chromium does not see. |
| 6 | File > Reopen Closed Tab menu (v1) | PASS ([34028]). |
| 7 | Cmd-N and File > New Window (v1, v2) | PASS. Opens the command bar; no second Chrome window ([34000]). |
| 8 | File > New Tab menu | FAIL in v1: opened Chromium's own NTP as an untracked tab, no log line, organization unchanged (`v1` screenshot 04). PASS in v2 after the action hook: command bar, no stray tab ([34014]). |
| 9 | File > Close Tab menu | FAIL in v1: Chromium closed the page behind Bato; the row stayed as an unloaded entry and nothing entered the closed stack. PASS in v2: closes the Bato page, reopenable with Shift-Cmd-T ([34015]). |
| 10 | Cmd-T / Cmd-W physical (v2 regression) | PASS (key monitor path, unchanged). |
| 11 | Cmd-R, Shift-Cmd-R (v1) | PASS. The active page reloaded (fixture reports `Navigation: reload`); no hook call, no change needed. |
| 12 | Cmd-F (v1) | PASS. Find bar visible over the page, 3 matches highlighted, Escape closes. |
| 13 | Zoom Cmd-+ / Cmd-- / Cmd-0 (v1) | PASS. 125% bubble and scaled page, Cmd-0 resets. |
| 14 | Print Cmd-P (v1) | PASS. Print dialog attached over the page, preview rendered, Esc cancels. Sidebar is the grey slab behind it (known F3). |
| 15 | File upload (v1) | PASS. Choose File opened the native panel; Cmd-Shift-G path entry selected `upload-fixture.txt`, page showed "Chosen: upload-fixture.txt (28 bytes)". |
| 16 | OAuth-style `window.open` popup (v1) | PASS functionally: popup opened, `postMessage` reached the opener ("Popup replied: approved"), `window.close()` closed it. Cosmetic defect below. |
| 17 | Certificate error (v1) | PASS. `https://127.0.0.1:18767/` (self-signed) shows Chromium's "Your connection is not private" interstitial in the Bato window, "Not Secure" in the address bar, Back to safety/Advanced present; the row is titled "Privacy error". |
| 18 | Back/Forward Cmd-[ ] | Not re-run; unchanged by this work (acts on the active page, COMPACT-FOLDERS-RESULTS). |

## Defects and open items

1. Fixed during the run: menu New Tab and Close Tab bypassed Bato (rows 8, 9).
2. Open, cosmetic: the `window.open` popup is a full-size 760x800 Chrome window with a stock tab strip and an empty grey slab where the sidebar would be (`native-slot-factory-refused`), instead of a compact popup. Functionality is fine. Screenshot `logs/commands-shots/13-popup.png`.
3. Open: Chromium's other Tab-menu and window items still create or change untracked state with Bato selection unchanged. Seen: Tab > New Tab to the Right (stray NTP, `v2-03-newtab-right.png`), Tab > Duplicate Tab (stray tab). Not exercised but same route: Pin Tab, Group Tab, Close Other Tabs, Close Tabs to the Right, Move Tab to New Window, New Incognito Window, History > recently closed items ("Restore Window"). Suggested next step: offer these IDs to the client at their action lambdas and consume them (or hide the Tab menu).
4. Open, pre-existing: after closing the selected temporary tab (Cmd-W) the window showed the previously used page while `activeEntryID` was empty until the next keypress; a second Cmd-W did nothing. Not caused by this change, not investigated.
5. `AppController` paths (Dock menu, or only the Settings window key) for New Window and Reopen Closed Tab are not hooked: there is no `Browser` to offer the command to.
6. Cmd-1..9 order uses `visibleEntries` (Favorites, pins, tabs); pins filed in folders sort by pin-list position, not folder order.
7. Closed-tab history is in memory per Profile for the session; it is not persisted across relaunch.
8. The cert fixture covers only the interstitial, not "Advanced > proceed" or HSTS.
