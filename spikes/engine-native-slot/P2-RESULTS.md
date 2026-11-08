# Arc parity P2 (Swift side): real-host results

Run 2026-11-08, uncommitted. Covers audit item 13 (create workspace), item 18 (hover card) and the open DnD items (empty Essentials, row shift, Essentials index-0 line).

Code: `BatoCore/BrowserState.swift` (`addWorkspace(color:)`, `nextWorkspaceColor`), `BatoRuntime/PageRuntime.swift` (`addWorkspace(name:color:)`), `BatoBrowserUI/SidebarDragDrop.swift` (`.emptyFavorites` slot, `FavoritesDropZone`, `SidebarDropMap.shiftPlan`, layer shifts, thicker/clamped tile line), new `BatoBrowserUI/SidebarHoverCard.swift`, `NativeWorkspaceController.swift` (`createSpace`, `WorkspaceEditor(creating:)`, hover and drag wiring; row `toolTip` replaced by accessibility help). Tests: `NewSpaceTests` (4), `SidebarHoverCardTests` (3), 8 new cases in `SidebarDropMapTests`; full `swift test` passes (215 Swift Testing + 223 XCTest). Mirrors staged, `SidebarHoverCard.swift` added to client.json/BUILD.gn/compile_native_slot.py, client.patch regenerated (59 files, 54 mirrors), `native_slot.py check` ok, `build --execute` waited (logs/p2-build*.log), `test_patch.py` OK.

Launches (SSD, `--use-mock-keychain`): `tmp/launch-p2-v{1,2,3}.py`, state `runtime/p2-state-v1` (dnd-seed with Favorites emptied), exits 0 via "Quit Bato" (`logs/p2-v{1,2,3}-exit.json`). The real dist/Bato.app was left running and untouched. Shots: `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/p2-*.png`.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Pager + and Spaces > New Space open a name/colour sheet, no workspace created yet | PASS | `p2-1-newspace-sheet.png`, `p2-3-newspace-menu.png` |
| 2 | Esc cancels, organization unchanged | PASS | `p2-2-esc.png`, organization.json workspaces |
| 3 | Typing a name and Return creates it with the chosen colour (default is the first palette colour the Profile does not use) and switches to it | PASS | `p2-22-sheet-typed.png`, `p2-23-created.png`, organization.json (Recipes, #8975A8) |
| 4 | Sheet height fits content (first build had blank space) | PASS | `p2-22-sheet-typed.png` |
| 5 | Empty Favorites: dashed "Drop to add to Favorites" area appears at the top when a tab drag starts with zero Essentials | PASS | `p2-5b-*`, `p2-9-zone-mid.png` |
| 6 | Dropping on it creates the first Essential; zone disappears | PASS | `p2-9-zone-after.png`, organization.json favorites |
| 7 | Row shift: rows below the insertion line animate ~10pt apart (150ms ease-out) and the line sits in the gap, also inside a folder | PASS | `p2-8-rowshift-mid.png`, `p2-17-folder-shift-mid.png` (a first build shifted the wrong way inside folders and shifted rows for tile lines; fixed, covered by tests) |
| 8 | Essentials index-0 line visible (3pt, clamped off the sidebar edge) | PASS | `p2-10-tile0-mid.png` |
| 9 | Hover card (title + host, no thumbnail) after ~600ms on rows | PASS | `p2-12-hover-row.png`, `p2-18-hover-crop` |
| 10 | Hover card dismisses on move-out, key, and click; does not return under a stationary pointer after a click | PASS | `p2-13`, `p2-14`, `p2-20`/`p2-21` (a first build re-raised it after a click; fixed) |
| 11 | Hover card dismisses on scroll | NOT VERIFIED | Local event monitor covers scrollWheel; no synthetic scroll was driven |
| 12 | Existing behaviour: click selects, hover close x, context menu, DnD reorder/tab to folder/tab to Essentials | PASS | `p2-16`, `p2-21`, `p2-24-context.png`, `p2-17` |
| 13 | Middle-click close, workspace swipe | NOT RE-VERIFIED | Code untouched (no synthetic middle click or trackpad swipe available) |
| 14 | Compare against Dia references | NOT DONE | No Dia capture exists for the New Space sheet or hover card; visual match is by Arc description only |

## Open items

- Creating a Space leaves the previous page showing and the footer reads "The page couldn't open. Select it to try again." (`showSelection` returns false for an empty workspace; the pre-existing `addWorkspace` path does the same, so `createSpace` ignores the false return and checks that the workspace count grew). Needs a real "empty workspace" selection in the engine path.
- New Space has name and colour only; no icon or gradient theme.
- The hover card is a click-through panel placed 8pt right of the row, so it overlaps the sidebar edge and web content; no thumbnail.
- Row shift covers vertical lines only; Essentials tiles do not spread apart, and sections above the line or non-slot views (dividers, headings) do not move.
- The Favorites zone pushes rows down by its 52pt height for the duration of the drag (no height animation, only a fade).
- Row `toolTip` (title + URL) was removed in favour of the card; the URL is still exposed as accessibility help.
