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
