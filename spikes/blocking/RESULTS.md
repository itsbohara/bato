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
