# Per-Profile blocking, D5 and D6

Written 2026-11-07. Nothing here was built into the engine or run on the real host; C++ only passed `clang++ -fsyntax-only`.

## Design

**Layout** (`<state>` = `--bato-workspace-state`, root override `--bato-blocking-dir`):
- `<state>/blocking/lists/*.txt` and `lists-status.json`: filter lists, shared by every Profile.
- `<state>/blocking/<ProfileUUID>/blocking-settings.json`: enabled flag and exceptions, per Profile.

Why shared lists plus per-Profile settings: the lists are identical public downloads, so per-Profile copies would repeat the download and the rule-set parse for no isolation gain. What must not leak between Profiles is policy (the switch and exceptions), and that stays per Profile. One engine is built per distinct list set (`ListSet` keyed by directory), so today every Profile shares one engine; a future per-Profile list selection only adds another `ListSet`.

**Resolution (C++).** `native_slot_client.mm` records each browser's Profile key in a mutex-guarded map when the browser is created (UI thread), from its request context cache path: `<root>/Default` is the launch Profile (resolved to the key Swift last passed for it in `CreatePage`/`OpenProfileWindow`), `<root>/<key>` is that Profile. `BatoWorkspaceBlockingProfileKey(browser_id)` (any thread) feeds `SimpleHandler::GetResourceRequestHandler` (IO thread), which gets or creates the Profile's `ProfileBlocking` and gives it to the request handler. An unknown browser or invalid key is not filtered (fail-open). Workspace mode off resolves to key `default`. The 250 ms poll now refreshes each Profile's settings (cheap, first) and each list set's engine (off the IO thread); a Profile's settings are null until first read, which allows requests. Engines stay immutable, shared_ptr held.

**Swift.** `BlockingProfiles` (new) owns the shared `FilterListUpdater`, one `BlockedCounters` (browser ids are process-wide) and one `BlockingService` per validated key (`service(forProfile:)`, nil for unsafe keys such as `..` or `lists`). `BlockingHost.shared.service(forProfile:)` replaces the single `service`; `BatoSwiftBlockingStart` now receives the blocking root. `BlockingControls` takes `serviceForProfile` and the active page's `profileKey`, so the Page menu toggles exceptions in the active page's Profile. `WorkspaceSlot.swift` passes `page.profileID.uuidString` (a small isolated edit in `blockingMenuItems`).

**Migration.** Not migrated: old `blocking/default/` (exceptions reset to default-on; lists redownload into `blocking/lists` at next launch). Alpha, no user data.

## D5 pin title

`BrowserState.recordNavigation` (the single commit path from `PageRuntime`'s `.navigation` event) now updates `title` only for temporary tabs. Favorites and pins keep the title they were saved with; `lastURL` still updates. A temporary tab pinned later keeps the title it had. There is no entry rename UI today, so the "unless the user renames" case is unreachable. Side effect: "Make temporary" on a navigated pin shows the saved title until the page's next title change (one existing test expectation changed accordingly).

## D6 copies wording

Copies get salted identifiers, so they really do create new Profiles; the count was accurate but confusing, and reuse showed "in 0 new Profiles". `ImportSummary.reusedProfiles` plus `workspaceDescription(asCopies:)` now yields e.g. "3 workspaces as copies in 2 new Profiles (separate from the originals)" and "1 workspace in 1 existing Profile". Used by both the preview totals and the completion message.

## Files

Swift: `BatoBlocking/{BlockingProfiles (new),BlockingService,BlockingHostExports}.swift`, `BatoBrowserUI/{BlockingControls,ArcImportController}.swift`, `BatoCore/BrowserState.swift`, `BatoImport/ImportPlan.swift`.
Engine client: staged `simple_handler.cc`, mirrored `native_slot_client.{h,mm}`, `WorkspaceSlot.swift`, `compile_native_slot.py`, staged `cef/BUILD.gn` (BlockingProfiles input), `client.json`, regenerated `client.patch`. `PageRuntime.swift` and `NativeWorkspaceController.swift` were also re-staged because the concurrent Profile switcher work had changed them (their WIP is in the patch; re-run `tmp/regenerate-workspace-client.py` after that work changes again).

## Tests

Full suite log `/Volumes/Mahesh/personal/bato-build/logs/perprofile-blocking-swift-tests.log`: 117 XCTest + 148 Swift Testing = 265 passing (includes the concurrent switcher tests; 245 before). New: `BlockingProfilesTests` (isolated exceptions/enabled per Profile, per-Profile settings files and reload, service identity and directory helper, shared counters, unsafe keys, one list download into the shared directory), two D5 tests in `BrowserStateTests`, one D6 wording test in `ArcImportApplyTests`. Client patch: 31-file round trip and 27 mirrors verified; `native_slot.py check` passes. Not run: `native_slot.py build`.

## Verify on the real host (after the coordinator builds)

1. Two Profiles, same site with trackers. Turn blocking off for the site in Profile A only: A loads trackers, B still blocks, counts per page correct in each window. Relaunch and confirm each Profile's exception persists (`blocking/<UUID>/blocking-settings.json`; no settings file in the other Profile).
2. First load in a freshly created Profile: expect a short unfiltered moment until its settings are read (<= one poll), then blocking. Launch Profile's very first requests before the first page creation are unfiltered by design (key not yet known).
3. `--bato-blocking-log` shows `ready` once (one engine), lists exist only under `blocking/lists`; no download per Profile.
4. Popups, DevTools and Chrome-owned tabs in a Profile window use that window's Profile key; confirm no crash on quit with several Profile windows and that quit still exits naturally.
5. D5: open a pin, navigate within it, relaunch: sidebar title stays the saved title; temporary tabs follow the page title.
6. D6: import preview with and without "import again as copies" when Profiles already exist.
