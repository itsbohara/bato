# Linked bridge runtime evidence

Date: 2026-10-27. Pinned CEF156.0.14 / Chromium156.0.8078.48, Apple Silicon. The coordinator owns all runtime/UI tests; this directory's implementation agent compiled and inspected artifacts without launching browser processes.

## Build and explicit lifecycle

The isolated sample overlay compiles and links Swift/AppKit through Objective-C++, with CEF sandbox support enabled. `nm` confirms the Swift C-entry symbols are in the main executable; `otool` confirms system Swift runtime dependencies. No injected dylib or Chromium core rebuild is used. Helpers retain the upstream sample code.

Window availability can lag `OnAfterCreated`. The final bridge retries on the CEF UI thread and captures only browser identifiers, removing owning browser references in `OnBeforeClose`. Focus notifications can also complete attachment. Native popup browsers are excluded.

The coordinator's full-native run with a fresh disposable Profile and `--use-mock-keychain` rendered the fixture and attached the Swift companion. Sanitized events recorded `BrowserNativeWidgetWindow`, main-thread attachment, companion width224, browser width1200, and no rectangle overlap. Closing the actual browser window produced Swift detach, zero bridge browser references, message-loop return and `cef-shutdown-complete`; the process exited promptly.

In the subsequent opt-in focused-companion run, the coordinator used actual accessibility UI actions to click the native button (count1), enter test text in its native field, and click **New native split**. The supported command reported enabled, a second browser attached to the same window, and the main window visibly showed the fixture beside a new-tab page. Field contents are not logged. Closing the browser window detached both browsers and the shared companion, returned the message loop, and completed CEF shutdown.

The initial **Focus browser** implementation focused CEF content without making the browser window key. After adding explicit AppKit window activation before content focus, the coordinator's final control run verified the following through actual accessibility UI actions:

- **New native split** created a second browser in the same window.
- **Focus browser** made the main browser window key and visibly focused its address bar.
- The explicit Window-menu companion item selected the native panel again.
- **Close all browsers** closed both browsers through `CloseAllBrowsers(false)`. Each detached, the shared panel detached after the last browser reference, the message loop returned and `cef-shutdown-complete` was recorded. The process exited promptly.

This passes the bounded native control and clean-close experiment with the disposable mock-keychain Profile. It does not prove page-text focus: the observed focus target was the browser address bar. Attachment or a programmatic focus request alone is not an action-button pass. Native in-window sidebar input, saved pairs, real-extension popup association, signing/encryption and complete production lifecycle remain separate requirements.

## Keychain isolation

Initial linked builds showed a permanently loading/blank fixture and teardown-watchdog expiry. The same behavior persisted with callbacks disabled, Swift/Bridge omitted, and the exact unmodified sample copied into the source overlay. All232 bundled CEF framework files matched the working baseline by SHA256. App/helper property lists and compile/link flags also matched apart from source-root strings.

Transplanting the already working baseline main executable into the same overlay app package rendered and closed normally. Relinking all baseline objects reproduced its exact main binary bytes. Recompiling stock sample sources with only source-root normalization reproduced all four baseline objects byte-for-byte; that normalization was diagnostic and was not adopted as a fix. Single-object transplants, a fresh executable inode and ad-hoc app re-signing did not resolve the loading problem.

A shutdown process sample revealed a worker waiting inside `SecItemCopyMatching` and Keychain decryption. The coordinator then ran the same previously failing stock binary with a new disposable Profile and only the additional `--use-mock-keychain` flag: the fixture rendered and closing the window exited promptly. The subsequent full-native linked run passed rendering/attachment/shutdown with that flag as well.

This establishes a dominant Keychain-dependent failure in these changing development builds. It does not identify the precise Keychain ACL rule or establish production signing/encryption behavior. Mock-keychain Profiles are test-only, contain no real secrets and must never be reused for personal browsing. The build does not enable mock keychain by default.

Local raw logs and process samples remain outside Git under `~/.cache/bato/linked-native-bridge/`. No browser data, Keychain item contents, credentials or private captures are included here.

## Extension-run shutdown remains bounded evidence

During the coordinator's later synthetic split-controller extension experiment, one native **Close all browsers** run detached the bridge's browsers/panel but did not return the application event loop; the owned process was eventually stopped explicitly. Follow-up controller runs exited cleanly, including a restore across a clean boundary. The original incomplete shutdown remains a recorded failure; extension-enabled lifecycle is not universally passed.

A separate **Quit application** command was added for a supported comparison. Its first actual UI run reported `IDC_EXIT` enabled, then failed with an Objective-C exception: `SimpleApplication.terminate:` sent the sample delegate's selector to the actual Chromium `AppController` delegate. This is recorded as a failed Quit run, not graceful shutdown.

The sample-only override now routes termination directly through the known CEF handler, retaining `CloseAllBrowsers(false)` and the global closing notification already sent by the Chrome command. The revised dispatch needs a repeat of the actual UI test; no fix for the earlier intermittent hang is claimed. [QUIT-PATH.md](QUIT-PATH.md) records source details and diagnostic distinctions. Mock-keychain test Profiles retain the same test provider across restarts; they are not recreated for each restore run or mixed with earlier real-keychain Profiles.

## Reserved Views experiment

The corrected native geometry uses the exported content view's own bounds. Initial logs with the mock-keychain test show a native sidebar at x0/y0 with width260/height524, a top native row at y524 with height44, and the CEF BrowserView at local x260/y44 with width540/height524 in an800×568 content area. These are corresponding AppKit bottom-origin and CEF top-origin coordinates.

The coordinator visually verified the reserved260-point sidebar and44-point top row, with the rendered fixture starting in the remaining browser rectangle without overlap. Closing the real window produced native detach, zero bridge browser references, message-loop return and completed CEF shutdown.

Actual native controls were not exposed in the observed accessibility tree. Coordinate clicks at visible controls did not produce a logged native action, so real native input remains unverified. This observation does not distinguish a computer-use limitation from native hit-testing/accessibility integration. Resize/focus, extension behavior and split acceptance remain open. The earlier conversion through `NSWindow.contentLayoutRect` produced negative native coordinates and was corrected.
