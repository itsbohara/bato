# Built-in blocking plan

Planning only (2026-11-07). Nothing here was built or run. Labels: **[V]** verified in the pinned checkout or a cited source; **[A]** assumption to test; **[D]** decision for the user.

## Requirements (DESIGN.md, confirmed)
Enabled by default; global Settings switch; persistent per-site exceptions; uBlock-Origin-like capability desired but unproven. Built-in blocking and the AdGuard extension are independent controls and must be tested alone and together. No telemetry; filter updates must be diagnosable.

## Reference approach: Ardia (GPL-3.0, idea only, no code used)
- **[V]** Ardia README: "full uBlock Origin is built in", Chromium 156 with a patch series (https://github.com/mantrakp04/ardia). It first used uBlock Origin Lite (MV3, as a component extension) and moved to full uBO (its docs/ardiacore-parity.md).
- **[V]** `packages/ardiacore/scripts/ubo.sh`: downloads the official `uBlock0_<ver>.chromium.zip` from gorhill/uBlock GitHub releases, checks a pinned SHA-256, patches manifest/JS (pins an extension key, strips the subscribe/updater content scripts, hardens the diff-updater), and loads it per profile as a component extension. A navigation hold keeps a profile's first navigations back until the extension is ready. A second engine patch removes Helium's own uBO so two engines never filter each request.
- **[V]** Its docs describe a hook in Chrome's DNR `ActionTracker` to report blocked requests per tab. Same seam exists here (below).
- Lesson for Bato: the extension route needs load-ordering (race at first navigation), a stable extension ID/key, and a policy for the extension's own UI versus Bato's exception UI.

## Seams in this checkout (src = /Volumes/Mahesh/personal/bato-build/source/chromium/src) [V]
| Seam | Evidence | Fit |
| --- | --- | --- |
| CEF resource request handler | `cef/include/cef_request_handler.h:141` `GetResourceRequestHandler` ("called on the browser process IO thread"); Chrome-style factory interception in `cef/libcef/browser/chrome/chrome_content_browser_client_cef.cc:482` `WillCreateURLLoaderFactory` (only for CEF-created Profiles) | Public API, no Chromium patch, per-request URL/type/initiator. Network-only. |
| Chromium subresource filter | `components/subresource_filter/` (flatbuffer indexed ruleset, `core/common/indexed_ruleset.*`, `content/browser/ruleset_service.h`, throttles); helper created for every tab in `chrome/browser/ui/tab_helpers.cc:324`; per-site allow via `ContentSettingsType::ADS` (`.../subresource_filter_content_settings_manager.cc:67-74`); offline tooling `components/subresource_filter/tools/` (`indexing_tool`, `ruleset_converter`); EasyList-derived data `third_party/subresource-filter-ruleset` (README: CC-BY-SA-3.0) | BSD, mmap'd, fast. Activation is gated by Safe Browsing metadata / field-trial configs (`activation_scope` param, `subresource_filter_features.cc:160`) and rulesets arrive via component updater; a local-ruleset publisher and all-sites activation need an engine patch [A]. Network (subresource/subframe) only; no cosmetic/scriptlets. |
| DNR via a Bato-owned extension | `extensions/browser/api/declarative_net_request/` (+ `filter_list_converter/`, converts ABP lists to DNR JSON); limits in `extensions/common/api/declarative_net_request.webidl:884-926` (30,000 guaranteed static rules, 100 static rulesets / 50 enabled) | Uses the extension machinery already exercised (Bitwarden/AdGuard evidence in FEASIBILITY-RESULTS.md). Rule caps cap list size; cosmetic via content script. |
| Full MV2 uBO | `extensions/common/api/_permission_features.json:847` `webRequestBlocking` is `max_manifest_version: 2`; `extensions/common/switches.cc:16` `--allow-legacy-extension-manifests`; `chrome/browser/extensions/manifest_v2_handler*` | MV2 loading is gated. Whether it works at 156 in CEF Chrome style is **[A]** (Ardia ships it on 156, with its own patches). |

Engine args (`out/Debug_GN_arm64/args.gn`) are Chrome-style with extensions enabled, and Bato already carries a patch overlay (`spikes/engine-native-slot/engine.patch`, 8 files), so a small additional patch is within the existing process but costs a rebuild.

## Candidates
| Option | License | Capability | Perf / risk |
| --- | --- | --- | --- |
| A. Full uBlock Origin as an installed extension | GPL-3.0 (gorhill/uBlock; lists in uAssets also GPL-3.0) | Best: network, cosmetic, scriptlets, dynamic filtering | Needs MV2 enablement (Chromium is removing it), webRequest slows request path, load race, extension UI vs Bato UI, double-filtering with AdGuard. Highest upstream drift risk. |
| B. uBOL-style MV3 DNR ruleset in a Bato component extension | Rules from EasyList/EasyPrivacy: GPL-3.0+ or CC-BY-SA-3.0 (dual, https://easylist.to/pages/about.html; also `third_party/subresource-filter-ruleset/LICENSE`). uBOL itself is GPL-3.0 (not used) | Network + redirect stand-ins + CSS cosmetic; no procedural cosmetic/scriptlets | Browser-native matching, no per-request JS. Rule caps. Per-site exception = dynamic `allowAllRequests` rule per host (Profile-scoped, persisted by Chromium). |
| C. Chromium subresource_filter + EasyList | BSD (Chromium) + list license as above | Network only | Best perf and memory; patch needed for local ruleset + activation. Exceptions via `ContentSettingsType::ADS` per Profile. |
| D. Brave adblock-rust via C ABI in a CEF handler | MPL-2.0 (file-level copyleft: compatible with an MIT app when linked as a separate library; modified MPL files must be published). Brave's `adblock-resources` also MPL-2.0 | Network + cosmetic + uBO-syntax + scriptlet resources; cosmetic/scriptlet delivery needs Bato-side renderer injection [A] | Engine is fast (Brave's production blocker) but runs in our process on the handler thread; needs Rust toolchain in the build, C ABI, immutable-engine swap on list updates. Redirect/worker/cached coverage is **[A]**, must be tested. |
| E. Install AdGuard only | GPL-3.0 libs, but installing the extension is the user's own act | Already passed narrowly (FEASIBILITY-RESULTS.md) | Not a "built-in default"; keep as separate control. |

## Licensing assessment (not legal advice)
- Bato is MIT. GPL-3.0 uBO or AdGuard code cannot be *linked into or derived into* Bato code without making that combination GPL.
- Shipping an unmodified uBO package as a separate extension that talks to the browser only through Chrome extension APIs is generally treated as aggregation (https://www.gnu.org/licenses/gpl-faq.html#MereAggregation). The obligations then attach to the uBO bytes: ship its license, offer corresponding source for anything modified (Ardia patches it, which triggers this). The disk image becomes a mixed-license distribution; the MIT repo itself stays MIT. Safest variant: do not bundle; first-run downloads the pinned upstream release (checksum-verified, like Ardia's script) after a user action. **[D]**
- EasyList: dual GPL-3+/CC-BY-SA-3.0. Fetching lists at runtime from upstream avoids redistribution. Bundling an offline seed list needs attribution and keeps the list (not the app) under CC-BY-SA; compiled DNR/ruleset outputs are adaptations of the list.
- adblock-rust and adblock-resources (MPL-2.0) are compatible with bundling; keep notices and publish modifications to MPL files. Pin versions; adblock-rust publishes on crates.io (GitHub shows no releases).
- Chromium ships `third_party/subresource-filter-ruleset` with EasyList credits in chrome://credits; copy that practice.

## Recommendation
**Primary: option D (adblock-rust) behind a Bato-owned `BlockingEngine` seam**, not a Chromium patch, because: permissive-enough license, no MV2 dependency, no rule-count cap, uBO-compatible syntax, exceptions and Profile scope fully under Bato's persistence, and the only engine patch needed is none (CEF handler is public). Keep **C** as the fallback if D shows coverage gaps in the spike (it is the only one with Chromium-owned redirect/worker/frame coverage). Treat **A** as an optional, user-installed power feature, not the default. Rationale is partly **[A]**: the spike decides it.

## Design
- **Global switch + per-site exceptions**: `BlockerSettings { enabled: Bool, exceptions: [host] }` stored per Bato Profile (exception applies to every workspace sharing that Profile). Matches DESIGN.md "persistent per-site exceptions" and Profile-owned engine data. Exception key: registrable-domain (eTLD+1) of the *top-level* page, not the request URL. Persisted in the organization store (needs a schema bump, version 3, in `app/Sources/BatoCore/BrowserState.swift`, validated with host normalization) **[D: store here vs a separate settings file]**.
- **Engine ownership**: one immutable compiled engine per list-set; background compile on update; atomic swap; callback does lookup only.
- **Lists**: default EasyList + EasyPrivacy + uBlock-filters-compatible resources; fetched from upstream over HTTPS to Bato's cache dir, validated (size, parse count, non-empty), keep last-good; daily check with ETag; failure keeps last-good and shows status in Settings. **[D]** whether any list is bundled as an offline seed and which lists are default.
- **UI**: site-info/shield button in the sidebar navigation header (`app/Sources/BatoBrowserUI/NavigationHeader.swift`, next to the host pill): shows blocked count for this page, toggle "Blocking on this site", link to Settings. Settings pane: global switch, list status/last update, exceptions list with remove. Menu item Page > Blocking. Reload-on-toggle prompt.
- **AdGuard coexistence**: separate labels; Settings copy states built-in exception does not disable extensions.

## Acceptance (synthetic fixtures; extend `spikes/fixtures/server.py` and `spikes/fixtures/www`)
1. Fixture with a custom filter list (not EasyList) blocks: script, image, XHR/fetch, subframe, WebSocket, stylesheet; a control resource from the same page loads (HTTP 200, executes).
2. Third-party only rule blocks cross-origin but not same-origin; `$domain=`/`$important` exceptions honoured.
3. Redirect chain, service-worker fetch, dedicated worker, and cached resource coverage: each recorded pass/fail separately (no inference).
4. Cosmetic: `##.ad` hides fixture element; exception restores it.
5. Per-site exception: toggle persists across clean restart, applies to subdomains, does not leak to another registrable domain or another Profile.
6. Global off, then on: no restart needed or the prompt is accurate.
7. List update: corrupt/oversized/empty download rejected and last-good kept; engine swap during active page loads does not drop requests.
8. AdGuard alone / built-in alone / both: block counts reported separately; no breakage of a fixture login page.
9. Perf: compile time and resident memory of the default lists on the mini; added per-request latency on a 500-request fixture page; budgets set from the baseline run, not guessed.
10. Privacy: no URLs leave the machine except list fetches; no per-site telemetry. Verify with a recorded network capture.

## First bounded milestone (1-2 days, source-only plus fixtures)
Spike `spikes/blocking/`: Rust crate + C ABI wrapper around adblock-rust (version pinned, license notices recorded), a Swift/C++ shim called from a CEF `GetResourceRequestHandler` in the existing native-slot host, one fixture list, checks 1, 2, 3 and 9 only, recorded in `spikes/blocking/RESULTS.md`. Exit criteria: works for main/sub/XHR/worker, otherwise switch to C and scope the engine patch. No UI, no persistence, no list download yet.

## Decisions needed
1. License posture for uBO (not bundled / bundled-as-separate-GPL-component / not offered).
2. Approve adblock-rust (MPL-2.0) plus Rust in the build as first spike, with Chromium subresource_filter as fallback.
3. Default lists and whether an offline seed is bundled (CC-BY-SA attribution).
4. Where exceptions persist (organization schema v3 vs settings file).

## Decisions (2026-11-07)

- Engine: adblock-rust spike first, behind a Bato blocking-engine layer; subresource filter is the fallback.
- uBlock Origin: offered as an optional user-initiated download of the official release on first run; never bundled or modified by Bato.
- Per-site exceptions: separate per-Profile settings file, not the organization schema.
