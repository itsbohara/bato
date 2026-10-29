# Source-engine Quit acceptance, 2026-10-29

The opt-in V3 experiment passed client veto, real beforeunload cancellation and approved application Quit in the pinned ARM64 Debug component build. This supersedes the current Quit blocker for this bounded source-engine case; earlier failures remain in [sanitized evidence](runtime-evidence.json).

The incremental build succeeded in90.83s. The post-build checker resolved the component dependency closure and required ARM64 images and seven helper bundles.31 engine-pipeline guard tests, two exact-patch round-trip tests and the synthetic fixture test passed. These tests do not replace UI acceptance.

Using a fresh SSD mock-Keychain Profile, the coordinator enabled the synthetic controller, opened its options page, created two controlled tabs and paired them. Four CEF browsers were tracked. Actual File → Bato Quit application first reached the client callback with veto=true; no framework entry or closure followed. The page remained usable.

After actual Arm unsaved changes, the next Quit reached the framework with startupComplete=true and displayed “Leave site? Changes you made may not be saved.” Clicking Cancel retained PID70805, the armed page and all four tabs, including the controlled pair. An actual activity click advanced its counter from2 to3. Standard application-menu Quit then displayed the same confirmation again. Clicking Leave closed all four browsers, returned the real CEF message loop, completed CefShutdown and produced natural exit0. No signal or forced-exit fallback was used; owned browser processes were absent afterward.

A single Command-Q press did not show a dialog or produce another request event. The menu included Warn Before Quitting; keyboard warning/hold behavior was not resolved. The standard application-menu route passed independently of the explicit diagnostic File item.

Raw logs retain component duplicate-class warnings, a CacheStorage warning, waitpid no-child error and late helper rendezvous parent-died errors. They did not prevent this observed clean exit; their broader implications are unmeasured. Raw logs and synthetic Profiles remain outside Git in the dedicated SSD workspace.

## Limits and next gate

This is an explicitly flagged experiment with a live browser target, synthetic extension and mock Keychain. No-window Quit, keyboard confirmation, download/active-app veto, system shutdown, restart/session restoration and real extension approvals remain unpassed. The default prebuilt sample's earlier failed Quit run is unchanged. No production foundation is selected.

The next native-host gate is the [registered native-slot plan](../native-composition/NATIVE-SLOT-PLAN.md): real Swift input/accessibility must coexist with native Chrome split and real extension UI in one host. Visual reservation alone does not pass that gate.
