# Public Views geometry reservation

This isolated sample patch reserves260px at the left and44px at the top using `CefWindow::SetToBoxLayout`, `CefBoxLayoutSettings.inside_border_insets`, and BrowserView flex. It changes no Chromium compositor/view hierarchy. It is opt-in via `--bato-views-layout` and applies only to the sample's Views window path; do **not** pass `--use-native` for this experiment.

Apply to a **disposable staged distribution source root**, after the linked-native-bridge patch and before its CMake build:

```sh
python3 spikes/views-layout/apply.py "$STAGED_CEF_ROOT"
```

The script refuses the ordinary shared distribution directory name, checks its anchor, and is idempotent. Copy files into the stage; do not use hard links for patched sources. Retain the baseline disposable Profile mapping patch and original upstream licensing. The baseline source is not modified by this script's verification.

Verification performed: Python syntax and application/idempotence against a temporary copy of the actual pinned sample. Compile/runtime verification is pending integration with the linked bridge. No additional engine download is needed.

The reserved region is intentionally blank. Adding owned AppKit controls through the exported window handle remains a separate experiment. No public CEF API for hosting an arbitrary NSView was found. A public AppKit `addSubview` into `NSWindow.contentView` can be tested without reparenting Chromium content, but requires evidence for layering, focus, resize/fullscreen, and extension prompts. See [boundary audit](../native-composition/BRIDGE-BOUNDARY.md).

The patch now explicitly calls the public `window->Layout()` after `Show()` and emits sanitized `cef-reserved-bounds` JSON after that call and on layout notifications. `local` is BrowserView bounds in its CEF parent; `screen` is DIP screen bounds. These distinguish a zero-sized browser from AppKit overlay/stacking problems. No page URL, title, or content is logged. This is a diagnostic refinement after the coordinator's first blank-window observation, not a verified rendering fix.

For shutdown investigation, pinned [`CefMainRunner`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/main_runner.cc) releases its keepalive on `CefQuitMessageLoop` and waits for Chrome windows to disappear. Its shutdown path already drains pending UI and IO tasks before context cleanup. The stock final-`OnBeforeClose` quit sequence therefore has source support; an arbitrary delay is not an established repair for a watchdog after message-loop return. Compare the same Views/Profile/extension setup without application-owned AppKit siblings, and collect a teardown stack before attributing the failure to CEF or the bridge.
