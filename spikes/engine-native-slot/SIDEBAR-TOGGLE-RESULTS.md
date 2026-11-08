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

# Stuck floating sidebar after Cmd-T: real-host results

Run 2026-11-08, uncommitted. Root cause: with the sidebar hidden, `showCommandBar` and its commit/cancel paths call `requestNativeFocus`, which lands in `WorkspaceSlot.focusNative`; that reveals the sidebar (geometry mode 2) so a hidden control can take focus. The pointer never enters the overlay, so `mouseExited` never fires, and the only other dismissal was a click outside the sidebar. Fix: `SidebarPeekDismissal` (BatoCore, pure rules, 7 unit tests in `SidebarPeekDismissalTests`) decides when a floating sidebar goes away; `WorkspaceSlot` feeds it pointer exit, a 0.5 s pointer poll while floating, key presses in the page (non-Command), clicks outside, and window resign. Focus left on the control `focusNative` landed on counts as incidental, so the poll dismisses and hands focus back to the page; real sidebar focus (rename, search) and open sheets/menus still hold the overlay. New file registered in `client.json`, `compile_native_slot.py` and `BUILD.gn` inputs; mirrors staged, client patch regenerated (60 files, 55 mirrors), `native_slot.py check` ok, `build --execute` waited to exit 0 (segment `logs/sbp-build.log`), `swift test` 247 pass.

Launches (SSD, `--use-mock-keychain`, `tmp/launch-sbp.py v1|v2|v3`, states `runtime/sbp-state-v*`, exits 0 via Quit Bato, windows selected by pid). Shots `tmp/sbs-shots/peek-*.png`. The pointer was moved with posted CGEvents (`tmp/movemouse.js`); `agent-desktop mouse-move` does not move the real pointer. Another session was driving a second test instance on the same screen during the run; its windows are visible in a few discarded shots.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Before fix: hidden, Cmd-T, type, Enter: overlay still up 5 s later | REPRODUCED | `peek-before-5-after-enter-5s.png` |
| 2 | After fix: same flow, overlay gone by 2 s (visible at 0.4 s, poll interval) | PASS | `peek-after-3-*`, `-4-*`, `-5-*`, `peek-v1-cmdt-enter-2s.png`, `peek-w2-cmdt-enter-2s.png` |
| 3 | Cmd-T then Esc while hidden: overlay not left behind | PASS (failed on the first fix, `peek-v2-cmdt-esc-2s.png`) | `peek-w1-cmdt-esc-2s.png` |
| 4 | Edge hover reveals, pointer exit dismisses | PASS | `peek-u1-*`, `peek-u2-*`, `peek-t2-*`, `peek-w4-*` |
| 5 | Plain key press in the page dismisses a hover overlay (pointer inside it) | PASS | `peek-y1-*`, `peek-y2-after-key.png` |
| 6 | Cmd-S docks from peek, hides when docked | PASS | `peek-u3/u4`, `peek-w5/w6` |
| 7 | Show-sidebar button docks the sidebar | PASS | `peek-u5`, `peek-w7` |

Not exercised: window resign dismissal and click-outside dismissal on the new path (covered by the unit rules; click-outside unchanged in behaviour), fullscreen floating sidebar, a keystroke while the pointer rests inside the 6 pt edge strip (the overlay re-reveals because the pointer is still on the edge, as Arc does).
