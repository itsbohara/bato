# Registered native slot results

On2026-10-29, the pinned source-built normal Chrome window passed a bounded Swift/AppKit input and lifecycle experiment. A single engine-owned NativeViewHost held new application-owned controls inside the reserved left region. This is an experiment ABI; the production foundation remains undecided.

## Observed acceptance

- The native accessibility tree exposed the wrapper group, Swift group, button and editable field inside the normal browser window. Real screenshot-coordinate mouse clicks advanced the native counter0→1, then2 with the native split open, then3 after Quit cancellation. These were not programmatic button invocations.
- Actual field editing changed its displayed synthetic value and focused native AX element. Tab moved to Chromium Reload; Shift-Tab returned to the native field and further typing edited that field. The native Focus browser button returned AX focus to the page.
- Fullscreen hid native controls; exit restored their counter/text and reserved geometry. Window zoom visibly expanded Chrome while retaining the260-point slot. A white right edge remained in the fullscreen screenshot, as in the earlier reservation test; fullscreen fidelity is unpassed.
- The synthetic controller enabled, its options page opened, and its API created a visible native Chromium split. Both fixture pages were visible beside the Swift slot. An actual mouse click/type edited the left page field; the native button remained usable. The Chrome extensions menu opened from its toolbar anchor and listed the synthetic controller. Real extension popups were not tested.
- Four CEF browsers shared one attached slot. First diagnostic Quit was client-vetoed. A subsequent armed Quit showed the real beforeunload dialog; Cancel preserved the page, slot, counters and process. Native and page mouse actions worked afterward. Repeated standard application-menu Quit → Leave detached token1 once, released the client's final retained slot, returned the actual CEF loop, completed shutdown and naturally exited0.
- A second fresh synthetic launch attached token1, then Command-N attached token2 in a second window. Closing the second window detached only token2 (client count1). The first window's real native button still worked. Final application Quit detached token1 (count0), completed loop/shutdown and naturally exited0. No owned browser remained after either successful run.

## Retained failures and limits

The first build failed on raw_ref conversion; the next failed Chromium's global exit-destructor and explicit property-synthesis checks. Corrections preserve those checks, using the proper pointer, NoDestructor state storage and explicit synthesis. The engine/Swift/sample build then passed in75.86s. First launch refused before UI because CFBundle did not identify the already-loaded framework. Lookup now obtains only the known loaded library with RTLD_NOLOAD and resolves the three declared experiment exports. That sample correction rebuilt in6.17s. All failed patch versions/logs remain outside Git. Final dependency checking covered527 ARM64 images; nm confirmed all three API exports.36 engine-build tests and2 exact-engine-patch tests pass.

Free-resize and divider mouse drags produced no observable size change. They are unresolved tests, not passes. Minimum-size limits, scale changes, tab moves, explicit AX parent/frame attributes and full focus traversal remain open. The tool exposed only the modal dialog while it was active, so it did not demonstrate background native-control rejection; source guards and post-Cancel usability do not replace that test. Tab-modal behavior also remains unpassed. Component/runtime warnings remain in raw SSD logs.

Next acceptance should address drag/resize observability, modal input rejection and real extension popup/focused-pane behavior before choosing the engine foundation. This does not implement Bato product UI, saved pins or production security/signing.
