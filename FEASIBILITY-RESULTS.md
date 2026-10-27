# Feasibility results

Date: 2026-10-27. The user approved the design and bounded experiment. This records observed diagnostic behavior, not a complete Bato application or a selected production foundation.

## Environment and pinned engine

Apple Silicon Mac mini, macOS 27.0.1, Xcode 26.3 (17C529), CMake. The experiment uses CEF `156.0.14+g4fa4ab5`, Chromium `156.0.8078.48`, and the official arm64 binary distribution. Both the prebuilt stock client and a locally compiled stock `cefclient` ran. No Chromium source checkout/build was performed.

[Baseline report](spikes/cef-baseline/RESULTS.md) records archive hashes, sample build flags, launches, and local evidence locations. [Extension lock](spikes/fixtures/extensions-lock.json) pins official developer packages and their verified release-asset digests. Profiles, downloaded extensions, logs, and engine binaries stay outside Git under `$HOME/.cache/bato`.

## Observed evidence

| Check | Result | Practical limit |
| --- | --- | --- |
| Official arm64 engine provenance | Passed | Verified distribution SHA1; recorded local SHA256. |
| Sample compile and Chrome-style launch | Passed | Stock sample, not Bato application. |
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
| Peek and complete focus/popup lifecycle | Untested | Requires production composition boundary. |

## Important interpretation

The stock sample intercepted the Web Store download and displayed Save As. After saving the official CRX into the test cache, Chromium completed installation and showed its added-extension confirmation. Management confirmed enabled state with Developer mode off; the extension survived restart. The Save dialog was not a failed installer, and no download-handler patch was required for that result.

The first native accessory attempt overlapped Chrome’s toolbar. Explicit sizing fixed that diagnostic layout in Views-hosted cefclient, but overlap recurred in the full native Chrome window. Generic dylib injection remains a test hook, not the production bridge. See the [native composition report](spikes/native-composition/RESULTS.md).

## Checks still required before foundation selection

- A supported native Swift sidebar, command bar, and lifecycle integration without reparenting compositor internals.
- Divider resizing, saved split restoration, real-extension behavior on both panes, and cross-origin popup/permission association. Synthetic focused-tab association passed in the native split.
- Actual Bitwarden test-vault autofill on a controlled HTTPS fixture.
- MetaMask disposable-wallet connection, rejection/approval, and explicit test-message signing.
- Shared request-context behavior across Bato workspaces plus broader storage/extension isolation.
- AdGuard store installation and broader filtering; built-in blocker integration/coexistence.
- Peek, crash recovery, helper/sandbox behavior, signing/distribution, and security-update ownership.

## Fixture verification

The coordinator reran four Python HTTP fixture tests, the Node mocked-wallet request-gating test, and the synthetic popup privacy/targeting test; all passed. These verify test fixtures only. No real vault, funded wallet, production secret, or private browsing data was used.

The [split investigation](spikes/native-composition/SPLIT-INVESTIGATION.md) corrects the early BrowserView-count inference with versioned runtime evidence. Switching between cefclient and cefsimple preserved the localStorage marker but did not preserve the observed test cookie; cross-sample cookie continuity is not a pass. Sample Quit/lifecycle behavior also needs investigation.
