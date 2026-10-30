# Native workspace connection

Bounded acceptance on2026-10-30/31, using the same pinned ARM64 Debug component engine and synthetic mock-Keychain data. The source host now connects `BatoBrowserUI`, `BatoRuntime` and private organization storage to real same-window Chromium pages. The standalone preview is unchanged. This is not a production foundation or daily-use readiness pass.

## Implementation

The authored page boundary returns the exact inserted tab identity, validates window membership for close, observes default beforeunload cancellation, and forwards active-tab identity after tab-strip operations unwind. Native focus uses `NativeViewHost.RequestFocus` and its existing hostable callback. The client retains one explicit engine context and fixed browser-ID bindings per Swift generation, copies deferred URL/title strings, and releases references before terminal callbacks. Unsolicited teardown unloads entries without deleting organization.

An initial browser seed and posted readiness event avoid treating a later Chrome new tab as the blank anchor. The placeholder rejects website navigation and can be replaced when needed. Closing/window lifecycle guards prevent creation/focus during Quit. Physical keyboard routing uses an owned-window AppKit local monitor; Chromium menu items remain intact and actual menu commands use the guarded CEF hook. See the keyboard follow-up below.

The overlay covers21files (8engine/13client), including four staged Swift modules. Nine canonical repository sources are hash-checked against staged bytes. Original source hashes and Quit/helper/reservation protections remain intact. No checkout/configure, sandbox changes or assertion suppression.

## Verification

- Forty Swift tests pass:11core,9store,3session and17runtime. New runtime cases cover external selection, failed selection persistence, and unsolicited teardown without session deletion.
- Six overlay guard tests and two engine patch tests pass. The13-file client patch independently passed forward/reverse application and final hash verification on temporary copies.
- Final build passed in2m54.91s;527ARM64images pass the dependency check and eight authored exports were independently verified.
- Freshv3 startup: actual native field/Return created the login fixture without the earlier anchor workaround. Short lists appeared at the top of the sidebar; focus changes no longer submitted an empty address.
- Normal Quit with a temporary entry exited0. Same-provider restart restored its original organization ID and actual login page, creating only the anchor and selected page.
- Native CmdT focused the address field. A restored entry was pinned; Chrome navigation changed its live URL/title while keeping the saved login destination. A second temporary quit-fixture page was created.
- Selecting the pin through Chrome's tab strip, then CmdW from native focus, unloaded the correct pin and reset its live destination to the saved login URL. The other temporary page remained selected and present.
- Actual page click armed beforeunload. Native close displayed Chromium's normal confirmation. Cancel preserved the entry and cleared pending-close state; actual page activity advanced0→1. A second close followed by Leave removed only the temporary entry.
- Selecting the unloaded pin opened its saved login URL. Creating Workspace2 hid the Personal workspace's pin and selected blank content.
- Final normal Quit closed both remaining browsers, detached once, returned the message loop, completed CEF shutdown and exited0. Before/after organization JSON compared equal:2workspaces,1pin,0temporary entries, active empty Workspace2.

## Retained failures and limits

The first compilation rejected capturing CEF `BindOnce` lambdas; explicit bound arguments fixed it. A later link rejected a Swift macOS15 library against the existing macOS13 executable; the experiment's Swift action now matches that ABI. This establishes neither minimum OS support nor distribution compatibility.

Workspacev1 aborted before initialization because registration read the global command line too early. It now receives main's already parsed local object. Workspacev2 exposed an initial-anchor readiness race, a bottom-aligned short list and focus-loss address submission; those were corrected. Its terminal wrapper/browser disappeared across an interruption, so it has no clean-exit pass. Earlier CmdT focus and CmdW attempts had no effect and informed the native focus/menu changes; they are retained separately from later passes.

An earlier **page-focused CmdW attempt after clicking the web page** had no effect. The bounded keyboard follow-up below resolves that reproduced case; it does not establish blanket keyboard acceptance. Native Chrome tab-X preserves an unloaded organization entry, unlike explicit Bato temporary close. Fullscreen/untracked tabs, extra windows, anchor-loss recovery, broader lazy restore, split ownership, extension behavior and production signing/Keychain remain open integration gates.

Raw logs, snapshots, exit receipts and browser data remain on the SSD. Workspacev3 has known clean mock-provider history and must keep that provider on every restart. No real credentials or personal browser data were used or committed.

## Keyboard follow-up2026-10-31

The old binary reproduced the page-focused CmdW failure after an actual click on the synthetic quit fixture. Disarm followed by standard application-menu Quit returned the loop, completed CEF shutdown and exited0. Restart also rendered the previously empty active workspace with only its blank anchor; the inactive workspace's saved pin remained unloaded.

Pinned source explains a likely routing conflict: `chrome/browser/global_keyboard_shortcuts_mac.mm` recognizes menu actions named `commandDispatch:`, `performClose:` or `terminate:`. Replacing the action with our `dispatch:` prevents that menu item from resolving to a Chromium command. `chrome/browser/ui/cocoa/chrome_command_dispatcher_delegate.mm` normally executes recognized shortcuts ahead of NSMenu; page-focused unrecognized events may instead enter renderer redispatch. This is source-supported inference, not a fully instrumented trace of the failed event.

The client adds a public AppKit local event monitor for exact CmdT/W in the active owned key window, with sheet/modal and live managed-page guards. The monitor routes through the existing runtime and `CloseBrowser(false)` boundary. The first iteration kept its menu override; the final iteration removes it below. It does not use a global event hook or private selectors. The monitor is removed on slot detach. Runtime results follow after validation.

The first local-monitor build passed actual page-focused CmdW→default dialog→Cancel, retained the same temporary entry, and accepted a real activity click0→1. Repeated CmdW→Leave removed only that temporary entry; inactive workspace/pin JSON was unchanged. CmdT while the dialog was open did not bypass it; CmdW on the blank anchor left the host open. That run then failed an untracked-tab check: after Chrome's + created a New Tab, CmdW removed a background managed login entry and left New Tab present. The failed state/logs are retained; normal Quit exited0.

A second source review found a competing fallback: `NativeWorkspaceController.WorkspaceRoot.performKeyEquivalent` called `closeSelection` without engine identity checks. Chromium's `ui/base/cocoa/command_dispatcher.mm` documents that default key-equivalent dispatch walks the NSView hierarchy, not the responder chain. It can therefore reach the sidebar while a Chrome-owned tab is active; runtime selection still remembers its previous managed entry. The embedded host now opts out of sidebar key equivalents and uses only its scoped router. The controller's default remains compatible for other callers.

The CEF command fallback also now requires the actual active identity at capture and rechecks it when its posted task runs, dropping obsolete work. The original CEF callback browser is not proven stale: pinned `ChromeBrowserDelegate::HandleCommand` obtains the active tab synchronously. The previously missing queued-task identity check was a separate concrete gap.

The second iteration kept background organization safe but CmdW on an untracked New Tab did nothing. The final iteration removes the menu override entirely: local monitoring handles known Bato keyboard contexts, and original Chromium menu targets/actions preserve its normal reserved-command recognition. Actual menu commands use the existing CEF callback with active-identity guards. No private selector implementation or global keyboard hook was added.

Finalv3 acceptance passed: original File→New Tab created a Chrome-owned tab, and CmdW closed it. Native CmdT still focused the Bato address field. With a real managed quit-fixture page present, Chrome + created another untracked New Tab; CmdW closed only that Chrome tab and organization JSON compared equal before/after. An actual Arm click followed by page-focused CmdW opened the standard beforeunload dialog. Cancel retained the same entry and actual page activity advanced0→1. Repeated page-focused CmdW→Leave removed the temporary entry. Final organization equaled the pre-run state:2workspaces,1inactive pin,0temps. Normal application-menu Quit detached once, returned the loop, completed CEF shutdown and exited0.

The final incremental build passed25.63s;527ARM64images passed the dependency check, and the guarded13-file patch roundtrip and9source mirrors passed. Six overlay guard tests passed earlier in this follow-up. Existing40Swift tests were not rerun for these keyboard-only changes; all changed Swift compiled in the actual source host. A1200ms held-CmdW trial onv2 closed only the managed plain page and preserved Chrome's New Tab/anchor; OS repeat-event counts were not instrumented.

No extension was installed or exercised in this follow-up. The dummy-login fixture's name referred only to a local synthetic page. The user reiterated that extensive extension testing is deferred in favor of application progress. File-menu New Tab remains Chrome-owned rather than creating a Bato organization entry; menu unification, modified shortcuts, alternate keyboard layouts, fullscreen/split/window gates and remaining application work are still open. See keyboard-evidence.json for this separate checkpoint; workspace-evidence.json retains the original workspacev3 build hashes/results.


## Workspace customization, 2026-10-31

The Chromium-connected sidebar now edits the current workspace name and color through an AppKit sheet. A captured workspace UUID prevents late page callbacks from redirecting the edit. Save validates and commits both fields before publication; metadata changes deliberately skip engine selection/reconciliation. Cancel discards the local draft. Existing custom colors remain selectable; six named colors are offered. Sidebar tint/selection highlights follow the active workspace.

Forty-six Swift tests pass, including six new model/runtime cases; guarded client13-file patch reverse/forward/hash roundtrip and9mirrors pass. Incremental source build29.90s;527ARM64 artifact images checked. Independent bounded review found no actionable defect. No engine ABI/schema changes.

Runtime v1: Cancel left organization bytes unchanged; blank-name Save showed an inline error and kept the sheet open. Research/Ocean saved exactly two metadata changes without changing stable IDs/entries/selection. Switching to Personal loaded its existing pin, then saving Sage with that real page open retained its selected page. Returning to Research and standard Quit completed loop/detach/shutdown/exit0. Runtime v2 same-provider restart restored Research/Ocean in the editor with the inactive pin unloaded. Cancel and normal Quit preserved exact organization bytes, exit0. No browser/build remains. See workspace-customization-evidence.json for limits; no extension tests were run.
