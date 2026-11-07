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
