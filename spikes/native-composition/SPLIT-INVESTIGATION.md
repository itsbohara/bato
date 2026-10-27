# Chrome-native split investigation

Date: 2026-10-27. Pinned installed engine: CEF `156.0.14+g4fa4ab5+chromium-156.0.8078.48`, CEF revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. This investigation did not download or rebuild Chromium. Runtime experiments are coordinated by the root agent; this report separates bundled-header facts, current upstream evidence, and actual test results.

## Correction to the earlier architectural inference

**A maximum of one Chrome-style CEF BrowserView does not mean a maximum of one visible WebContents.** Chromium implements its own two-tab split within its Chrome browser view using `MultiContentsView`. It can display two independent tab WebContents with a resizable divider. This is distinct from placing two CEF Chrome BrowserViews into a CEF Views window.

CEF's own [issue #3980](https://github.com/chromiumembedded/cef/issues/3980) explicitly tracks split support. The maintainer reports that the old `SideBySide` feature became permanently enabled in M145, that related UI is absent in `cefclient`, and that it works with the default Chrome UI, giving `cefsimple --use-native` as the example. The issue was closed as completed for M145. Therefore an absent split control in `cefclient` is not evidence that CEF156 cannot split Chrome tabs.

This removes the prior **source-based assumption** that Bato necessarily needs a mixed Chrome/Alloy pair or a custom Chromium split implementation. It does not establish Bato's native Swift sidebar, its tab-control bridge, saved-pair persistence, or real-extension behavior on both panes.

## Facts verified in the pinned distribution

The actual CEF156 `include/cef_command_ids.h` defines:

| Name | Numeric value in this exact build | Meaning / caveat |
| --- | --- | --- |
| `IDC_NEW_SPLIT_TAB` | `34057` | Browser-level command creating a new split from the active tab. |
| `IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW` | `50111` | Link context-menu action; requires the corresponding link context. It is not a generic two-URL constructor. |
| `IDC_BOOKMARK_BAR_OPEN_SPLIT_VIEW` | `51023` | Bookmark-bar split action; depends on bookmark selection context. |

Use `cef_id_for_command_id_name()` for version-safe command lookup rather than persisting these numbers. The bundled [`CefBrowserHost`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_browser.h) exposes `CanExecuteChromeCommand` and `ExecuteChromeCommand`. Query and execute from the browser UI thread after browser creation. Check actual availability before invoking.

The bundled [`CefCommandHandler`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_command_handler.h) can observe/intercept Chrome commands. Returning `false` delegates to the default implementation; returning `true` consumes the command. Its visibility/enabled callbacks only apply to items that Chrome would already expose/enable; they do not create a tab strip or a normal-browser window.

Pinned `tests/cefsimple/simple_app.cc` confirms that `--use-native` takes the `CefBrowserHost::CreateBrowser` path without a supplied parent NSView. With the default Chrome runtime style, that produces full Chrome UI. This is **not** the parent-NSView embedding path that forces Alloy. In this sample, native means the platform/default Chrome window path; it does not mean a Swift-owned Bato window.

## Current upstream implementation evidence

The following Chromium sources were inspected at moving `main` on the research date. Requests for the exact `156.0.8078.48` source URLs were not retrievable, so current-main internals are supporting evidence rather than a claim of byte-identical pinned behavior. Bundled CEF headers and the runtime experiment are the version-specific anchors.

- [`browser_command_controller.cc`](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/ui/browser_command_controller.cc): `IDC_NEW_SPLIT_TAB` invokes `NewSplitTab` with side-by-side layout unless the active tab is already split. Its enabled state requires a `TYPE_NORMAL` browser. A custom embedded/popup browser may therefore lack the command even though the engine contains the split implementation.
- [`browser_commands.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ui/browser_commands.cc): `NewSplitTab` inserts an adjacent tab, joins it with the current tab through `TabStripModel::AddToNewSplit`, and activates the new side. It chooses the split new-tab page or an appropriate ordinary new-tab page depending on Profile/tab context.
- [`multi_contents_view.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ui/views/frame/multi_contents_view.cc): the browser owns two contents containers, shows both for a split, and displays a resize area. This is the missing distinction between CEF BrowserViews and underlying WebContents.
- [`tab_strip_model.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ui/tabs/tab_strip_model.cc): split membership is maintained in the tab model. It is not a reparented external Alloy browser.

No historical `--enable-features=SideBySide` flag should be necessary for this pinned >=M145 baseline. Test the default first. Flags for newer orientation/UI variants are separate from basic side-by-side support and should not be added speculatively.

## Extension control route and active-pane association

Current upstream [`tabs.json`](https://chromium.googlesource.com/chromium/src/+/main/chrome/common/extensions/api/tabs.json) defines `chrome.tabs.createSplit([tabId1, tabId2])` and `chrome.tabs.create({splitWithTabId: ...})`. The two existing tabs must be adjacent, in the same window, not already split, and have compatible pinned/group states. The runtime guard and error handling live in [`tabs_api.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/extensions/api/tabs/tabs_api.cc). This is a possible bounded control bridge if native CEF commands do not expose the required tab targeting; it is not selected as Bato's production architecture.

These APIs are gated by `ApiTabsSplitView` in [`_api_features.json`](https://chromium.googlesource.com/chromium/src/+/main/chrome/common/extensions/api/_api_features.json); current [`extension_features.cc`](https://chromium.googlesource.com/chromium/src/+/main/extensions/common/extension_features.cc) enables that feature by default. Check actual API presence in the pinned extension execution context before relying on it. An ordinary website cannot invoke the Chrome extension tabs API. Current schema uses `splitViewId`; the older security FAQ calls the concept `splitId`, so implementation must follow the actual version's schema rather than copy the FAQ's identifier.

The [Chromium split security FAQ](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ui/tabs/docs/split_view_security_faq.md) describes two visible WebContents, with only one active/focused pane. Chrome's thicker active outline and per-pane origin/permission indicators are security requirements to preserve. Visibility of both pages is not equivalent to an `activeTab` permission grant to both.

Current [`extension_action_runner.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/extensions/extension_action_runner.cc) runs actions and grants tab permissions for its owning WebContents/tab ID. Extension menu controllers use the browser's active tab to select that WebContents; for example [`extensions_menu_view_model.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/ui/extensions/extensions_menu_view_model.cc). Thus the expected association is the selected pane's tab, not the entire split pair. Broad host-permission content scripts may run in both pages independently. Real Bitwarden, AdGuard, and MetaMask behavior still requires per-pane tests; a visible popup alone cannot prove correct target-origin association.

## Supported experiment plan

1. Use stock `cefsimple --use-native`, default Chrome style, the existing disposable Profile A, and the same four explicitly loaded developer extensions. Do not inject the native accessory initially; isolate Chrome's built-in split path.
2. The macOS simple sample does not itself map `--cache-path` into `CefSettings` as `cefclient` does. Before launch, the baseline agent must explicitly set `root_cache_path` and `cache_path` from the selected disposable directory (a sample-only patch), or otherwise demonstrate equivalent isolation. Do not accidentally open default browser storage.
3. Inspect the full Chrome tab/toolbar/link context menus for the split action. Create a split through that supported UI before adding any CEF patch. Use two distinct controlled fixture URLs and verify independent interaction plus divider resizing.
4. Activate left then right. For each side, open the synthetic action popup and record the tab ID/origin it targets; then check real extension popup operation. Bitwarden autofill and MetaMask connection/signing still need disposable test credentials and explicit user-triggered actions.
5. If UI is missing, inspect `CanExecuteChromeCommand` and actual browser type before concluding the feature is unsupported. A small sample-only command invocation is a fallback; no Chromium rebuild should be needed just to test command34057.
6. Test saved split restoration and Bato's Swift control bridge separately. A full Chrome tab strip working in the stock sample is engine evidence, not approval to ship Chrome's UI as Bato.

## Runtime results

The coordinator ran the pinned source-built `cefsimple --use-native`, using the sample-only disposable Profile mapping patch, and verified the following through native computer use:

- The ordinary tab context menu exposed **New Split View with Current Tab**. Selecting it produced two visible pages and a split divider in one Chrome window.
- The left pane displayed the fixture root; the right pane navigated independently to `/wallet.html`. The right page discovered the real MetaMask provider and returned `accounts: []` and `chainId: 0x1` through read-only requests.
- Focusing the left fixture changed the active-side indicator and URL display to the left page. Focusing the right page changed both to the right page.
- After reloading synthetic probe v0.2.0, its real action popup reported left tab ID `35508142` with fixture path `/`, and right tab ID `35508171` with `/wallet.html`. The worker counter advanced from 1 to 2 across those popup interactions. These IDs are ephemeral test observations, not application identifiers.
- The splitter is present, but attempted computer-use drags did not produce a confirmed width change. Divider resizing remains unverified; this observation alone does not establish an engine defect.

A subsequent combined run inserted the corrected Swift/AppKit accessory into the same native Chrome path. Native controls, a real split pair, synthetic content/worker messaging, and Bitwarden's real welcome action popup coexisted. A real native button click advanced the visible count to 2. **The accessory overlapped Chrome's toolbar in this native-window variant**, despite the earlier clean layout in Views-hosted `cefclient`. Thus combined feature presence passed narrowly, while production native layout did not.

The sample's Quit menu/shortcut did not produce a confirmed process exit in this run. The owned disposable process was stopped explicitly for the next test. Production lifecycle/shutdown remains separate work; no graceful-shutdown claim follows.

See [sanitized runtime observations](split-runtime-evidence.json) and the [integration matrix](../../FEASIBILITY-RESULTS.md). Actual Bitwarden autofill, MetaMask account approvals/signing, cross-origin popup permission behavior, native sidebar integration, and saved split restoration remain unpassed. The native Chrome split result supersedes the earlier inference that the BrowserView count restriction necessarily requires a custom Chromium split implementation.
