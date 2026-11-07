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
