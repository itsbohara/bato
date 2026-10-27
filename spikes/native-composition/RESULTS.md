# Native composition results

Date: 2026-10-27. Diagnostic executed on Apple Silicon, macOS 27.0.1, Xcode 26.3. This is not a native-shell or extension compatibility pass.

## Pinned engine and source findings

Actual CEF binary: `156.0.14+g4fa4ab5+chromium-156.0.8078.48`, arm64. Source revision from its bundled `cef_version.h`: `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. The baseline agent supplied and launched the verified binary; this agent did not download another engine or change its sources.

The bundled source headers retain the documented restrictions:

- [`cef_types_mac.h`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/internal/cef_types_mac.h): a supplied parent NSView or windowless rendering forces Alloy runtime style.
- [`cef_types_runtime.h`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/internal/cef_types_runtime.h): a Chrome-style Views window hosts at most one Chrome-style BrowserView, plus possible Alloy views.
- [`cef_window.h`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/views/cef_window.h) exposes a platform window handle; macOS defines the handle as an NSView pointer. A handle does not grant supported reparenting of Chrome's view hierarchy.

The probe uses Apple's [`NSTitlebarAccessoryViewController`](https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller) on the existing NSWindow. It leaves CEF's compositor and WebContents views in their original hierarchy.

## Executed experiment

The baseline agent launched stock `cefclient` in Chrome Views mode with a disposable Profile and four unpacked extensions (three real compatibility targets and the synthetic probe). It inserted the Swift dylib using `DYLD_INSERT_LIBRARIES`, with `BATO_NATIVE_PROBE=1` and `BATO_NATIVE_PROBE_AUTOTEST=1`. The unmodified baseline and the extension results are owned by `../cef-baseline/`; their success is not inferred here.

The injected code ran in the browser process on the main thread. Its AppKit accessory attached to `CefNSWindow` and `BrowserNativeWidgetWindow`. Sanitized event records are preserved in `diagnostic-evidence.json`; no URLs, window titles, vault material, wallet data, or real Profile content were copied.

| Check | Observed result |
| --- | --- |
| Swift/AppKit dylib compile/link | Passed: arm64, AppKit linked, linker ad-hoc signed. |
| Injection into stock development client | Passed in the observed build; no shipping/signing claim. |
| Native controls attached to real Chrome-style windows | Passed diagnostic attachment. Coordinator saw native label/input/button in accessibility and screenshot. |
| Native button action | Passed: programmatic check reported `inWindow=true`; a separate real CUA click increased visible action count from 1 to 2. |
| Native input focus | Passed narrow smoke check: `makeFirstResponder` accepted the field and yielded `NSTextView`. A separate CUA input operation changed the visible field value to the controlled test string. Full native-to-page-to-popup traversal remains untested. |
| Window resize | Passed narrow smoke check: +32px resize followed by restoration, for both observed windows. |
| Correct native titlebar layout | Initial attempt failed; corrected height-constrained variant passed diagnostic visual check in the source-built client. Details below. |
| Swift-owned shell / native reserved sidebar | Not implemented or passed. |
| Two Chrome-style pages in one native split | Subsequent native Chrome diagnostic passed two-page display and synthetic action targeting; see [split investigation](SPLIT-INVESTIGATION.md). Swift-owned split and divider resize remain unpassed. |
| Peek/fullscreen/popup anchoring/lifecycle | Not verified by this probe. |

The coordinator separately observed an actual Bitwarden action popup rendering a default-manager prompt while the probe was inserted. This supports simultaneous presence in that one diagnostic interaction; it does not prove Bitwarden unlock/autofill or correct positioning under a production native shell.

## Layout correction and limits

After the observed layout problem, the source added an explicit 38px accessory height and a minimum width constraint. The corrected variant compiled into a separate cache path (`native-composition/constrained`), leaving the initial running dylib untouched until a coordinated relaunch.

The baseline agent then launched the source-built stock client with the corrected dylib and the same disposable Profile, omitting `--load-extension` for its separate persistence experiment. In that run, the native accessory had an observed frame and visible rectangle of 800×36px; the programmatic native action, native focus, and +32px resize/restoration passed again. There were no observed constraint warnings in the captured log. Sanitized events are in `diagnostic-constrained-evidence.json`.

The coordinator inspected the actual screen through computer use: the native label, text field, and button occupied a clean separate row above the Chrome toolbar; the original overlap and unused white bottom region were gone, and the local test fixture remained usable. This passes the **diagnostic AppKit accessory composition** check. It does not pass sidebar reservation, native window ownership, split pages, full focus traversal, or extension popup anchoring.

Even a well-laid-out titlebar accessory would not establish the agreed architecture. Chrome still owns its Views window, compositor, toolbar, and WebContents layout. A production bridge must define an explicit lifecycle boundary, input/focus ownership, reserved sidebar and command-bar geometry, extension approval association, and two-page composition. Generic notification attachment and dylib injection are diagnostic mechanisms, not the planned application architecture.

Do not reparent `WebContentsViewCocoa` or `RenderWidgetHostViewCocoa` merely because the diagnostic can enumerate them. Their layout/focus/compositor ownership remains Chromium's, and the CEF native parent-view API explicitly selects a different runtime style.

## Next gate

After real-extension baseline validation, compare a supported CEF Views layout with a Swift-owned state/controller bridge against the required native-shell behavior. If reserving native surfaces and two Chrome-capable panes needs CEF/Chromium changes, scope the exact patch and update burden before implementing the shell. Preserve the user's Swift-native requirement; do not silently replace it with a Views-only UI or an Alloy page that cannot provide the required extension UI.

## Combined native-window follow-up

The coordinator subsequently tested the accessory in full native Chrome `cefsimple`, with an actual split pair and a real Bitwarden welcome popup. Native button input still worked, but the accessory overlapped Chrome’s toolbar in this window type. The earlier clean titlebar result is specific to Views-hosted cefclient. A production Swift bridge must reserve geometry explicitly through a supported integration boundary; accessory injection alone is insufficient. See [split runtime observations](split-runtime-evidence.json).
