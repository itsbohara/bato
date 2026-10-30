# Native Chromium workspace experiment

This opt-in source-built host connects `BatoBrowserUI`, `BatoRuntime`, the organization store and normal Chromium tabs in one window. Bounded runtime acceptance now covers real creation, saved navigation/reset, default-dialog cancellation, workspace switching and same-provider clean restart. It is a developer experiment, not a distributable or daily-use browser.

Use the existing pinned SSD engine checkout and `spikes/engine-build/native_slot.py`; do not rerun checkout/configure. The client overlay stages four Swift modules into `cef/tests/cefsimple/bato/` and links their objects into the existing native-slot library. Nine source mirrors are checked against repository bytes before building, so a stale staged sidebar or runtime is refused.

Workspace mode requires `--bato-workspace-state=/absolute/organization/directory` and initial `--url=about:blank`, in addition to the existing native-slot/reservation/Quit flags. The first slice supports one window and one explicitly bound engine request context. The organization Profile UUID is checked against that binding; it does not establish additional Profile isolation.

Dedicated synthetic acceptance Profiles use mock Keychain on every launch, including restarts. Keep those Profiles separate from personal/baseline data. The initial blank page is a retained placeholder, protected against website navigation. Selecting an empty workspace uses it; closing it through Chrome's tab strip creates a replacement only when needed and never during window/application teardown.

Native address entry creates same-window tabs using an authored helper that returns the exact inserted WebContents' CEF identity. Each live Swift generation binds to a fixed retained browser ID. Main-frame URL/title events update organization through validated commits. Native sidebar and exposed Chrome tab-strip selection synchronize. CmdT native focus and CmdW from native focus passed; one page-focused CmdW attempt had no effect and remains an explicit keyboard gate. Public Cocoa menu routing is scoped to the known workspace window and restored on detach. Default Chromium beforeunload remains in charge of cancellation, observed through a WebContents-owned close observer.

Explicit sidebar/CmdW closure changes organization only after confirmed engine close. Unsolicited Chrome tab-X/window/application teardown unloads the handle while preserving its organization entry. Thus native tab-X currently differs from a Bato temporary-tab close. Untracked Chrome-created tabs, additional windows, fullscreen commands, split ownership and remaining extension checks are not complete application behavior.

The standalone `BatoShell` remains an organization preview. Its package declares macOS15 as a build floor; the source experiment's Swift action targets the existing CEF macOS13 ABI to match its executable. Compilation and acceptance on this Mac do not establish support for either minimum OS version.

## Current evidence

The v3 synthetic run created a real page on fresh startup, exited normally, and restored its stable entry on same-provider restart. A pin preserved its saved login URL while navigating to the storage fixture. Closing that pin reset its session URL; a separate temporary page remained. Default beforeunload Cancel preserved the temporary page and working input (activity counter0→1); Leave removed it. Reloading the pin opened its saved destination. A new empty workspace hid the other workspace's pin and selected the blank placeholder. Final Quit exited0 and left organization JSON exactly unchanged.

Forty Swift tests and eight overlay/patch tests pass. See the source host's workspace evidence for retained failures and remaining limits. This does not select a production foundation or establish daily-use readiness.
