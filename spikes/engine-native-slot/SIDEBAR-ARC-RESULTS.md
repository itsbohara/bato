# Sidebar restyle toward Arc: real-host results

Run 2026-11-08, uncommitted. Swift (`SidebarStyle.swift`, `NativeWorkspaceController.swift`, `AppearanceTokenTests.swift`), one engine line (`chrome/browser/ui/views/frame/browser_view.cc`, regenerated `engine.patch`/`manifest.json`), new fixtures `spikes/fixtures/www/sidebar/*` (8 pages, each with a distinct SVG favicon). Mirrors staged, `client.patch`/`client.json` regenerated (55 files, 50 mirrors), `native_slot.py check` ok, `build --execute` (detached, waited for siso exit), `test_patch.py` OK, `cd app && swift test` all pass (3 new `AppearanceTokenTests` for row fill ordering and wash colours).

Launches (SSD, `--use-mock-keychain`): `tmp/launch-sidebar-v{1,2,3}.py`, states `runtime/sidebar-state-v{1,2,3}`, exits 0 via "Quit Bato" (`logs/sidebar-v{1,2,3}-exit.json`). v1 = first build (before join fix and New Tab alignment), v2 = final build with Increase Contrast ON, v3 = final build with Increase Contrast OFF (IC read at launch). System appearance toggled Light/Dark; restored Dark + Increase Contrast ON afterwards.

Shots (Bato window only) in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/`:
- IC on, final build: `sidebar-dark-ic-hover.png`, `sidebar-light-ic-hover.png`, `sidebar-dark-ic-selected.png`, crops `sidebar-dark-join.png`, `sidebar-light-join.png`, `sidebar-dark-tiles-zoom.png`
- IC off, final build (no strokes): `sidebar-dark-hover.png`, `sidebar-light-hover.png`, crops `sidebar-dark-noic-join.png`, `sidebar-light-noic-join.png`
- before join/alignment fix: `sidebar-dark-initial.png`, `sidebar-dark-ic-loaded.png`

Reference: `/Volumes/Mahesh/personal/bato-references/` holds only Dia captures, no Arc image; comparison is against the task's Arc description, not pixels.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Close x only on hover (rows and tiles; stays in AX tree) | PASS | Chat row shows x only while hovered; Video and Maps rows none (`sidebar-*-hover.png`) |
| 2 | Real favicons on rows/tiles; rounded letter tile fallback, no globe | PASS | Distinct SVG favicons (red play, pink note, etc.). Letter tiles shown for not-yet-loaded saved pages (`sidebar-dark-initial.png`). Favicons only arrive once a page has loaded, so saved pages not yet opened show the letter tile |
| 3 | Selected = soft fill, no stroke; hover subtler | PASS (IC off) / PASS with hairline (IC on) | Dark white 13%, light black 7%; hover 7%/4%; `sidebar-dark-hover.png` selected Video vs hovered Chat. IC on adds a 1pt hairline as allowed. Radius 10pt (spec 8-10) |
| 4 | Tiles: 3 per row, 44pt, centred 20pt favicon, soft fill, no heavy border | PASS | Dark white 8%, light black 6%; IC on adds a hairline. Tile width follows the sidebar (255pt default, so ~75pt tiles) |
| 5 | Rows 38pt, 13.5pt medium, aligned inset | PASS | Row icons at the same x as the New Tab plus. No URL second line (skipped as allowed) |
| 6 | New Tab row: dim plus + label, same metrics and hover | PASS | `sidebar-dark-hover.png`; plus sits in the same 16pt icon column as page icons |
| 7 | Folder glyph tinted with workspace colour | PASS | Blue "Work" folder glyph; name text stays secondary grey. Glyph is the closed-folder-fill when collapsed (not captured collapsed) |
| 8 | Header/traffic-light alignment not regressed | PASS | Unchanged in all shots |
| 9 | Content card: toolbar and page join square, only outer card rounded | PASS | Engine: contents radii were a uniform 12pt; now upper corners 0, lower 12pt (0 in fullscreen). `sidebar-dark-join.png`, `sidebar-light-join.png`, `-noic-join.png` (white page): flat join, no dark notch. IC on shows Chromium's 1px separator line under the toolbar (unchanged) |
| 10 | Light and dark | PASS | Both captured with IC on and off |

## Remaining gaps

- Favicons are session-local and only exist for pages loaded this session; saved-but-unopened pages show letter tiles (Arc caches them).
- Split-pair view keeps Chromium's own corner treatment (`kSplitViewContentRoundedCorners`), so splits still have rounded upper pane corners; not checked.
- Peek preview inset still uses its own rounded corners (intended).
- Collapsed folder glyph, the folder-tint in light mode and tile hover-with-close were not captured.
- Increase Contrast is read at launch only (existing N2), so IC on/off needed relaunches.
- Hover shots needed a physical pointer (`agent-desktop hover --headed`).
