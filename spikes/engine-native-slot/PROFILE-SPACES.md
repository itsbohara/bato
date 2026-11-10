# Profile per Space in one window

Goal: Spaces of different Profiles share one visible Bato window. Switching to a Space of another Profile swaps the page area in place; logins and cookies stay isolated per Profile.

## Constraint

A Chrome `Browser` is bound to exactly one Profile, and the native slot embeds the Swift sidebar inside that Browser's NSWindow (`bato_native_slot_register_v1` creates one root view per window). One Chromium Browser per Profile in use is therefore unavoidable; the question is how to present them as one window.

## Options considered

1. Re-parent each Profile's BrowserView/contents view into a single host window. Needs engine changes (views::Widget re-parenting, focus manager, WebContentsDelegate and Browser command routing all assume the owning Browser window). Highest risk, new ABI, long Chromium rebuilds.
2. Per-Profile windows kept as siblings, with exactly one visible and the same frame (chosen).
3. Child windows stacked over a host window's page area. Child NSWindows do not take part in Chromium's focus manager and menu/command routing; rejected.

## Chosen: frame-synced sibling windows (client only)

- The model already lets one workspace list hold Spaces of every Profile (pager dots, swipe, Ctrl-n and the switcher cross Profiles). Favorites come from the Space's Profile, so the strip follows it.
- `WorkspaceSlot.show()` runs whenever the engine selects a page (`WorkspaceEngine.select` calls `onShow(token)`). When the target window differs from the one carrying the sidebar, it copies the visible window's frame onto the target and orders the target in front. The old window stays ordered in, exactly underneath. The sidebar view and card overlay are re-mounted by `WorkspaceHost.mount` as before.
- Why the old window is not ordered out: a first real-host run did so, and switching back to a hidden window was rejected by the engine (`native-slot-rejected reason unavailable`, `active-browser-unavailable`), because `Widget::IsVisible()` lags `orderFront` by a runloop turn and the slot guard requires it. A covered but ordered-in window stays visible to the engine (and Chromium's occlusion tracking still pauses its rendering).
- Swipe: `WorkspaceSwipe`'s page switch already commits at release (`switchWorkspace` -> runtime selection -> `select`), so the window swap happens at that moment; the slide animates the sidebar only.
- Commands (Cmd-T/W/L, history, downloads) are routed by the key window, which is the visible Profile window, and by `WorkspaceEngine.windows[profile]`. Popups and permission prompts are anchored to their own Browser window, which is the visible one while that Profile is shown.
- Split and Peek require both panes in one Profile; the runtime already enforces same-Profile pairs and a Space has one Profile, so both panes are in the visible window.
- Moving or resizing: the mounted slot's window posts move/resize notifications and every sibling window adopts its frame, so no stray window shows behind it, and the frame is copied again at each swap.
- Quit and teardown are unchanged: hidden windows are still live Browsers and close with the app. Session restore is organization based and creates each Profile's window lazily on first page.
- Create a Space: the Profile pill lists every Profile (check on the choice), a separator and "New Profile…". A new Profile is only created together with the Space (`PageRuntime.createProfile(... theme:icon:)`), so cancelling leaves nothing behind. The info button tooltip explains that Profiles keep logins and cookies separate.

## Risks and gaps

- Native fullscreen: each window has its own macOS Space, so while the visible window is fullscreen the swap does not sync frames (the new window appears windowed). Not solved.
- The covered window is occluded; Chromium may throttle its rendering, so background media in another Profile's window can pause.
- Window menu and Mission Control list one window per Profile in use.
- A freshly created Profile window can appear at its default frame for a moment before the first selection syncs it.
- Move to Profile: the Space menu's "Profile" submenu (check on the current one, "New Profile…") asks for confirmation, then `PageRuntime.moveWorkspace` saves the new Profile, closes the Space's live pages without asking and reopens the active selection in the new Profile's window; other pages reopen from their saved addresses when shown. A Profile's last Space cannot be moved out, a selected Favorite is deselected, and the Space's closed-tab history is dropped.
- No engine ABI change; export count stays at the current value.
