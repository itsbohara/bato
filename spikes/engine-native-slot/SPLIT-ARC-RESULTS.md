# Arc-style split view

Date: 2026-11-08. Uncommitted. Test instance only (mock keychain, SSD paths, `runtime/splitarc-state-v2` template, wrapper `tmp/launch-splitarc.py`, runs v1-v6, last exit receipt `logs/splitarc-v6-exit.json`, exit 0, one detach). dist/Bato.app and Application Support untouched.

## Design decisions

- **Engine already supports stacked layout.** Chromium 156 `MultiContentsView` has `SplitTabLayout::kStacked`. New export `bato_native_slot_present_split_v2(..., stacked)` selects it (`UpdateSplitLayout` on an existing pair); `_v1` wraps it as side-by-side. Orientation is persisted per pair in `PageSplit.orientation` (omitted when horizontal, missing decodes horizontal).
- **Chrome's toolbar is hidden while a pair is displayed** in a native-sidebar window (`BrowserViewLayoutDelegateImpl::IsToolbarVisible`). `MultiContentsView` reserves a 40pt band above each pane (`kNativePaneToolbarHeight`, must equal `SplitPaneChrome.toolbarHeight`), drops its 8pt inset (the card margin already surrounds the panes), squares the page corners, and hides Chrome's outline, padding and mini toolbar (`ContentsContainerView::SetNativePaneChrome`).
- **Per-pane native toolbars** (`SplitPaneOverlayView`) sit just below the card view. The card (`ContentCardFrameView`) now cuts one 12pt rounded rect per pane (same radius, shadow and hairline) with the workspace tint between, and draws the 2pt accent outline around the focused pane. Engine pushes pane frames through new `bato_native_slot_register_split_layout_callbacks_v1`, so divider drags move the toolbars live. Chromium's content view takes mouse events over its area, so the overlay forwards clicks from a local monitor.
- **Back/forward/reload/stop** are client-side CEF calls (`CefBrowser::GoBack` etc.) on any page of the slot, so an unfocused pane navigates without taking focus; state is polled at 0.4s.
- **Toolbar split button (unsplit state)**: hosted in the titlebar container like the show-sidebar button; the engine reserves a 40pt trailing exclusion (`kNativeSplitButtonSlot`) so Chrome's toolbar ends before it.
- **Add Split flow**: the command bar opens first (side remembered); choosing a URL creates the tab and the pair in one transaction (`BrowserState.addSplitTab`), choosing an existing page pairs it (`createSplit(with:side:)`). Cancelling changes nothing. From a pane's split menu the selected page leaves its pair and re-pairs with the new tab (the old partner stays as a tab).
- **Pane close ×** closes that pane's page through the normal close path (unload for pins); the pair dissolves and the other page stays.
- Sidebar toggle in the first pane: the existing titlebar show-sidebar button is kept; the first pane's row only leaves room for it.

## Results

Shots in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/` (window crops).

| Check | Shot | Result |
|---|---|---|
| Left/right: two rounded cards, 8pt tint gap, divider between | split-4-lr, split-5-hover-unfocused | pass |
| Top/bottom stacked cards | split-8-tb | pass (v4 build; engine, model and toolbars) |
| Focused pane toolbar: back, forward, reload, link glyph + host, split, close | split-4-lr | pass |
| Unfocused pane minimal: dimmed back/forward, host, close | split-4-lr, split-6-focus-switch | pass |
| Unfocused pane hovered shows reload and split button, minimal again on exit | split-5-hover-unfocused, split-6-focus-switch | pass (120ms fade coded; animation not frame-checked) |
| Accent outline follows focus (click on pane toolbar) | split-6-focus-switch | pass |
| Close pane: pair dissolves, other tab stays | split-9-close | pass |
| Split button menu lists Add Right/Left/Top/Bottom | split-10-menu | pass (menu text shown; glyph images not rendered by this menu style) |
| Page > Split View submenu and tab context "Open in Split View" > Right/Bottom | via AX; split-4-lr, split-8-tb | pass |
| Add Split opens the command bar, creates the pane on choice | palette seen (split-3-palette) | PARTIAL: committing from the palette could not be driven (the automation cannot activate the sheet window); the model/runtime path is unit tested |
| Light and dark | split-11-light, split-4-lr | pass; Dark restored |
| Sidebar split row shows both favicons and titles | split-4-lr | pass (favicons added to the two side buttons) |
| Orientation persisted across relaunch | none | not run |
| Divider drag resize with toolbars following | none | not run (layout pushes frames every layout pass, unverified by drag) |
| Extension icons in focused pane toolbar | none | NOT IMPLEMENTED (Chrome's toolbar is hidden; no native extension action API) |
| Toolbar split button in unsplit state, shown and clickable | split-0-start (glyph visible at trailing end) | glyph pass; menu click not exercised separately |

## Open items

Palette-driven Add Split commit; divider drag; orientation relaunch; extension icons; pane toolbar height 40pt leaves the first pane's centre line about 3pt off the traffic lights; Top/Bottom shot taken on the build before the host-width fix; menu glyphs not shown; the split-pair "Widen/Enlarge" menu remains in the sidebar only.

## Verification

`test_patch.py` OK (24 exports, new split-toolbar policy test); `swift test` 255 XCTest + 222 Swift Testing pass; client patch 62 files and 57 mirrors, engine 10 files verified; `native_slot.py check` patched; builds succeeded.

# Split row in the list, Ctrl-Tab switcher, resize grabber (2026-11-08, uncommitted)

Test instance only (mock keychain, SSD): wrapper `tmp/launch-splitrow.py`, seed `runtime/splitrow-seed`, states `runtime/splitrow-state-v{1,2}`, exits 0 via Quit Bato (`logs/splitrow-v{1,2}-exit.json`), builds `logs/splitrow-build-{1,2}.log` (client-only, 65-file client patch). dist/Bato.app and Application Support untouched. Shots `tmp/sbs-shots/splitrow-*.png`. 280 tests pass (new: `SplitRowTests` rows/DnD/move/swap/regression, `TabSwitcherTests`, `SplitGrabberTests`, `TabSwitcherPanelTests`).

Changes: the "Split view" block is gone; `BrowserState.sidebarRows()` collapses each pair to one row at its first drawn member (drawing and drop indices share it); `SidebarPairView` (one pill, two halves); `placeSplit`/`moveSplit`/`swapSplitSides`/`setSplitOrientation` in model and runtime; selecting either member now shows the pair and leaving only hides it (root cause of the Ctrl-Tab bug: `selectEntryInPlace`, `activateSplit` and `deactivateSplit` deleted any unpinned pair when the selection left it; four old tests changed to the new rule); MRU switcher; grabber in `ContentCardFrameView`.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | No top block; pair is one row at its first member's place (Today, folder) | PASS | splitrow-selected, -unselected-full |
| 2 | Halves equal width, favicon + title, divider, row height 38 | PASS | splitrow-selected-hover |
| 3 | Selected: container fill, lighter half plates, 4pt gap; hover shows a close on each half (closes that pane) | PASS | splitrow-selected-hover |
| 4 | Unselected idle: no fill, 1pt separator; hover fills the row, one close at the far right closes both, per-half hover card | PASS (single close drawn, click not exercised; card seen) | splitrow-hover-close, -light-hover-unselected |
| 5 | Click a half shows the pair and focuses that pane; middle-click | PASS click (AX); middle-click coded, not exercised | state `active/activeSplit` |
| 6 | Context menu: Pin Pair (hidden when saved), Separate All Tabs, Swap Sides, Convert to Vertical/Horizontal, Adjust Widths, per-tab submenus, Move to Workspace, Close Both Tabs | PASS (Separate and Swap verified by state; the others listed in menu) | splitrow-context-menu, -after-swap, -after-separate |
| 7 | Orientation toggle on a displayed pair | NOT RUN (menu item present, `setSplitOrientation` unit-tested) | |
| 8 | DnD pair as unit: reorder, into folder, to another Space (both members, state consistent) | PASS | splitrow-dragging, -after-drag-2, -after-folder; organization.json |
| 9 | DnD pin/unpin whole pair; Favorites refuses pairs | PASS unit tests; folder drop converted both to pins on host | SplitRowTests |
| 10 | Dropping a single tab onto a half | OUT OF SCOPE (lands before/after the row) | |
| 11 | Bug A: Ctrl-Tab away from a shown pair keeps it; switching back to a member shows it | PASS | state before/after, splitrow-after-switch-back; `testSwitchingAwayAndBackKeepsAndRedisplaysThePair` |
| 12 | Ctrl-Tab quick tap switches with no panel | PASS (toggled to previous, no panel in splitrow-ctrltab-tap) | |
| 13 | Hold Ctrl: panel after 300ms, centred, MRU order, pair = one card, Tab advances, release commits | PASS | splitrow-ctrltab-panel, -panel-2, -committed |
| 14 | Shift-Tab, Esc cancel, wrap | unit-tested state machine only; not driven on host | `TabSwitcherTests` |
| 15 | Switcher visuals vs Arc checklist (181x158 cards, 15 pad, #1a1919 plate, #3d3d3d border, r28, selected #423f82 r11, 150x100 plate, 16pt favicon + 14pt title) | PASS in values; plates show a large favicon, not a page thumbnail (no capture API) | splitrow-ctrltab-panel-2 |
| 16 | Grabber pill 2x24, #56505c idle, #949199 hover, centred in gap | PASS | splitrow-grabber-idle, -hover |
| 17 | Grabber drag resizes live; ratio persisted (0.5 to 0.333), gap follows pointer | PASS | splitrow-grabber-dragging, -after |
| 18 | Resize cursor | NOT VERIFIED (cursor not visible in captures) | |
| 19 | Light and dark (Dark restored) | PASS row, switcher | splitrow-light-selected, -light-ctrltab |

Arc split-view checklist items not met: pane gap is 8pt (Arc 10) and pane radius 12 (Arc 10) because both are engine layout constants; focus outline uses the workspace accent, not fixed #4f40f9, and has no glow; toolbar copy-link toast, extension icons and split-menu items (Move Left/Right, Separate Tab, Convert, Share) are not done; row context menu lacks Share, Change Icon, Rename, Duplicate, Archive entries.

## Open items

Pane gap/radius engine change; orientation toggle, Esc/Shift-Tab and middle-click not exercised on host; unpinned pairs now persist while hidden (they only disappear by Separate or closing a member); closing one member of a saved pair unloads it and re-selecting it re-shows the pair; Ctrl-Tab MRU is session-only and starts with the current tab then sidebar order; the grabber persists the ratio on every drag step (one save each); a user running Arc beside the test repeatedly took focus, so physical steps were guarded with a frontmost check.

# Cmd-W on a split (2026-11-08, uncommitted)

Arc behaviour recorded in ARC-REFERENCE-CHECKLIST.md section 5 (driven in Arc with two test example.com tabs, removed afterwards).

Bato now matches: `BrowserState.unloadPinnedPair`, `PageRuntime.closePinnedPair` (Cmd-W / Close Tab on a displayed pinned pair, and "Close Both Tabs" on a pinned row) unload both members through the engine, keep the pair saved, clear the selection (empty card) and skip the usual successor selection. Unpinned pairs keep the existing behaviour, which equals Arc's (only the focused pane closes).

Test instance `runtime/pin-state-v10` (exit 0, `logs/pin-v10-exit.json`); shots `tmp/sbs-shots/pin-cmdw-*.png`. Cmd-W key events posted to the process did not reach the inactive window, so the Close Tab menu item (same `closeSelection` path as Cmd-W) was clicked via the menu bar.

| Check | Result | Evidence |
| --- | --- | --- |
| Pinned pair shown, Close Tab: pair stays as one row, nothing selected, empty card, organization.json keeps the pinned pair | PASS | pin-cmdw-1, -2 |
| Re-selecting a half restores both panes | PASS | pin-cmdw-3-reselected |
| Unpinned pair, Close Tab: only the focused pane closes, other tab stays (Arc equivalent) | PASS | pin-cmdw-4-unpinned-after |
| Regression tests | PASS: `closingPinnedPairUnloadsBothKeepsPairAndClearsSelection`, `closingUnpinnedPairStillClosesOnlyTheFocusedPane`, `testUnloadPinnedPair*` | |
