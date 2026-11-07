# Milestone 4 plan

Written 2026-11-07 before edits. Not committed. No Ardia code, no images in the repo.

| # | Item | Approach |
| --- | --- | --- |
| 1 | Profile delete | Engine export `bato_native_slot_delete_profile_v1(key)`: refuses the launch key and non-UUID keys, closes the Profile's browsers without beforeunload, then hands the path to Chromium's `DeleteProfileHelper` (browsing data wiped at once, directory removed when the Profile is destroyed or at the next launch via `kProfilesDeleted`). Client drops the cached request context. Swift: `BrowserState.deleteProfile`, `PageRuntime.deleteProfile` (backup first, engine call, forget live pages), Settings > Profiles Delete with a confirm sheet; per-Profile blocking settings directory removed. |
| 2 | Fullscreen sidebar reveal | Engine: in fullscreen an owned window keeps the host visible as a 6 pt edge (hidden) or overlay (mode 2) with no reservation, and `set_sidebar` is accepted in fullscreen. Swift: existing edge hover / Cmd-S path, Cmd-S in fullscreen toggles the overlay. |
| 3 | Recently Closed | Client maps the History > Recently Closed items to `reopenClosedTab`. |
| 4 | Cosmetic filtering | adblock FFI cosmetic resources (hide selectors, injected scripts) fetched per URL in the client, injected as CSS/JS per frame, honouring per-Profile enable and site exceptions. |
| 5 | Split pointer divider | Investigate MultiContentsView divider hit-testing; fix if cheap, else document. |
| 6 | Downloads popover | Refit popover height on list change; keep it inside the window. |

Verification: `native_slot.py check`, `swift test` (`logs/m4-swift-tests.log`), build (`logs/m4-build-segment.log`), real host `tmp/launch-m4-v*.py`, mock keychain, throwaway Profile only, quit via "Quit Chromium".
