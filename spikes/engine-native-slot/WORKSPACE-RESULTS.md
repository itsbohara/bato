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


## Explicit saved destinations, 2026-10-31

Saved pin/Favorite context menus now expose Update Saved URL. Ordinary navigation leaves the saved destination unchanged; the action copies the latest committed supported address without changing the entry ID, organization order, selection or live handle. Loaded, visible saved entries only; closing/unloaded entries are rejected and unchanged entries have a disabled menu item. Runtime revalidates at invocation, so a menu captured before navigation cannot save an obsolete address. Invalid or failed navigation blocks this action until a supported navigation commits; attempt UUIDs preserve newer reentrant rejections and generation-specific state is cleared at terminal events.

54Swift tests pass (16core/9store/3session/26runtime), including8newcases. Source build26.99s, guarded13clientfile patch reverse/forward/hash roundtrip and9mirrors passed. Initial independent review flagged the stale-navigation edge; coordinator completed the final guard/reentrancy review after subagent availability was interrupted. No schema or engine ABI changed.

Runtime v1: unchanged-address context action was disabled. Navigating the existing pin from login to the storage fixture changed lastURL/title while preserving savedURL. Explicit Update Saved URL changed only savedURL. The real storage page stayed open; unload preserved the stable pin and disabled the action; reopening loaded the updated destination under the same entry UUID. Standard application-menu Quit completed loop/detach/CEFshutdown/exit0 and left organization bytes exactly unchanged. Raw logs/state snapshots stay on the SSD. Full evidence and limitations are in saved-destination-evidence.json. No extensions were tested.


Same-provider runtime v2 restart restored the same pin selected in Personal at the updated storage URL. Only placeholder+selected page were created. Final standard Quit detached once, returned the message loop and completed CEF shutdown/exit0; organization bytes exactly matched the pre-restart snapshot. The artifact checker passed527ARM64 images. No owned browser/build remains. Runtime covered one pin; Favorites/shared-workspace behavior and invalid/failed/reentrant navigation were covered by model/runtime tests rather than broader UI/disk-fault tests.


## Unpin and remove from Favorites, 2026-10-31

Saved context menus now expose Unpin / Remove from Favorites. Both atomically move the same entry into current-workspace temporary tabs and clear savedURL. Identity, title, latest destination and current selection are retained; background conversion does not select or create a page. Shared Favorite removal clears selections of that now-local entry elsewhere, preserving all other entries/selections. Pending closes block conversion until Cancel/confirmation; unloaded saved pages can be converted without loading.

62Swift tests passed (19core/9store/3session/31runtime), including8newcases. Independent bounded review found no actionable defect. Guarded13clientfile reverse/forward/hash roundtrip,9mirrors and21overlayfiles passed. Incremental source build26.11s. No engine API or organization schema change.

Runtime v1 passed live pin→Unpin: exact persisted state differed only by saved status/list placement, while stable UUID/current selection/destination/page survived. Added that same temporary tab to Favorites, switched to empty Research, then Remove from Favorites moved it to Research temporary tabs. Exact state comparison confirmed Personal’s obsolete selection cleared and Research remained unselected; visible blank anchor was retained. Selecting the converted tab reused the existing Chromium page; only anchor+one page were created throughout. Normal application-menu Quit detached once, returned loop and completed CEF shutdown/exit0, with exact organization bytes unchanged. No extension tests. Full evidence is in unsave-entry-evidence.json; raw logs and snapshots stay on the SSD.


Same-provider v2 restart restored the converted temporary tab selected in Research, with the same entry UUID/storage destination and complete organization bytes unchanged. Pin Tab then returned it to a saved pin in Research; exact document comparison confirmed ID/destination/selection retained. Normal Quit again detached once, returned loop and completed CEF shutdown/exit0; organization bytes unchanged.527ARM64 artifact images passed. No owned browser/build remains. Pending-close/unloaded/failed-save and temporary-close cancellation cases were covered by tests; the live run focused on conversion, workspace ownership and restart.


## Sidebar ordering, 2026-10-31

Every sidebar entry menu now includes Move Up / Move Down. Adjacent moves stay within current Profile Favorites, current workspace pins or current workspace temporary tabs. Full entries and all workspace selections remain intact; a committed order update does not reconcile engine visibility or touch live handles/pending closes. Runtime revalidates at invocation. Boundary actions remain disabled through explicit AppKit menu validation settings. Existing arrays persist order; no schema/engine API change.

68 Swift tests passed (22 core / 9 store / 3 session / 34 runtime), including six new cases. Independent bounded review found no actionable defect. Guarded 13-client-file actual reverse/forward/hash roundtrip, 9 source mirrors and 21 overlay files passed. Source build28.61s;527ARM64 artifact images passed.

Runtime v1 added a second synthetic pin in Research. Its single-item temporary section had both movement actions disabled. The first pin’s Move Up and last pin’s Move Down were disabled as expected. Moving background storage Down changed only pin array order and left the modal fixture selected; moving it Up restored exact initial organization bytes. Setting a real in-page activity counter to1 and then moving the selected modal pin Up retained counter1 and the visible page, with only order changed in JSON. Only anchor+the two intended pages were created; no ordering-created browsers. Normal application-menu Quit closed3browsers, detached once, returned loop and completed CEF shutdown/exit0. Organization bytes remained unchanged. Raw logs/snapshots stay on SSD; full evidence is in entry-order-evidence.json. No extension tests.


Same-provider v2 restart restored pin order modal→storage, the same stable IDs and selected modal fixture. Only placeholder+selected modal were created; inactive storage stayed unloaded. Full organization bytes matched the pre-restart snapshot. Final normal Quit closed2browsers, detached once, returned loop and completed CEF shutdown/exit0; bytes unchanged. No owned browser/build remains. Actual runtime covered two pins/single temporary-item boundaries; Favorites/temporary ordering, failed saves and pending-close/unloaded moves were covered by tests.


## Workspace ordering, 2026-10-31

The native Workspace actions menu beside Edit… now exposes Move Workspace Up / Move Workspace Down. Adjacent moves reorder the global workspace array while preserving full contents, Profile associations, stable IDs, active workspace and every selection. The menu captures the workspace UUID; runtime revalidates its current position before committing. Boundary actions are disabled. A committed move skips engine reconciliation and preserves live handles, unloaded pages and pending closes. Existing arrays persist order; no schema or engine API change.

73 Swift tests passed (24 core / 9 store / 3 session / 37 runtime), including five new cases. Independent bounded review found no actionable defect. Guarded 13-file client patch reverse/forward/hash roundtrip, 9 source mirrors and 21 overlay files passed. Source build27.73s;527ARM64 artifact images passed, exit0.

Runtime v1 started with active Research second and its modal/storage pins intact; Move Workspace Down was disabled. An actual page click advanced its activity counter0→1. Moving Research Up retained counter1, the same page and selection; exact full-document comparison showed only the workspace array reversed. The picker displayed Research then Personal, with Research still selected, and Move Workspace Up was disabled. Move Down restored exact initial bytes; a final Move Up restored the exact expected reversed document. Only anchor+selected modal were created, with inactive storage unloaded; no moves created browsers. Standard application-menu Quit closed2browsers, detached once, returned the message loop and completed CEF shutdown/exit0; organization bytes remained unchanged. Raw logs/snapshots stay on the SSD; see workspace-order-evidence.json. No extension tests.

Same-provider v2 restart restored Research first, Personal second and Research selected, with the same modal entry UUID and actual modal.html page URL. Full organization bytes exactly matched v1final before restart, after restore and after final Quit. Only anchor+selected modal were created; inactive storage stayed unloaded. Normal application-menu Quit again closed2browsers, detached once, returned the loop and completed CEF shutdown/exit0. No owned browser/build remains. Actual runtime covered two same-Profile workspaces; cross-Profile ordering, boundary/missing rejection, failed saves and pending-close/unloaded moves were covered by model/runtime tests.


## Entry workspace transfer, 2026-10-31

Pin and temporary-tab context menus offer Move to Workspace for other same-Profile destinations in current order. The transaction moves the full entry to the end of the matching destination section, preserving UUID, kind, saved/session URLs and all unrelated data. It keeps the current workspace and destination selection; only a moved source selection is cleared. Background moves skip engine reconciliation; selected moves hide the page after committing while retaining the live generation. Favorites remain Profile-wide. The entry’s own pending close, same-workspace and cross-Profile moves are rejected. No schema/engine API change; standalone preview unchanged.

Guarded13-file client patch reverse/forward/hash roundtrip,9source mirrors and21overlay files passed. 79 Swift tests passed (26core/9store/3session/41runtime), including six new cases (two core/four runtime). Independent bounded review and coordinator review found no actionable defect. Source build28.56s passed; compiler output archived on the SSD. 527ARM64 artifact images passed, exit0. See entry-transfer-evidence.json. No extension tests.


Runtime v1 loaded the selected modal fixture in Research and advanced its activity counter0→1 with an actual click. Moving the background unloaded storage pin to Personal changed only source removal and destination append in the exact full document, preserving Research’s modal selection and counter1. Moving the selected modal pin then kept Research active, cleared only its source selection, retained Personal’s nil selection and showed about:blank; exact expected document matched. Selecting Personal showed storage then modal pins with blank content initially. Selecting modal reused the same live Chrome page with counter1, without reload. Final full-document comparison matched only those explicit workspace/entry selections. Only anchor+selected modal were created; storage stayed unloaded and transfers created no browsers. Standard application-menu Quit closed2browsers, detached once, returned the loop and completed CEF shutdown/exit0, preserving exact organization bytes.

Same-provider v2 restart restored active Personal with storage then modal pins, the same stable entry IDs and selected modal fixture at its actual URL/title. Full organization bytes matched v1final before restart, after restore and after final Quit. Only anchor+selected modal were created; storage stayed unloaded. Normal application-menu Quit closed2browsers, detached once, returned the loop and completed CEF shutdown/exit0. No owned browser/build remains. Actual runtime covered two pins; temporary transfers, invalid/cross-Profile destinations, pending closes, failed saves and unloaded/lifecycle callbacks were covered by core/runtime tests. No extension tests.
