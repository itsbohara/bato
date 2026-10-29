# Native application Quit experiment

Prepared against CEF `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f` and Chromium `156.0.8078.48`. This is an opt-in source experiment. Patch/hash checks, compilation and bounded runtime acceptance now pass; see [results](RESULTS.md). The coordinating agent owns applying the patch, guarded incremental build and actual UI acceptance.

## Supported command boundary

The client continues calling the existing public `CefBrowserHost::CanExecuteChromeCommand` and `ExecuteChromeCommand`, resolving `IDC_EXIT` through `cef_id_for_command_id_name`. There is no public CEF ABI addition or generated API/hash change.

V2, retained in V3, adds a narrowly gated interception in `ChromeBrowserHostImpl::ExecuteChromeCommand` after its existing UI-thread marshaling. Only macOS, `IDC_EXIT` and explicit `--bato-native-quit` select it. It explicitly preserves support/enabled checks and the controller's no-active-tab guard, then invokes the CEF browser delegate. Missing/unhandled delegates are logged and refused; the flagged command never falls through to the ActionManager. The original default dispatch remains unchanged when the flag is absent or for other commands.

The existing delegate hook still calls the client command handler first. A true `OnChromeCommand` consumes the command; only false reaches the framework adapter. This is a supported-public-CEF-call experiment, not a general repair of Chrome's Action framework command callbacks.

### Retained V1 failure

The first delegate-only hook built but failed at runtime: the native menu request recurred thousands of times with no client-handler or adapter events, then exited with SIGSEGV. It is not a Quit pass. The root preserved that patch, manifest, Profile and raw log outside Git before reversing exactly its reviewed source files.

Pinned source explains the missed dispatch path. `BrowserCommandController::CreateCommandUpdater` can select `CommandActionUpdater`, whose execution invokes an ActionItem directly. The mapped `kActionExit` action calls `chrome::Exit`; it bypasses legacy `HandleCommandWithDisposition` and its CEF delegate hook. `NSApp terminate:` then re-entered the sample's public exit-command request. V2 intercepts before that path and adds an independent sample reentrancy refusal. This diagnosis is supported by exact source and the absence/presence of runtime events; no runtime feature-state log was recorded.

The adapter lives in an existing framework Objective-C++ source already compiled by GN. It requires the UI thread and an actual `AppController` application delegate, requires `startupComplete`, then enters `AppController.sharedController tryToTerminateApplication` **inside the framework**. Clients never call that private integration selector. The controller retains its quit confirmation, download/active-app checks, beforeunload handling, trying-to-quit state, termination notifications and keepalive release. Controller unavailability is logged and handled without recursion, default fallthrough or forced exit. A handled request is not proof it succeeded; cancellation can return normally while keeping the browser alive.

Relevant pinned owners:

- [Command enable/dispatch, updater selection and legacy delegate entry](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/ui/browser_command_controller.cc), lines648–685 and2874–2879.
- [Action-backed command dispatch](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/ui/actions/command_action_updater.cc), `ExecuteCommandWithDispositionAndContext`; [exit ActionItem](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/ui/browser_actions.cc), `kActionExit`.
- [Existing client command callback](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/chrome_browser_delegate.cc), lines292–309.
- [Normal macOS application termination](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/chrome_browser_application_mac.mm), lines289–321.
- [Controller checks and keepalive](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/app_controller_mac.mm), `tryToTerminateApplication` and `allowApplicationToTerminate`.

## V3 normal startup and cancellation integration

V2 passed the first client veto in the browser, but its next request logged `native-quit-controller-unavailable`: the sample had installed `SimpleAppDelegate` where the adapter required Chrome's controller. That result did not demonstrate application Quit or beforeunload cancellation. The root preserved and reversed that experiment before preparing V3.

V3 pairs the CEF patch with [`startup.patch`](startup.patch), pinned separately to the Chromium commit. With `ENABLE_CEF` and `--bato-native-quit`, `ChromeBrowserMainPartsMac::PreCreateThreads` runs its existing normal controller/menu initialization rather than skipping it. The sample skips both of its delegate assignments and its nib load in this mode, retaining its local delegate only as the diagnostic menu target. This lets the real AppKit launch sequence deliver the controller's launch notifications, including its startup-complete state, active-app veto controller and observers. There is no manual late launch-notification replay. `DidEndMainMessageLoop` similarly retains normal controller cleanup in opted-in mode. Default CEF and non-CEF behavior are preserved.

The second Chromium change handles a concrete cancellation boundary. The app-modal beforeunload dialog's Cancel button calls `chrome_browser_application_mac::CancelTerminate()`. Its original implementation sends `cancelTerminate:` to `NSApp`; that selector belongs to `BrowserCrApplication`, while the CEF sample uses `SimpleApplication`. Under the same CEF/flag gate, the framework function instead checks that the installed delegate is an `AppController` and calls its existing `stopTryingToTerminateApplication` internally. This resets the normal trying-to-quit state and confirmation state. It adds no private selector call to the client or generic application subclass and leaves the default implementation unchanged. A missing controller is refused; there is no fallback to an unsupported selector.

Compilation and the bounded launch, cancellation and termination sequence now passed in [runtime results](RESULTS.md). Active-app vetoes and the other listed lifecycle limits still require separate acceptance.

## Explicit sample trigger and diagnostics

With `--bato-native-quit`, the sample adds **File → Bato Quit application**. Its target is the explicitly retained sample delegate object, independent of whichever delegate Chrome installs. The action invokes the sample's UI-thread method, which selects a live Chrome browser with an enabled version-resolved exit command and calls the public CEF API. The opt-in `SimpleApplication.terminate:` route uses that same method. The default direct-handler sample path is unchanged.

The additional `--bato-veto-first-quit` diagnostic makes the sample's client command handler consume its first exit command. Only the explicit native-quit mode installs this handler; no default handler is added. The veto flag changes only its test counter. A separate scoped in-progress flag refuses synchronous recursion and resets on every return; a public `CefRefPtr` keeps the client alive until that reset completes. Requests, vetoes and cancellations do not change the sample's `is_closing_` state. With no eligible live browser it logs unavailable; no-window application Quit is outside this experiment.

Fixed diagnostic events contain no URL, title, field value or browser storage:

- `sample-native-quit-menu-ready` and `sample-native-quit-requested` mark setup/request.
- `sample-client-quit-command` records only whether the client consumed it.
- `native-quit-host-dispatch` marks the explicit CEF-to-delegate route; host guard/unhandled events refuse it without fallback. `sample-native-quit-reentrant-refused` independently stops any accidental synchronous recursion.
- `native-quit-controller-readiness` records the startup-complete boolean; `native-quit-controller-startup-incomplete` refuses premature dispatch. `native-quit-controller-requested`, `native-quit-controller-returned` and `native-quit-controller-unavailable` distinguish framework dispatch. `tryingToQuit` at return is immediate state, not a final cancellation/completion result.
- Sample browser counts and `sample-quit-message-loop-requested` describe closure progress.
- `cef-message-loop-exited` appears only after the real `CefRunMessageLoop` return; `cef-shutdown-complete` only after real `CefShutdown` completion.

The preexisting explicit SSD-only mock-Profile guard is byte-preserved. The patch adds no extension installation, debugging listener, server transport, IPC command endpoint, security-disable flag or process-exit fallback.

## Provenance and application

[`manifest.json`](manifest.json) records the seven exact before/after source hashes and complete [`quit.patch`](quit.patch) hash. Paths are relative to embedded `src/cef`. The sample's before hash is the engine pipeline's already-applied runtime/storage-guard hash, not pristine upstream source. The original `engine-build/lock.json` checkout digest remains unchanged. [`startup.json`](startup.json) records the two Chromium-relative paths and their exact before/after hashes plus the complete startup-patch hash.

Read-only verification:

```sh
python3 spikes/engine-quit/check.py
```

The checker verifies both pinned source revisions, both manifests/patch bytes and all nine target files, then asks Git to check forward or reverse application in each source root. A mixed/unknown state within either patch or across the pair is refused without mutation. The root pipeline must apply the complete reviewed patch idempotently and verify final hashes before building. Do not rerun upstream configure/checkout over existing source patches. No GN source-list change is needed.

A small temporary-copy round-trip test exercises actual forward/reverse application of both patches, exact restored bytes and partial/tampered source refusal without changing the checkout. It skips its source-copy case if the external checkout is unavailable. Root pipeline tests independently cover application guards.

## Runtime acceptance

Use the rebuilt component sample in place, a dedicated synthetic mock-Keychain Profile with the same provider on every restart, and controlled fixtures. Retain all failed-run evidence outside Git.

1. Confirm the real menu exists and page renders. With the veto-first flag, click it once: expect client veto, no framework entry, no browser closure, and continued interaction.
2. On the controlled beforeunload fixture, actually click its arm control to establish a user gesture. Request Quit again. Cancel the browser's leave dialog, verify the process/window remain usable and the fixture still responds.
3. Request Quit again, approve leaving, and require actual loop exit, completed CEF shutdown and natural process exit. Do not count a dispatch log or zero browser references as completion.
4. Retest with the synthetic controller extension and split fixture state, then test normal application-menu/Cmd+Q routes separately. Downloads, active-app vetoes, session/system shutdown and no-window behavior require separate acceptance; preserved source code is not their runtime pass.

No cancellation, application Quit or general lifecycle pass follows from source inspection or compilation alone. This change does not implement the native Swift input/accessibility host or select a production foundation.
