# Native split control audit

Date: 2026-10-27. Scope: pinned source audit plus coordinator runtime checks with disposable Profiles. Engine remains CEF `156.0.14+g4fa4ab5`, Chromium `156.0.8078.48`.

## Result

A public extension API route for creating and separating native split pairs exists in the **exact pinned Chromium source**, not only moving upstream. Runtime creation and display passed in a normal Chrome window. The populated CEF Views popup could not receive two tabs through the tested creation/move route. A Swift-to-extension transport and production installation policy remain unresolved.

The exact tag was retrieved successfully using Python `urllib.request` and base64 decoding of Gitiles `?format=TEXT`. The web tool failed the same URL; that failure is not evidence that the source tag is unavailable. This updates the retrieval limitation in [the earlier investigation](SPLIT-INVESTIGATION.md).

## CEF command boundary

The installed distribution's `include/cef_browser.h` exposes `CefBrowserHost::CanExecuteChromeCommand` and `ExecuteChromeCommand`. Check availability and dispatch on the browser UI thread using `cef_id_for_command_id_name()`; hardcoded numbers below are identification evidence only.

| Pinned command | ID | Useful operation |
| --- | --- | --- |
| `IDC_NEW_SPLIT_TAB` | 34057 | Create a split involving the current tab, if enabled. |
| `IDC_NEW_TAB` | 34014 | Ordinary new-tab command. |
| `IDC_CLOSE_TAB` | 34015 | Close current tab. |
| `IDC_SELECT_NEXT_TAB` / `IDC_SELECT_PREVIOUS_TAB` | 34016 / 34017 | Relative tab activation. |
| `IDC_SELECT_TAB_0` through `IDC_SELECT_TAB_7` | 34018–34025 | First eight positions. |
| `IDC_SELECT_LAST_TAB` | 34026 | Last position. |

The bundled command list contains no generic arbitrary-two-tab pair constructor, unpair command, or split-ratio setter. These commands alone do not provide a durable Bato tab model. CEF browser identifiers must not be treated as extension `tabs.Tab.id` values without an explicit verified mapping.

## Version-specific extension route

The exact [tabs schema](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/common/extensions/api/tabs.json) includes:

- `tabs.createSplit([firstId, secondId])`, returning a split ID.
- `tabs.create({url, splitWithTabId, ...})` for creating the second page.
- `tabs.unsplit(splitViewId)` and `Tab.splitViewId`.
- Ordinary query, move, update/activate and remove operations for tab control.

Neither the inspected schema nor CEF commands provide a divider-ratio argument. Persist saved URLs and Bato identifiers; runtime tab/split IDs are references to resolve anew during restore.

Exact [_api_features.json](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/common/extensions/api/_api_features.json) gates `tabs.createSplit` and `tabs.unsplit` on `ApiTabsSplitView`. Exact [extension_features.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/extensions/common/extension_features.cc) enables that feature by default. CEF configuration/runtime still needs a presence test.

Exact [tabs_api.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/extensions/api/tabs/tabs_api.cc), lines 3572–3687, validates separate IDs, same window/pinned/group states, adjacency, absence of an existing split, and editable tab strip. It rejects DevTools tabs and reports failed creation. Unsplit resolves the requested split in the caller's browser context before separating its tabs. These checks are useful negative acceptance cases; the bridge must propagate errors rather than replace a failed operation with an overlay.

The [official public API reference](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-createSplit) lists split creation/separation as Chrome155+. Its permission section distinguishes ordinary tab manipulation from access to sensitive tab URL/title fields. The route runs in an extension context, not a website or content script.

Decoded exact-tag SHA256 values, recorded for reproducibility:

```text
tabs.json              5380b79db1c0078e99ca5f97f55bde46d357e07d76d3afcf886020c69a8c4b23
_api_features.json     b53ad4ade8742f48593433d53da785b19f910c5f5612946f4073df0ba7a53a4c
extension_features.cc  fd634b38ec97ab62d83100361abcae7d28425ba9decd61928c368bf42df32e67
tabs_api.cc            e7e8866b4827033b036d83a3ae6907ff18d523f565a3747c999e800996374a65
```

## Browser type and downstream boundary

The exact `TabsCreateSplitFunction::Run` has no `TYPE_NORMAL` check. Exact [TabListBridge::CreateSplit](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/tabs/tab_list_bridge.cc), lines383–397, maps handles to indices and invokes `TabStripModel::AddToNewSplit`. Exact [TabStripModel::AddToNewSplit](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/tabs/tab_strip_model.cc), lines1972–2014, likewise contains no normal/popup type guard. This differs from the ordinary new-split browser command. Therefore try the extension route in a CEF Views Chrome window before concluding that its browser type blocks split. Public API success still must be followed by visible two-pane display and interaction checks; the inspected model code does not establish that every host renders a split.

## Views popup runtime follow-up

The coordinator's Views-hosted experiment identified an important boundary: its original browser window was extension window type `popup`. The controller's declared options page opened successfully in a **separate normal Chrome window**. A request to create fixture tabs in popup window `35508564` returned tabs `35508603` and `35508604` in normal window `35508597` instead. Those are ephemeral diagnostic IDs. This is a redirected creation result, **not a Views-native split pass**.

The exact source explains the behavior. [OpenTabHelper](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/extensions/open_tab_helper.cc), lines194–198, requests new foreground/background tabs. [browser_navigator.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/navigator/browser_navigator.cc), lines121–139 and298–310, permits creation in the selected window only if it supports the tab-strip feature or has an empty tab model; otherwise it finds/creates a tabbed browser. A populated Views popup therefore does not obtain a second tab through this route.

The coordinator also attempted an explicit move of two controlled tabs into that popup. Chromium returned **`Tabs can only be moved to and from normal windows.`** Exact `tabs_api.cc`, lines3124–3128, calls `MoveTabToWindow` with `allow_other_window_types=false`; its lines469–475 reject a target whose type is not `TYPE_NORMAL`. `windows.create({tabId,...})` has a separate exception for moving a tab into a newly created empty popup; that does not establish a way to add a second tab to the existing Views host.

In the normal Chrome window, the coordinator created and paired the controlled login/wallet tabs with `tabs.createSplit`, then activated the pair and visually verified both pages. The returned split ID was `473480009` (ephemeral). Divider drag and keyboard attempts did not establish a width change. Separation and reconstruction after restart remain untested. The successful normal-window operation does not establish a Swift sidebar hosting path.

The controller now validates returned creation window IDs, retains created IDs for cleanup if redirected, and refuses to pair outside the explicitly selected target. Its explicit move button logs requested and returned IDs or the API error. The absence of a type guard in `createSplit` itself is insufficient: the host must first contain two eligible tabs. The current public extension route has not demonstrated that prerequisite for a populated CEF Views popup.

## Next executable experiment

The [disposable controller extension](../split-controller/README.md) implements these controls, leaving the existing activeTab probe's narrow permissions intact. Its JavaScript syntax check passed; runtime execution is owned by the coordinator. Use an extension page with explicit buttons and only loopback fixture URLs. Do not grant external messaging or make a website-to-host command endpoint.

1. Show `typeof chrome.tabs.createSplit` and `typeof chrome.tabs.unsplit` in the extension page. Fail clearly if absent.
2. On a user button, create two adjacent tabs in the selected disposable window, at `/login.html` and `/wallet.html` on port18765; save only their ordered URLs in extension local storage.
3. Pair their returned IDs, query both, and assert equal nonnegative `splitViewId`. Activate each side with `tabs.update(id, {active:true})`; verify the existing probe still targets that side.
4. Unsplit using the returned split ID, verify independent tabs, then pair again. Exercise closing one member and record the remaining member's state. Verify actual visible layout separately.
5. Close these two controlled tabs, restart the same application/Profile, then recreate from saved URLs and pair newly returned IDs. This tests deliberate reconstruction rather than reuse of stale IDs or Chrome session restore.
6. Independently test divider drag and resulting geometry. Do not infer divider persistence from pair membership.

Only after those pass, design an authenticated native transport tied to the correct Profile/window and a durable controller-extension install/update path. Existing `--load-extension` loading is temporary developer machinery; Bitwarden's demonstrated Web Store persistence does not prove persistence or privileges for a Bato controller extension. Native sidebar geometry, lifecycle, real vault/wallet targeting and extension permissions remain separate foundation gates.

## Normal-window reconstruction runtime result

The delegated coordinator test used the linked `cefsimple --use-native` executable, this controller extension, and a newly created disposable `profile-split-restore`. Both launches used the same executable identity/Profile and `--use-mock-keychain`; no debug listener was enabled. The mock encryption-key provider is test-only, not production Keychain acceptance.

Through native computer use, management Details → Extension options opened the full-page controller in a normal Chrome window. Both split methods were functions. Creating the fixture pair returned tabs `343657744`/`343657745` in the requested normal window `343657741`. Pairing yielded shared split ID `1617381372`; activating left showed the dummy login and wallet fixture together. Separating reported `splitViewId: -1` for both. Pairing again worked, then Close test tabs removed both controlled entries.

The first Close all browsers action logged detachment of remaining linked browsers and `linked-detached`, but the process remained without message-loop/shutdown completion. Cmd+Q had also not closed the process earlier. After a bounded wait, only that owned process was stopped with SIGTERM. Therefore the following result is **reconstruction after a forced stop**, not a clean-restart acceptance pass; no cause for the first shutdown failure is established.

After relaunch with the same identity/Profile/flags, opening the controller and pressing Restore saved pair recreated the fixed URLs in fresh tabs `343657818`/`343657819`, normal window `343657800`, with shared split ID `651031505`. Native AX and a screenshot confirmed both fixture pages visible again. This demonstrates durable ordered-URL storage and explicit pair reconstruction with new runtime IDs. It does not demonstrate Bato's pin model, arbitrary URLs, session restoration, split-ratio persistence, or real extensions.

The reconstructed test tabs were closed. The final native Close all browsers action **did** finish cleanly: the log contained `cef-message-loop-exited` and `cef-shutdown-complete`, and its owned process was absent. No browser process or debug listener from this delegated test was left running; the coordinator's fixture server was untouched.

One divider drag produced no confirmed width change, so resizing remains unverified. No source fix was attempted during the runtime test. See [sanitized evidence](../split-controller/runtime-evidence.json) for the exact narrow observations. This normal-window result does not alter the earlier populated Views-popup creation/move limitation.

A third bounded run then tested the **clean second→third shutdown boundary** using the unchanged executable identity, disposable Profile, mock-Keychain and developer-extension flags. No new Create/save operation occurred: Restore saved pair alone created fresh tabs `343657885`/`343657886` in normal window `343657874`, with shared split ID `963640437`. Native AX and screenshot again showed the login and wallet fixture together. Thus ordered fixed-URL pair reconstruction also passed across a demonstrated clean shutdown, while the first forced-stop result remains recorded separately.

After closing the third run's controlled tabs, native Close all browsers again logged message-loop exit and completed CEF shutdown; its owned process was absent. This adds one narrow clean-restart acceptance case, not general lifecycle reliability or production Profile/Keychain acceptance. The fixture remained untouched and divider resizing was not retried.

## Distinct application-quit follow-up

A later prebuilt-engine-only run exercised the new native **Quit application** control separately from Close all browsers. With the same dedicated disposable mock-Keychain Profile and controller extension, the operator restored the pair, separated it, paired again, and closed its controlled tabs before selecting Quit application in the Swift companion.

The command availability log reported `enabled: true`, but execution terminated with an uncaught `NSInvalidArgumentException`: `-[AppController tryToTerminateApplication:]: unrecognized selector sent to instance` (instance address omitted). The sample stack included `-[SimpleApplication terminate:]`. Sample browser-list diagnostics had counted four creations, then two closures from pair cleanup, leaving count2 before the quit request. There was no completed command-dispatch log, message-loop exit or completed CEF shutdown. The process disappeared as a crash result, not graceful completion. This new application-quit failure does not erase the earlier clean close-all/reconstruction cases or resolve the first intermittent hang.

See [sanitized quit evidence](../linked-native-bridge/quit-runtime-evidence.json). No Keychain/credential prompt appeared, no engine build or code edit occurred in this test, the owned process was gone afterward, and the fixture server was left running.
