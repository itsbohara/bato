# Disposable native split controller

Test-only MV3 extension, version0.1.0. Public-key-derived fixed ID: `cobnhdbbicillijggklemifjachneafl`. No private key is retained. Permissions: local extension storage only; no host permissions, external messaging, background worker, or page script injection.

Load this directory explicitly into the pinned sample's **disposable Profile**, then open the full-page URL:

```text
chrome-extension://cobnhdbbicillijggklemifjachneafl/controller.html
```

In the coordinator's first Views-hosted test, initial direct navigation to that extension URL returned `ERR_BLOCKED_BY_CLIENT` despite the enabled management card and matching ID. This is a navigation observation, not evidence that the tabs API is absent. The manifest therefore also declares `options_ui` with `open_in_tab: true`: open `chrome://extensions`, this extension's Details, then Extension options to request a browser-owned extension-page navigation. Reload the extension after this manifest change. That alternate route opened the controller successfully in the coordinator's test.

The coordinator verified that Extension options opens the controller, but did so in a new full Chrome window. To test the original Views popup instead, press List window IDs and types, then Use unique Views popup. Selection rejects zero or multiple popup windows and remains in memory only. Subsequent operations use the selected popup ID; logs include the target ID/type. Use controller window restores the original targeting. Close this controller's controlled tabs before changing targets. No window titles, URLs or tab inventory are requested.

Run the fixture on `127.0.0.1:18765`. Create two test tabs, pair them, then activate left/right. The controller remains a separate tab so it can operate the pair. Return to it to inspect state, separate, pair again, or close its two tab IDs. Its action popup intentionally reports that the full-page controller must be used; native Views samples need not expose a toolbar action.

For reconstruction: create once to save the fixed ordered fixture URLs, close the controlled tabs, restart the same sample/Profile with this developer extension loaded, reopen the controller and press Restore saved pair. It recreates tabs with fresh IDs. It does not rely on Chrome's session restore. Only the two hardcoded fixture URLs are persisted. After a controller-page reload, old IDs are deliberately not recovered; close leftover test tabs through the browser UI before starting another run.

The page logs method availability and IDs/membership/activation/index, never arbitrary page titles, URLs, or contents. Errors remain visible. No actual engine capability is implied by shipping these controls; record API responses and visible behavior separately. Divider ratio is not controlled by this extension.

Syntax check: `node --check spikes/split-controller/controller.js`.

In the first explicit popup-target run, `tabs.create` returned tabs in the separate normal window. Creation now validates the returned window IDs and reports redirection; Pair refuses tabs outside the selected target. The explicit Move controlled tabs into selected target button attempts `tabs.move` and reports its error/result. No Views split acceptance follows from creating or pairing tabs in the normal window.
