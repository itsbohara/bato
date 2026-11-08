# Polish round 3: real-host results

Run 2026-11-07 on the uncommitted build (`libBatoNativeSlot.dylib` 18:20, newer than the Round 3 Swift edits at 18:19), driven with `agent-desktop` plus `osascript` System Events chords. Nothing built, edited or committed. Logs and screenshots are on the SSD (`logs/polish3-v1*`, `logs/polish3-v2*`, shots in `logs/polish3-v{1,2}-shots/`); none are in the repo. Wrappers `tmp/launch-polish3-v1.py` (guard `logs/polish2-v1-exit.json`, state `runtime/polish3-state-v1` copied from `polish2-state-v1`) and `tmp/launch-polish3-v2.py` (guard `logs/polish3-v1-exit.json`, state `runtime/polish3-state-v2`, same source); both use `--use-mock-keychain`. Fixture servers 18765/18766 were already up (HTTP 200). Bato was frontmost before every key chord (`tmp/p3-key.sh`, `tmp/p3-keycode.sh` abort otherwise). Dark mode only.

## Modes tested

- **Increase Contrast ON** (host default): run v1, 4 Profile windows.
- **Increase Contrast OFF**: `defaults write com.apple.universalaccess increaseContrast -bool false` works for new processes but the running Bato does not observe the change live (a refreshed screenshot was identical to IC-on), so IC-off needed a relaunch (v2, 2 windows). Setting restored to `1` afterwards (`defaults read` = 1, `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` = true).

## Results

| # | Check | IC on | IC off |
| --- | --- | --- | --- |
| P1 | "History" + Return opens History, not web search | PASS. Command row is first and selected; Return from a Storage tab switched to History (title History, no search). | PASS (same flow; title History after Return). |
| P1b | Arrow choice preserved while query unchanged | PASS. Down selected the web-search row and it stayed selected after 3 s; Up returned to the command. | PASS (Down selected search row after 3 s). |
| P2 | Blue/green visibly tinted vs orange | PASS. Research (slate blue), Personal (green), Work (orange), Space 2/Side (rose brown) all clearly tinted. | PASS. Blue, green and orange all strongly tinted, orange the most saturated. |
| P3 | Selected-row ring | As expected: 1.5 pt light ring on selected row and selected favorites. | PASS. Neutral pill, no ring. |
| P4 | Favorite fallback letters differ | PASS. Tiles B, S, A for different local pages with different hues; two pages with identical title letter "E" get different hues. | not rechecked (identical in IC-off screenshots) |
| P5 | Shortcuts card same width | PASS. Card spans x 366-976 in Shortcuts and Privacy. | PASS. Same. |
| R1 | Cmd-Y / Shift-Cmd-J / Cmd-, route to Bato | PASS. History tab, Download History tab, Settings window (960x700). | PASS. |
| R2 | Clean quit via "Quit Chromium" | PASS, 4 Profile windows: exit 0 (`logs/polish3-v1-exit.json`); attached/detached 4/4, `profile-contexts-released` 2, `cef-shutdown-complete` 1, no `refused`/`mismatch`/`Cannot create profile`. | PASS: exit 0 (`logs/polish3-v2-exit.json`); attached/detached 2/2, contexts released 2, shutdown 1, no refusals. |

## Dia comparison (17, 33, 11)

Green tint in Bato (#3F5F3A-ish wash) now reads like Dia 33's dark green translucent sidebar, slightly brighter. Settings pane grouping with "Content blocking" heading and right-aligned controls is closer to Dia 11. Still open versus Dia (unchanged from Round 2): the sidebar is a blank dark slab behind the command bar (F3; Dia 17 keeps it visible), no leading search glyph spacing in the input (the glyph overlaps the first letter), profile switcher not exercised.

## Defects and notes

- **N1 (low): command-bar input glyph overlaps the first character** ("H" overlaps the magnifier icon at the left of the field) in both modes.
- **N2 (info): Bato does not react to Increase Contrast changes while running**; it reads the setting at launch (or first draw). Harmless unless live switching is a goal.
- **F3 persists (low):** blank sidebar behind the command bar.
- Chromium's "Make Chromium faster" Memory Saver bubble appeared after Cmd-Y in an IC-on window (stock Chromium, not a Bato issue).
- `127.0.0.1` fixture favorites and temp tabs were not re-created; only the existing state was exercised.

## Not verified

Light mode, Profile switcher popover, favicon-backed favorites, Settings Profiles sheets, Esc cancel.

---

# Side-by-side polish pass (2026-11-08)

Existing build (`libBatoNativeSlot.dylib` 21:59, newer than all Swift sources) run once with `tmp/launch-sbs-v1.py` (guard `logs/m6-v5-exit.json`, state `runtime/sbs-state-v1`, `--use-mock-keychain`, SSD paths); quit through the app menu, exit 0 (`logs/sbs-v1-exit.json`). Before shots, cropped to the Bato window, in `tmp/sbs-shots/` on the SSD (`w-106-a.png` sidebar plus recovery-style sheet, `cmdbar-a.png`, `profile-pop-a.png`, `settings-privacy-a.png`). Dark mode with Increase Contrast ON only. References: Dia 33, 17, 10. No engine build was run, so the fixes below are NOT yet in any binary and have no after screenshots; the client mirrors (`client.json` `source_mirrors`, patch hashes) were not regenerated because the engine agent owns `client.patch`/`client.json` this batch. Next engine/client build must sync the five edited mirrors below.

| Surface | Gap vs Dia | Fix | Status |
| --- | --- | --- | --- |
| Sidebar selected row | Bato lifts the row lighter (label 16%); Dia sinks it into the tint with a darker pill (33, 17) | `SidebarStyle.selectedRowFill`: dark black 28%, light white 55% | Fixed in source, unverified in host |
| Command bar field | Hairline under the field and 22pt text; Dia has no divider and ~20pt | Divider removed, field 20pt | Fixed in source |
| Command bar rows | Tab/arrow glyphs and 13pt detail; Dia uses globe for URLs, magnifier for searches, larger secondary text | Globe/magnifier glyph for open/navigate rows, detail 14pt | Fixed in source |
| Switcher popover | Rows 30pt; Dia ~24-26pt (33) | Rows 27pt | Fixed in source |
| Settings rail | All rail labels medium weight; Dia regular with a bold selected row (10) | Regular, semibold when selected | Fixed in source |
| Switcher popover arrow | NSPopover always draws an arrow; Dia's menu hangs flush under the header | none | Remaining (needs custom panel) |
| Sidebar width | Bato default 255pt wide so favorites are 75pt tiles; Dia about 190pt (tiles about 55x41pt) | none, width is user-resizable and engine-owned | Remaining, confirm intended default |
| Command bar | Go pill is white; Dia's is workspace-tinted sage; Dia has "Add tabs or files" and mic controls; bar sits lower | none | Remaining |
| Settings | Rail is a lighter grey slab; Dia's rail matches the content background | none | Remaining |
| Launch window | Blank grey slab sidebar on the about:blank window (F3) | none | Remaining, WorkspaceSlot/engine |
| Archive sheet, recovery card, downloads, light mode, motion | not captured this run (no Dia light capture exists; motion not measurable by screenshot) | none | Not verified |

## Files changed (Swift only)

`app/Sources/BatoBrowserUI/SidebarStyle.swift`, `CommandBarController.swift`, `SettingsWindowController.swift`, `SwitcherPopover.swift` (all four have client mirrors). Other modified files in the tree (`NativeWorkspaceController.swift`, `BrowserState.swift`, `PageRuntime.swift`, `ClosedTabRuntimeTests.swift`) belong to another agent and were not touched.

## Tests

`cd app && swift test`: 215 tests in 26 suites passed.
