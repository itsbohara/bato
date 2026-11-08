# Show-sidebar button: real-host results

Run 2026-11-08, uncommitted. Swift: `ContentCardFrameView` in `NativeWorkspaceController.swift` owns the button (`sidebar.left`, 13pt, secondary tint, borderless, same as the header toggle; the header toggle has no hover fill, so neither does this). Engine: `browser_view_layout_delegate_impl.cc` adds `kNativeSidebarToggleSlot` (38pt) to the leading exclusion whenever the sidebar reserves no width (hidden or floating), so Chromium's back/forward start after the button. Unit tests: `ShowSidebarButtonTests` (visibility rule, slot arithmetic). Mirror staged, client/engine patches regenerated (56 files, 51 mirrors), `native_slot.py check` ok, `build --execute` waited to exit, `test_patch.py` OK, `swift test` 215 pass.

Design note: the first attempt hosted the button in the card overlay inside the window content view; Chromium's `BridgedContentView hitTest:` returns itself for every point over its own toolbar, so clicks never reached it (v1, v2). The button now sits in the traffic lights' titlebar container, positioned from the zoom button's frame.

Launches (SSD, `--use-mock-keychain`, `tmp/launch-toggle-v{1,2,3}.py`, states `runtime/toggle-state-v{1,2,3}`, exits 0 via Quit Bato). v3 is the final build. Windows selected by pid. System appearance toggled, Dark restored.

Shots in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/`: `toggle-docked-dark.png`, `toggle-hidden-dark.png`, `toggle-restored-dark.png`, `toggle-peek-dark.png`, `toggle-fullscreen-dark.png` (page only), `toggle-hidden-light.png`, `toggle-restored-light.png`.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Hidden: button right of traffic lights, on their centre line | PASS | `toggle-hidden-dark.png`, `-light.png` |
| 2 | No overlap with back/forward (toolbar shifted right) | PASS | Same shots; back arrow starts ~40pt after the button |
| 3 | Click shows the sidebar and the button disappears | PASS | AX press and a physical click both gave geometry mode 0 to 1; `toggle-restored-*.png` |
| 4 | Docked: button absent, header toggle remains | PASS | `toggle-docked-dark.png`, no "Show sidebar" in AX tree |
| 5 | Hover-at-left-edge peek unchanged | PASS | `toggle-peek-dark.png` (mode 2, sidebar over toolbar, button hidden) |
| 6 | Fullscreen: no button over the page | PASS | `toggle-fullscreen-dark.png`, no AX match; button returns after exit |
| 7 | Dark and light | PASS | Both captured |

## Gaps

- Hover fill matches the header toggle, which has none.
- A second Profile window and window resize were not checked.
- The button is not in Chromium's focus order, only reachable by mouse, AX and Cmd-S.
