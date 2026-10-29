# Bounded native-slot experiment plan

Date: 2026-10-29. Source: Chromium156.0.8078.48, commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`, CEF `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. Read-only plan following [the input audit](NATIVE-INPUT-AUDIT.md). No implementation, build or runtime acceptance is claimed. Quit lifecycle work remains separate.

## Smallest useful experiment

Keep the demonstrated normal Chrome window and its complete toolbar, origin UI, split subtree and extension anchors. Behind an explicit macOS test switch, add **one engine-owned `views::NativeViewHost` for the left reserved region**. It hosts only a newly created application-owned Objective-C++ root containing linked Swift/AppKit controls. Leave the top reservation empty initially. Test a native button, text field and focus return before adding Bato product UI.

Use an engine-internal adapter around that application root, rather than requiring client code to implement Chromium internals. The adapter is a new NSView conforming to `ViewsHostable`, backed by `ui::ViewsHostableView`. The client supplies a plain owned NSView through a narrow explicit experiment API. Only these new roots are attached; no compositor, WebContents or existing Chromium NSView is discovered or moved.

## Existing handles are insufficient

[`CefBrowserView::GetForBrowser`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/views/browser_view_impl.cc#L88) explicitly returns null unless the browser is Views-hosted. Normal native Chrome therefore has no public `CefBrowserView` to extend. The CEF `ChromeBrowserView` class is the Views-hosted specialization; changing only that class misses this normal-window target.

`CefView::GetWindow` returns its containing CefWindow; it is not an arbitrary native-view host. [`CefWindow::GetWindowHandle`'s macOS adapter](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/views/view_util_mac.mm#L45) exposes the widget's native view, or an NSWindow's content view. `CefBrowserHost::GetWindowHandle` likewise supplies the existing host handle. None registers a native hit target, AX subtree or layout-owned slot. Reusing those handles with `addSubview` repeats the earlier failed integration pattern.

A new explicit framework/client boundary is required. Do not smuggle registration through an NSWindow property, inspect private subviews, look up private Chromium symbols, or assume a web/extension message can authorize native attachment.

## Proposed patch ownership and sequence

| Owner | Bounded change |
| --- | --- |
| Chromium normal `BrowserView` lifecycle/layout | Notify the existing CEF delegate when an initialized normal widget can host the experiment, after relevant layout changes, and before native widget teardown. Forward declarations/internal delegate methods can keep client pointers out of Chromium's public view classes. |
| CEF normal-window delegate/controller | Own one slot registration per live Browser/window; create the NativeViewHost as a BrowserView child, attach after the widget exists, update bounds/visibility, detach before widget destruction. BrowserView owns its child; the controller holds a non-owning tracked reference. |
| Reservation geometry | Refactor one shared calculation to return reduced Chrome parameters plus safe slot bounds, using the same unreserved/reserved visual-client rectangles and frame exclusions. Do not independently infer slot coordinates from NSWindow frame or `contentLayoutRect`. |
| CEF macOS adapter | Wrap the application-created root in the new engine-owned ViewsHostable adapter. Keep Chromium C++ headers/protocol implementation inside the matching engine. |
| Application sample | Register callbacks before initialization, create its own Objective-C++ root and linked Swift/AppKit contents, retain its ownership until detached notification, and log only fixed labels/tokens/counts/geometry. |

The existing [`cef::BrowserDelegate`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/browser_delegate.h) is an internal, UI-thread browser-lifetime boundary already called by patched Chromium. It has no native-slot callbacks today. The proposed additions must be opt-in and preserve stock behavior when disabled.

[`BrowserView::Layout`](https://github.com/chromium/chromium/blob/156.0.8078.48/chrome/browser/ui/views/frame/browser_view.cc#L4942) can defer or return during startup/fullscreen/teardown. A slot layout notification must respect those guards and avoid reentrant invalidation loops. Its normal layout applies through `LayoutSuperclass<views::View>`. Widget teardown suppresses layout before deleting WebContents; detach the slot before the underlying native host becomes invalid. Do not wait only for the final `CefLifeSpanHandler::OnBeforeClose`.

## Client callback contract

For the first source experiment, define a matching, explicitly versioned framework registration API; this is a proposed Bato experiment boundary, **not an existing upstream CEF capability**. Its implementation/ABI must be reviewed before use. A later upstream-style CEF API requires the generated C wrappers and API hashes as well.

- Register a factory and lifecycle callbacks before CEF initialization. Factory creation happens on the main/CEF UI thread only after a supported widget and nonempty safe slot rectangle exist. No polling for NSWindow creation.
- Identify the window/slot with an opaque generation-bearing token, not a persisted CEF browser ID or NSWindow pointer. A normal Chrome window may contain several CEF browsers through tabs/splits; factory invocation and detach happen once per window slot.
- Factory returns only the application's new native root. The engine retains its wrapper/root while attached. A null result refuses the slot cleanly. Bounds changes resize that root through public AppKit behavior; optional notifications report only authoritative geometry.
- Detach removes the NativeViewHost attachment, clears AX parent and focus links, invalidates pending callbacks/tokens and then notifies the application to release its retained root. Tab moves must resolve the current window without transferring or recreating unrelated window slots.
- Reject popup/DevTools/Views-hosted windows in this first experiment. Reject a nonlocal remote-Cocoa application before passing any native pointer. [`NativeViewHostMac::GetRemoteCocoaApplication`](https://github.com/chromium/chromium/blob/156.0.8078.48/ui/views/controls/native/native_view_host_mac.mm#L95) exposes this topology; a raw NSView pointer is not a cross-process view transport.

Factory code and callbacks are native application code. No website-to-host command endpoint, injected library or global window discovery is needed.

## Adapter obligations

[`NativeViewHost::Attach`](https://github.com/chromium/chromium/blob/156.0.8078.48/ui/views/controls/native/native_view_host.h#L49) requires a View already in a valid Widget. NativeViewHostMac retains its native root and recognizes `ViewsHostable`; its attach path registers the host and initially stitches the parent accessible. Its existing hit-test type is routed to `kSubView`, including modal-blocked handling, by [the macOS window host](https://github.com/chromium/chromium/blob/156.0.8078.48/ui/views/cocoa/native_widget_mac_ns_window_host.mm#L1354).

The new adapter must implement the actual [ViewsHostable contract](https://github.com/chromium/chromium/blob/156.0.8078.48/ui/base/cocoa/views_hostable.h): attach/detach bookkeeping, widget-coordinate bounds conversion, visibility, first-responder selection, accessible element and accessible parent. Attach already adds the adapter NSView in NativeViewHostMac; do not duplicate that work or copy WebContents layer/migration code into an AppKit-only root.

Return a native accessible group containing the application controls, expose its recorded Views parent through native AX semantics, and clear the parent on detach. Focus requests must select a known native child (for example the text field), rather than assume an NSView container accepts first responder. Preserve normal AppKit editing and define Tab/Shift-Tab return to Views. A generic NSView's `SetParentAccessible` path is a no-op; the pinned [adapter-parent test](https://github.com/chromium/chromium/blob/156.0.8078.48/ui/views/controls/native/native_view_host_mac_unittest.mm#L219) is a useful lifecycle precedent, not Bato acceptance.

Only application-owned view/layer clipping may be adjusted. NativeViewHostMac's generic clip helpers are partly unimplemented, and the original interface was designed for WebContents. Native-root clipping, AX focus reporting, layer assumptions and destruction reentrancy need explicit checks rather than assumed compatibility.

## Geometry and acceptance

Compute the sidebar rectangle from the same before/after reservation geometry, excluding protected native caption/resize regions. Avoid covering the native traffic lights or titlebar drag area. Keep native controls hidden whenever reservation is inactive, including fullscreen and transitions. End-of-fullscreen notification alone may be too late: existing macOS CEF fullscreen callbacks are Views-hosted paths, so normal-window start/end visibility needs an explicit hook or a proven widget observer. Minimum sizes must include space for the slot and usable Chrome content.

Acceptance, in order:

1. One initialized normal window creates exactly one slot; extra tabs/split members do not duplicate it. Unsupported topology refuses cleanly.
2. Actual native AX exposes the group/button/field with correct parents and frame. Actual mouse click increments a counter; actual field editing works without logging contents. Programmatic `performClick` is insufficient.
3. Tab/Shift-Tab, browser-content focus return, menu accelerators, text editing and native/page modal blocking behave correctly. Inspect the actual AX-focused element and first responder.
4. Resize, zoom, scale changes, minimum sizes and fullscreen transitions preserve safe bounds and hide/restore the slot without covering Chrome's origin/security UI. No arbitrary private NSView frame edits.
5. Existing split pages, divider and extension/permission anchors remain usable. Then test moving a tab between two opted-in windows, closing either window and detach-once semantics.
6. Repeated create/close completes normal CEF shutdown with no callback after token invalidation, retaining neither native roots nor global CEF objects.

Stop after any failed prerequisite and record it separately. A visible reserved gap, an attached view or a compile alone does not select the engine foundation or pass native hosting.
