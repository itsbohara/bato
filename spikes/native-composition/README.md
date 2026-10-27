# Native composition diagnostic

This is a disposable diagnostic, not a Bato application shell. It inserts a Swift/AppKit dylib into the stock CEF Chrome-style browser process. The Objective-C constructor skips renderer/helper processes and schedules installation on the main queue. AppKit notifications identify eligible titled windows; a titlebar accessory adds a label, text field, and button. Diagnostics report class names and geometry, never window titles or URLs.

## Run

Use the exact CEF binary pinned by `../cef-baseline/`; do not download another engine distribution. Run from the repository root:

```sh
spikes/native-composition/build.sh
spikes/native-composition/run.sh "$CEF_EXECUTABLE" --url=about:blank
```

Set `CEF_EXECUTABLE` to the **full direct Mach-O executable path**, not the `.app` directory. Build and disposable Profile data default to `~/.cache/bato/native-composition`. `BATO_PROBE_OUTPUT` selects another diagnostic cache directory. Close the diagnostic before reusing its Profile. Never pass a real browser Profile.

`run.sh` enables an automatic native action, focus request, and +32px resize/restoration two seconds after attachment. Those events are programmatic smoke checks, not evidence of physical mouse/keyboard usability. It does not approve extension permissions, access a vault, connect a wallet, or install extensions. Add the baseline's explicit test-extension arguments when testing coexistence.

The injection route is for a locally controlled development executable. It is not a distribution strategy: hardened runtime/library validation may prevent it, and helper signing/sandbox behavior must be evaluated independently. A production native bridge would be linked and called at an explicit browser-process lifecycle boundary rather than injected or attached by generic window notification.

## Interpretation

See `RESULTS.md`. AppKit controls can exist in a Chrome-owned window without providing a supported Swift-owned browser host. This does not implement sidebar reservation, split pairs, Peek, browser navigation from Swift, extension popup anchoring, or full focus traversal. No compositor view is reparented.
