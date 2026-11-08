# Pinned collapse, Tidy | Clear, split polish (2026-11-08, uncommitted)

v3 (collapse animation, 18pt gap, hover refresh): `runtime/pin-state-v3`, exit 0. Test instance only (mock keychain, SSD): wrapper `tmp/launch-pin.py`, seed `runtime/pin-seed`, states `runtime/pin-state-v{1,2}`, exits 0 via Quit Bato (`logs/pin-v{1,2}-exit.json`). Builds: engine+client (v1), client-only (v2). dist/Bato.app and Application Support untouched. Shots in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/pin-*.png` (v1 shots: header hover, collapsed hover, Tidy/Clear hover, after Clear; v2: expanded, expand frames, collapsed idle, hover with the fixed chevron, split, Ctrl-Tab). References: `bato-references/arc/2026-11-08/` (03b, 07b, 09, 10-expand-frame*).

Verification: `swift test` 288 XCTest 0 failures + 224 Swift Testing passed; `test_patch.py` 10 OK (gap constant asserted); engine 8-file and client 65-file roundtrips verified.

## Checklist (ARC-REFERENCE-CHECKLIST.md sections 1 and 2, plus gaps)

| # | Item | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Idle: no fill, Space icon (colour dot) in the leading slot, no trailing dots | PASS | pin-expanded |
| 2 | Hover: rounded fill (r10, white 10%), icon becomes a DOWN chevron (10pt, 1.5 stroke, white 85%), trailing dots appear | PASS (first build drew it pointing up; fixed, v2 shot) | pin-hover-header |
| 3 | Label 13pt semibold, does not shift on hover | PASS | pin-hover-header |
| 4 | Click row or label collapses; header, Favorites, Tidy/Clear, New Tab, Today stay | PASS | pin-collapsed-hover, state `pinsCollapsed: true` |
| 5 | Collapsed chevron points right and stays visible when idle; dots hover-only | PASS | pin-collapsed-idle |
| 6 | Collapsed hover fill identical to expanded | PASS | pin-collapsed-hover |
| 7 | Divider+Tidy/Clear sit under the header after collapse | PASS in structure; gap is now 18pt custom spacing | pin-collapsed-idle |
| 8 | Expand ~220ms: pinned rows fade in while content below moves down | PASS; superseded Arc's overlap with a clipped wipe (no overlapping text, per coordinator) | pin-expand-frame2..4 |
| 9 | Chevron rotation on the same ease | PASS coded (animatable `chevronTurn`, 220ms ease in-out); not frame-checked | |
| 10 | Collapse and expand animate symmetrically (~220ms): a clipped picture of the pinned rows sits between the header and the content below; its height animates (stepped per frame, ease-out cubic) with a fade, so the content follows in lockstep and no text ever overlaps; chevron rotates | PASS (v9 build; no overlapping text in any captured frame) | pin-collapse-frame2..4, pin-expand-frame2..4 |
| 11 | Reduce Motion skips animation (expand and collapse) | coded, not run | |
| 12 | Tidy/Clear row only while pointer is over the sidebar; right aligned, 11pt semibold, idle ~35% | PASS | pin-collapsed-idle (hidden) vs pin-hover-header (shown) |
| 13 | Hover brightens the hovered label (95%), other dims, no pill | PASS | pin-tidyclear-hover-clear, -tidy |
| 14 | Tooltips: Clear "Clear unselected Today tabs" | PASS coded (toolTip set); tooltip window not in the capture. Tidy tooltip is "Archive duplicate Today tabs" (Arc: "Organize") | |
| 15 | Clear archives every unselected Today tab (selected tab and its split partner kept), restorable | PASS: 4 tabs archived, pair kept (pin-after-clear); records in organization.json; restore covered by `testClearedTabsAreRestorableFromTheArchive` and runtime test; the Archive sheet could not be driven (palette sheet not activatable by automation) | pin-after-clear |
| 16 | Tidy | Implemented, simple: archives later Today tabs repeating another tab's address (selected wins, pairs untouched). Disabled when none. Click not exercised on host; unit tested | PinnedCollapseTests |
| 17 | Divider stays visible when Tidy/Clear hidden | PASS | pin-collapsed-idle |
| 18 | Header ⋯ menu: Rename Space, Change Colour, New Folder, Hide/Show Pinned, Delete Space | PASS (Hide Pinned clicked: collapsed and persisted) | menu via AX |
| 19 | Collapsed state persisted per Space, legacy documents load expanded, bytes unchanged when never collapsed | PASS | unit tests |
| 20 | Pane gap 10pt (engine `kNativePaneGap`) | PASS: pixel scan of a row shows 10px between panes | pin-split-screen, pin-split-gap-zoom |
| 21 | Pane radius 10pt | PASS visually (`SplitPaneChrome.paneCornerRadius`; single page card stays 12) | pin-split-gap-zoom |
| 22 | Focus outline 2pt inside, #4f40f9 fixed colour, follows radius | PASS (pixels 81,64,250 two px inside the pane edge) | pin-split-screen |
| 23 | Soft glow ~11pt, only outside the panes | PASS (gradient across the gap) | pin-split-gap-zoom |
| 24 | Ctrl-Tab split card shows both titles | PASS (favicon + title per row under the two plates; Arc itself shows no titles, requested here) | pin-ctrltab-full |

## Open items

- Space header is part of the scrolling list, not fixed above an independently scrolling pinned area (Arc geometry item).
- Tidy is duplicates-only; no sort by host. Tidy and Clear clicks beyond Clear were not repeated after Tidy; archive restore through the sheet not driven.
- New Tab hover is now re-read from the pointer after the slide and when the row is re-added (coded; the pointer was not resting on the row in the v3 capture, so the fix is not shown on host).
- Glow on the side facing the sidebar is also drawn (outside-the-card region); Arc shows it too, not compared pixel-for-pixel.
- Header has no drop target (dragging a tab onto a collapsed section does nothing).

Re-renders during the animation (the runtime commits and calls render again) are deferred until it ends; otherwise they dropped the picture and the animation snapped. Captured with `screencapture -R` (window-id capture does not show mid-animation frames).
