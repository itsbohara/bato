# Arc-style native sidebar

Date: 2026-10-31. Status: bounded real-host acceptance passed.

The native sidebar replaces the engineering-style control stack with a compact branded/workspace header, rounded address surface, explicit New tab focus and Find page controls, two-column 62-point Favorite tiles, and 34-point pin/temporary rows. Section counts, native symbols, selected/hover surfaces and the bottom workspace/Profile footer organize the same actions inside the existing 260-point slot. Close/unload controls remain present and accessibility-labelled. Full title/address help preserves long-title information. Stable entry IDs restore focused page controls during runtime row rebuild. Drawing resolves semantic system colors on an opaque workspace-tinted surface and redraws for appearance/accessibility display-option changes.

Only app/Sources/BatoBrowserUI/NativeWorkspaceController.swift changes application behavior. Existing context menus, workspace editing/actions, Find Page sheets, keybindings and page/save semantics are preserved. No engine API, organization schema or standalone-preview change. Full browser chrome, rounded page geometry and sidebar resize/hide/reveal/Cmd+S remain future engine integration.

## Build and source review

Independent source review found no actionable defect. The Swift package built in 5.34s before the final header adjustment. V1’s actual source-host build passed in 28.38s/two steps, with compiler output SSD logs/arc-sidebar-compiler.log. The final header build passed in 27.84s/two steps, retained as logs/arc-sidebar-header-compiler.log. Guarded 13-file client reverse/forward/hash roundtrip, nine source mirrors and 21 overlay validation passed. Canonical source, staged source and binary match.

The 527 ARM64-image scan passed for the preceding Find Page checkpoint. This UI-only change adds no engine/dependency change, so no repeated heavy artifact scan is claimed. No new model/runtime tests were needed for the visual-only source change; existing behavior is covered by the affected real-host workflows below.

## Runtime acceptance

A baseline host completed normal application-menu Quit exit0 with exactly one native detach, message-loop return and CEF shutdown. Its synthetic capture is SSD logs/arc-sidebar-baseline.png. A separate organization fixture runtime/arc-sidebar-state-v1 contains three Favorites, two pins, two temporary tabs and two workspaces, including long titles. Both runs use the existing synthetic workspace-v3 engine Profile with mock Keychain on every launch; no personal browser data is involved.

V1’s dark-mode rendering showed the rich 260-point layout, long-title ellipsis and full accessibility help. A real modal-fixture click advanced counter0→1. The Library Favorite opened the dummy-login fixture as the third browser; its context menu retained all expected commands and enabled-state gates. Returning to the modal page reused counter1. Find Page no-match disabled Open; Escape preserved exact organization bytes. Footer switching showed empty Research with shared Favorites, then returned to the live Personal modal page at counter1. Root verified exact organization equality through cancellation, the workspace roundtrip and Quit. Normal application-menu Quit PID56626 exited0 with one detach, loop return and CEF shutdown. Initial/empty/final captures remain SSD logs/arc-sidebar-v1-*.png.

Visual review found the header icons bunched. The retained three-line correction gives the heading fill distribution, lowers workspace-title horizontal compression resistance and constrains the title to its identity column. V2 showed the corrected right-aligned header controls. New tab focused the native address field, confirmed through accessibility; typing a local HTTP address and clicking the arrow opened the actual dummy-login fixture as the third browser and increased temporary rows from two to three. Clicking the new row’s close control removed it and restored two temporary rows. Returning to the modal page accepted a real click counter0→1. Final and new-tab captures are SSD logs/arc-sidebar-v2-final.png and arc-sidebar-v2-new-tab.png. Normal application-menu Quit PID64150 exited0 with one detach, loop return and CEF shutdown. Root verified the final organization bytes exactly match the pre-run document.

No owned browser/build remains; old CUA bindings point to exited processes. Runtime visual acceptance is limited to the current dark appearance at 260-point sidebar width in a normal window. Light mode, short-window layout, general window resizing, increased contrast, hover appearance and row-focus restoration were not separately exercised; their code must not be described as runtime-passed. No extension tests. Remaining foundation and daily-use gates stay open.

## Next engine integration boundary

Rounded page geometry belongs in Chromium’s existing `ContentsContainerView::SetRoundedCorners` path, which updates native page contents, DevTools and overlays together. Preserve Chrome’s origin UI, toolbar and extension anchors while changing the content surface.

Sidebar resizing and hiding need one per-window geometry state shared by Chrome’s reservation insets, native slot bounds and minimum-window size. Define engine-command behavior while the sidebar is hidden: current `FindSlot` requires host visibility and therefore gates creation, selection, close and native focus. Hiding only the Swift root leaves the reserved 260-point gap; hiding the host also blocks those commands. A coordinated engine integration must handle geometry and command availability while preserving modal, fullscreen and lifecycle guards.
