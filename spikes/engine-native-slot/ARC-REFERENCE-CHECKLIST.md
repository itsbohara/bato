# Arc reference checklist (captured 2026-11-08)

Reference captures of the real Arc app for pixel parity. Screenshots live only in the private
folder `/Volumes/Mahesh/personal/bato-references/arc/2026-11-08/` (never in the repo); filenames
below refer to that folder. Window: 1470x892 pt, dark theme, 1x display, sidebar ~262 pt wide.
All values are points in window coordinates, estimated from 1x pixel samples (+-1 pt); colours are
sampled sRGB hex. "White N%" is an estimate against the local background.

## Sidebar geometry (for context)

- [ ] Favorites tiles: 3 across, ~78x46, gap ~9, x 8..260, y 45..91, radius ~10, fill ~white 8%.
- [ ] Space header row centre y=117; label 13 pt semibold, left x=44; icon/chevron slot centred x~26.
- [ ] Pinned rows pitch 41 pt (single line), 2-line rows (title + host) slightly taller; folders bold.
- [ ] Pinned area scrolls independently under the fixed Space header (content clips beneath the header;
      thin white overlay scrollbar at x~262 appears while scrolling/hovering).
- [ ] Row hover: rounded fill (radius ~10) across x 8..252, ~36 tall (see `95-sidebar.png`).
- [ ] Divider above Tidy|Clear/New Tab: 1 pt line, ~white 8%, x 18..242, y~684 (expanded).

## 1. Pinned section collapse (Space header row)

Shots: `02-sidebar-idle`, `03-space-header-hover`, `03b-space-header-hover-zoom`, `05-collapsed`,
`06-collapsed-header-hover-zoom`, `07-collapsed-header-idle-zoom`, `07b-collapsed-full-idle`,
`10-expand-frame1..6`.

Expanded
- [ ] Idle: row has no fill; leading slot shows the Space icon (not a chevron); trailing `...` hidden.
- [ ] Hover: rounded fill appears over x 8..260, y ~99..135 (height ~34-36), radius ~10-11, ~white 10%.
- [ ] Hover: the Space icon is replaced by a chevron pointing DOWN (~10 pt wide, stroke ~1.5, white ~85%)
      at x~26; `...` (3 dots, ~3 pt each) appears at x~242, white ~70%.
- [ ] Label stays 13 pt semibold white at x=44 in all states (does not shift on hover).
Collapsed
- [ ] Clicking the chevron (or row) hides ALL pinned rows/folders; Space header row, favorites tiles,
      Tidy|Clear row, New Tab and Today tabs remain.
- [ ] Chevron rotates to point RIGHT and stays visible even when not hovered (idle collapsed still shows
      the right chevron instead of the Space icon). `...` still only on hover.
- [ ] Hover fill identical to expanded hover.
- [ ] After collapse the divider+Tidy|Clear row sits directly under the header (gap ~18 pt below header
      bottom); New Tab follows ~34 pt below that.
Animation (frames ~85 ms apart; `10-expand-frame1..6`)
- [ ] Expand ~200-250 ms: pinned rows fade in (opacity ramp) while content below slides down;
      mid-frame shows rows overlapping lower content (cross-fade, no clip reveal). Finished by frame 3.
- [ ] Chevron rotation and fill follow the same short ease (no spring overshoot observed).
Tidy | Clear row (above New Tab)
- [ ] Appears only while the pointer is over the sidebar; right-aligned: broom glyph + "Tidy", 1 pt
      vertical separator (~12 tall), "Clear"; 11 pt semibold; idle ~white 35%.
- [ ] Hover: the hovered label goes to ~white 95% while the other dims further; no background pill.
- [ ] Tooltip on Tidy: "Organize". Tooltip on Clear: "Clear unselected Today tabs" + keyboard shortcut
      chip. Clear closes all unselected, unpinned tabs in the Today section (not exercised: describes the
      tooltip only; destructive on real data). Tooltip: dark indigo pill, bold white 13 pt, radius ~12,
      appears below-left of the pointer (`09b-clear-tooltip`).
- [ ] The divider line to the left of Tidy stays visible even when Tidy|Clear are hidden (`07-collapsed-header-idle-zoom`).

## 2. Split view

Layout (`20-split-idle-left-focused`, `34-restored-full`)
- [ ] Two panes side by side, each 591 wide (window 1470: left pane x 268..859, right pane x 869..1460).
- [ ] Gap between panes 10 pt; outer margins 10 pt top (y=10), right (1460) and bottom (882).
- [ ] Pane corner radius ~10 pt; page background #232429; each pane owns its toolbar band at the top
      (y 12..42, bg #24222d, divider 1 pt #2e2f34 at y=42, ~30 pt tall + divider).
- [ ] Window/chrome background shows through the gap (~#1a1524 with theme tint).
Focus outline (`20-split-idle-left-focused`, `40-split-right-focused-full`)
- [ ] Focused pane: 2 pt outline, colour #4f40f9 (accent violet), drawn INSIDE the pane bounds, following
      the 10 pt corner radius, wrapping toolbar + page.
- [ ] Outer glow: soft violet shadow ~10-12 pt, fading from ~#3a3644 to the window bg (visible in the gap and
      toward the sidebar side).
- [ ] Unfocused pane: no outline, no glow. Focus moves on click inside the pane; sidebar split row
      highlight does not change with pane focus.
Toolbars (`21b/21c/21d`, `40b-split-toolbars-right-focused`)
- [ ] Focused toolbar: back, forward, reload (left); centred link glyph + host (13 pt semibold); extension
      icons, split icon, close X (right). Icons ~16 pt, white ~85% (back/forward disabled ~30%).
- [ ] Unfocused toolbar idle: only back, forward (dimmed), centred host and a close X at far right.
      No reload, no extension icons, no split icon.
- [ ] Unfocused toolbar hover: the full control set (reload, extension icons, split icon) fades in
      (`21b-split-right-toolbar-hover`); URL stays centred; no fill change.
- [ ] Toolbar content reflows when the pane is wider (more extension icons visible at larger width).
- [ ] Clicking the host area copies the link and shows a "Copy Link" toast with shortcut chips.
Resize grabber (`30-grabber-idle`, `31-grabber-hover`, `32-grabber-dragging-full`, `33-after-drag-full`)
- [ ] Pill centred in the gap at x 863..864, vertically centred (y 434..458): 2 pt wide x 24 pt tall,
      fully rounded.
- [ ] Idle #56505c (~white 25%); hover and while dragging #949199 (~white 50%). Dragging looks identical to
      hover; the gap stays 10 pt and both panes keep the 10 pt radius while resizing.
- [ ] Drag resizes live (left pane +90 pt in the test; right pane shrinks equally); extension icons reflow in
      the left toolbar during the drag. The gap/grabber moves with the divider.
- [ ] Grabber hit area is wider than the pill (full 10 pt gap); not measured for height beyond the pane.
Split menu (toolbar split icon on the focused pane; `70-split-icon-hover`, `71-split-menu-full`, `71b-split-menu`)
- [ ] Opens as a native menu directly below the split icon, left edge ~1 pt left of the icon, ~237 wide,
      ~215 tall, radius ~10, dark translucent (#1a1919-ish), 1 pt border.
- [ ] Items (24 pt rows, 16 pt leading glyphs, 13 pt): Move Left (disabled on the left pane), Move Right |
      Add Right Split, Add Left Split | Separate Tab from Split, Convert to Vertical Split View |
      Share Split View...   (`|` = separator).
Sidebar split row (`41`, `42`, `43`, `44-splitrow-left-focused`, `50b`, `51`, `52`)
- [ ] One row, two halves side by side with each half's favicon + 13 pt title; row inset x 8..252.
- [ ] Selected: outer container fill ~#423e4c, each half a lighter rounded rect (~#53 4e 5b), container
      radius ~10, half radius ~8, 4 pt gap between halves, container padding ~3-4 pt (container ~36 tall,
      halves ~29). Identical whichever pane is focused.
- [ ] Selected hover: both halves show a close X at the right of each half (~white 70%).
- [ ] Unselected idle: no fill; a 1 pt vertical separator (~white 30%, ~16 tall) sits between the halves.
- [ ] Unselected hover (either half): container fill appears (~white 8%, darker than selected) over the whole
      row, ONE close X appears at the far right (closes the whole split), and a tooltip with the hovered
      half's title appears below it.
- [ ] Selecting a half focuses the matching pane.
Row context menu (`60-splitrow-contextmenu-left-full`, `60b`, `61-splitrow-contextmenu-submenu`, `62`)
- [ ] Same menu from either half. Items: Share Split View... | Separate All Tabs, Add Tab... (disabled),
      Convert to Vertical Split View | Tab Options (disabled section label), per-tab entries with favicon
      and submenu arrow (x2) | Change Icon..., Rename... | Duplicate, Move to > | Archive Item,
      Archive Tabs Below.
- [ ] Per-tab submenu: Separate from Split View | Share >, Mute (disabled), Copy Link, Copy link as
      Markdown | Archive Item. Highlighted row uses the system accent fill, radius ~6.
- [ ] Menu ~240 wide, radius ~10, row pitch 24 (separators ~12), 13 pt text.

## 3. Ctrl-Tab recent-tab switcher

Shots: `90-ctrltab-1`, `90-ctrltab-2`, `92-ctrltab-panel-crop-sel2`, `92b-...sel3`, `92c-...wraparound`,
`99-ctrltab-anim1..3`, `99-ctrltab-wrapped-current`.
- [ ] Appears only while Ctrl is held: a quick Ctrl+Tab tap switches tabs with no panel; holding shows the
      panel after ~250-400 ms (not present in frames taken ~100-200 ms after the first Tab press).
- [ ] Panel centred in the window (both axes), x 446..1023, y 352..540 for 3 entries; width = 181 per
      entry + 32 padding; height 188.
- [ ] Panel: fill #1a1919 (near-opaque neutral), 1 pt border #3d3d3d (~white 15%), radius ~28 pt, 15 pt padding.
- [ ] Cards: 181 x 158, no gap between cards, equal widths; entries ordered most-recent first (the current
      tab is the first card).
- [ ] Selected card: fill #423f82 (indigo, accent tint), radius ~11; no fill/outline on unselected cards.
- [ ] Thumbnail: ~150 x 100, inset ~16 pt from the card edge, 12 pt below card top, radius ~6, with a
      soft dark shadow (visible as #161616 halo around it on a selected card).
- [ ] Label row: 16 pt favicon + 14 pt semibold white title, left aligned, vertically centred ~20 pt above the
      card bottom, truncated with an ellipsis around 120 pt.
- [ ] Split tab = ONE card containing two side-by-side thumbnails (~73 wide each, 4 pt gap) and two centred
      favicons with no title.
- [ ] First Tab press selects the second card; each further press advances, wrapping to the first.
      Shift reverses (not captured).
- [ ] Releasing Ctrl commits the highlighted card; Escape while held did not cancel in this capture.

## 4. Sidebar row context menus

Shots: `80-normaltab-contextmenu`, `81-pinnedtab-contextmenu`, `97-fav-menu` (split in favorites).
Normal (Today) tab
- [ ] Copy Link, Share > | Change Icon..., Rename..., Mute (disabled when silent), Customize Page... |
      Open in Split View, Duplicate, Move to > | Archive Tab, Archive Tabs Below.
Pinned tab
- [ ] Copy Link, Share > | Change Icon..., Rename..., Mute (disabled), Edit Pinned Page > | Open in
      Split View, Duplicate, Move to > | Remove Pin.
Split in favorites (observed incidentally)
- [ ] Share Split View... | Separate All Tabs, Add Tab..., Convert to Vertical Split View | Tab Options + two
      per-tab entries | Change Icon..., | Duplicate, Move to > | Archive Item, Close (Cmd+W shown).
Common
- [ ] Native dark menu, ~240 wide, radius ~10, 1 pt border, 24 pt rows, 13 pt text, separators between
      groups, opens at the pointer (flips up when near the screen bottom). Disabled rows ~white 35%.
- [ ] Space header `...`/right-click menu also exists (Change Space Icon, Rename Space, Edit Theme Color,
      Set Profile >, New Folder, Live Folders >, Share Space, Export Space into Folder >, Manage Spaces,
      Delete Space). Not part of the scoped features.

## 5. Cmd-W on a split (captured 2026-11-08, `cw-*.png`)

Test pairs made from two example.com tabs, removed afterwards (the pinned pair was archived, so Arc's archive holds one test item).
- [ ] Unpinned split, Cmd-W: closes only the FOCUSED pane's tab; the pair dissolves and the other tab stays selected as a normal
      single tab (`cw-03-split` -> `cw-04-unpinned-cmdw`).
- [ ] Pinned split (dragged into a pinned folder), Cmd-W: BOTH members unload, the pair stays in the sidebar as ONE split row
      (halves dimmed, no selection), content area empty ("Search or Enter URL..", `cw-08-pinned-cmdw`).
- [ ] Clicking either half of the unloaded pinned pair reloads and shows BOTH panes, first half focused (`cw-09-reselect`).
- [ ] The split row menu lists "Close  Cmd-W" as its last item; there is no Pin item on a split row (pinning is by dragging into the
      pinned area).

## 6. Space swipe (captured 2026-11-08, `swipe/` private shots and screen-recording frames)

Driven with synthesized phased trackpad scroll events (continuous, began/changed/ended, optional momentum) over the sidebar list; Arc accepts them. Timings come from a 30 fps variable-rate screen recording (about 33 ms resolution). Sidebar is 268pt wide in a 1470pt window.
- [ ] Content tracks the fingers: the Space header row, the Space's tab/folder list and the Today list slide horizontally together, linearly with finger travel (a synthesized 420 px of scroll moved the list 198pt, constant ratio 0.47 over the whole drag, so no easing or resistance inside the Spaces range).
- [ ] The neighbour Space's list is built and slides in alongside, flush against the edge: page pitch equals the sidebar width (~268pt), no gap and no divider. Swiping left brings the next Space in from the right; right brings the previous one from the left.
- [ ] No fade or scale on either list: both stay fully opaque while moving, the outgoing list is simply clipped by the sidebar edge.
- [ ] Static during the drag: window controls row, sidebar toggle, the Favorites tiles row (Notion/Gmail/Slack tiles stay, only their tint follows the Space colour) and the bottom bar (pager icons and +). Tab-list rows do not shrink or reflow.
- [ ] Sidebar background colour (Space theme, a gradient with a soft blob) cross-fades continuously between the two Spaces' themes with progress (purple-dark to green seen at ~45% progress as a blend of both); it also tints the Favorites tiles and the window chrome strip.
- [ ] The pager icon highlight in the bottom bar follows the drag (the neighbour's icon is already coloured before release when more than about half way); not measured to the frame.
- [ ] Ends: swiping right from the first Space reveals the Library page (Media, Downloads, Easels, Spaces, Boosts, Archived Tabs) as a neighbour page; swiping left from the last Space reveals a "Create a Space" page. So Arc has no rubber band at the Space ends, but the pages beyond them also stop with resistance: past the "Create a Space" page, 500 px of scroll (235pt unresisted) moved the page only ~30pt (~12%) and it returned on release. Bato has no pages beyond its ends, so it uses the same resistance on the first/last Space.
- [ ] Commit distance: 120-160 px of scroll (56-72pt, 21-27% of the width) released after a 200-250 ms hold springs back to the original Space; 190 px (89pt travel, 33-36%) commits. A short fast flick commits: 100 px over 150 ms (47pt, ~17% of the width, ~300pt/s) switched. So: roughly one third of the width, or a flick velocity of a few hundred pt/s.
- [ ] Release animation, snap back: ease-out, no overshoot, ~240 ms to settle (57pt offset: 14pt moved in the first frame, then 18, 9, 3, 5, 3, 2, 1, 1, 1).
- [ ] Release animation, commit: the remaining distance (~150pt) closes in ~120-160 ms with the same ease-out, tint finishing in step.
- [ ] The web content area does not move. It switches to the target Space's selected tab right at the commit (first frame after release) and shows that Space's page directly, no slide or crossfade of the page card.
- [ ] Space name label sits in the list (it moves with it). Keyboard (Ctrl-digit) and pager-icon switching were not captured; Bato gives them the same non-interactive slide as an assumption.

## 7. Create Space and theme picker (captured 2026-11-09, private shots in `2026-11-09/create-space/`)

Driven through Arc's UI only (synthetic mouse/keys). Window 1470x892 pt, 1x, sidebar 268 wide. Coordinates are window points (y from the window top); colours sampled sRGB. The test Space was deleted afterwards and Create Space was also cancelled once.
Entry
- [ ] Opened by the pager `+` -> "New Space" (menu: New Space, New Folder | New Easel, New Boost | New Split, New Tab). Also the page past the last Space (section 6). Not checked: a Spaces menu item.
- [ ] The page slides in from the right like a neighbouring Space (tint cross-fades from the current Space to the draft theme); Cancel slides it back (~250 ms, sidebar offset ~12 pt in the second frame) and restores the previous Space's tint.
Page (`02-create-page`)
- [ ] Replaces the list, Favorites row and Space header; window controls row and the pager dots stay (a new dot for the draft Space appears, and shows the chosen icon).
- [ ] Illustration: three fanned white cards, ~66x42, centred x=134, y 82..124. Title "Create a Space" 17 pt semibold centred y=150. Subtitle 13 pt regular, two lines, centred y=180 and 197, ~170 wide.
- [ ] Rows are x 14..254 (240 wide), radius ~8, translucent fill ~white 10% on dark: Space name y 238..273 (35 tall), Profile y 279..316 (37), Choose a Theme y 323..360 (37); 6-7 pt between rows.
- [ ] Name row: 18 pt dashed rounded-square "+" icon button at x=31, field 14 pt medium from x=48, placeholder "Space name...". Row brightens (white ~25%) while focused.
- [ ] Profile row: smiley glyph x=30, "Profile" 13 pt semibold at x=46, pill "Default v" x 96..166 (70x20, fully rounded, ~white 12%, 11 pt semibold), info (i) button at x=238. Pill menu did not open in the capture (single Profile); tooltip "Default".
- [ ] Choose a Theme row: brush glyph x=30, label 13 pt semibold x=46; fill goes to ~white 20% while its popover is open.
- [ ] Create Space: x 14..254, y 760..796 (36 tall), radius ~8, 13 pt semibold white. Disabled until the name is non-empty (dimmed text, ~45% fill). Fill is a darker tint of the theme (#454097 default; #7D647E with a purple/green theme). Cancel: centred y=818, 13 pt medium, white ~80%.
- [ ] Return creates, Escape cancels while the name field is focused (Return not driven; Create button was).
Icon picker (`10-icon-picker`, `11-icon-tab`)
- [ ] Callout popover below the icon button, ~272x270, arrow at the button; segmented Emoji | Icon at the top (selected tab indigo #5b6bd5-ish), Emoji tab: Search field + 7-column grid (pitch ~33) + category row; Icon tab: 8 columns x 7 rows of monochrome white glyphs (pitch ~31).
- [ ] Picking an icon closes the popover; the glyph replaces the dashed placeholder in the field and the pager dot.
Theme popover (`03-theme-popover` .. `swatch-p4`)
- [ ] Callout popover to the right of the row: x 268..623 (355 wide), y 88..594 (506 tall), radius ~22, arrow ~8 pt on the left edge at the row's centre y=341. Opens with no handle ("Tap to pick a color for this space") and the moon (dark) mode selected.
- [ ] Field: x 275..615, y 95..435 (340 square), radius ~16, dotted (dots ~1.4 pt, pitch ~5) over a ~white 6% fill. The field is a disc of radius 170: hue = angle around the centre (clockwise from the right: right red, bottom yellow-green, left cyan, top violet), lightness = distance (centre black, ~halfway vivid, rim white). Handles are clamped to the disc.
- [ ] Mode buttons: sparkle (auto/system), sun (light), moon (dark), 32x30 at y 120..150, centres x 404, 445, 484; selected fill ~white 20%, radius ~8. The popover itself switches to a light panel in light mode.
- [ ] Mode effect: light makes the content card a near-white tint of the colour (#E9E2E9 for a mauve) while the sidebar/window keeps the full colour; dark keeps the card the same tone as the window. Auto = system (dark here).
- [ ] Handles: primary 46 pt (3.5 pt white ring), extra handles 28 pt (2 pt ring); the selected one is the large one. Click on empty field moves the selected handle there; a click at one point also focuses the Space name field.
- [ ] `-` / `+` at (425,403) and (465,403), 20 pt apart: `+` adds a handle at a new spot with its own colour (max 3, `+` dims at 3), `-` removes the selected one (dims at 1). Window background becomes a soft diagonal gradient across the handle colours in handle order.
- [ ] Preset swatches: row centre y=467, 24 pt circles, pitch ~29.6, 9 per page, chevrons at x=291 and 599 (dim at the ends); 4 pages: solids, two-colour gradients, pastels, deep tones. Picking a swatch sets the handles (gradients set two). Page 1: #F2EFEA #E1B4C6 #A88CAA #D68681 #E3A376 #EEDD83 #A4E3AE #A2C3DD #7B7B98.
- [ ] Wavy slider (x 286..508, y 540): a sine wave on a rounded track with a white pill thumb; left = flat wave and a small thumb (~16x52), right = tall wave and a larger thumb (~28x62). Controls how strongly the colour replaces the neutral base (cream at left read #DDDCDA, at right #F0EDE9 in dark mode). Default thumb position ~75%.
- [ ] Dial (centre (565,539), ring radius ~35): 28 small dots filled clockwise from the top up to a white pill indicator; inner knob radius ~20 darkens as it turns. Controls grain: 0 at the top, a visible film-grain texture over the whole window by the bottom. Click or drag sets the angle.
- [ ] Everything previews live: sidebar, window chrome and content card tints change as the handle moves; nothing is committed until Create Space.
Create (`create-f1..6`, `create-final`)
- [ ] The page scales/fades toward the centre while a rounded tile with the icon (~64x80, ~white 50%) appears mid-screen, then the normal sidebar appears for the new Space: Favorites, Space header (icon + name), New Tab, themed. Roughly 0.5 s.
Edit an existing Space's theme (`20d-ctx`, `21-edit-theme3`)
- [ ] Space header right-click menu: Change Space Icon..., Rename Space..., Edit Theme Color..., Set Profile >, | New Folder, Live Folders > | Share Space..., Export into Folder > | Manage Spaces... | Delete Space (undo toast "Space deleted! Use Cmd-Z to undo.").
- [ ] "Edit Theme Color..." opens the same popover (same size, handles, mode, slider, dial and swatch page restored) near the top of the window without a callout arrow, previewing live.
Not verified: profile menu contents, dial/slider exact curves (linear assumed), emoji search, Return-to-create, effect of mode on text colours beyond the popover and sidebar labels turning dark on light themes.

## 8. Drag tab to split (Dia, captured 2026-11-09, private shots in `dia/2026-11-09/drag-split/`)

Driven with synthesized CGEvent mouse down/drag and window screenshots, on a 1920x1080 point display. Another agent was driving Arc and other apps on the same display, so only the first part of the drag was captured cleanly; items marked UNVERIFIED are assumptions Bato implements.
- [ ] Zones appear at the START of the drag, while the pointer is still on the sidebar row (`t1-a-sidebar`, `t2-0-start`), not on entering the page. Fade in not measured.
- [ ] Exactly two zones, "Add left split" and "Add right split"; no top or bottom zone. Content card x 206..1916, y ~37..1075 (toolbar included).
- [ ] Armed size ~194 x 327 pt: left zone x 244..437 (38 from the card's left edge), right zone x 1705..1898 (~18 from the right edge), both centred vertically on the card (y 392..719, centre ~555).
- [ ] Larger once the pointer is over the page: ~313 x 520 pt (left x 244..557, right x 1585..1898, y 296..816), same edge insets and centre (`t1-c-content`, `t2-1`). Exact trigger (pointer over page vs elapsed time) and the grow animation not measured.
- [ ] Look: dark fill ~#222 (opaque-ish), rounded radius ~20, 1.5 pt dashed inner border (~white 40%, 8 pt inside the edge, dash 5 / gap 4), soft drop shadow, a half-filled-rectangle glyph (~16 pt, left or right half filled) above a 13 pt semibold label, both ~white 60%, centred in the zone.
- [ ] The page stays visible and unblurred between the zones; no dimming of the page.
- [ ] Drag image is a ~208 x 104 snapshot of the dragged page (not the row), centred on the pointer; the dragged row leaves the list for the duration (rows below it close up).
- [ ] Mouse-down on a sidebar row selects that tab as usual, so the page under the zones is the dragged tab's own page in the first frames; after the drag started the current tab was unchanged in the later frames (`t1-c`). Which tab Dia treats as "the other pane" was not confirmed.
Second pass (2026-11-09, own example.com/org/net tabs, 1920x1080, private shots in `dia/2026-11-09/drag-split/` 50-81):
- [ ] Hover highlight: the targeted zone grows about its centre by ~1.15 (313x520 -> ~360x597) and turns amber: fill ~#3D2F1E, dashed border ~#D57F00 (the Space's gold accent; 213,127,0), glyph and label amber. The other zone stays grey. Dragging back out restores it. Bato matches (hoverScale 1.15, amber constants); the amber is a constant, Dia probably takes it from the Space accent. Dia also nudges the targeted zone towards the pointer vertically (centre moved 484..660 for pointer y 440..760); Bato does not.
- [ ] Drop on a zone: the dragged tab becomes the pane on that side, the current tab the other (left drop: dragged left, selected right). Sidebar shows one split row with both titles; the dragged page's pane gets the gold focus outline. Each pane gets its own toolbar (back, forward, reload, URL, X). Bato matches.
- [ ] Already split: Dia still shows the zones and a drop adds a third pane (org | net | com, three-way split row). Bato only has pairs, so it shows no zones (UNMATCHED, would need N-way splits).
- [ ] Dragging the selected tab: Dia shows the zones; dropping makes a split of that tab with a New Tab (Ask anything page) in the other pane. Bato now does the same (zones for the unsplit selected tab, drop keeps the page on its side and opens the command bar for the other pane).
- [ ] Drop in the page centre / between the zones: not a no-op in Dia. Releasing a row there tore the tab off into a new window (drag image changes to a window thumbnail with traffic lights). Bato is single-window, so it stays a no-op (UNMATCHED).
- [ ] Escape mid-drag: the drag cancels, zones vanish, tab stays where it was, nothing changes.
- [ ] Zone sizes were identical in the second pass (armed 194x327 at the start of the drag, 313x520 over the page), so section values hold.
Arc (`arc-drag-split/`): Arc has the equivalent, with a different look. Dragging a sidebar tab over the page splits it live: the current page shrinks to the other half and a dark rounded placeholder card (favicon plus title, ~168x250) shows where the tab will land, with a divider handle between; the half follows the pointer side (left half when the pointer is left of the middle, right half when right). Over the middle strip or toward top/bottom the card just floats on the full page (no split; a purple page outline appears when the drag is over the page in another Space). Drop on a half: split row with both titles appears in the sidebar and each pane gets its own header (URL, X). Escape cancels with nothing changed. Dragging near the sidebar edge can switch Space mid-drag.
- [ ] Not verified: grow animation timing, fade timing, drop animation, dragging a pinned tab or a Favorite, Arc top/bottom splits, Dia zone order with more than three panes.

## 9. Profile per Space (Create a Space Profile pill, reference supplied by the owner, 2026-11-10)

Source is a screenshot of the Create a Space page with the Profile pill menu open; Arc itself was not driven for this section and nothing was created in it.
- [ ] The pill opens a small dark popup menu directly under it: one row per Profile with a checkmark on the current choice, a separator, then "New Profile...".
- [ ] "New Profile..." creates a Profile and selects it for the Space being created.
- [ ] The info (i) button explains that Profiles keep logins and cookies separate.
- [ ] Spaces of different Profiles share one window; switching to a Space of another Profile changes the page area in place (design: PROFILE-SPACES.md).
- [ ] Space header menu has "Set Profile >" (section 7); Bato does not implement it yet.

## Not captured / caveats

- Grabber "dragging" colour is indistinguishable from hover; no distinct pressed style seen.
- Collapse animation frames were overwritten; only the expand animation (`10-expand-frame*`) is kept.
- Ctrl-Tab panel appear/disappear easing could not be measured (panel absent at first frame, present by
  ~300 ms); Shift+Ctrl+Tab and >3 entries (row wrapping/scroll) not captured.
- Vertical split orientation not captured (would require converting the user's split).
- Opening the Clear action was not exercised (would close real tabs).
- Space swipe: exact easing curve and spring constants are inferred from ~33 ms frame spacing; the pager icon change point, keyboard/dot-click transition and a momentum-only release are unverified.
