# Feasibility results

Dates: 2026-10-27–29. The user approved the design and bounded experiment. This records observed diagnostic behavior, not a complete Bato application or a selected production foundation.

## Environment and pinned engine

Apple Silicon Mac mini, macOS 27.0.1, Xcode 26.3 (17C529), CMake. The earlier runtime experiments use CEF `156.0.14+g4fa4ab5`, Chromium `156.0.8078.48`, and the official arm64 binary distribution. Both the prebuilt stock client and a locally compiled stock `cefclient` ran. The separately authorized SSD source build completed successfully at those exact revisions in5h38m14s: ARM64 Debug component `cefsimple`, symbols0, two jobs, system Xcode/macOS SDK26.2. Patched layout/sample ARM64 objects and successful exit were independently verified; repaired source-built control/reservation runs now render and close with exit0, with only narrow visual geometry/zoom/fullscreen evidence.

[Baseline report](spikes/cef-baseline/RESULTS.md) records archive hashes, sample build flags, launches, and local evidence locations. [Extension lock](spikes/fixtures/extensions-lock.json) pins official developer packages and their verified release-asset digests. Profiles, downloaded extensions, logs, and engine binaries stay outside Git under `$HOME/.cache/bato`.

## Observed evidence

| Check | Result | Practical limit |
| --- | --- | --- |
| Official arm64 engine provenance | Passed | Verified distribution SHA1; recorded local SHA256. |
| Sample compile and Chrome-style launch | Passed | Stock sample, not Bato application. |
| Full Chromium/CEF source compile | Passed | One developer ARM64 component sample, local reservation/runtime patches; no distributable framework or production-host acceptance. |
| Extension management UI | Passed | Actual `chrome://extensions` rendered and exposed enabled state. |
| Bitwarden Web Store installation | Passed | Official store ID, version 2026.10.0, runtime location `FROM_STORE`; installed in initially empty Profile B. |
| Bitwarden installed-extension persistence | Passed | Restarted without developer-loading flags; enabled card and official extension remained. Automatic updates untested. |
| Bitwarden action popup | Passed narrowly | Real popup rendered and responded to onboarding controls. No vault login/unlock/autofill pass. |
| AdGuard developer package | Passed narrowly | Version 5.5.3.3 enabled, real popup and options editor worked. Store installation/update not tested for AdGuard. |
| AdGuard network filtering | Passed narrowly | Explicit fixture rule produced `net::ERR_BLOCKED_BY_CLIENT`; independent control script returned HTTP 200 and executed. Default-list coverage untested. |
| AdGuard cosmetic filtering | Passed narrowly | Fixture cosmetic target disappeared with explicit rule; returned under site exception. |
| AdGuard per-site exception persistence | Passed narrowly | Global protection stayed on, site switch off survived restart and restored target script/cosmetic content. |
| MetaMask developer package | Passed narrowly | Version 13.54.0 enabled; real onboarding and toolbar action route observed. |
| MetaMask page provider | Passed narrowly | EIP-6963 discovered `MetaMask (io.metamask)`; `eth_accounts` returned `[]`, `eth_chainId` returned `0x1`. No connected wallet or signing pass. |
| Synthetic MV3 content/worker messaging | Passed | Fixture content script received worker response. Not evidence for real-extension behavior. |
| Startup developer-loading persistence | Not provided by this mechanism | Omitting `--load-extension` removed those developer-loaded extensions; this differs from successful store installation. |
| Profile cookie/localStorage restart and isolation | Passed narrowly | A marker survived restart; B initially had neither A marker nor A extensions; distinct B marker did not replace A. Does not prove every storage type or Bato workspaces. |
| Swift/AppKit native composition | Partial diagnostic pass | Clean accessory row in Views-hosted cefclient; combined native Chrome split + Bitwarden popup worked, but accessory overlapped toolbar there. Native sidebar and production layout not passed. |
| Two-page split | Passed display and synthetic action targeting | Native Chromium split displayed independent pages; action popup selected distinct focused tab IDs/paths. Divider drag, saved-pair restore, and real vault/wallet per-pane acceptance remain unverified. |
| Explicit linked Swift/Objective-C++ bridge | Passed narrowly | Native Chrome window attachment, actual native action/text input, supported split-command dispatch, shared-window tab tracking, detach and completed CEF shutdown passed in a disposable mock-Keychain Profile. Companion panel is a diagnostic, not Bato's sidebar. |
| Reserved Views geometry | Passed visually; input open | Public CEF layout reserved260px left/44px top; Swift controls and page rendered without overlap and closed cleanly. Native controls were absent from observed accessibility tree; real input remains unverified. |
| Source-built normal-window reservation | Passed narrow visual checks |260/44 reserved space, native zoom and fullscreen removal/restoration observed; both control/reserved native closes exit0. Fullscreen edge strip, minimum sizes, split/extension anchors and Swift input remain open. |
| Public extension split-control API | Passed in normal Chrome window | Actual `tabs.createSplit` produced two visible fixture pages. Requested Views-popup tab creation redirected to a normal window; moving tabs back was rejected. No Views split pass. |
| Split separation and saved-URL reconstruction | Passed narrowly in normal Chrome | Controller separated/re-paired tabs and reconstructed a visible pair with fresh IDs across a confirmed clean restart. Fixed fixture URLs in extension storage only; Bato saved pins and divider ratios are unimplemented. One earlier close-all run hung and required an owned-process stop. |
| Application quit with controller extension | Failed after partial correction | Revised direct-handler path avoids the selector exception and closes tracked browsers, but process stays alive without completed CEF shutdown. Owned-process TERM was required; not a graceful-quit pass. |
| Shared/isolated request-context storage | Passed narrowly across clean restart | A1/A2 shared four persistent stores; B isolated; session storage stayed tab-scoped/reset. Actual host identities canonicalized, failing the probe's distinct-identity expectation. No extension-state or workspace implementation pass. |
| Peek and complete focus/popup lifecycle | Untested | Requires production composition boundary. |

## Important interpretation

The stock sample intercepted the Web Store download and displayed Save As. After saving the official CRX into the test cache, Chromium completed installation and showed its added-extension confirmation. Management confirmed enabled state with Developer mode off; the extension survived restart. The Save dialog was not a failed installer, and no download-handler patch was required for that result.

The first native accessory attempt overlapped Chrome’s toolbar. Explicit sizing fixed that diagnostic layout in Views-hosted cefclient, but overlap recurred in the full native Chrome window. Generic dylib injection remains a test hook, not the production bridge. See the [native composition report](spikes/native-composition/RESULTS.md).

## Checks still required before foundation selection

- A supported native Swift sidebar, command bar, and lifecycle integration without reparenting compositor internals.
- A single host combining native input/accessibility, reserved geometry, native splits and extension UI. Normal Chrome lacks a public content-reservation API; the tested Views popup cannot receive the required second tab through public extension creation/move APIs.
- Divider resizing, Bato saved-pair integration, real-extension behavior on both panes, and cross-origin popup/permission association. Synthetic focused-tab association and normal-window controller URL reconstruction passed; neither establishes Bato's saved-pin behavior.
- Actual Bitwarden test-vault autofill on a controlled HTTPS fixture.
- MetaMask disposable-wallet connection, rejection/approval, and explicit test-message signing.
- Shared request-context behavior across Bato workspaces plus broader storage/extension isolation.
- AdGuard store installation and broader filtering; built-in blocker integration/coexistence.
- Peek, crash recovery, helper/sandbox behavior, signing/distribution, and security-update ownership.

## Fixture verification

The coordinator reran four Python HTTP fixture tests, the Node mocked-wallet request-gating test, and the synthetic popup privacy/targeting test; all passed. These verify test fixtures only. No real vault, funded wallet, production secret, or private browsing data was used.

The new storage fixture's explicit-operation, namespaced-store, mock sharing/isolation, session-scope, partial-failure and output-sanitization tests also passed. The [request-context probe results](spikes/profile-contexts/RESULTS.md) now record actual sharing/isolation and persistence across a confirmed clean restart, two clean native-window shutdowns, and the separate failed distinct-host-identity expectation.

The [split investigation](spikes/native-composition/SPLIT-INVESTIGATION.md) corrects the early BrowserView-count inference with versioned runtime evidence. Switching between cefclient and cefsimple preserved the localStorage marker but did not preserve the observed test cookie; cross-sample cookie continuity is not a pass. Sample Quit/lifecycle behavior also needs investigation.

## Linked bridge follow-up

The [linked bridge results](spikes/linked-native-bridge/RESULTS.md) replace generic injection with explicit CEF creation/focus/close callbacks for the experiment. Native full-Chrome and reserved Views runs both completed `CefShutdown` after real window closes. Initial blank-page/watchdog failures also occurred in an exact stock rebuild; a process sample showed a Keychain-decryption wait. The same failing executable rendered and closed using Chromium's test-only `--use-mock-keychain` flag with a fresh disposable Profile. This isolates development tests; production Keychain access, stable signing identity and encrypted storage remain unpassed. Do not apply that flag to personal Profiles.

The [split-control report](spikes/native-composition/SPLIT-CONTROL.md) records actual normal-window API success, clean-restart URL reconstruction and Views target rejection. One initial extension-controller close-all run detached the bridge browsers but did not leave the event loop; two subsequent runs completed shutdown. General extension-loaded quit remains a gate rather than a universal pass. The [boundary audit](spikes/native-composition/BRIDGE-BOUNDARY.md) and [engine seam proposal](spikes/native-composition/ENGINE-SEAM.md) map the remaining integration work. A [one-file reservation patch sketch](spikes/engine-reservation/README.md) passed pinned-source/hash and patch dry-run checks and now compiled in the source-built engine; narrow visual layout/zoom/fullscreen observations are recorded in [engine results](spikes/engine-build/RESULTS.md); the full hosting gate remains open. No production foundation or engine fork has been selected.

The separate [application-quit test](spikes/linked-native-bridge/QUIT-PATH.md) exposed a concrete sample integration bug: native Chrome's actual `AppController` delegate did not implement the method assumed by the sample's termination override. The revised override calls the known sample handler directly. After manual unlock, actual UI testing avoided that exception but left the process alive after tracked browsers closed. Completed loop/shutdown events were absent and bounded TERM was needed. The same report explains the missing native Chrome termination lifecycle; no complete quit fix has passed.
