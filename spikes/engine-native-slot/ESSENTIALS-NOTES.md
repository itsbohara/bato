# Browser essentials: first slice notes

Status: source and unit tests only. No engine build, no browser launch, no commit. Swift suite: 274 tests pass (SSD `logs/essentials-swift-tests.log`). See ESSENTIALS-PLAN.md for design.

## What was done

- `BrowserEssential` (history, downloads, chromium settings): exact `chrome://` allowlist. `BrowserState` now saves these URLs in organization; every other non-HTTP(S) URL is still refused.
- `PageRuntime.openEssential`: reuse the tab in the current Workspace or open one, so history and downloads stay per Profile.
- Command bar gained History, Downloads and Settings commands.
- Native Settings window (`SettingsWindowController`): rail of Profiles, Privacy, Import, Shortcuts, Advanced; Profiles lists Profiles with Create and Rename (current); Privacy has the current Profile's blocking switch and exceptions; Import launches the Arc flow; Advanced opens History, Downloads and Chromium Settings tabs. Settings actions that use sheets bring the browser window forward first.
- Client: `ValidCreateDestination` (page creation only) accepts the three chrome pages; `BatoWorkspaceChromeCommand` maps `IDC_SHOW_HISTORY`, `IDC_SHOW_DOWNLOADS`, `IDC_OPTIONS` to Swift commands 5, 6, 7, handled in `workspaceCommand`.
- Existing tests that used `chrome://settings` as an example of an unsupported URL now use `chrome://flags`.

## Files

New: `app/Sources/BatoCore/Essentials.swift`, `app/Sources/BatoCore/SettingsModel.swift`, `app/Sources/BatoRuntime/EssentialsRuntime.swift`, `app/Sources/BatoBrowserUI/SettingsWindowController.swift`, tests `EssentialsTests.swift`, `SettingsModelTests.swift`, `EssentialsRuntimeTests.swift`, plus the two plan/notes docs.

Edited: `BatoCore/BrowserState.swift` (one line in `validateURL`), `BatoCore/CommandBar.swift` (3 commands), `BatoBrowserUI/NativeWorkspaceController.swift` (settingsWindow property, `openEssential`, `showSettings`, `fromBrowserWindow`, one `settingsWindow?.reload()` in `render`, three switch cases, `import BatoBlocking`), `client/WorkspaceSlot.swift` (commands 5 to 7), `client/native_slot_client.mm`, `client/compile_native_slot.py`, `client.json` (4 files plus mirrors, patched hashes will be refreshed by regeneration), `Tests/BatoRuntimeTests/PageRuntimeTests.swift`.

Staged tree (`SSD/source/chromium/src/cef`): BUILD.gn inputs for the 4 new files added; the 4 new files, `compile_native_slot.py`, `native_slot_client.mm`, `WorkspaceSlot.swift`, `BrowserState.swift`, `CommandBar.swift` copied. NOT copied (shared with the styling agent, sync after merge): `NativeWorkspaceController.swift`, `CommandBarController.swift`. The styling agent's `SidebarStyle.swift` is not yet in `compile_native_slot.py`, `client.json` or BUILD.gn inputs.

## Coordinator steps

1. Merge with the styling agent, sync the changed mirrors into the staged tree, add `SidebarStyle.swift` to the compile list, client.json and BUILD.gn if it is new.
2. Run `SSD/tmp/regenerate-workspace-client.py`, then the native-slot check, then the engine-side client build.

## Needs engine build and real-host verification

- `IDC_SHOW_HISTORY`, `IDC_SHOW_DOWNLOADS` and `IDC_OPTIONS` reach `OnChromeCommand` from the app menu and from Cmd-Y, Shift-Cmd-J, Cmd-, while page content has focus (only Shift-Cmd-C is proven so far). If a command id is not delivered, Chromium opens its own unmanaged tab instead.
- Creating a `chrome://` tab through the client page-creation path, its title and URL events, and that the sidebar row, close and relaunch restore work.
- History and Downloads are separate per Profile (two Profiles, check different content).
- Cmd-, while the Settings window is key, and Settings opening alongside fullscreen, a sheet or Peek.
- Settings window look against Dia captures 10, 11 and 16 (rail width, row heights, switch style). Dark mode.
- Create Profile, Rename and Arc import started from Settings (sheet on the browser window).
- Reload from the blocking menu and Cmd-L navigate-current are web-only; they do nothing on chrome:// pages.

## Not done

Sidebar downloads indicator and progress, Appearance pane, per-Profile clear-data entry, new-window-opens-with preference, Settings window persistence of the last pane.
