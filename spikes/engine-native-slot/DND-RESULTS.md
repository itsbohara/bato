# Sidebar drag and drop: real-host results

Run 2026-11-08, uncommitted. Model: `BrowserState.placeEntry(_:in:at:)` + `canPlaceEntry` + `sidebarSection(of:)` (`BrowserState.SidebarSection`: favorites, pinned(folder:), tabs), `PageRuntime.placeEntry`. UI: new `BatoBrowserUI/SidebarDragDrop.swift` (`SidebarDropMap` hit testing, `SidebarEntries` drag destination with insertion line / folder highlight, `SidebarEntryDragSource` with lifted drag image), `NativeWorkspaceController.swift` (slot registration at render, drag start on page rows/tiles, pager dots as drop targets). Tests: `SidebarPlacementTests` (7), `SidebarDropMapTests` (7); full `swift test` passes. Mirrors staged, `SidebarDragDrop.swift` added to client.json/BUILD.gn/compile_native_slot.py, client.patch regenerated (58 files, 53 mirrors), `native_slot.py check` ok, `build --execute` waited (logs/dnd-build.log, dnd-build2.log), `test_patch.py` OK.

Launches (SSD, `--use-mock-keychain`): `tmp/launch-dnd-v{1,2}.py`, state `runtime/dnd-state-v1` (seed `runtime/dnd-seed`: Research with 2 pins in folder Work, 3 tabs, 6 Favorites; second workspace Home), exits 0 via "Quit Bato" (`logs/dnd-v{1,2}-exit.json`). Real user app was never touched. Drags via `agent-desktop drag --headed` with a 3-5s drop delay so mid-drag screenshots could be taken. Shots: `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/dnd-*.png` (`-mid` = during drag, `-after` = after drop).

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Reorder within Today tabs | PASS | `dnd-1-middrag-tabs.png` (line, dimmed source, drag image), `dnd-2-after-tab-reorder.png`, organization.json order |
| 2 | Tab to pinned (unfiled) at pin end | PASS | `dnd-3-tab-to-pinned-*.png` |
| 3 | Pinned onto folder heading (moves in; heading highlighted) | PASS | `dnd-4-pin-to-folder-mid.png` |
| 4 | Reorder within a folder | PASS | `dnd-5-folder-reorder-*.png`, folder pinIDs order |
| 5 | Today tab onto folder heading | PASS | `dnd-17-tab-to-folder-*.png` |
| 6 | Folder pin out to unfiled pinned; reorder within unfiled pinned | PASS | `dnd-18-*`, `dnd-19-*`, state order Music, Docs |
| 7 | Today tab onto Essentials grid (becomes Favorite at pointer slot, vertical line) | PASS | `dnd-6-tab-to-favorites-mid.png` / `-after.png` |
| 8 | Reorder Essentials tiles | PASS | `dnd-7-favorite-reorder-*.png` (state order verified; line sits at the sidebar edge and is partly hidden by the drag image) |
| 9 | Essential back out to Today tabs (becomes temporary, savedURL dropped) | PASS | `dnd-8-favorite-to-tabs-after.png`, `dnd-14-esc-final.png` |
| 10 | Drop onto workspace pager dot moves tab to that Space | PASS | `dnd-9-tab-to-workspace-dot-mid.png` (dot highlight), Home tabs in state. Context menu "Move to Workspace" already existed and is unchanged (`dnd-16-context-menu.png`) |
| 11 | Esc cancels, no change, source row opacity restored | PASS | `dnd-14-esc-*` shows `agent-desktop press escape` did not reach the drag (drop happened, expected tool limit); `dnd-15-esc2-*` with System Events key code 53: state unchanged, row restored |
| 12 | Order persists across relaunch | PASS | `dnd-13-relaunch.png` vs `logs/dnd-v2-before.json` |
| 13 | Click selects, hover close x, middle-click closes, context menu | PASS | `dnd-11-click-select.png`, `dnd-12-middle-close.png`, `dnd-16-context-menu.png` |
| 14 | Workspace swipe | NOT RE-VERIFIED | Code untouched (`SidebarScrollView`/`WorkspaceRoot`); no synthetic trackpad swipe available |

## Open items

- Empty Essentials: with no Favorites there is no tile region, so a tab cannot be dropped to create the first Essential by drag (menu Add to Favorites still works).
- No row-shifting animation; the insertion line only. Drag image looks slightly scaled in synthetic drags.
- Hovering a pager dot during a drag does not switch Spaces; drop only. Cross-Profile dots reject the drop.
- Dropping on a folder always appends; folder child rows insert at position. Moving to the unfiled pins end from below an expanded folder needs the New Tab row's upper half.
- Dragging folders themselves and split rows is not implemented. Placing a split member across kinds dissolves the pair.
- Tile insertion line for index 0 is at the sidebar edge (x = 8) and hard to see under the drag image.
