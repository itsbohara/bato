# Source engine build and first runtime results

Observed through 2026-10-29. Pinned CEF `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`, Chromium `156.0.8078.48` / `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`. This is a developer component experiment, not a distributable Bato application or selected foundation.

## Build and inspection

The guarded SSD build completed successfully in **5h38m14s**, 58154 steps, using two jobs, ARM64 Debug/component, symbols0, local Xcode26.3 and SDK26.2. The sample/runtime guard and reservation source objects were independently verified as ARM64. Former build/helper groups were absent after completion. Initial full log/state are preserved outside Git as `logs/build-initial-success.log` and `build-initial-success-state.json` under the SSD workspace.

The first artifact checker resolved523 ARM64 images but did not require dynamically selected Aperitif helpers. Xcode classic otool also misparsed helper filenames ending in parentheses; read-only descriptor inspection corrected that checker issue. Runtime-loaded libraries needed executable-runpath inheritance. Neither inspection failure required changing engine binaries.

## Failed initial control and packaging repair

The initial control launch, without reservation or extensions, failed before usable UI. Chromium selected `cefsimple Helper (Aperitif)`, which CEF's original bundle list omitted. Sandbox-path/GPU launch failed, followed by a debug blocking assertion when a pending cache backend was destroyed on the UI thread. Exit was SIGABRT, not clean shutdown. The code-sign-clone cross-device error was separate and explicitly nonfatal in pinned source; duplicate Objective-C class diagnostics were retained rather than suppressed.

The reviewed [packaging patch](helper-packaging.patch) adds Chromium's `content_mac_aperitif_helpers` to the CEF helper list, matching pinned Content Shell. It generates three additional correctly named helpers through CEF's existing templates. Exact before/after/patch hashes are in [the separate manifest](helper-packaging.json); the original checkout lock and completion digest were unchanged. Sandbox, field-trial feature selection and DCHECKs remain enabled. Normal Ninja regeneration and incremental compilation succeeded in **15.76s**, 27 steps. The updated checker then resolved526 ARM64 images and required all seven helper bundles. All26 guard/runtime-checker tests passed.

This is a helper compatibility experiment. It does not adopt Chromium's pure-C Aperitif preinitialization architecture or establish sandbox-before-static-initializer behavior, production signing, entitlements, renderer JIT or every helper role. No helper was manually copied/renamed and no security feature was disabled to obtain a pass.

## Actual repaired runtime

Both launches retained the component output tree in place and used fresh dedicated SSD mock-Keychain Profiles, no extensions and no debugging listener. Ordinary temp files were scoped to SSD `tmp`; the OS-managed code-sign clone deliberately uses its own location. Failed v1 Profile/log evidence was preserved.

| Case | Actual observation | Limit |
| --- | --- | --- |
| Control, `control-mock-v2` | Dummy login page visibly rendered with ordinary Chrome toolbar/origin UI. Native window close led to natural process exit0. | No vault autofill, arbitrary page input or application Quit test. |
| Reservation, `reservation-mock-v2` | Same fixture rendered with visible left/top space consistent with the260/44 layout patch. Toolbar and page remained visible. | Visual evidence, not instrumented native hosting rectangles or Swift input. |
| Native window zoom | Screenshot width changed from1200 to1920; left reservation remained visible at260 and the top offset remained. | Arbitrary drag resizing and minimum-size behavior untested. |
| Fullscreen round trip | Native controls entered fullscreen; reserved margins disappeared. Native exit restored both margins and page rendering. | One fullscreen capture had a white right-edge strip; complete viewport/edge fidelity remains open. Keyboard shortcut attempt did not establish a transition. |
| Reservation close | Native close led to natural process exit0; no owned source-sample processes remained. | Does not fix the separate extension-loaded application Quit failure. |

The sample's successful main return follows `CefShutdown`; no explicit loop/shutdown diagnostic events were added to this source sample. These results use natural exit0 and process absence, not invented log events. The initial failing run remains a failure. Early CUA app selection during library loading also started an unconfigured duplicate activation process, which was stopped explicitly; later selection used the exact initialized app path.

Raw logs and process samples remain under SSD `logs/`. No real credential, wallet or personal Profile was used. The fixture displays only dummy values; none was entered or submitted in these source-built runs.

## Remaining gate

Test minimum sizes, arbitrary resize, fullscreen edge fidelity, split/divider interaction, permission/extension anchors and real extension UI in this source-built host. Then implement and verify an explicit native slot with input/accessibility/lifecycle integration; see [native input audit](../native-composition/NATIVE-INPUT-AUDIT.md). Empty reserved space is not a native Swift sidebar. Application Quit, production encryption/signing and the full extension acceptance gate remain open.
