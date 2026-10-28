# Engine-facing seam proposal

Date: 2026-10-27. Proposal only. Engine: CEF `156.0.14+g4fa4ab5+chromium-156.0.8078.48`; CEF revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. Chromium links below use the exact `156.0.8078.48` tag, which was retrievable during this audit. No engine checkout, patch, or build was performed. This does not select a production foundation or a fork.

## Decision boundary

The coordinator demonstrated explicit linked Swift creation/teardown with a normal native Chrome window and completed CEF shutdown. In Views mode, public CEF layout reserved260px left and44px top and the page rendered in the remaining rectangle. Actual input into those AppKit sibling controls remains unverified. See [linked results](../linked-native-bridge/RESULTS.md).

The two paths still supply different halves of Bato's needs: normal Chrome has the demonstrated native split/extension path, while the Views host supplies application-controlled BrowserView bounds. Views is created as a popup browser and the coordinator's public second-tab route did not produce the required pair there. Do not convert those observations into a claim that all Views split mechanisms are impossible, or that a Swift controller around Views widgets meets the native-interface requirement.

The smallest-looking alternative to investigate first is **reserved native surfaces in the existing normal Chrome window**, retaining its toolbar/security UI initially. It preserves the behavior already demonstrated. This is a research priority, not a conclusion about implementation size.

## Exact owning code

| Boundary | Pinned owner | Proposed responsibility |
| --- | --- | --- |
| Native versus Views browser construction | [CEF `ChromeBrowserHostImpl::CreateBrowser`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/chrome_browser_host_impl.cc) | The Views branch changes a normal type to popup and supplies its existing BrowserView/widget. A normal-host extension must remain distinct from that branch. |
| CEF client-facing command/window behavior | [CEF `ChromeBrowserDelegate`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/chrome_browser_delegate.cc) | Potential CEF-to-Chromium adapter for an opt-in surface-reservation policy. Existing window-feature decisions do not expose the required rectangle. |
| Chrome layout selection | [Chromium `BrowserViewLayout::CreateLayout`](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_layout.cc) | Chooses tabbed versus popup layout from browser type. Changing type alters the layout implementation and associated behavior. |
| Normal-window page/chrome layout | [Chromium `BrowserViewTabbedLayoutImpl`](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_tabbed_layout_impl.cc), [layout application](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_layout_impl.cc) | Owns proposed layout, content placement, side surfaces, and application of child bounds. Reservation must enter this layout calculation rather than resize internal NSViews afterward. |
| Two-page presentation and divider | [Chromium `MultiContentsView`](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/multi_contents_view.cc) | Keep Chromium's two content containers, focus associations and divider intact; reserve around their shared surface. Its existing split-content insets are internal rendering/layout behavior, not a CEF AppKit hosting API. |
| Views frame/dialog positioning | [CEF `ChromeBrowserFrameView`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/views/chrome_browser_frame_view.cc) | Already derives client bounds from the hosted BrowserView. Any Views alternative must preserve this relationship for modal dialogs. |

## Alternative A: reservation in normal native Chrome

Propose an explicit, opt-in CEF window policy returning left/top reserved dimensions and reporting the resulting usable native rectangles. Defaults must preserve stock behavior. An internal adapter would feed those dimensions into the normal BrowserView layout; it must constrain the complete relevant browser surface consistently, including both split panes, indicators, prompts and overlays. The precise insertion point needs a source-level prototype against the pinned layout parameters; this audit does not assert that a one-line inset is sufficient.

Swift would own only its new AppKit surfaces, attached and removed through explicit per-window lifecycle callbacks. A host contract must define stacking, coordinates, accessibility, focus traversal, resize/fullscreen transitions and closure. Do not expose or transfer compositor/WebContents NSViews. A proper boundary should also identify the active tab/browser and re-evaluate identity when tabs move between windows.

First retain the ordinary Chrome toolbar, extension actions and per-pane origin indicators. Hiding/replacing toolbar or tab-strip UI is a separate change requiring equivalent origin and extension/permission anchors; a titlebar accessory or creation-time button visibility callback does not provide that replacement.

## Alternative B: normal multi-tab browser in a CEF Views host

Make the normal-to-popup conversion opt-in rather than unconditional for the experiment, then audit every one-browser-per-Views assumption. Merely deleting the conversion is not a complete fix. CEF's host lookup comments and browser/platform association currently distinguish a single Views host from multiple native tabs. New tab creation, popup routing, active-host selection, focus, close, detach and extension windows all need defined ownership.

The existing Views geometry could then reserve native regions, but AppKit sibling input/accessibility remains an independent gate. This alternative potentially changes more ownership behavior than Alternative A. Do not estimate it as smaller solely because the initial type conversion is a short conditional.

## Tab and split control

A new engine API is not yet justified for every tab operation. Normal Chrome already exposes [CEF command execution](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_browser.h) and version-safe command-ID lookup. Chromium's [command controller](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/browser_command_controller.cc) enables the new-split command only for a normal browser. This constructs a split from the active tab; it is not an arbitrary saved-pair restoration API.

The exact-version [extension tabs implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/extensions/api/tabs/tabs_api.cc) accepts two tab IDs for split creation and delegates to `TabListInterface::CreateSplit` after validation. A disposable test extension can validate native-normal tab creation, membership, activation, removal and restoration before adding an engine tab API. If a production native API proves necessary, scope it around window/tab IDs and explicit completion/error callbacks; retain Chromium's tab/split model and permission association. Do not persist runtime IDs as Bato identifiers.

## Next bounded experiment without an engine build

1. Keep the current normal-native linked binary, a fresh disposable Profile and the explicit test-only mock-keychain flag. Use the existing synthetic extension to create two controlled tabs in that window, join them, activate each and restore the same pair after recreating tabs. Record actual errors and active-target associations. This can narrow the control API gap using the prebuilt engine.
2. Independently isolate AppKit sibling input in the existing reserved Views test: native own-control action, keyboard input, focus return, resize and accessibility. Successful geometry alone does not pass this test. Avoid private-view inspection or replacing Chrome delegates.
3. Produce a reviewable source patch sketch for Alternative A against the small pinned owning files above. No runtime claim follows until it is compiled and tested. Public prebuilt binaries cannot execute altered CEF/Chromium layout code; injection, an adjacent panel, an extension side panel or post-layout NSView manipulation is not a substitute for that validation.

## Build and maintenance implications

The current samples link a prebuilt framework; rebuilding them cannot add an internal layout seam. Either alternative's engine changes require a matching CEF/Chromium framework build, locally or through a separately provisioned build environment/artifact. A changed public CEF interface also needs the generated API/wrapper surfaces and matching hashes, not just a sample-header edit.

The audit observed approximately14GiB available on this Mac. That is not a basis for beginning a full Chromium checkout/build. Recheck actual build requirements and arrange adequate separate capacity before any checkout; none is authorized or needed for the two prebuilt-engine experiments above. No numerical build-time estimate is established.

Any maintained patch must be rebased and exercised with engine security updates. Keep the seam opt-in and small, document its owning files/version, and require split, extension anchors, focus, fullscreen, Profile continuity and clean shutdown acceptance on every update. Foundation selection remains open until the native hosting and real-extension gates pass.
