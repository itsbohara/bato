# Milestone 2 results: downloads, site permissions, external protocols, default browser

Run 2026-11-07. Plan and baseline: MILESTONE2-PLAN.md. Not committed. No Ardia code; UI follows the existing Settings pane layout (Dia captures 10, 16).

## Changes

- V1 (command bar): `CommandBarController` now uses a plain `NSTextField` with its own magnifier `NSImageView` in a stack instead of `NSSearchField` with a cell subclass. Cause of the earlier failure: the `searchTextRect` override was not in the path that positions the typing editor (not isolated further).
- Engine (`engine.patch`, manifest unchanged at 17 files, `test_patch.py` 4 tests OK): `chrome_pages.cc` offers private command id 1000001 to the CEF client from `ShowSiteSettingsImpl` and from `ShowSettingsSubPageInTabbedBrowser` for `content*` sub-pages.
- Client: id 1000001 maps to Swift command 30; `ValidCreateDestination` accepts the site-settings subtree; `simple_handler.cc` returns a `CefResourceRequestHandler` with `OnProtocolExecution` allowing OS execution for non-engine schemes; `Info.plist.in` declares `http`/`https` URL types and HTML document types (client patch now 41 files, 36 mirrors).
- Swift: `BrowserEssential.sitePermissions` plus `siteSettingsURL(for:)` (allowlist: `chrome://settings/content[/...]`, `siteDetails?site=<origin>` only); `PageRuntime.openSiteSettings`; `NativeWorkspaceController.openSiteSettings`/`openExternalURL`; new `BatoCore/DefaultBrowser.swift` (injectable status and register); Settings > Privacy "Site permissions" group with Manage; Settings > Advanced "General > Default browser" row with "Make Bato Default"; `ExternalURLRouter` in `WorkspaceSlot.swift` replaces `application:openURLs:` on Chromium's app delegate for plain HTTP(S) links.
- Fixtures: `spikes/fixtures/downloads_server.py` (port 18768: small, slow 8 MB, large 48 MB, failing), `www/downloads.html`, `permissions.html`/`.js`, `protocols.html`.

## Process

`native_slot.py check` passed (58 files); `swift test` 161 XCTest tests plus 158 Swift Testing tests, 0 failures (`logs/m2-swift-tests.log`; new: 2 essentials, 1 runtime, 5 DefaultBrowser). `build --execute` succeeded (pid 30480; segment `logs/m2-build-segment.log`, which is short because siso reused its daemon). Real host: baseline `tmp/launch-m2-v1.py` (old binary) and `launch-m2-v2.py` (new binary), `--use-mock-keychain`, guards chained from `logs/recfix-v5-exit.json` then `m2-v1-exit.json`, quit via "Quit Chromium", both exit 0 (`logs/m2-v{1,2}-exit.json`); v2 shows 1 `cef-shutdown-complete`, no `refused`/`mismatch`. Note: v2 reused `runtime/m2-state-v1` (my seeded copy of recfix-state-v1, already used by v1) because the wrapper substitution missed the state path; `runtime/m2-state-v2` is unused. Screenshots `logs/m2-shots/`.

## Results

| # | Check | Result |
| --- | --- | --- |
| 1 | V1 command bar glyph (v2, Cmd-T + long text) | PASS. Text starts clear of the magnifier, vertically centred (`20-cmdbar.png`). |
| 2 | Download progress/done bubble, small and slow (v1, v2) | PASS (Chromium stock). Files in ~/Downloads. |
| 3 | Failing download | PASS (stock): "Couldn't finish download" with Resume; chrome://downloads "Failed - File incomplete". |
| 4 | "Full Download History" | PASS: tracked Download History row (F1 route). |
| 5 | Downloads per Profile | PASS: Clients Profile had no icon and empty history while Personal listed three. |
| 6 | Permission prompts (notifications, clipboard, camera) | PASS (stock chips/bubbles); granted and denied states persist. Geolocation not exercised (OS location prompt). |
| 7 | Revocation | PASS: page-info toggle and Reset permissions. |
| 8 | Per-origin and per-Profile permissions | PASS: other origin and the Clients Profile report `prompt`; Clients siteDetails showed Notifications "Ask" while Personal had "Allow". |
| 9 | Page info "Site settings" (v1 vs v2) | v1 FAIL: untracked Chromium tab. v2 PASS: command 1000001 routed, tracked row in the window's Profile, organization.json holds `chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A18765`. |
| 10 | Settings > Privacy Manage | PASS: tracked `chrome://settings/content` row in Personal. |
| 11 | `mailto:` link (v1 vs v2) | v1 FAIL: row navigated to ERR_UNKNOWN_URL_SCHEME. v2 PASS: row unchanged, Chromium launched the OS handler (Apple Mail compose window; console "Launched external handler"). I discarded the draft; Mail stays running. Chromium shows no confirmation for mailto. |
| 12 | Unregistered custom scheme | PASS: no error page, row unchanged, nothing launched, no dialog. |
| 13 | `tel:` link | Not exercised in v2 (would launch FaceTime). v1 showed the same error as mailto. |
| 14 | Default browser plumbing | PASS. `lsregister -dump` lists `claimed schemes: http:, https:` for the app; Settings > Advanced shows "Bato isn't your default browser" and the Make Bato Default button. The button was NOT clicked; system default is still Dia (`urlForApplication` for http/https = Dia.app). Click path covered only by 5 unit tests with fakes. |
| 15 | `open -a <app> http://...` (v1 vs v2) | v1 FAIL: untracked Chromium tab. v2 PASS: `external-url-routed requested 1 opened 1`, new selected "Bato compatibility fixtures" row. |
| 16 | Quit and lifecycle | PASS (exit 0 each run). |

## Defects and open items

1. Settings > Privacy lists the "Site permissions" group between blocking and the "No sites are excluded from blocking" caption, so the exceptions text appears under the wrong group (low; reorder in `privacyPane`).
2. Links macOS hands Bato while it is starting (cold launch) are not routed: the swizzle installs after the workspace exists, so Chromium opens them in an untracked tab. Needs an earlier hook (medium, once Bato is the default browser).
3. Bundle id is still `org.cef.cefsimple` and the app is unsigned; the default-browser change and its confirmation have only been checked as far as registration, not end to end.
4. Chromium confirmation dialog for non-allowlisted external schemes was not seen (no installed handler for the fixture scheme); only mailto's direct launch was observed.
5. Chromium user-education promos ("Make Chromium faster") appear on a fresh Profile window; Chromium branding in omnibox chip text. Not addressed.
6. The download button moves into the toolbar overflow chevron at a 760 pt window; stock behaviour. Downloads go to ~/Downloads with no Save As prompt.
7. No Bato-native per-origin permission list or sidebar downloads indicator (needs engine exports; Dia captures show neither).
8. Row title for site settings is the page's title ("Settings", later "Settings - Site settings").
