# Native workspace connection

Bounded acceptance on2026-10-30/31, using the same pinned ARM64 Debug component engine and synthetic mock-Keychain data. The source host now connects `BatoBrowserUI`, `BatoRuntime` and private organization storage to real same-window Chromium pages. The standalone preview is unchanged. This is not a production foundation or daily-use readiness pass.

## Implementation

The authored page boundary returns the exact inserted tab identity, validates window membership for close, observes default beforeunload cancellation, and forwards active-tab identity after tab-strip operations unwind. Native focus uses `NativeViewHost.RequestFocus` and its existing hostable callback. The client retains one explicit engine context and fixed browser-ID bindings per Swift generation, copies deferred URL/title strings, and releases references before terminal callbacks. Unsolicited teardown unloads entries without deleting organization.

An initial browser seed and posted readiness event avoid treating a later Chrome new tab as the blank anchor. The placeholder rejects website navigation and can be replaced when needed. Closing/window lifecycle guards prevent creation/focus during Quit. Cocoa menu routing uses post-initialization command IDs and public AppKit APIs; it restores previous targets on detach. One page-focused keyboard case remains open below.

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

One **page-focused CmdW attempt after clicking the web page** still had no effect. CmdW from native focus and native close controls passed. Investigate keyboard routing in that context next; no blanket keyboard acceptance. Native Chrome tab-X preserves an unloaded organization entry, unlike explicit Bato temporary close. Fullscreen/untracked tabs, extra windows, anchor-loss recovery, broader lazy restore, split ownership, extension behavior and production signing/Keychain remain open integration gates.

Raw logs, snapshots, exit receipts and browser data remain on the SSD. Workspacev3 has known clean mock-provider history and must keep that provider on every restart. No real credentials or personal browser data were used or committed.
