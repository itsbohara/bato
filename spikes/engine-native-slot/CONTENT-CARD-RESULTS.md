# Floating content card

Date: 2026-11-08. Status: implemented and real-host checked in dark, light, fullscreen, narrow and wide sidebar; three checks below are partial or failing.

## What changed

The tinted window now shows as an 8pt frame on top, right and bottom of the web content, with all four corners of the card rounded (10pt), a soft shadow and a hairline. Chrome's toolbar sits inside the card, above the page. The sidebar keeps its own tint behind and beside the card; the old resize-grip line is gone (the 6pt drag/keyboard/accessibility hit area remains, invisible).

- Engine layout (`browser_view_layout_delegate_impl.cc`, regenerated into `engine.patch`/`manifest.json`): when the native sidebar owns tabs, Chrome's child layout is inset 8pt top/right/bottom, and 8pt on the leading side when the sidebar reserves no width (hidden). Fullscreen and windows without an attached sidebar are unchanged. `kNativeCardMargin` must match `ContentCardFrameView.margin`.
- Client Swift, `NativeWorkspaceController.swift`: new public `ContentCardFrameView`. It paints the same gradient as the sidebar (`SidebarStyle.tint`, per workspace accent, light/dark, Increase Contrast) in the gutter with an even-odd rounded cut-out, excludes the sidebar's own width, draws the shadow and a 1pt hairline (2pt, stronger under Increase Contrast). It never takes hits and follows `AppearanceWatcher`. `makeCardFrame()` creates one per window and keeps them in step with the workspace tint.
- Client Swift, `WorkspaceSlot.swift`: each slot adds its card above Chrome's views in the window content view, updates it on attach, sidebar width/mode changes and fullscreen enter/exit (hidden in fullscreen). The sidebar content now runs under the grip, and the grip no longer draws a divider mark.
- `test_patch.py`: compact-top-row policy assertion now expects the card margins.

Mirrors staged, `regenerate-workspace-client.py` (55-file client patch, 50 mirrors) and `regenerate-slot-engine.py` (8-file roundtrip) verified; `native_slot.py check` patched; three `build --execute` runs finished successfully (the last is the client-only build with the grip change). `test_patch.py` OK, `swift test` 215 passed.

## Real-host runs

Mock keychain, SSD paths only: states `runtime/card-state-{v1,v2,d3}` (copies of `sbs-state-v1`), profiles `runtime/profiles/card-*`, wrappers `tmp/launch-card.py`, logs `logs/card-*.log`. Final run d3 quit via the app menu, exit 0 receipt `logs/card-d3-exit.json`, two detach events. Light mode was reached by toggling system appearance live (and restored to Dark), which also exercised the live repaint. Real Application Support and dist/Bato.app untouched. Screenshots are cropped to the Bato window only, in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/`.

Reference used: `/Volumes/Mahesh/personal/bato-references/dia/2026-11-01/02-new-tab.jpg` (Dia, dark). No light Arc/Dia reference exists in the library, so light is compared to the dark reference geometry only.

| Check | Shots | Result |
|---|---|---|
| Inset gap top/right/bottom (8pt, matches Dia ~8pt) | card-dark, card-light, card-wide, card-narrow | pass |
| Corner radius, all four corners | card-dark, card-light | pass (10pt; Dia reads ~12pt) |
| Shadow / hairline | card-dark, card-light | pass, subtle; Dia shows no hairline, only the tint edge |
| Toolbar inside the card | card-dark | pass |
| No divider line between sidebar and card | card-dark, card-narrow, card-wide | pass |
| Sidebar colour continuous behind card | card-dark, card-light | pass (same gradient in gutter) |
| Traffic lights placement | card-dark | FAIL: sidebar header and lights are unchanged, but the toolbar row now sits 8pt lower than them (Dia aligns both rows) |
| Fullscreen: no inset, no card | card-fullscreen, card-fs-restored | pass (card returns on exit) |
| Dark and light | card-dark, card-light | pass, repaints live |
| Narrow (220) and wide (400) sidebar | card-narrow, card-wide | pass |

## Remaining differences from Dia/Arc

- Toolbar row is 8pt below the traffic lights; align by raising the titlebar height constant (46 in `browser_native_widget_mac.mm` and the layout delegate) to 54 and re-centring the sidebar header, or moving the sidebar header down 8pt.
- Chrome's toolbar is its own near-black surface with a 1px light line beneath it, so toolbar and page differ in colour; Dia's toolbar is the page colour. Needs a Chrome-theme/toolbar colour change.
- In light mode a small dark sliver shows at the card's right edge where the toolbar meets the page (Chrome's container background behind the page's rounded corner).
- No sidebar toggle button in the toolbar (Dia has one); it stays in the sidebar header.
- Not verified: Increase Contrast, hidden sidebar and transient reveal visuals, multi-window other-Profile windows, window minimum size (the 16pt of margin is not added to the minimum), Peek over the card.
- The card is a painted overlay above Chrome's views: if Chromium re-adds a native view above it (new tab content) the slot re-raises it on the next geometry update only, so it was observed stable in this run but is not guaranteed.

## Follow-up round (2026-11-08)

Important finding: this Mac has Increase Contrast ON, so every earlier screenshot (and all earlier sidebar polish captures) ran under Chromium's high-contrast recipe: black/white toolbar, a 1px light separator under it and a dark-grey frame behind the page corners. That, not the card, caused the "toolbar differs from page", "line under toolbar" and "dark sliver in light mode" differences. With Increase Contrast off the stock toolbar colour already equals the page surface. Increase Contrast was toggled in System Settings for the checks and restored to ON (its original state); dark mode was restored to Dark.

Changes:
- Traffic lights: engine titlebar height 46 -> 62 (`kNativeSidebarTitlebarHeight`, toolbar row + 2 x card margin) so AppKit centres the lights on the toolbar row; the layout delegate caps the leading exclusion height at the toolbar row so the taller titlebar cannot stretch the toolbar. The sidebar heading row drops 11pt (`SidebarMetrics.headingDrop`) to share that centre line.
- Radius 12 (`browser_view.cc` page corners and `ContentCardFrameView.cornerRadius`).
- Left gutter: Chrome reserves sidebar width + 8pt; the card now has a visible gap from the docked sidebar, tint continuing through it.
- Re-raise: the overlay layer has `zPosition = 1000`, so compositing order no longer depends on subview order (kept the explicit re-raise too).
- Toolbar blending: no code change needed in normal contrast. Under Increase Contrast Chrome's own high-contrast toolbar (black/white, separator line) is kept on purpose for accessibility.

Builds: three more `build --execute` passes (waiting for `pgrep -f depot_tools/autoninja` empty each time), all successful; `test_patch.py` OK, `swift test` 215 passed, `native_slot.py check` patched. Final run `card-f1`, mock keychain, `runtime/card-state-f1`, quit through the app menu, exit 0, two detach events (`logs/card-f1-exit.json`).

| Check | Shots | Result |
|---|---|---|
| Traffic lights centred with toolbar row | card3-normal-dark (zoom of header), card2-hidden | pass: lights, toolbar buttons and sidebar heading share a centre line within 1pt |
| Toolbar matches page, no light line, normal contrast dark | card3-normal-dark | pass |
| Same in light, no dark sliver at right edge | card3-normal-light, card2-light | pass |
| Radius 12pt, all four corners | card3-normal-dark, card3-normal-light | pass |
| Gap between docked sidebar and card (left) | card3-normal-dark, card3-normal-light, card2-newtab | pass (8pt tint gap) |
| Overlay stays above Chrome views: tab switch, new tab (new native view) | card2-newtab | pass |
| Overlay above DevTools | card2-devtools | not verified: Cmd-Option-I did not open DevTools in this build |
| Overlay above new window, Peek | none | not verified |
| Increase Contrast | card3-hc-dark | pass: lighter sidebar wash, strong 2pt card edge, Chrome high-contrast toolbar with its separator (kept by design) |
| Hidden sidebar | card2-hidden | pass: 8pt gutter on all four sides, lights sit in the toolbar row; gutter is thin against the dark tint |
| Fullscreen, narrow, wide | from first round (card-fullscreen, card-narrow, card-wide) | not re-shot after the gap/radius change |

Still open: sidebar toggle button in the toolbar, minimum window size ignores the margins, light-mode sidebar tint is a saturated pink for this workspace (palette work), DevTools/new-window/Peek overlay order untested.

## Increase Contrast ignored by the chrome (2026-11-08)

Decision: Bato looks the same with macOS Increase Contrast on or off. Native shell: the card stroke is always the 0.14/1pt hairline, row and tile contrast strokes, the high-contrast sidebar tint, Settings card stroke, command bar 1.5pt border and downloads ring boost are gone, `AppearanceWatcher.increaseContrast` and its accessibility-options observer are removed. Engine: `OsSettingsProviderMac::PreferredContrast()` (`ui/native_theme/os_settings_provider_mac.mm`, 9th engine file) returns kNoPreference, so Chromium keeps its normal toolbar colours and separator. Side effect: web content's `prefers-contrast` also reports no preference.

Host verification with Increase Contrast ON (system setting untouched), test state `runtime/nohc-state-v1`, mock keychain, own window selected by pid, quit via app menu (exit 0 receipt `logs/nohc-v1-exit.json`), Dark restored. dist/Bato.app (pid 78069) untouched.

| Check | Shot | Result |
|---|---|---|
| No bright card border (dark) | `tmp/sbs-shots/nohc-dark.png` | pass |
| No white line under toolbar (dark) | same | pass |
| Toolbar colour equals normal-contrast shot (`card3-normal-dark.png`), not near-black | same | pass |
| Sidebar tint and row fill match normal contrast (dark) | same | pass |
| No bright card border, toolbar light-tinted, only the faint stock separator (light) | `tmp/sbs-shots/nohc-light.png` vs `card3-normal-light.png` | pass |
| Workspace swipe over sidebar | not exercised | unverified: agent-desktop scroll sends no gesture phases, and the seed state has one workspace |

Checks: `native_slot.py check` patched/84 files, `spikes/engine-native-slot/test_patch.py` OK, `swift test` all passing (WorkspaceSwipeTests added). `spikes/engine-quit/test_patch.py` still fails with "Quit source hash differs: browser_util.h"; it fails identically without these changes (the native slot overlay modifies that file).
