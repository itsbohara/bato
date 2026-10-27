# Controlled compatibility fixtures

Run from the repository root:

```sh
python3 spikes/fixtures/server.py
```

The server binds only `127.0.0.1:18765`, serves only `www/`, disables directory listings and caching, accepts no POST handler, and writes no request logs. Stop with Ctrl+C. `--port` changes the port; adapt test filter rules and vault URI accordingly. No external scripts, network services, or dependencies are used by these pages.

- `/login.html`: standard username/current-password fields; local comparison against deliberately public dummy values. Use only a disposable test vault entry for the exact origin. The page never authenticates to a service; it cannot prove real site login by itself.
- `/blocking.html`: independent harmless control and target scripts plus a cosmetic target. In AdGuard's user rules, add `|http://127.0.0.1:18765/ads/network-probe.js$script` and `127.0.0.1###bato-cosmetic-ad`. With filtering off, both scripts execute and the cosmetic target is visible; with the test rules active, only the target script is blocked and the cosmetic target disappears. Check the Network panel and filter log to distinguish blocking from page errors. A default-list decision on localhost is not an acceptance test.
- `/wallet.html`: EIP-6963 provider discovery with a legacy fallback. No account-access or signing request is sent at load. Buttons explicitly request account access, inspect existing accounts/network, revoke account permission, or sign a fixed compatibility message. No transaction, typed-data, token approval, or chain-changing request exists. Use a newly created, unfunded disposable wallet. Signature formatting is checked; cryptographic signer recovery is not implemented and remains an independent check.
- `/`: non-secret localStorage/cookie marker for shared/isolated Profile and restart checks; displays the synthetic extension content-script/service-worker response.

Load `probe-extension/` unpacked in the disposable runtime. Version `0.2.0` adds the minimal `activeTab` permission. Its action popup queries the active tab and shows its ID plus only an allowed loopback URL's origin/path; query strings, fragments, page titles/content, and non-loopback URLs are omitted. Open the popup with each split pane focused and compare tab IDs and fixture paths. Its button sends a message to the MV3 service worker and increments a `chrome.storage.local` counter. Reopening and restarting should retain the count in the same Profile. A content script only runs on loopback fixture origins. This diagnostic has no blocker, wallet provider, real autofill, or real-extension installation/update behavior. Its success cannot establish compatibility with the required extensions.

HTTP loopback is treated as potentially trustworthy in Chromium, but this does not exercise a publicly trusted HTTPS origin, secure cookies, mixed content, TLS, remote-site matching, or cross-site frames. Use a controlled HTTPS origin for the final Bitwarden and browser security gates. The alternate `localhost` link preserves the current port and works only if local name resolution reaches the IPv4 loopback binding; the authoritative fixture URL is numeric IPv4.

## Verification

```sh
python3 -m unittest discover -s spikes/fixtures -p 'test_server.py' -v
node spikes/fixtures/test_wallet.mjs
node spikes/fixtures/test_popup.mjs
```

Python tests exercise real HTTP resources, loopback binding, traversal/listing denial, submission rejection and manifest file references. The Node test uses a mocked provider to verify no unsolicited wallet permission request, rejection handling, the fixed `personal_sign` payload, and revocation. These are fixture checks, not runtime extension compatibility passes.

The recorded 2026-10-27 runtime observations used port 8765. Future runs default to 18765 to avoid sharing a port with an existing local service. Historical evidence retains the actual observed URLs.
