# Peek native integration plan

Source review: 2026-11-02. This is a proposed implementation route, not a rendered Peek result. The first preparatory `PeekSession` contract has targeted tests; it is not connected to the host. This review makes no compatibility or completion-percentage claim.

## Pinned source and constraints

Reviewed the existing checkout: CEF `156.0.14+g4fa4ab5`, revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`; Chromium `156.0.8078.48`, commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`. Source paths below are relative to that Chromium checkout, including its `cef/` directory and the existing Bato native-slot overlay.

The agreed behavior is a same-Profile link preview, one per window, with confirmed dismissal when beforeunload applies and promotion that preserves the existing live page. Existing normal navigation and Command-click must retain their behavior. Neither a separate Chrome popup window nor an AppKit panel containing a copied compositor view implements that requirement.

## What the source establishes

| Source | Established behavior | Consequence |
| --- | --- | --- |
| `ui/views/controls/webview/webview.h`, `SetWebContents` / `SetOwnedWebContents` | A Views WebView can host an existing WebContents without taking ownership, or explicitly take ownership. | Use an engine-owned Views presentation; do not extract its native NSView into Swift. |
| `ui/views/controls/webview/webview.cc`, `SetWebContents`, `AttachWebContentsNativeView`, `DetachWebContentsNativeView` | Native attachment, accessibility parent, background, focus and detach are handled by WebView and its NativeViewHost. | Reparenting requires these engine lifecycle operations, not direct AppKit manipulation. |
| `chrome/browser/ui/views/frame/multi_contents_view.cc`, constructor and `CalculateProposedLayout` | A higher-index Lens overlay container is rendered above normal contents and receives a proposed layout rectangle. | This is a local stacking/layout precedent, not a generic arbitrary-page Peek API. Do not repurpose the Lens-owned container. |
| `chrome/browser/ui/views/frame/browser_view.cc`, active-tab change handling around lines 2111–2165 | Active-tab changes clear both ContentsWebViews, update browser UI and mount the active tab or split. | An independently attached preview can be overwritten by ordinary browser reconciliation. Presentation needs a coordinated BrowserView/MultiContentsView policy. |
| `cef/libcef/browser/chrome/chrome_browser_host_impl.cc`, `OnSetFocus`, `DoCloseBrowser`, `GetCurrentTabIndex` | Focus selects a tabstrip index; physical close routes through `TabStripModel::CloseWebContentsAt` when the contents belongs to that Browser. | A newly detached WebContents cannot inherit normal CEF focus/close behavior automatically. Keep ownership explicit. |
| `cef/libcef/browser/chrome/chrome_browser_delegate.cc`, `CreateBrowserHost` | CEF host attachment associates the existing WebContents, platform delegate, request context and Browser. | Creating a generic WebView alone does not create a properly bound CEF page. |
| `cef/include/cef_life_span_handler.h`, `OnBeforePopup` | Native Chrome-style popups normally create a Chrome UI popup window. | Popup interception is not an existing in-window overlay seam. |
| `chrome/browser/ui/views/side_panel/side_panel_web_ui_view.{h,cc}` | Side panels host WebUI through their own wrapper/host, visibility, keyboard and lifecycle policies. | A useful lifecycle example, not a drop-in arbitrary HTTP(S) page or live-tab promotion implementation. |
| Existing `cef/libcef/browser/chrome/chrome_content_browser_client_cef_mac.mm`, `FindSlot`, `BrowserInSlot`, `bato_native_slot_new_tab_v1`, close observer | Input operations require an owned visible normal window, no fullscreen/transition/modal/closing state, and known tab membership. New-tab creation activates a normal tab synchronously. | Preserve these guards. An ordinary new tab must not be treated as a hidden preview, and its selection callback must not mutate organization as though it were an adopted tab. |
| `spikes/engine-native-slot/client/native_slot_client.mm`, `CreateWorkspacePage` and `SelectWorkspacePage`; `client/WorkspaceSlot.swift` | Bound pages currently have normal organization roles. Creation, callback routing and selection use those bindings. | Preview creation and callback routing need an explicit transient role and full live-generation binding. |

## Recommended first native experiment

Use a tab-owned preview for the first experiment. Keep the preview's WebContents in the same normal Browser's TabStripModel and actual request context, and make it the engine's active page while presented. This preserves the existing CEF close route and allows Chromium's toolbar/origin UI to describe the page the user is interacting with. The organization selection remains the parent until promotion succeeds.

Add a dedicated opt-in Peek presentation policy to `MultiContentsView` rather than attaching an arbitrary extra AppKit child. The initial engine experiment should arrange the active preview's existing ContentsWebView into an inset rectangle above a backdrop and preserve the parent's live tab. That is only a presentation seam: showing the parent live underneath, stacking with native content, correct accessibility, modal prompts and full focus behavior must be designed and demonstrated before calling it the complete Peek overlay. Do not mount the same WebContents in two WebViews at once. A normal BrowserView active-tab reconciliation must either preserve this owned policy or end presentation safely.

The first native patch should touch these areas together:

1. `chrome/browser/ui/views/frame/multi_contents_view.{h,cc}`: explicitly owned preview layout/backdrop, normal-layout restoration, bounds and focus behavior. A dedicated policy must coexist with the existing split implementation; initially refuse active split layouts instead of silently separating a saved pair.
2. `chrome/browser/ui/views/frame/browser_view.cc`: coordinate active-page mounting with that policy, and end or suspend it safely on incompatible selection, fullscreen, sheet and window teardown. Do not let a hidden view bypass the existing input guards.
3. `cef/libcef/browser/chrome/chrome_content_browser_client_cef_mac.mm` and internal/canonical `bato_native_slot.h`: separate versioned present/end operations for exact parent/preview CEF identities; same window/context checks; no unrelated tab/split adoption; revalidation after tab mutations. Keep original slot ABI signatures unchanged.
4. `client/native_slot_client.mm` and `client/WorkspaceSlot.swift`: a transient-preview binding separate from normal organization page bindings; defer CEF callbacks and revalidate full generations. Native active preview events must not enter ordinary `PageRuntime.selected` handling. Beforeunload cancellation retains presentation. Confirmed close removes it and restores a still-valid parent. Normal tab adoption must retain the exact live token and engine browser.
5. `PageRuntime` and native UI: bind the process-local `PeekSession`, define parent/workspace teardown behavior, then add explicit Open in Peek and eventual Shift-click interception. Keep normal and Command-click routing unchanged.

This is larger than a safe one-small-task change. A successful build by itself would not establish the ownership, origin, beforeunload, focus or promotion behavior.

## Small prerequisite

Allow transactional organization insertion with the preview's existing entry UUID, rejecting collisions across the full document before publication. The current `LivePage` identity contains that entry UUID as well as Profile and generation. A promotion that creates an unrelated UUID or reloads a URL loses the identity it is supposed to retain.

This prerequisite belongs in the core model and its collision/persistence tests. It does not perform promotion by itself: the future runtime still has to commit the adopted entry, transfer the exact live generation into its live-page map, and relinquish `PeekSession` only after a successful, revalidated adoption. A failed save must leave the preview owned and usable. Keep the existing PageEngine interface and engine/client overlay unchanged for this small step.

## Acceptance for the later native patch

Use synthetic HTTP(S) fixtures and one explicitly bound test request context. Verify actual parent and preview identities/context, visible input in the preview, authoritative preview origin, real beforeunload Cancel/Leave, exact-token promotion without browser creation/navigation/reload, and restoration of the parent's live state. Exercise rejected/stale parent identity, a second preview request, workspace change, split refusal, fullscreen/modal transitions, and clean Quit. Confirm private/saved organization remains unchanged except for an explicit successful promotion. Keep raw browser profiles and screenshots outside the public repo. No extension matrix is required merely to establish this presentation seam.
