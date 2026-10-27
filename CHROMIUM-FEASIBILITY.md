# Chromium integration feasibility

Research date: 2026-10-27. Source review only; no downloads, builds, installs, or compatibility tests performed. Recommendations below are engineering proposals, not changes to agreed product scope. Sources are moving upstream pages; pin the exact CEF release and source revision before implementing.

## Finding

Do not select CEF merely because it embeds Chromium. The agreed combination of a native Swift interface, split pairs, and Chrome extension popups crosses a documented CEF boundary. First prove the integration with the required extensions, then commit to an engine foundation.

### Direct upstream evidence

- **macOS native embedding forces Alloy style.** The current [`cef_types_mac.h`](https://github.com/chromiumembedded/cef/blob/master/include/internal/cef_types_mac.h) documents that supplying a parent NSView, or enabling windowless rendering, always selects Alloy. Setting Chrome style alongside a parent view is therefore not a documented escape hatch.
- **Extension UI needs Chrome style.** In [CEF issue #3859](https://github.com/chromiumembedded/cef/issues/3859), the maintainer says request-context extension functions such as network interception should work with Alloy, but functionality requiring Chrome UI, including toolbars, will not. A Chrome-style window is required for `chrome://extensions`. The request to support that page in Alloy was closed as not planned. This does not prove that every content script, extension API, or extension works.
- **Runtime style constrains composition.** [`cef_types_runtime.h`](https://github.com/chromiumembedded/cef/blob/master/include/internal/cef_types_runtime.h) distinguishes Chrome browser functionality from the more flexible Alloy embedding/OSR model. A Chrome-style Views window can contain at most one Chrome-style BrowserView, plus Alloy BrowserViews. Two full Chrome-style pages in one split window are therefore not a straightforward supported configuration.
- **Chrome toolbar integration exists in CEF Views.** [`CefBrowserView::GetChromeToolbar`](https://github.com/chromiumembedded/cef/blob/master/include/views/cef_browser_view.h) exposes a Chrome toolbar only for Chrome style, configured through its delegate. [`CefCommandHandler`](https://github.com/chromiumembedded/cef/blob/master/include/cef_command_handler.h) permits command interception and selected menu/toolbar visibility decisions. These are useful customization surfaces, not evidence of a Swift-native toolbar or arbitrary NSView reparenting support.
- **Profile primitives exist.** [`CefRequestContext`](https://github.com/chromiumembedded/cef/blob/master/include/cef_request_context.h) supports separate contexts, shared storage, cache paths, and cookie managers. That is a plausible mapping for Bato Profiles; extension state and all storage types still require tests.

## Options

| Option | Benefit | Limitation / decision gate |
| --- | --- | --- |
| CEF Alloy in native Swift/AppKit shell | Direct native view embedding; natural sidebar, overlay, and split composition | Documented extension UI limitation. Cannot claim Bitwarden or MetaMask compatibility from content-script success. |
| CEF Chrome-style Views window, customized controls | Closest CEF baseline for extension management and Chrome-owned popup behavior | Native Swift shell integration and split composition remain unproven. Keeping a separate Chrome window for extension UI is a diagnostic, not acceptance of the agreed UX. |
| Custom CEF / Chromium browser-layer integration | Potential control over native presentation while retaining browser extension machinery | Engineering and security-update ownership increase substantially. Must investigate a minimal patch surface, build feasibility, and update process before selecting. |

Recommendation: start with a stock CEF Chrome-style baseline using a pinned macOS arm64 binary distribution. Attempt native shell composition only after required extension behavior passes. Do not spend weeks polishing an Alloy UI first. If native composition fails, write an explicit comparison of a small upstreamable CEF patch versus deeper Chromium browser integration; do not silently replace Swift with Electron or remove extension requirements.

CEF [binary distributions](https://github.com/chromiumembedded/cef#binary-distributions) avoid downloading/building Chromium itself. The [tutorial](https://chromiumembedded.github.io/cef/tutorial) describes CEF's framework, helper bundles, styles, and native/Views integrations. A full Chromium fallback uses Xcode/SDK, APFS, depot_tools, GN, and Ninja per the [official macOS build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md); it is a different maintenance commitment, not a drop-in Swift framework. Preflight available disk, RAM, SDK, and build time on the mini before considering that route.

## Bounded feasibility experiment

Proposed budget: two focused engineering days, followed by an evidence report; extend only for a named missing test. Run only on the agreed Mac mini, in a separate spike directory with fresh disposable Profiles. Record macOS/architecture, SDK, CEF+Chromium versions, extension versions/manifests, installation method, logs, and short recordings. No real vault credentials or funded wallet are necessary for the experiment.

1. **Baseline:** launch stock Chrome-style CEF with a persistent Profile. Install exact official releases of all three extensions. Separately record store installation, extension updates, disable/remove, and restart behavior. An unpacked official developer build may isolate runtime failures, but does not pass the end-user installation requirement.
2. **Bitwarden:** open its action popup; unlock a test vault; autofill dummy username/password fields in a controlled HTTPS fixture through popup, inline UI, and shortcut; verify correct target origin and operation after tab changes and restart. Bitwarden's [autofill architecture](https://contributing.bitwarden.com/architecture/deep-dives/autofill/) confirms content-script/background coordination; [user documentation](https://bitwarden.com/help/auto-fill-browser/) defines the interaction modes. Desktop biometric/native-messaging integration is a separate, unconfirmed target.
3. **AdGuard:** use the current official Chrome-targeting MV3 release; open popup/options, block a deterministic network fixture and cosmetic fixture, add/remove a per-site exception, reload, and restart. Its [MV3 documentation](https://kb.adguard.com/kb/adguard-browser-extension/mv3-version/) distinguishes that build from MV2. First isolate extension filtering with Bato's future blocker off, then test coexistence when the built-in blocker exists.
4. **MetaMask:** create a disposable test wallet, open/unlock popup, connect and disconnect a controlled dapp, approve and reject account access and a clearly labelled test message, switch account/network, verify origin/account identity and state after restart. Exercise both action popup and dapp-triggered approval window. [MetaMask's connection guide](https://support.metamask.io/third-party-platforms-and-dapps/manually-connecting-to-a-dapp/) documents account selection/connection. Do not substitute popup appearance for injected-provider and approval behavior.
5. **Native composition:** introduce the smallest Swift/AppKit sidebar and navigation bridge without changing extension behavior. Exercise keyboard focus, popup anchoring, fullscreen, resizing, permissions, split pair, and Peek. Test extensions on both split panes and in Peek. Document exactly which parts remain Chrome Views versus Swift/AppKit. This is the decisive architecture gate.
6. **Profiles:** use two workspaces sharing Profile A and one using Profile B. Verify A shares cookies, site storage, extension installation/settings and test extension state; B isolates them. Restart and repeat. Confirm split/Peek always uses the initiating Profile.

## Pass / fail and next action

Pass requires reproducible extension behavior, persistent isolated Profiles, user-installable extensions, and native composition consistent with agreed scope. A plain web page, rendered extension popup HTML, developer-mode loading alone, or a separate Chrome diagnostic window is insufficient.

If the baseline fails, identify missing API/installation behavior before spending on Swift UI. If baseline passes but native composition fails, retain that finding and scope the minimal CEF/Chromium adaptation. The foundation remains undecided until these gates pass. Report each row as passed, failed, or untested; never infer an overall pass from documentation.

Before daily use, define engine/application update ownership and rerun this matrix on upgrades. CEF's [security guidance](https://github.com/chromiumembedded/cef#security-updates) says matching Chromium vulnerabilities likely affect CEF and warns that corresponding CEF builds can lag Chromium releases. macOS signing, helper sandboxing, extension provenance/update integrity, ordinary downloads/permissions, media support, and crash recovery remain separate acceptance work.
