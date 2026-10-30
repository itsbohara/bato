# Native Chromium workspace experiment

This opt-in source-built host connects `BatoBrowserUI`, `BatoRuntime`, the organization store and normal Chromium tabs in one window. Bounded runtime acceptance now covers real creation, saved navigation/reset, default-dialog cancellation, workspace switching and same-provider clean restart. It is a developer experiment, not a distributable or daily-use browser.

Use the existing pinned SSD engine checkout and `spikes/engine-build/native_slot.py`; do not rerun checkout/configure. The client overlay stages four Swift modules into `cef/tests/cefsimple/bato/` and links their objects into the existing native-slot library. Nine source mirrors are checked against repository bytes before building, so a stale staged sidebar or runtime is refused.

Workspace mode requires `--bato-workspace-state=/absolute/organization/directory` and initial `--url=about:blank`, in addition to the existing native-slot/reservation/Quit flags. The first slice supports one window and one explicitly bound engine request context. The organization Profile UUID is checked against that binding; it does not establish additional Profile isolation.

Dedicated synthetic acceptance Profiles use mock Keychain on every launch, including restarts. Keep those Profiles separate from personal/baseline data. The initial blank page is a retained placeholder, protected against website navigation. Selecting an empty workspace uses it; closing it through Chrome's tab strip creates a replacement only when needed and never during window/application teardown.

Native address entry creates same-window tabs using an authored helper that returns the exact inserted WebContents' CEF identity. Each live Swift generation binds to a fixed retained browser ID. Main-frame URL/title events update organization through validated commits. Native sidebar and exposed Chrome tab-strip selection synchronize. CmdT native focus and CmdW from native/page focus passed in bounded synthetic checks. A public AppKit local event monitor handles only exact CmdT/W in the active owned key window, checks sheet/modal/managed-page state and is removed on detach. Sidebar key equivalents are disabled in this host so they cannot target a remembered background entry. Chromium menu targets/actions remain intact; untracked tab close passes through. Queued CEF commands revalidate active identity. File-menu New Tab remains Chrome-owned; its organization integration is pending. Default Chromium beforeunload remains in charge of cancellation, observed through a WebContents-owned close observer.

Explicit sidebar/CmdW closure changes organization only after confirmed engine close. Unsolicited Chrome tab-X/window/application teardown unloads the handle while preserving its organization entry. Thus native tab-X currently differs from a Bato temporary-tab close. Untracked Chrome-created tabs, additional windows, fullscreen commands, split ownership and remaining extension checks are not complete application behavior.

The standalone `BatoShell` remains an organization preview. Its package declares macOS15 as a build floor; the source experiment's Swift action targets the existing CEF macOS13 ABI to match its executable. Compilation and acceptance on this Mac do not establish support for either minimum OS version.

## Current evidence

The v3 synthetic run created a real page on fresh startup, exited normally, and restored its stable entry on same-provider restart. A pin preserved its saved login URL while navigating to the storage fixture. Closing that pin reset its session URL; a separate temporary page remained. Default beforeunload Cancel preserved the temporary page and working input (activity counter0→1); Leave removed it. Reloading the pin opened its saved destination. A new empty workspace hid the other workspace's pin and selected the blank placeholder. Final Quit exited0 and left organization JSON exactly unchanged.

Forty Swift tests and eight overlay/patch tests pass. See the source host's workspace evidence for retained failures and remaining limits. This does not select a production foundation or establish daily-use readiness.

The keyboard follow-up passed page-focused default-dialog Cancel/Leave, working page input after Cancel, untracked Chrome tab closure without organization changes, and final normal exit0. It exercised no extensions. See `spikes/engine-native-slot/keyboard-evidence.json` and the workspace report for retained intermediate failures and exact limits.


## Workspace customization

The embedded sidebar’s Edit… control opens a native sheet for the current workspace name and color. Save commits both fields together; Cancel leaves organization unchanged. Six named colors are available, and an existing custom hex color is retained if no replacement is chosen. Workspace identity, Profile binding, page entries and selections remain unchanged. Metadata edits do not create, select or close engine pages. Sidebar tint and selected-row color follow the current workspace.

The model/runtime suite now totals46 passing tests (14core,9store,3session,20runtime). Six added cases cover atomic invalid edits, stable organization/Codable roundtrip, inactive workspaces, commit-before-publication, unchanged live generations/pending closes, and failed saves without engine effects. The source host compiled the edited Swift modules in29.90s; the guarded13-file client patch roundtrip/9mirrors and527ARM64-image dependency check passed. No engine API or document version changed. Actual source-host checks passed Cancel, blank-name validation, metadata-only saves with preserved IDs, switching with an existing pin, and same-provider restart showing Research/Ocean. Both runs completed normal Quit with exit0. Runtime evidence is recorded in `spikes/engine-native-slot/workspace-customization-evidence.json`.

The standalone preview retains its earlier UI; this editor is in the Chromium-connected sidebar. Multiple engine Profiles, workspace deletion/reordering, folders, split ownership and the remaining compatibility gates are separate work.


## Explicit saved destination updates

Pins and Favorites expose Update Saved URL in their context menu after a loaded page navigates to a different address. Ordinary navigation still changes only the session URL. The explicit action replaces the saved destination with the latest committed HTTP(S) address, preserving the entry UUID, placement, selection and live page. Unloading and reopening then uses that saved destination.

The action is disabled for unloaded, unchanged, closing or unavailable pages. Runtime rechecks eligibility when invoked and refuses updates after unsupported navigation or a failed navigation save, until a valid destination commits. Per-generation navigation-attempt tokens prevent an older callback from clearing a newer rejection during observer reentrancy. This transient guard stays out of organization storage. No engine API or organization schema changed. Removing/unpinning saved entries remains separate work.

Fifty-four Swift tests pass (16core,9store,3session,26runtime), including eight new cases for saved-only edits, shared Favorites, rejected contexts, persistence failures, stale generations, reentrant navigation, and unload/reopen behavior. The source build passed in26.99s, with guarded13-file patch roundtrip and9source mirrors. Actual source-host checks passed ordinary-navigation saved-URL preservation, explicit savedURL-only replacement, unloaded/unchanged menu disabling, same-ID reopen at the new destination, same-provider restart, and two normal Quit exit0 runs. The527ARM64-image dependency check passed. Runtime covered one pin; Favorites and navigation failures were tested with the fake engine. Exact runtime and artifact evidence is recorded in `spikes/engine-native-slot/saved-destination-evidence.json`.
