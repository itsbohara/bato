# F1: History, Downloads and Settings chords bypass Bato

Run 2026-11-07. Fix verified on the real host; not committed.

## Symptom

Cmd-Y, Shift-Cmd-J, Cmd-, and the History > Show Full History, Window > Downloads and Settings menu items opened Chromium's own untracked chrome:// tab instead of calling `BatoWorkspaceChromeCommand` (Swift commands 5, 6, 7).

## Root cause

The client mapping is correct. `OnChromeCommand` is never called for these commands, because the only engine hook that feeds it is not on their path.

- `cef/libcef/browser/chrome/chrome_browser_delegate.cc:296` (`ChromeBrowserDelegate::HandleCommand`) is the only caller of `CefCommandHandler::OnChromeCommand` (`:307`). It is reached from `chrome/browser/ui/browser_command_controller.cc:675-686` (`HandleCommandWithDisposition`) and from `ChromeBrowserHostImpl::ExecuteCommand` (`cef/libcef/browser/chrome/chrome_browser_host_impl.cc:345-365`).
- Temporary stderr logging on the first line of `BatoWorkspaceChromeCommand` printed nothing for Cmd-Y, Cmd-, , Shift-Cmd-J, Cmd-R or a View > Reload menu click (log `logs/f1-v1.log`), so the callback is not reached from keyboard or menu dispatch at all. Only the host-initiated IDC_EXIT path (the `native-quit-host-dispatch` special case at `chrome_browser_host_impl.cc:345`) reaches the handler; that special case already documents "Action-backed commands can bypass Chrome's legacy CEF delegate hook".
- The Shift-Cmd-C mapping cited as "known to reach the handler" was never confirmed (NAV-HEADER-RESULTS.md rows 5 and (a): "Fail (not verified)"), so it is not evidence that the hook works from the keyboard.
- The three commands are action-backed: `chrome/browser/ui/browser_actions.cc:4020` (kActionOptions), `:4577` (kActionShowHistory), `:4605` (kActionShowDownloadsPage) invoke `chrome::ShowSettings/ShowHistory/ShowDownloads` directly, and `chrome/browser/app_controller_mac.mm:1800-1830` (`executeCommand:withProfile:`) and `:2097-2104` (`showPreferencesForProfile:`) also call them directly.
- All of those routes end in `chrome::ShowHistory(browser)`, `ShowDownloads(browser)`, `ShowSettings(browser)` in `chrome/browser/ui/chrome_pages.cc`, which open the singleton tab.

Not established: which exact upstream call site skips `HandleCommandWithDisposition` (lldb attach to the debug build hung or crashed, so no backtrace). The fix does not depend on it, because it sits at the terminal functions all routes share.

## Fix

Engine (one new file in `manifest.json`/`engine.patch`, now 12 files):

- `chrome/browser/ui/chrome_pages.cc`: new `HandledByCef(browser, command_id)` calls `browser->cef_delegate()->HandleCommand(id, CURRENT_TAB)`; the one-argument `ShowHistory`, `ShowDownloads` and `ShowSettings` return early when it is true (IDC_SHOW_HISTORY, IDC_SHOW_DOWNLOADS, IDC_OPTIONS). Sub-page and host-name overloads are untouched. When the client declines (Chrome-owned active tab), Chrome opens its own tab as before.
- Original saved to `tmp/slot-engine-diagnostics-base/chrome/browser/ui/chrome_pages.cc`; `regenerate-slot-engine.py` round trip passed; `test_patch.py` 4 tests OK.

Client: only a two-line comment in `client/native_slot_client.mm` explaining why 5/6/7 arrive from the chrome_pages hook. No logic change; temporary diagnostics were removed.

Mirrors: while I worked, the concurrent Swift styling agent changed `NativeWorkspaceController.swift`, `CommandBar.swift`, `SidebarStyle.swift`, `CommandBarController.swift` and `SettingsWindowController.swift`. I re-staged those mirrors (`tmp/f1-stage.py`) and regenerated; the first build failed on their half-edited `NativeWorkspaceController.swift` (`workspaceIDs` undefined) and passed on the next restage. The staged tree therefore contains their work in progress as of the final build.

Build: `native_slot.py check` passed (50 files); `build --execute` succeeded three times (diagnostic client, engine, final client). Last segment archived at `logs/f1-build-segment.log` (it starts at the last `offline mode` line, so it also contains the earlier failed attempts).

## Verification (real host)

Wrappers `tmp/launch-f1-v1.py` (diagnostic client only, reproduced F1: no log, Chromium tab `chrome://history`), `launch-f1-v2.py` (engine fix, diagnostic client) and `launch-f1-v3.py` (final binary), all `--use-mock-keychain`, receipt guards chained from `logs/essentials-v2-exit.json`. States `runtime/f1-state-v{1,2,3}`. Quit only through the app menu item "Quit Chromium" (the app menu is titled "cefsimple"); exit codes 0 in `logs/f1-v{1,2,3}-exit.json`. Bato confirmed frontmost (System Events) before each chord. Real chords via `osascript` keystroke.

| Check | Result |
| --- | --- |
| Cmd-Y with History row closed (v2) | PASS. Log showed IDC 40010, command 5 routed; Bato "History" row created and selected, address chrome://history, `organization.json` holds the history URL. |
| Shift-Cmd-J (v2) | PASS. Command 6 routed; Bato "Download History" row selected (chrome://downloads), URL in org JSON. |
| Cmd-, (v2) | PASS. Command 7 routed; native "Settings" window opened (panes Profiles, Privacy, Import, Shortcuts, Advanced). |
| Menu: History > Show Full History | PASS. Command 5 routed, History row recreated. |
| Menu: Window > Downloads | PASS. Command 6 routed; the existing Download History row was reselected (the earlier close of that row had not applied). |
| Menu: cefsimple > Settings... | PASS. Command 7 routed; the Settings window was already open and stayed key; no chrome://settings tab in the window list. |
| Final binary smoke (v3): Cmd-Y, Shift-Cmd-J, Cmd-, | PASS. History and Download History rows created, Settings window listed, window titles show no stray Chromium tab. |
| Quit and lifecycle | PASS. Exit 0 each run; v2: `native-slot-detached` 2, `profile-contexts-released` 2, `cef-shutdown-complete` 1, no `refused`/`mismatch`; v3 no `refused`/`mismatch`. |

## Not verified

- Which upstream site bypasses `HandleCommandWithDisposition` (see above). Reload and other commands are probably equally unreachable from `OnChromeCommand` via menus; nothing here fixes that.
- Cmd-, with the Settings window key; keys with a Chrome-owned active tab (expected: Chromium opens its own tab).
- Incognito history disclaimer path (`ShowHistory` returns the disclaimer only after the hook declines).
- `ShowSettings`, `ShowDownloads` callers other than the menu (download bubble "Show all", profile menu) now also route to Bato when a Bato page is active; not exercised.
- Swift test suite not run (no Swift code changed by me).
