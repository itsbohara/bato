# Bato: Arc import and built-in blocking

Research date: 2026-10-27. Source review only: no import, extension, engine, or browser build was executed. Recommendations below are implementation proposals, not verified capabilities or additional user decisions.

## Recommendation

Implement organization import independently of the browser engine. Evaluate Brave’s `adblock-rust` as the first native blocking candidate, after the Chromium integration passes its extension feasibility gate. Keep AdGuard extension compatibility as a separate requirement. Neither a built-in blocker nor an installed extension substitutes for proving the other works.

Confirmed user decisions: blocking starts enabled and supports persistent per-site exceptions; Bitwarden, AdGuard AdBlocker, and MetaMask are first-alpha compatibility targets. Global blocking control, filter subscription policy, update cadence, and exception scope across Profiles still need design recommendations.

## Arc organization import

The current [Meridian importer](https://github.com/Undermove/meridian-browser/blob/main/src/importers/arc.js) reads `~/Library/Application Support/Arc/StorableSidebar.json`. It parses alternating key/value arrays; maps Spaces, Profile references, Profile-specific Favorites, pins, folders and temporary tabs; uses each tab’s `savedURL`; and reads some theme/icon fields. Split/easel-like child groups are flattened into folders. Its conversion uses fresh random IDs, so copying that behavior would not itself provide idempotent imports. This is useful reference code, not an Arc schema contract or proof of compatibility with Mahesh’s installed Arc version.

Its [LICENSE](https://github.com/Undermove/meridian-browser/blob/main/LICENSE) is MIT with a copyright notice. If adapting source, pin the reviewed revision and preserve its required notice; independently inventory dependencies. No source was copied during this research.

Proposed importer contract:

- Read a copied sidebar fixture; never edit the source Arc files. Begin with user-selected files so the parser can be exercised without broad filesystem access.
- Parse into a versioned intermediate model, then show a preview of Spaces, Profiles and counts before a single transactional import.
- Preserve ordering, nested folders, titles, saved URLs and shared Profile relationships. Unknown entries produce a visible warning/count; unsupported groups preserve recoverable links without claiming original layout fidelity.
- Track source identity and import batch identity; offer skip/reimport explicitly rather than silently duplicating entries.
- Treat Profile mapping as organization metadata. Do not claim imported logins, cookies, passwords, wallet state, extension configuration or history. Those are separate data migration problems.

Acceptance gate: a sanitized fixture with two Spaces sharing one Profile, another Space with an isolated Profile, shared Favorites, nested/empty folders, duplicate URLs, Unicode titles and saved URLs imports with exact expected order/counts. Exercise missing keys, malformed JSON, broken references, cycles and unknown entries; fail safely without partial writes. Repeating import follows the documented duplicate policy. Hash the original before/after and verify unchanged. A private real-Arc fixture must then pass the same checks; do not commit private tab names.

## Blocking candidates

| Candidate | Primary evidence | Fit and remaining work |
| --- | --- | --- |
| Brave `adblock-rust` | [Project README](https://github.com/brave/adblock-rust), [MPL-2.0 LICENSE](https://github.com/brave/adblock-rust/blob/master/LICENSE), [network example](https://github.com/brave/adblock-rust/blob/master/examples/example.rs) | Native Rust library with network matching, cosmetics and replacement resources; uBlock syntax extensions. Proposed first choice through a small C ABI bridge. Bato must supply request context, renderer integration, list/resource management and persistence; no Swift binding or CEF compatibility has been demonstrated here. |
| Ghostery adblocker | [README](https://github.com/ghostery/adblocker/blob/master/README.md), [MPL-2.0 LICENSE](https://github.com/ghostery/adblocker/blob/master/LICENSE) | JS/TypeScript engine with ready integrations for Electron and WebExtensions. A native Swift/Chromium host needs its own execution/integration path; less direct than Rust for the selected architecture. |
| AdGuard library reuse | [tsurlfilter](https://github.com/AdguardTeam/tsurlfilter), [Go urlfilter](https://github.com/AdguardTeam/urlfilter) | TypeScript and Go projects are GPL-3.0 per their repositories. Additional runtime/bridge and license choices make these secondary research options. Installing AdGuard as an extension does not require choosing either as Bato’s built-in engine. |

License observations are not a complete distribution audit. Check exact pinned artifacts and transitive components before shipping. Filter lists and scriptlet/replacement resources have their own terms: [EasyList’s copyright page](https://easylist.to/pages/about.html) describes dual licensing and attribution for named lists; this does not cover every external subscription.

If CEF is chosen, its versioned [resource request handler documentation](https://cef-builds.spotifycdn.com/docs/141.0/classCefResourceRequestHandler.html) exposes request interception on the IO thread. That is a candidate integration point, not proof of complete worker, redirect, frame, cached-resource or Chrome-runtime coverage. The spike must establish coverage in the actual selected build. Avoid fetching lists or doing expensive compilation in the request callback; propose background compilation and atomic immutable-engine swaps.

## AdGuard coexistence and acceptance

[AdGuard’s current extension documentation](https://github.com/AdguardTeam/AdguardBrowserExtension#permissions-required) identifies MV3 dependencies including `declarativeNetRequest`, `scripting`, `userScripts`, storage, navigation and request APIs. It describes toolbar controls, site toggling, options and manual element blocking. These are concrete integration targets beyond extension installation. Record the exact release/manifest tested; avoid treating experimental unpacked installation as store/update support.

Proposed semantics: Bato’s toggle controls Bato’s blocker only. AdGuard keeps its own settings; do not silently disable or synchronize it. An allow decision in one layer does not guarantee the other permits the request. Label the Bato control clearly and explain continued blocking when another blocker is active. Installation alone should not change the confirmed built-in default.

Test all four combinations of Bato/AdGuard enabled and disabled on a controlled fixture. Verify network blocking, cosmetics, exceptions and restart persistence independently, then together. Measure both request outcomes and page behavior so double-counted statistics do not pass as correctness. Cover subframes, SPA navigation, split views, Peek, redirect chains and a worker/cache case. Require login, Bitwarden autofill and MetaMask test-account connection/signature flows to remain usable with protection enabled; use no funded wallet or real transaction.

For Bato’s engine, add deterministic filter tests for first/third-party and resource-type rules, exception precedence, one cosmetic rule and one replacement/scriptlet case. Verify global disable and per-site disable bypass every Bato filtering layer, including injection after reload. Proposed Profile-scoped exceptions must be consistent across that Profile’s workspaces and isolated from other Profiles. Test offline launch, invalid/partial list updates and last-known-good rollback; list update policy remains a design proposal.
