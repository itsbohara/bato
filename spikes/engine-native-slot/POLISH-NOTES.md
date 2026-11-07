# Swift UI polish pass v1 (2026-11-07)

Source: static comparison of Bato `perprofile-v1-shots` 01-14 against Dia captures
(33-profile-switcher, 17-command-bar-url; Dia sidebar visible in both). No new real-host
run was made; none of the fixes below has had a screenshot check yet.
Styling lives in `app/Sources/BatoBrowserUI/SidebarStyle.swift`; edits to
NativeWorkspaceController.swift and CommandBarController.swift are localized constants/view setup.

## Gap list

| Surface | Gap vs Dia | Status |
| --- | --- | --- |
| Sidebar rows | 13pt text, 34pt rows, 16pt icons; Dia ~14pt, ~36pt, 18pt | Fixed (33, 17) |
| Selected row | Accent-tinted fill plus accent stroke; Dia is a neutral lifted pill, no stroke | Fixed (label-colour 13% fill, stroke only under Increase Contrast) |
| Hover | quaternaryLabel fill | Fixed: 7% label fill, same radius |
| Favorites | 2-up tiles 62pt with 11pt caption and star glyph; Dia is 3-up icon-only tiles on a soft fill, no caption | Fixed (3-up, 46pt, 22pt icon; titles remain in AX label and tooltip) |
| Section headings | 11pt semibold with bright count | Fixed: medium weight, tertiary count. Dia has no headings; consider hiding them when a section has one entry type only |
| Top actions (New tab / Find page) | 12pt medium side-by-side buttons; Dia uses a single "+ New Tab" row at the end of the tab list, 14pt regular | Partly: font 13 regular. Layout move remains |
| Footer workspace picker | Bordered NSPopUpButton looks like a stock control | Partly: borderless. Dia uses a dot pager at the bottom; remains |
| Profile switcher menu | Native NSMenu; Dia's menu is a dark custom popover with larger dots and a gear for settings | Remaining (needs custom NSPopover/panel) |
| New/Rename Profile sheet | 330pt fixed height left ~90pt blank at bottom | Fixed: sheet sizes to content |
| Workspace/Folder/Arc import sheets | Same fixed-height pattern; Arc import has blank space and no all-imported state | Remaining (SidebarStyle.fitSheet is reusable) |
| Command bar | radius 16, 52pt rows, 13pt medium titles, full-width system selection, Cancel/Open buttons; Dia radius ~20, 44pt rows, inset rounded selection, single-line title + url, "Go" pill | Partly fixed: radius 20, hairline border, 44pt rows, 14pt titles, rounded inset selection. Remaining: bezeled search field, Cancel/Open footer, translucency |
| Sidebar background | Opaque gradient of workspace colour; Dia uses a translucent material with a stronger tint and rounded page inset | Remaining; needs engine window transparency, real-host test |
| Top row | Toolbar owned by Chromium (stock omnibox, extension icons); not in Swift layer | Out of scope |
| Peek chrome | Text buttons "Open as Tab"/"Close" in sidebar; no reference capture | Not changed |
| Animation | No row hover/selection animation, no sheet or command bar fade/scale | Remaining |

## Needs real-host screenshot check

- 3-up Favorites with images vs SF symbol fallback, tile close button position (top-right 2pt).
- Selected/hover contrast on every workspace colour, light and dark.
- Borderless workspace picker still reads as clickable.
- New Profile sheet height (creating and rename); command bar border and selection inset.
- Tab titles at 14pt truncation in the narrowest sidebar.

## Round 2 (2026-11-07)

Source: `ESSENTIALS-POLISH-RESULTS.md` gaps G1-G7, F2, F3, F4, F6, against Dia captures 10, 11, 16, 17, 33.
Swift UI layer only; nothing built into the engine, no screenshot check yet. `swift test` green (log `logs/polish2-swift-tests.log` on the SSD).

| # | Change | Reference | Needs screenshot check |
| --- | --- | --- | --- |
| 1 | Sidebar tint: `SidebarStyle.tint` blends the workspace colour at 55-80% over the window background (colour darkened in dark mode); high contrast keeps a faint wash | 33, 17 | Green/blue/rose on dark and light; text contrast; selected pill on each |
| 2 | Selected outline: the ring was the NSButton focus ring, restored on the selected row by `render()` after every state change (not the contrast stroke). Row and close buttons now use `focusRingType = .none`; contrast-mode stroke is neutral, not accent. Selected fill 16% label colour with a soft shadow and hairline | 33 | No outline after selecting, after relaunch and when keyboard-focused. Keyboard focus is now invisible on rows; revisit if full-keyboard access needs a cue |
| 3 | Settings: 960x700, 270pt rail with 44pt rows and 17pt text, 26pt heading, 72pt+ rows, 17/14pt row text, larger icon tiles. Trailing controls get required hugging so actions, switches and chords right-align (F4). Rail rows are AX elements (button role, label, press action) and accept the first click while another window is key (F2) | 10, 11, 16 | Right alignment after reload; clicks on the rail with the browser window key; AX tree lists the five rail rows. Back/forward title bar and trailing chevrons not done |
| 4 | Sidebar: section headings, "Saved pairs" heading and the two top buttons removed. One "+ New Tab" row (id `bato-focus-new-tab`) opens the tab list, right after a hairline that separates it from pinned/folders, above the temporary tabs as in Dia. Find Page remains in the command bar. `bato-edit-workspace` is gone: "Edit Workspace..." is the first item of the workspace actions menu | 33, 17 | Row left inset of the "+" vs tab icons |
| 5 | Favorites: 58pt tiles, 26pt icons, shadow + hairline for depth, close button fades in only on hover (still in the AX tree and clickable), initial-letter fallback tile with a per-host hue instead of a star | 17, 33 | Depth on tinted sidebar; hover reveal; favicon case |
| 6 | Command bar: 680x470, radius 22, borderless 22pt field, 48pt one-line rows (title then subtitle), "Go" pill replaces Cancel/Open (id `bato-command-bar-open` kept, Return and Esc unchanged, `bato-command-bar-cancel` removed), provider picker moved to the footer. F6: an exact command name ranks above web search (`CommandBarResults`, tested) | 17 | Pill contrast in light and dark; footer provider picker; row truncation |
| 7 | F3 not fixed here: the grey sidebar behind the command bar and sheets is not drawn by the Swift layer (the root view always paints its gradient), so the host hiding or detaching the slot view during a sheet is the likely cause (WorkspaceSlot / engine, out of scope) | 17, 33 | Confirm whether the window background shows through |
| 8 | Workspace picker: dot pager (id `bato-workspace-picker` on the group, one labelled button per workspace, active dot larger) replaces the popup. Header lost the palette button, which frees about 30pt, so the name should no longer collapse to "..." at about 215pt | 33 | Name at 215pt; dots with 7+ workspaces |

Not done: Profile-switcher popover (still NSMenu), translucency, Settings back/forward bar, animations.

## Round 3

Swift UI only; not built into the engine, not run in the real host. `swift test` log: `logs/polish3-swift-tests.log` (SSD).

- **Root cause of P2 and P3 (same cause):** the Polish 2 test host had Increase Contrast on (`com.apple.universalaccess increaseContrast = 1`). That switches `SidebarStyle.tint` to its 8%/4% high-contrast wash (which is why even orange read as faint brown) and makes `SidebarPageView.draw` stroke the selected row with `labelColor` at 0.6 alpha, 1.5 pt (the light ring; tiles get the dimmer `separatorColor` ring). The ring is the intended Increase Contrast outline, not a layer border, focus ring or bezel. Retest with Increase Contrast off before judging either.
- **P3 hardening:** selected rows no longer get the drop shadow or the 0.07 white hairline (tiles keep both); the only outline left is the Increase Contrast one.
- **P2:** `SidebarStyle.vivid` lifts the stored colour to at least 0.6 saturation and 0.8 brightness (near-greys stay neutral) before blending; the Increase Contrast wash is now 30%/20% dark, 20%/12% light instead of 8%/4%.
- **P1:** `CommandBarSelection.rowAfterRefresh` (BatoCore, unit-tested) keeps the id-based selection only when the query is unchanged; any edit selects the top row.
- **P4:** `FaviconFallback.spec` (BatoCore, tested): IP, localhost or empty hosts take the first letter of the page title; hue is seeded from full URL plus title.
- **P5:** Settings scroll view forced to `.overlay` scrollers; a legacy scroller took 16 pt from the clip view and narrowed the cards on long panes.
- **P6:** left as is (bare `127.0.0.1:port` resolves to https; use `http://`).
