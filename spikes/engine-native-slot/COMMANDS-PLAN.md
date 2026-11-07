# Browser command ownership (ALPHA-GAPS milestone 1)

Static audit of Chromium 156 source plus the F1 finding. Nothing here is measured yet; COMMANDS-RESULTS.md records the real-host run.

## How a command reaches Bato

- Every Bato page is a tab of one Chrome `Browser` per Profile window (`bato_native_slot_new_tab_v1` calls `chrome::NewTab` on the slot's browser; `bato_native_slot_active_browser_id_v1` is the active tab's browser). Chrome's tab strip is hidden, so anything that acts on "the active tab" acts on the Bato page the sidebar shows.
- `OnChromeCommand` (via `BrowserCommandController::HandleCommandWithDisposition`) is not on the path of accelerators and menu items that are action-backed (`browser_actions.cc`, F1). Terminal functions in `chrome::` are on every path, so the narrow hook is an offer to `cef_delegate()->HandleCommand()` at the terminal function, the F1 pattern.
- Physical Cmd-T, Cmd-W, Cmd-L, Cmd-S, Shift-Cmd-C are already claimed by the client's key monitor (`WorkspaceKeyRouter`), ahead of Chromium.

## Audit

Target = what the command acts on. "Bato state" = does it change or ignore Bato's organization (sidebar rows, selection, saved entries).

| Command | Chords | Chromium route | Target | Effect on Bato state | Decision |
| --- | --- | --- | --- | --- | --- |
| Reload / Hard reload | Cmd-R, Shift-Cmd-R | `chrome::Reload` / `ReloadBypassingCache` on active WebContents (action + IDC) | Active tab = Bato page | None (same entry, same URL; navigation events already flow) | Leave to Chromium; verify it hits the right page |
| Stop | Cmd-. | `chrome::Stop` on active WebContents | Active Bato page | None | Leave |
| Back / Forward | Cmd-[ , Cmd-] | `chrome::GoBack/GoForward` on active WebContents | Active Bato page (split: focused side, COMPACT-FOLDERS-RESULTS) | None; navigation recorded by page events | Leave |
| New Tab | Cmd-T | Key monitor (physical); menu and toolbar: `kActionNewTab` lambda -> `chrome::NewTab` | Command bar | Physical chord is Bato-owned; the menu item left an untracked Chromium NTP (found in the real-host run, COMMANDS-RESULTS.md) | Fix: offer in the action lambda (not in `chrome::NewTab`, which Bato's own helper calls) |
| Close Tab | Cmd-W | Key monitor (physical); menu: `kActionCloseTab` lambda -> `chrome::CloseTab` | Bato selection | Physical chord is Bato-owned; the menu item closed the page behind Bato's back and left its row | Fix: offer in the action lambda |
| Reopen Closed Tab | Shift-Cmd-T | `chrome::RestoreTab` -> Chrome `TabRestoreService` (+ `AppController` `TabRestorer` when no browser window is key) | New Chrome tab in the window, no entry | Creates an untracked page; Bato rows never reopen | Fix: engine offer in `RestoreTab`; Swift closed-tab stack |
| New Window | Cmd-N | `chrome::NewWindow` -> `NewEmptyWindow(profile)` (+ `AppController::CreateBrowser` when no browser window is key) | Second Chrome window in the Profile | Second window with no sidebar and an untracked tab, violates one window per Profile | Fix: engine offer in `NewWindow`; Bato maps it to the command bar |
| Next / Previous Tab | Ctrl-Tab, Ctrl-Shift-Tab, Cmd-Opt-Right/Left, Shift-Cmd-] / [ | `chrome::SelectNextTab/SelectPreviousTab` (`CycleToMruTab` only with the disabled-by-default `kCtrlTabMru`) | Chrome tab strip order | Selects a tab behind Bato's back: sidebar selection and `activeEntryID` can diverge from the visible page; order is Chrome's creation order, not sidebar order | Fix: engine offer in both functions; Bato steps through sidebar order with wrap |
| Select Tab 1-8, Last | Cmd-1..8, Cmd-9 | Action lambdas `SelectNumberedTab` / `SelectLastTab`; IDC route in `HandleCommandWithDisposition` | Chrome tab strip index | Same divergence as above | Fix: offer in the action lambdas for 1-8 and in `SelectLastTab`; Bato picks the nth row in sidebar order, Cmd-9 the last |
| Find | Cmd-F | `FindBarController` on active WebContents | Active Bato page | None | Leave; verify the find bar is visible and works in the native slot |
| Zoom in / out / actual size | Cmd-+ , Cmd-- , Cmd-0 | `chrome::Zoom` / `ZoomController` of the active WebContents | Active Bato page | None; zoom is per-origin in the Profile, not Bato state | Leave; verify it changes the visible page |
| Print | Cmd-P | `chrome::Print` on active WebContents | Active Bato page | None | Leave; verify the dialog opens attached to the Bato window |

Not in scope, noted: Shift-Cmd-N (incognito window, an OTR Profile with no Bato organization), Shift-Cmd-W (close window), Cmd-D and Cmd-Opt-B/Cmd-Shift-O (Chrome bookmarks, unrelated to Bato favorites), Cmd-Shift-A (tab search), Cmd-Shift-D, Chrome tab-group commands. `AppController` paths for New Window/Reopen are only used when no browser window is key (Dock menu, only the Settings window is key) and are not hooked: there is no `Browser` to offer the command to.

## Design

Engine (3 files, `engine.patch`, manifest now 17 files; the plan first listed no New Tab/Close Tab hook, the real-host run added it):

- `chrome/browser/ui/browser_commands.cc`: local `HandledByCef(browser, id)` (same shape as F1's), called at the top of `NewWindow`, `SelectNextTab`, `SelectPreviousTab`, `SelectLastTab`. Not in `SelectNumberedTab`: CEF's own `OnSetFocus` calls it to select the focused page and the client must not see that.
- `chrome/browser/ui/browser_actions.cc`: local `HandledByCef`; the Cmd-1..8 lambdas call `SelectNumberedTabUnlessCefHandles`, which offers `IDC_SELECT_TAB_0 + n` first; the `kActionNewTab` and `kActionCloseTab` lambdas offer `IDC_NEW_TAB` and `IDC_CLOSE_TAB`.
- `chrome/browser/ui/browser_tab_restorer.cc`: `RestoreTab` offers `IDC_RESTORE_TAB`.

Client (`native_slot_client.mm`, `WorkspaceSlot.swift`): `BatoWorkspaceChromeCommand` maps the IDs to Swift commands 1 (New Window = command bar), 8 (reopen), 9/10 (next/previous), 21..29 (shortcut 1..9) and logs every received id as `workspace-chrome-command`. A Chrome-owned active tab (`chrome://` pages Bato does not own) makes the client decline so Chromium behaves as before.

Swift:

- `BatoCore`: `ClosedTab`, `ClosedTabStack` (capacity 25), `BrowserState.closedTab(for:)`, `reopenTab(_:)`, `adjacentEntryID(step:)`, `entryID(forShortcut:)`.
- `BatoRuntime`: `PageRuntime` keeps one stack per Profile (the window is per Profile). A temporary tab is recorded when its entry is removed (engine `closed` event or an unloaded close), never saved entries (pins and Favorites stay in the sidebar). `reopenClosedTab()` restores title and `lastURL` at the old index of the old workspace (first workspace of the Profile if that is gone), selects it and lets the runtime load it. Empty stack: the chord is consumed and does nothing.
- `NativeWorkspaceController`: three small public methods; they ignore the chord while a sheet, command bar or finder is up.

Order for next/previous and Cmd-n is `visibleEntries` (Favorites, pins, then temporary tabs). Pins filed into folders sort by their position in the workspace's pin list, not by folder; refine if the folder order matters.
