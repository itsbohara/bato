# Blocking spike results

Run 2026-11-07, real host (Chromium 156 / CEF 156.0.14 Debug arm64, mock-keychain engine Profile, fresh organization state cloned from split-pairs-state-v1). Flags: `--bato-blocking=<fixture list>` and `--bato-blocking-lib=<release libbato_adblock_ffi.dylib>`. Nothing committed.

## Build
- `native_slot.py check`: patched, 27 files. `build --execute` succeeded (segment small: engine already contained the hook; the binary links the switch strings). Rust `cargo build --release` of `spikes/blocking/adblock-ffi` succeeded (dylib about 3.0 MB).
- Defects fixed: none. No source changes.

## Result table (active page navigated to blocking-network.html with Cmd-L, load 1 then one Cmd-R reload)
Engine event column = `{"bato":"blocking","event":"blocked"}` seen in stderr for that request.

| Row | Expected | Page result | Engine event | Verdict |
| --- | --- | --- | --- | --- |
| script-control | allowed | executed | none | pass |
| script-tracker | blocked | failed (load 1), executed (reload) | blocked, script | engine pass; row flaky (fixture) |
| script-same-origin | allowed | executed | none | pass |
| script-allowed-tracker | allowed | executed | none | pass (exception rule) |
| script-important | blocked | failed | blocked | pass |
| script-domain-only | blocked | failed | blocked | pass |
| image-control | allowed | executed | none | pass |
| image-pixel | blocked | failed | blocked, image | pass |
| xhr-control | allowed | failed | none | fixture defect (no CORS) |
| xhr-beacon | blocked | pending | blocked, xmlhttprequest | request blocked; row never settles (see below) |
| fetch-control | allowed | executed | none | pass |
| fetch-beacon | blocked | failed | blocked | pass |
| worker-script-control | allowed | executed | none | pass |
| worker-script-blocked | blocked | failed | blocked, script | pass (worker script load is hooked) |
| worker-fetch-control | allowed | executed | none | pass |
| worker-fetch-beacon | blocked | failed | blocked | pass (fetch from a dedicated worker is hooked) |
| css-control | allowed | executed | none | pass |
| css-ads | blocked | failed | blocked, stylesheet | pass |
| frame-control | allowed | executed | none | pass |
| frame-ads | blocked | failed | blocked, subdocument | pass |

Cosmetic target `.bato-fixture-ad` stayed visible: no cosmetic filtering exists in this spike (expected, not in scope).

Engine `ready` event appeared once at startup. Ten blocked events per page load: script x3, stylesheet, image, subdocument, xmlhttprequest x3 (XHR, fetch, worker fetch; fetch is reported as xmlhttprequest), worker script (reported as script). Request types seen and blocked: script, stylesheet, image, subdocument, xmlhttprequest/fetch, worker script, fetch from worker. Not exercised: websocket (list rule present, no fixture row), media, font, ping, service worker, shared worker, main-frame (deliberately never filtered), redirects, requests initiated by extensions.

## Findings (all in fixtures or page expectations, none in the hook)
1. xhr-control failed because the fixture server sends no CORS headers (console shows the CORS error). The control row cannot pass as written; fetch-control uses no-cors and passes.
2. script-tracker race: `/ads/tracker.js` is also loaded same-origin by script-same-origin, and that copy marks the script-tracker row executed. Whichever finishes last wins. Blocking itself worked in both loads (blocked event logged). Fix by giving the same-origin check its own file or mark id.
3. xhr-beacon stays pending while the engine logs it blocked. Likely cause (inferred, not isolated): RV_CANCEL maps to ERR_ABORTED, which XHR reports as `abort`, and the page only listens for `error`. fetch, script, image, css and workers do report failure. Add an `onabort` handler to the fixture to confirm; if a distinct blocked error code is wanted (ERR_BLOCKED_BY_CLIENT) the hook would need a different mechanism.
4. Engine init time was not measured: the hook logs no timestamps. `ready` is emitted during handler construction, before native-slot-attached; dylib load and a 13-line list are expected to be negligible. Add a timestamp/duration to the ready event for a real figure.

## Lifecycle
Launch PID 76390, wrapper `launch-blocking-v1.py` (receipt guard compact-folders-v1-exit.json, fresh blocking-state-v1). Quit through app menu (Quit Chromium): exit 0, single sample-native-quit-requested, native-slot-attached/detached and cef-shutdown-complete markers; browser count 3 created and 3 closed. Organization bytes before quit equal final bytes (sha256 prefix 3188c82deb811af0). The organization changed from the cloned start state because the page navigation was saved. Browser zoom was lowered with Cmd-minus to see all rows and reset with Cmd-0.

Not run: launch without the switches (optional step; blocking-inactive path is the `!g_blocking.engine` early return in the hook, not exercised on a real host).

## Logs (SSD, /Volumes/Mahesh/personal/bato-build)
logs/blocking-build.log, logs/blocking-v1.log, logs/blocking-v1-exit.json, logs/blocking-v1-before.json, logs/blocking-v1-before-quit.json, logs/blocking-fixture-18766.log, tmp/blk1-4.png screenshots, tmp/launch-blocking-v1.py.

# Milestone 2 integration and real-host check (2026-11-07)

## Integration
- `WorkspaceSlot.swift` builds one `BlockingControls` (service from `BlockingHost.shared.service`, active page = the selected entry's latest URL plus its CEF browser id from `WorkspaceEngine.pages`, reload = `perform(.load(url))` on that page) and appends its two items under Page, after Copy URL. The Page menu is built once when the root attaches; when the service does not exist yet the items are simply absent. On the real host the service existed at attach time.
- `native_slot.py build --execute` now copies `cargo-target/release/libbato_adblock_ffi.dylib` into `cefsimple.app/Contents/Frameworks/` after a successful build (cargo builds it, GN does not know it, and the host looks there by default). It prints a warning and skips when the dylib is absent. The launch wrapper alternative would have needed `--bato-blocking-lib` on every launch.
- Two defects found on the real host and fixed in the staged `simple_handler.cc` (client.patch regenerated, round trip verified):
  1. Browser abort on first request: `HostOfUrl("")` reached `CefParseURL`, whose wrapper `CHECK`s a non-empty URL. The main frame URL is empty during the first navigation. Now an empty URL returns "" and the page URL falls back to the request initiator/frame URL.
  2. SIGSEGV after the message loop exited (exit -11, v2 run): the 250 ms refresh task kept calling `CefPostDelayedTask` during shutdown. A `g_blocking_stopping` flag is set before `CefQuitMessageLoop()` and the task stops rescheduling. The v3 run quit with exit 0. A task already past the check could still post once; not observed.

## Build and tests
- Swift suite (`logs/integrate-swift-tests.log`): 106 XCTest + 130 Swift Testing = 236, all pass.
- Builds (`logs/integrate-build.log`, `integrate-build2.log`, `integrate-build3.log`): all "finished successfully"; only existing NSEvent Sendable warnings. `native_slot.py check`: patched, 41 files.

## Real host (default lists, no `--bato-blocking`; `launch-integrate-v2.py`, `runtime/integrate-state-v2`)
- Lists were fetched over the network on first start (state started with no lists): engine `ready` events `ms=23 bytes=2075727` (EasyList), then `ms=39 bytes=3589129` (EasyList + EasyPrivacy). Nothing was committed or bundled.
- With the real lists the fixture rows that a generic EasyList rule matches are blocked (`xhr-beacon`, `fetch-beacon`, both `/ads/beacon.json`); the rest are allowed, as expected since the fixture rules live in the fixture list. Page menu: "Blocking: On for this site", "3 blocked on this page" (3 `blocked` log lines).
- Toggle off for 127.0.0.1: `blocking-settings.json` gets `exceptions: ["127.0.0.1"]`, the page reloads about 0.5 s later, beacon rows become `executed`, menu reads "Blocking: Off for this site" and "0 blocked on this page". Toggle on: exceptions empty, rows fail again, count back to 3.

## Real host (fixture list added with `--bato-blocking=<fixture list>`; `launch-integrate-v3.py`, `runtime/integrate-state-v3`)
- `ready` events: 781 bytes / 0 ms (fixture list alone, before the downloads finished), then 2076508 / 23 ms and 3589910 / 44 ms.
- All 20 rows of blocking-network.html match Expected (script-tracker, script-important, script-domain-only, image-pixel, xhr-beacon, fetch-beacon, worker-script-blocked, worker-fetch-beacon, css-ads, frame-ads fail; the 10 controls and same-origin / allowed-tracker execute). Menu shows "10 blocked on this page" (10 `blocked` lines).
- 127.0.0.1 exception then reload: all 20 rows executed, count 0 (workers, CSS and frames included). Toggled back: 10 blocked again. Settings file reflects each change.
- Quit through the Bato app-menu quit item: exit 0, one `native-slot-attached`, one `slot-client-detached`, one `native-slot-detached`, one `cef-message-loop-exited`, no signal. Organization file bytes before quit equal final bytes.

## Still open
- Persistence of an exception across a restart was not exercised (file content verified after each toggle; the next launch of the same state would show it).
- Memory/latency numbers, first-launch race for the very first navigation (the `ready` event arrived before the first page load here), subdomain exception coverage, and the Settings pane remain unverified.
- The cosmetic probe is not hidden (no cosmetic filtering), as designed.

Logs (SSD): logs/integrate-v1.log (crash 1), integrate-v2.log/.out/-exit.json (crash on quit), integrate-v3.log/.out/-exit.json, integrate-swift-tests.log, integrate-build*.log, integrate-v2-pre-import.json and related org copies, tmp/launch-integrate-v{1,2,3}.py, tmp/arc-fixture/.
