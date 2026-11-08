# Command palette restyle (Arc look): real-host results

Run 2026-11-08, uncommitted. Swift only: `CommandBarController.swift` (rewritten view layer; init no longer takes `providerChanged`, gains `pageIcon`), `SidebarStyle.swift` (palette constants; `commandBarSize` replaced by width/header/inset/max-rows), `NativeWorkspaceController.swift` (one line: passes `pageIcons` to the bar). The five Swift mirrors were staged and `client.patch`/`client.json` regenerated, `native_slot.py check` and `build --execute` run only while `autoninja` was idle, `test_patch.py` OK, `cd app && swift test` 215 tests pass.

Launches (SSD only, `--use-mock-keychain`, state copied from `runtime/sbs-state-v1`): `tmp/launch-palette-v{1..4}.py`, states `runtime/palette-state-v{2,3,4}` (v1 mistakenly reused `sbs-state-v1`), logs and exit receipts `logs/palette-v{1..4}*`, all exit 0 via the app menu "Quit Bato". Latest build is v4. System appearance was toggled to Light for the light shots and restored to Dark.

Reference: no Arc captures exist in `/Volumes/Mahesh/personal/bato-references/` (only `dia/`, whose `17-command-bar-url.jpg` is a different design). Comparison is against the Arc description in the task, not an Arc image.

Shots (Bato window only, `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/`): `palette-dark-empty.png`, `palette-dark-query.png`, `palette-dark-fewrows.png`, `palette-light-empty.png`, `palette-light-query.png`, `palette-light-fewrows.png` (v4); `palette-dark-down2.png`, `palette-dark-after-return.png`, `palette-light-favicon.png` (v2, same visuals).

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Panel 760pt wide, centred horizontally over the window | PASS | palette-dark-empty.png: x 226-986 of 1100pt window (760pt) |
| 2 | Upper third vertically | PARTIAL | 7+ rows: top at ~25% of window height. Fewer rows: AppKit re-centres the sheet, so the top moves down (top at ~38% with 2 rows); `setFrameTopLeftPoint` is ignored for sheets |
| 3 | Dark translucent ~#1c1c1e, radius 12, 1px hairline, soft shadow | PASS (colour approximate) | palette-dark-*.png: vibrancy under 0.098/0.098/0.106 tint at 0.9 alpha; reads as ~#232325 because the vibrancy lifts it |
| 4 | Page visible, not heavily dimmed | PARTIAL | Page around the panel is visible. The panel is nearly opaque (page does not show through); the host window greys when the sheet is key |
| 5 | Magnifier + 19pt medium field, placeholder "Search or Enter URL..." in secondary grey, 56pt header, full-width hairline | PASS | palette-dark-empty.png, palette-light-empty.png; the old glyph/first-letter overlap (N1) is gone |
| 6 | Rows 50pt, inset 8pt, 16pt favicon, 14pt semibold title | PASS | rows at 50pt pitch, pill inset 8pt from panel edges |
| 7 | Selected row: indigo #5b5bd6 pill radius 8, white text, "Switch to Tab" + arrow in white rounded square | PASS | palette-dark-query.png, palette-light-query.png |
| 8 | Unselected: grey uppercase workspace label + arrow in dim rounded square, no background | PASS | "WORK", "SPACE 2" rows |
| 9 | Non-tab rows get a sensible label | PASS | "Open", "Peek", "Run"/"Command" (palette-dark-fewrows.png) |
| 10 | Panel height hugs rows, up to 7, no scrollbar, 8pt bottom padding | PASS | palette-dark-fewrows.png (2 rows), palette-dark-empty.png (7 rows) |
| 11 | Real favicons where available, neat fallback otherwise | PASS | palette-light-favicon.png shows the DuckDuckGo favicon; fixture example.test pages show `FaviconFallback` letter tiles (they have no icon) |
| 12 | Light mode: light translucent panel, same accent pill | PASS | palette-light-*.png |
| 13 | Keyboard: Down moves selection, Return runs the choice, Escape dismisses | PASS | palette-dark-down2.png (Down x2 moves to third row); Return on "fav" opened "fav at DuckDuckGo" (palette-dark-after-return.png); Escape closed the sheet (AX showed no sheet field afterwards, no shot of the closed state kept). Done on the v2 build; the v4 change only touched window sizing |
| 14 | Increase Contrast border / live appearance change | NOT VERIFIED | border width logic kept (1.5pt on Increase Contrast), not exercised |

Behaviour notes: the provider picker, "Go" pill and hint footer are removed (Search provider stays in Settings > General); invalid-input messages and errors show in a single status line under the list (not exercised in a shot). When the sheet is not key (host window active) Escape/Return need the field focused first; this is unchanged from before.

## Remaining gaps

- Top edge moves with result count (see check 2). A fix needs a non-sheet floating child panel, which touches the host's sheet lifecycle.
- Panel is near-opaque, not Arc's see-through; no Arc capture to calibrate tint.
- Selected pill is a fixed indigo, not workspace-tinted.
- Rows show the URL after the title; Arc shows only a trailing label for tabs (kept for disambiguation).
- No Arc reference image on disk, so pixel comparison against Arc was not possible.
