# Native bridge boundary audit

Date: 2026-10-27. Read-only audit of the cached official CEF `156.0.14+g4fa4ab5+chromium-156.0.8078.48` distribution, revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. No browser was launched, no engine was downloaded, and no runtime result is claimed here.

## Finding

CEF exposes a supported browser lifecycle at which a linked Objective-C++ shim can call Swift. It does **not**, in the audited Chrome-native public API, expose a reserved AppKit sidebar rectangle, a native-content hosting slot, or control of the normal Chrome tab strip's geometry. Replacing injection with linked callbacks improves ownership and shutdown; it does not by itself solve Bato's native layout gate.

This is a blocker to selecting the **unmodified Chrome-native CEF path as the complete Bato shell**, not proof that Chromium cannot support the product. The remaining experiment must establish a supported layout boundary or scope the required CEF/Chromium API change before application slices begin. Overlaying a Swift sidebar over a page would fail reservation, input, and origin-indicator requirements.

## Exact public API boundaries

Source links below identify the same revision as the inspected local headers, rather than moving upstream `main`.

| Requirement | Audited surface | Consequence |
| --- | --- | --- |
| Enter Swift when a browser exists | [`CefLifeSpanHandler::OnAfterCreated`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_life_span_handler.h) on the browser UI thread | Safe boundary for browser actions. A browser callback is not a guarantee that every top-level window/layout object is ready; check the handle and defer once or use the appropriate Views window callback when needed. |
| Reach the containing NSWindow | [`CefBrowserHost::GetWindowHandle`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_browser.h), [`cef_window_handle_t`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/internal/cef_types_mac.h) | macOS handle is `NSView*`, not `NSWindow*`. The stock [`simple_handler_mac.mm`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/tests/cefsimple/simple_handler_mac.mm) obtains `[view window]`. This gives identity/access, not ownership of Chromium's child layout. |
| Put Chrome inside a Swift-owned parent NSView | `CefWindowInfo.parent_view` | On macOS, supplying this forces Alloy. It cannot silently preserve the Chrome-native split/extension path by setting runtime style to Chrome. |
| Reserve space with CEF Views | [`CefView::SetBounds`, `SetInsets`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/views/cef_view.h), [`CefPanel` layout/children](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/views/cef_panel.h) | Supported geometry for CEF Views children, including a BrowserView. The audited public Views interfaces offer no general AppKit `NSView` hosting child. A Swift controller manipulating Views widgets does not establish a Swift-native sidebar. |
| Obtain/customize Chrome toolbar in Views | [`CefBrowserView::GetChromeToolbar`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/views/cef_browser_view.h), [`GetChromeToolbarType`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/views/cef_browser_view_delegate.h) | Views-specific toolbar retrieval depends on the delegate selection and attachment to a CefWindow. It is not a normal native Chrome window tab-strip or sidebar API. `CEF_CTT_NONE` is the delegate's default; it is not a public instruction to strip every normal Chrome window's toolbar. |
| Hide individual Chrome buttons/icons | [`CefCommandHandler`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_command_handler.h) | Creation-time visibility callbacks cover default-visible toolbar buttons/page-action icons. They do not reserve a sidebar or replace/hide the whole tab strip. Hiding extension buttons without a replacement would also require an explicit popup/permission anchoring design. |
| Close through CEF | `CloseBrowser(false)`, `TryCloseBrowser()`, `IsReadyToBeClosed()` | Preserve asynchronous unload/cancellation. `TryCloseBrowser()` belongs in a top-level close handler; do not replace Chrome's existing delegate merely to intercept this. |
| Release Swift state | `OnBeforeClose`, and Views-specific `OnBrowserDestroyed` | Release browser references and invalidate callbacks. Views destruction occurs before `OnBeforeClose`; do not assume native objects remain live at the latter callback. |

`CefView::SetInsets` and `CefWindowInfo.bounds` must not be presented as Chrome-native WebContents insets. The former is a Views surface; the latter supplies initial window bounds. No audited method transfers compositor or `WebContentsViewCocoa` ownership to AppKit.

## Why the accessory result is insufficient

The earlier runtime showed a correctly sized accessory in Views-hosted `cefclient`, but overlap in normal native Chrome `cefsimple`. AppKit titlebar accessories are a legitimate AppKit API; Chromium's custom window layout still owns the page/toolbar rectangles. Successful attachment does not demonstrate that Chrome consumes the accessory's reserved height, nor that a left accessory can reserve a full-height sidebar. This audit does not establish the exact cause of the observed overlap.

A linked probe should report attachment, native window identity, accessory frame, and cleanup separately from visual layout success. It must not shrink, reparent, swizzle, or replace delegates of internal `BrowserView`, `WebContentsViewCocoa`, `RenderWidgetHostViewCocoa`, or their discovered NSView ancestors to claim a supported solution. A transparent helper window aligned beside the browser is also not evidence for one coherent native browser window under resize, fullscreen, focus, and extension prompts.

## Shutdown detail relevant to the next probe

The pinned browser API explicitly identifies `DoClose` as **Alloy-only**. Therefore a Chrome-native bridge must not depend on `SimpleHandler::DoClose` setting its `is_closing_` flag. The stock macOS sample's long termination comment describes an older/general path, while the current header defines the style-specific contract.

The supported sequence is to request non-forced browser close; allow browser/window close processing and any cancellation; receive `OnBeforeClose` for every tracked browser; quit the message loop when the final browser is gone; then call `CefShutdown` after the loop returns. The stock [`simple_handler.cc`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/tests/cefsimple/simple_handler.cc) and [`cefsimple_mac.mm`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/tests/cefsimple/cefsimple_mac.mm) implement the final callbacks/loop boundary. This is source evidence, not proof that the prior menu issue has been resolved.

Key bridge state by browser ID and native-window identity: multiple tabs can share a native window, and extension/popup windows need explicit eligibility rules. Window-scoped Swift UI should attach once per eligible window and outlive closing one tab if other tabs remain. Cancel pending asynchronous Swift work when its owner is removed. Do not retain a raw CEF pointer in a Swift closure beyond browser teardown. An `OnBeforeClose` callback alone is insufficient evidence for a clean exit: record message-loop return, post-`CefShutdown` completion, and process exit.

## Bounded next decision

1. Compile and run the linked probe to prove explicit creation, native input, per-window ownership, and clean teardown. Keep sidebar reservation open unless geometry is visibly and repeatably correct.
2. If Chrome-native reservation remains absent, scope an engine-facing seam: supported reserved content bounds; hostable AppKit surface/focus traversal; native tab/split control; and extension/security UI anchors. Locate the owning Chromium layout code before estimating patch size or build/update cost.
3. A separate CEF Views experiment may prove geometry with CEF controls, but must independently re-prove native split availability and show a supported AppKit hosting boundary. The existing one-Chrome-BrowserView limit does not disprove Chromium's internal split; see [split investigation](SPLIT-INVESTIGATION.md).

The output of this audit is a precise open integration boundary. It neither selects a fork nor authorizes dropping the Swift-native requirement.

## Follow-up: Views browser type and a viable narrow experiment

The exact pinned [`ChromeBrowserHostImpl::CreateBrowser`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/chrome_browser_host_impl.cc) explicitly converts a normal browser to `TYPE_POPUP` with a trusted source when `params.browser_view` exists (lines391–397). Neither audited public delegate offers a normal-browser type selector. That explains why normal-only commands cannot be assumed available in Views; it does **not** establish that the extension tabs split API rejects it. The split API route needs an actual Views runtime test.

A supported **geometry** experiment remains viable: reserve260px left and44px top with the public CEF box layout, then add only application-owned AppKit subviews to the exported window's `contentView`. The AppKit operation uses public methods and does not move Chromium's NSViews. However CEF does not document a native-child hosting contract for that contentView. Native stacking, coordinate conversion, hit-testing, focus return, resize/fullscreen, and extension anchors must all pass before selecting this mixed boundary. It is an experiment with public APIs, not an already-supported CEF native-widget abstraction.

The isolated [Views reservation patch](../views-layout/README.md) provides the geometry half. It does not add AppKit controls or claim a split pass.
