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

# Palette round 2: fixed top edge, query suggestions (2026-11-08)

Uncommitted. The sheet is replaced by a borderless child `NSPanel` (`CommandBarController.present(over:card:completion:)`) anchored by its top edge: centred on the content card, top 38% down it (`SidebarStyle.commandBarFrame`), growing downward. Typed queries add provider suggestions (`SearchSuggestions`, `SearchSuggestionFetcher` in `BatoCore/CommandBar.swift`; DuckDuckGo `duckduckgo.com/ac/?q=`, Google `suggestqueries.google.com/complete/search?client=firefox&q=`, Brave `search.brave.com/api/suggest?q=`, Bing `api.bing.com/osjson.aspx?query=`), 120 ms debounce, new request cancels the old one, failures show nothing. Rows for a query: search row, up to 3 open-tab matches, suggestions, then commands, capped at 7 (`CommandBarResults.queryRowLimit`). New preference `searchSuggestions` (default ON) in `AppPreferencesStore`, switch under Settings > Privacy > Command bar. Addresses, empty input and input over 100 characters are never sent. Browsing history rows are not included: history lives in Chromium and Swift has no access to it.

Also fixed while measuring: the table's inset style added ~10pt above the first row and cut the last row; now `.plain` with zero scroll insets (pill top 8pt under the divider, 8pt below the last row).

Behaviour changes from the sheet: the panel is non-modal. Cmd shortcuts other than edit keys, Q, H and M are swallowed while it is key (otherwise Cmd-W would close the page behind). Esc, a click anywhere outside, the app resigning key, or the parent window closing all dismiss it; Return/arrows unchanged.

Build/test: `swift test` 247 XCTest + 221 Swift Testing, 0 failures (new: `SearchSuggestionsTests` 15 incl. parsing, endpoints, row assembly, debounce, cancellation, stale response; `CommandBarAnchorTests`; two `AppPreferencesStoreTests`). Mirrors staged (6 files), `client.patch`/`client.json` regenerated (60 files, 55 mirrors), `test_patch.py` OK, `native_slot.py build` run only while `autoninja`/`siso` were idle (`logs/palette2-build3.log`; builds 1-2 failed or were overtaken by a concurrent agent's half-written `WorkspaceSlot.swift`, no effect on this change).

Runs: `tmp/launch-palette2-v1.py`/`v2.py`, states `runtime/palette2-state-v{1,2}`, profiles `runtime/profiles/palette2-v{1,2}`, `--use-mock-keychain`, SSD only, quit via the app menu (exit 0: `logs/palette2-v{1,2}-exit.json`). dist/Bato.app untouched. A second `cefsimple` instance from another agent shares the bundle id, so System Events cannot target keystrokes by pid; keys and the click were posted with a CGEvent `postToPid` helper (`tmp/postkey`), windows picked by pid and shot with `agent-desktop screenshot --window-id`. System appearance was set to Light for the light shots and restored to Dark. Shots: `tmp/sbs-shots/palette2-*.png` (cropped; `raw2-*.png` uncropped, used for pixel measurement).

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Top edge identical for 1 row, 4, 7 rows and empty query (dark) | PASS | `raw2-{empty,onechar,full,few,many}-dark.png`: hairline top at y=422 in all five. Window bounds from `list-windows`: panel y=459 on screen = 384pt below the window top, 38% of the card (8..997) |
| 2 | Top edge, light | PASS (1px) | `raw2-*-light.png` y=421 in all five; 1px offset vs dark is the hairline detector on a light page, same frame |
| 3 | Horizontally centred on the content card | PASS | docked-sidebar run: panel centred on the card, not the window (`palette2-empty-dark.png` crop offset); width 760 |
| 4 | Empty query unchanged (open tabs, "Switch to Tab" on selected) | PASS | `palette2-empty-dark.png`, `palette2-empty-light.png` |
| 5 | 1 char: search row + tab matches + provider suggestions, 7 rows | PASS | `palette2-onechar-dark.png`, `-light.png` |
| 6 | Full query "hello": search row + 6 suggestions | PASS | `palette2-full-dark.png`, `-light.png` |
| 7 | Suggestion rows: magnifier glyph, plain title, no trailing label unless selected | PASS | `palette2-full-*`; selecting one shows "Search" + arrow (`palette2-many-down2-dark.png` shows a tab row selected, "Switch to Tab") |
| 8 | Selected row in query mode: indigo pill, white, title only (URL hidden), trailing "Search"/"Switch to Tab" | PASS | `palette2-onechar-*`, `palette2-many-down2-dark.png` |
| 9 | Few rows (no suggestions, 1 row): padding correct, no clipping | PASS | `palette2-few-dark.png`, `-light.png` (after the `.plain` table fix; before it the pill was clipped) |
| 10 | Offline / provider failure shows only local rows, no error | PASS (unit) / not run live | `SearchSuggestionFetcherTests.testFailureAndAddressInputDeliverNothing`; `palette2-few-dark.png` is the no-suggestions layout (nonsense query returned none). Network was not cut live |
| 11 | Privacy toggle: default ON, persists, OFF stops fetching | PASS | `palette2-settings-privacy-on.png`; toggled off, `preferences.json` has `"searchSuggestions": false`, `palette2-suggestions-off-dark.png` shows only the search row for "hello" |
| 12 | Keys: type, Down/Up, Return opens search in a new tab, Esc dismisses | PASS | `palette2-down2-dark.png` (v1 build), `palette2-after-return-full.png` ("hello at DuckDuckGo" tab opened, URL `?q=hello`); Esc closed the panel and Cmd-T reopened it |
| 13 | Click outside dismisses | PASS (synthetic click) | CGEvent click posted to the process closed the panel (`palette2-clickout.png`); not tried with a physical mouse |
| 14 | Focus: panel is key on open, field focused; main window key again after dismiss | PASS | typing reached the field on every open; after Return the new tab window was key (`list-windows` is_focused) |
| 15 | Shadow / radius / hairline preserved | PASS | `palette2-*-dark.png`, `-light.png` |
| 16 | Hidden-sidebar run (card full width) | NOT VERIFIED | the anchor follows `ContentCardFrameView.cardRectOnScreen`, covered by `CommandBarAnchorTests` only |
| 17 | Parent window resize while open | NOT VERIFIED | observer re-anchors via `didResize`, not exercised |

## Open items

- Browsing history is not a source of rows (Chromium owns it); only open tabs, pins and Favorites match.
- Fullscreen/resize re-anchoring and the hidden-sidebar centre were not exercised on the host.
- The focus after Esc relies on `requestNativeFocus`; page keyboard focus after Esc was not checked separately.
- Suggestions come from the provider chosen in Settings > General; there is no separate suggestion-provider setting.
