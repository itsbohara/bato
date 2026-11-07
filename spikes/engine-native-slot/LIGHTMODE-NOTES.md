# Light mode, contrast and Dia gaps (Swift only)

Not built into the engine and not run in the real host. `swift test` green (167 tests, log `logs/lightmode-swift-tests.log` on the SSD). No light-appearance Dia capture exists in `dia/2026-11-01`; light values are derived, not matched.

## Changes

- `AppearanceWatcher` (new): one notification, `AppearanceWatcher.didChange`, for NSApp effective appearance (KVO) and Increase Contrast / Reduce Transparency (`accessibilityDisplayOptionsDidChange`). Sidebar views, Settings cards and nav pill, command bar surface and Go pill listen; no relaunch needed (N2).
- `SidebarStyle.tint` now takes an `NSAppearance` and resolves under it. Found by the new unit test: in dark mode bright workspace colours (yellow, white) gave white text 2.7-3.7:1; dark body brightness is now capped. All palette colours reach 4.5:1 primary and 3:1 secondary text in both appearances, with and without Increase Contrast.
- Tile shadow and hairline are dynamic (a white hairline was invisible in light; black shadow was heavy). Letter-icon fill darkened for white glyph contrast.
- Settings: selected rail row uses `selectedContentBackgroundColor` + `alternateSelectedControlTextColor` (white-on-accent failed on yellow accents); cards get a 1pt stroke under Increase Contrast; back/forward pill with pane history plus title in the title-bar row (ids `bato-settings-back`, `bato-settings-forward`, `bato-settings-title`); bold section headings above cards (`bato-settings-section-*`).
- Command bar: border 1.5pt and fully opaque Go pill under Increase Contrast. Downloads ring track stronger under Increase Contrast; download row hover fill re-resolves on appearance change.
- Recovery/uBlock sheets: primary button on the right with a return-key hint in its title (AX label unchanged; ids `bato-recovery-button-N` keep the caller's index).
- Workspace and Profile switchers are now `SwitcherPopover` (NSPopover, system material, so Reduce Transparency is automatic). Ids: `bato-space-name` and `bato-profile-button` unchanged; rows `bato-switcher-workspace-N`, `bato-profile-item-N`, `bato-switcher-new-workspace|new-profile|rename-profile|settings`; gear row opens Settings, Profiles pane. `bato-profile-*` editor ids untouched. No arrow-key row navigation yet (rows are AX-pressable).
- Audited and left as is (already semantic): sidebar rows, Archive, Arc import, uBlock offer, New/Rename Profile and Workspace sheets, downloads popover.

## Real-host checklist (each in light, dark, and with Increase Contrast; toggle appearance while running, not only at launch)

1. Sidebar on all 6 palette colours plus yellow and white: title, secondary text, pager dots, footer profile label readable; gradient not muddy.
2. Selected/hover rows and favorite tiles: edge and shadow visible in light, no outline unless Increase Contrast.
3. Letter-icon tiles, close buttons, downloads ring and popover (hover fill, red failure text).
4. Command bar: surface, border, selection pill, Go pill, footer provider picker.
5. Settings: all six panes; rail selection with a non-blue accent colour (System Settings > Appearance); cards visible in light; section headings; back/forward enable/disable and pane history; stroke under Increase Contrast.
6. Sheets: recovery (primary on right, Return triggers it, Esc cancels), restore picker, quit prompt, uBlock offer, Archive, Arc import, New/Rename Profile, Workspace/Folder editors.
7. Switcher popovers: click `bato-space-name` and the footer profile button; check marks, dots, ⌃N hints, gear opens Settings; Esc and outside-click close.
8. Live toggles with the window open: System Settings appearance Light/Dark/Auto, Increase Contrast, Reduce Transparency; sidebar, Settings and an open command bar update without relaunch.
9. Known unchanged: Chromium's own toolbar and omnibox (engine-owned); F3 grey behind sheets.
