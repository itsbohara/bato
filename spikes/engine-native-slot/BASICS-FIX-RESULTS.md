# Basics fix results (2026-11-08)

Swift/client-side fixes for ARC-PARITY-AUDIT items 1, 2, 4, 5, 7, 9. Real host: `cefsimple` test instance, `--use-mock-keychain`, SSD paths only (wrappers `launch-basics-v{1,2,3}.py`, states `runtime/basics-state-v{1,2,3}`, profiles `runtime/profiles/basics-v{1,2,3}`, logs `logs/basics-v*`), windows chosen by pid, every instance quit through the app menu (exit 0, receipts `logs/basics-v1-exit.json` (last overwritten by v2), `logs/basics-v3-exit.json`). The user's dist/Bato.app was running and untouched. Screenshots: `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/basics-*.png`. `swift test`: 215 Swift Testing tests plus XCTest suites, 0 failures (new `BasicsMenuTests`).

| # | Item | Result | Evidence |
| --- | --- | --- | --- |
| 1a | Ctrl-1..9 switches workspace | PASS | Spaces menu items carry Control-digit key equivalents. Synthetic Ctrl-2 / Ctrl-1 (System Events) switched Research and Workspace 2 and back (basics-ctrl1/2, basics-v2-ctrl1/2); menu clicks on the Space rows also switch |
| 1b | Shortcuts label | PASS | Settings > Shortcuts row now "Switch workspace ⌃1-9" (unit test). Settings window not re-screenshotted |
| 2a | Copy URL via Edit menu | PASS | Edit > Copy URL (clipboard read with pbpaste = page URL); Copy URL as Markdown gives `[Video - Bato sidebar fixture](http://127.0.0.1:18765/sidebar/video.html)`. basics-edit-menu.png |
| 2b | Cmd-Shift-C chord | PASS via menu routing, BLOCKED by Raycast for raw keys | `agent-desktop press cmd+shift+c` (AXPress of the bound menu item) copied the URL. A raw synthetic Cmd-Shift-C never reaches Bato on this Mac: Raycast's Clipboard History opens on the same global hotkey (basics-chord-c.png shows its panel). This is the cause of the audit's "never worked" and of NAV-HEADER's unconfirmed chord; it is not an app bug. Change or disable Raycast's clipboard hotkey for a physical check. Cmd-Opt-Shift-C (Markdown) reached Bato and copied |
| 2c | "Copied" toast | PASS | basics-copied-toast-v3.png (pill below the toolbar, fades after about 1s) |
| 3 | Middle-click closes sidebar row | PASS | duplicate row closed by a physical middle click (basics-after-middle-click.png) |
| 4 | Tab context menu | PASS | Close Tab, Duplicate, Reload, Open in Peek, Mute Tab, Copy URL (renamed from Copy Link, same AX id) added to the existing menu (basics-tab-context-menu-v2.png). Close and Duplicate exercised (Duplicate made a new selected tab). Open in Peek exercised (peek presented, Close dismissed). Reload only clicked: it re-loads the page URL through the navigate hook, no navigation event was inspected. Reload and Peek are enabled only for the selected tab. Mute Tab uses the audio agent's `TabAudioCenter`; it is disabled when the tab has no audio state and was not exercised with playing audio |
| 5a | Spaces menu | PASS | Lists spaces with ⌃1-9 and a checkmark on the active one, Next/Previous Space (⌃⌘→/←), New Space; rebuilt on every state change (New Space added a row live). basics-spaces-menu.png. Next/Previous and New Space items not separately clicked/keyed (⌃⌘ arrows untested) |
| 5b | Stock menus removed | PASS | Bookmarks and Profiles menus hidden (top level now: File Edit View History Tab Spaces Window Help Sidebar Peek Page); View > Show Tabs Vertically removed (basics-view-menu-v2.png). Chromium re-shows a hidden item as its menu opens, so items are removed, not hidden. Chromium's Profiles menu was hidden, not replaced with Bato's Profiles. "Always Show AI Mode" and "Always Show Bookmarks Bar" were not in this build's View menu but are on the removal list |
| 6 | Cmd-N / File > New Window | PARTIAL | No longer opens the command bar and never opens a stock Chromium window; it brings the Profile's window forward (deminiaturizes if needed). It does not create a second window: both key and menu produced command 35 and the pid's window count stayed 1. Each Profile has exactly one window and one sidebar (`windows[profileID]` map, single mounted sidebar), so a true second window needs engine/sidebar work |

## Files by layer

- Core (testable): `app/Sources/BatoCore/SettingsModel.swift` (label, `LinkFormat`, `SpaceMenuEntry`, `BrowserState.spaceMenuEntries`, `ChromiumMenuPolicy`), `app/Tests/BatoCoreTests/BasicsMenuTests.swift`.
- UI: `app/Sources/BatoBrowserUI/NativeWorkspaceController.swift` (tab context menu, `PageMenu`, middle-click, `CopiedToast`, space APIs, `showWindow`, Copy URL formats).
- Client Swift: `spikes/engine-native-slot/client/WorkspaceSlot.swift` (Spaces menu, Edit > Copy URL items, menu cleanup in `MenuBranding`, command 35).
- Client native: `spikes/engine-native-slot/client/native_slot_client.mm` (IDC_NEW_WINDOW maps to command 35 instead of 1).
- Regenerated: `client.json`, `client.patch` (shared with the engine agent's changes). `engine.patch` untouched by this work.

## Open

- Real second window for Cmd-N (engine plus multi-window sidebar).
- Physical Cmd-Shift-C check after freeing the hotkey from Raycast (or change it).
- Mute Tab with live audio, Reload navigation, Next/Previous Space chords.
- Chromium's Profiles menu is hidden rather than replaced by Bato's Profiles.
- Cmd-D and other Bookmarks menu key equivalents are gone with the hidden menu (intended).
