# Explicit linked native bridge experiment

This sample links Swift code into the pinned CEF156 `cefsimple` browser process through Objective-C++. There is no injected dylib, global window discovery, Chromium patch, or compositor reparenting. It remains a feasibility experiment rather than Bato's application architecture.

Observed build/runtime evidence and its limits are recorded in [RESULTS.md](RESULTS.md).

`prepare.py` creates a cache source overlay with an independent copy of the small cefsimple sample and symlinks to the unchanged pinned distribution. It preserves the baseline's explicit disposable Profile mapping; if absent, it adds equivalent mapping. The existing baseline source/build are unchanged. Swift is compiled to a linked object; CEF helpers remain upstream. Upstream sample code retains its CEF license (see [license](../cef-baseline/CEF-LICENSE.txt)).

## Build and launch

From the repository root:

```sh
sh spikes/linked-native-bridge/build.sh
```

The executable is `~/.cache/bato/linked-native-bridge/build/tests/cefsimple/Release/cefsimple.app/Contents/MacOS/cefsimple`. The coordinator owns launching; close all other disposable sample instances first, use an explicit disposable Profile, and retain the existing pinned extension flags when needed. Example direct launch (no developer extensions):

```sh
"$HOME/.cache/bato/linked-native-bridge/build/tests/cefsimple/Release/cefsimple.app/Contents/MacOS/cefsimple" \
  --use-native \
  --use-mock-keychain \
  --cache-path="$HOME/.cache/bato/linked-native-bridge/profile-test-mock" \
  --url=http://127.0.0.1:18765/
```

Do not use personal Profiles. No debug listener is enabled by this example. The experiment does not install extensions, approve wallet requests, access a vault, or send fixture form data.

For the coordinator's isolated fixture runs, Chromium's `--use-mock-keychain` prevents the observed macOS Keychain wait. Use it **only with a dedicated disposable test Profile created using that provider, and keep the same flag on every restart of that Profile**. Do not toggle providers on an existing real-keychain Profile, including the earlier baseline Profiles A/B. Mock keychain changes the test encryption-key provider; never use that Profile for real secrets or treat its storage behavior as production encryption evidence. The disposable example above includes it; build defaults do not. Production Keychain identity, signing and encryption remain separate acceptance requirements.

The coordinator reproduced blank/loading pages and teardown-watchdog expiry in the linked, bridge-disabled, Swift-free and exact-stock overlay builds. The already working baseline main transplanted into the same app package worked. A shutdown sample showed a worker blocked in `SecItemCopyMatching`/Keychain decryption. The same previously failing stock binary then rendered and closed promptly with only a fresh disposable Profile and `--use-mock-keychain`. This isolates a dominant Keychain-dependent startup/shutdown problem; it does not establish the exact Keychain ACL rule or a production remedy. Source-path normalization was used diagnostically to reproduce baseline object bytes, not adopted as a workaround.

## Explicit boundary

- `SimpleHandler::OnAfterCreated` calls `BatoBridgeAfterCreated`. It obtains the documented CEF NSView window handle, finds its NSWindow, and explicitly passes that window and browser identifier to Swift.
- Window availability can lag `OnAfterCreated`. Up to 40 UI-thread retries run at 50ms intervals, capturing only the browser integer identifier. Closing erases its reference, making pending retries harmless. A focus notification can also trigger attachment.
- CEF popup browsers are excluded from companion creation so extension/permission popup geometry is not changed.
- Swift owns a small native **companion NSPanel outside Chrome's frame**, with a text field, action counter, browser focus, native split command, and Close all browsers controls. This proves a lifecycle/control boundary while avoiding the titlebar overlap experiment. Chrome is narrowed when sufficient screen space exists; panel placement follows move/resize notifications.
- `OnGotFocus` updates the browser identifier used by native controls. Runtime focused-pane association still requires verification.
- The split button dynamically resolves `IDC_NEW_SPLIT_TAB`, checks `CanExecuteChromeCommand`, and delegates to `ExecuteChromeCommand`; command availability is reported. This does not save or restore pairs.
- Close all browsers calls the supported sample `CloseAllBrowsers(false)` path. `OnBeforeClose` removes each CEF reference and explicitly detaches the Swift panel when that window has no remaining browsers. Loop return and completed `CefShutdown` have separate log events.
- The separate **Quit application** control queries and executes version-resolved `IDC_EXIT`. Availability/dispatch and sample browser-list/quit-loop events are logged separately from completed shutdown. This is an application-quit experiment, not a forced-exit fallback; see [QUIT-PATH.md](QUIT-PATH.md) for the exact macOS source path and its sample-application nuance.
- Diagnostic JSON contains ephemeral browser IDs, classes and geometry, never URLs, titles, field contents, or browser storage.

## Limits and acceptance

Successful compilation is not evidence of runtime layout, focus, split or shutdown acceptance. The coordinator must click actual native controls and verify `linked-detached`, `cef-message-loop-exited`, `cef-shutdown-complete`, and process exit. Check resize, multiple tabs, extension popup anchoring and split interaction independently.

The coordinator completed the narrow full-native control test: actual native button/field interaction, native split creation, browser-window activation, selecting the companion from the Window menu, and closing both split browsers through the native **Close all browsers** button. The shared panel detached once after the final browser, CEF shutdown completed and the process exited. This used a disposable mock-keychain Profile. Browser focus visibly landed in the address bar; page-text focus, in-window native sidebar input and real-extension association are still open. See [RESULTS.md](RESULTS.md) for the separate reserved-Views visual/close pass and all limits.

The companion panel **does not reserve an in-window sidebar or command-bar surface**. It keeps full native Chrome UI and is not the approved Bato design. It can be clipped when a user moves Chrome to the edge of a screen; full screen/Spaces, accessibility, tab moves between windows, and display changes are unhandled. No private content inset APIs are used. A single-window Swift-native shell remains an open foundation requirement.

For selecting the diagnostic companion, it is explicitly registered in the application's Window menu. The opt-in `--bato-focus-native-controls` requests that this panel become key shortly after attachment so a native UI inspection can target its controls. This request itself is programmatic setup, not evidence of a real user action. **Focus browser** explicitly activates the browser NSWindow before delegating CEF focus.

The command target follows CEF focus notifications when received; there is no claim yet that every Chrome-internal tab/split pane is surfaced as a CEF browser with those notifications. Attach-time handle availability and graceful Chrome-style close behavior need actual runtime evidence.

## Optional reserved Views experiment

The build also applies [the public Views layout patch](../views-layout/apply.py). Launch with `--bato-views-layout` and **without** `--use-native` to opt in. The sample reserves 260 points at the left and 44 points at the top through `CefBoxLayoutSettings.inside_border_insets`; the BrowserView receives the remaining layout space. Swift then adds native sibling views to the exported `window.contentView` with public `addSubview`, without replacing any root view. A native sidebar provides the same action/focus/split/close controls; the top native field is a focus target. Resize notifications recalculate sibling geometry and report sizes.

This is a separate experiment from the full Chrome-native companion window. It requires visual/runtime verification that the Swift views occupy exactly the reserved CEF rectangles, that focus and extension popups remain usable, and that the Views host can display the Chromium split through the controller route. Views native split controls may be unavailable. It does not yet implement Bato tabs, sidebar behavior, a working navigation command bar, or saved splits. The launcher rejects `--bato-views-layout --use-native` because that combination would not reserve browser space.

For lifecycle isolation, add `--bato-disable-bridge` to suppress Swift attachment and native control/focus callbacks while keeping the same linked executable and sample layout mode. This distinguishes attachment behavior from linked-runtime/build behavior; it is not a shipping option.

For a stronger build isolation, run `BATO_LINK_NATIVE_BRIDGE=OFF sh spikes/linked-native-bridge/build.sh`. This removes Swift/Bridge linking and compiles out callback invocation/focus-handler registration while preserving the same cache source overlay, CEF framework, helpers, sample Profile mapping and shutdown diagnostics. Rebuild normally to restore the bridge. Never rebuild while the test executable is running.

The final build control is `BATO_STOCK_SAMPLE=ON BATO_LINK_NATIVE_BRIDGE=OFF sh spikes/linked-native-bridge/build.sh`. It recopies the unchanged baseline sample and applies none of this directory's source or Views layout patches. The baseline's preexisting disposable Profile mapping remains. This produces a source-overlay/path/package control comparable to the known baseline; it has no added shutdown JSON logs.
