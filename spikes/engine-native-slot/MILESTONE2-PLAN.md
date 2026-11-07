# Milestone 2 plan: downloads, site permissions, external protocols, default browser

Written 2026-11-07 before the build, from a real-host baseline on the unmodified binary (`logs/m2-v1.log`, screenshots `logs/m2-shots/` on the SSD, state `runtime/m2-state-v1`). Reference: Dia captures 10 (Privacy) and 16 (Advanced) in `dia/2026-11-01/` for pane layout; no Dia capture shows a downloads, permission or default-browser surface, so Bato adds native UI only inside the existing Settings window and keeps everything else Chromium's. No Ardia code is used.

## Baseline: what Chromium already does under CEF (verified, per Profile)

| Area | Behaviour on the unmodified build | Verdict |
| --- | --- | --- |
| Download start, progress | Toolbar download icon and bubble appear; the bubble lists the file with progress and "Done". Files land in `~/Downloads` (Chromium's default; no Save As prompt). | Keep |
| Download failure | A truncated response shows "Couldn't finish download" with a Resume button in the bubble; chrome://downloads shows "Failed - File incomplete" struck through. | Keep |
| "Full Download History" | Reaches `chrome::ShowDownloads`, which the engine already offers to Bato (F1): a tracked "Download History" row opens. | Keep |
| Per-Profile downloads | The Clients Profile window has no download icon and its chrome://downloads is empty while Personal lists three downloads. | Keep |
| Permission prompt | Notifications, clipboard and camera requests show Chromium's address-bar chip and bubble (Block / Allow) in the Bato window; state persists (`navigator.permissions.query` reports granted / denied). | Keep |
| Revocation | Page-info bubble toggles and "Reset permissions" work; chrome://settings/content/siteDetails shows the per-origin list. | Keep |
| Per-origin and per-Profile storage | `localhost:18765` and `127.0.0.1:18765` are separate origins; the Clients Profile reports `prompt` for the origin Personal granted. | Keep |
| Page info "Site settings" link | **Defect M-A.** Opens `chrome://settings/content/siteDetails?...` as a Chromium tab Bato does not track: the sidebar keeps the old row selected, `organization.json` has no row, the window title becomes "Settings". Same route as the stray tabs in COMMANDS-RESULTS item 3. | Fix (engine) |
| External protocol (`mailto:`, `tel:`) | **Defect M-B.** The row navigates to an `ERR_UNKNOWN_URL_SCHEME` error page ("This site can't be reached") and saves `mailto:...` as the row's URL. No Chromium "Open ...?" dialog, no OS handoff. Cause: CEF routes unknown schemes through the client's `CefResourceRequestHandler`; with none (or `allow_os_execution` left false) the request just fails (`resource_request_handler_wrapper.cc:1164`). | Fix (client) |
| Default browser | **Gap M-C.** `Info.plist` has no `CFBundleURLTypes` or document types, so macOS cannot offer Bato as a web browser. Links opened from other apps (`open -a <app> https://...`) arrive in `-[AppController application:openURLs:]` and become an untracked Chromium tab (**defect M-D**, screenshot 16). | Fix (plist, Swift) |
| Chromium promos | "Make Chromium faster" bubble appears on a fresh Profile window. Out of scope; noted. | Note |

## Decisions

1. **Downloads: no Bato surface.** Everything already works per Profile and "Show all" reaches the tracked row. A sidebar downloads indicator would need new engine download-event exports and Dia shows none in the captures; deferred.
2. **Permissions: keep Chromium prompts, storage and revocation.** Add only the missing route and one Bato entry point.
   - Engine, `chrome_pages.cc`: `ShowSiteSettingsImpl` and `ShowSettingsSubPageInTabbedBrowser` (sub-pages beginning `content`) offer the private id `1000001` to the CEF client before opening a Chromium tab. When the client declines (Chrome-owned active tab), Chromium behaves as before.
   - Client: id 1000001 becomes Swift command 30; Swift opens `chrome://settings/content/siteDetails?site=<origin of the selected page>` (or the all-sites list) as a tracked row in the current Workspace's Profile.
   - Model: `BrowserEssential` gains `sitePermissions`; the allowlist accepts only `chrome://settings/content[/letters-and-slashes]` with, on `siteDetails` only, one `site=<http(s) origin>` query item. The client's page-creation check mirrors it. Everything else under `chrome://settings` stays refused.
   - Settings > Privacy: a "Site permissions" group with a Manage button that opens the list as a tracked row. A native per-origin list is not built: it would need a content-settings export from the engine.
3. **External protocols: let Chromium's flow run.** Client only: `GetResourceRequestHandler` returns a handler whose `OnProtocolExecution` sets `allow_os_execution` for navigations to schemes the engine cannot load. Chromium then shows its own confirmation dialog and keeps the choice per Profile. No Bato dialog.
4. **Default browser: plumbing, never an automatic change.**
   - `Info.plist.in` (client patch): `CFBundleURLTypes` for `http`/`https` and HTML document types.
   - `DefaultBrowser` (BatoCore, injectable, unit tested) reads whether Launch Services hands `http` and `https` to this app and, only from the Settings button "Make Bato Default" (Advanced > General), asks `NSWorkspace.setDefaultApplication` for the schemes not yet ours (macOS shows its own confirmation).
   - Links macOS hands Bato: Swift replaces `application:openURLs:` on Chromium's application delegate; plain HTTP(S) links open as a tracked tab in the current Workspace, anything else (and any link before the workspace exists) keeps Chromium's behaviour. Cold-launch links are not routed in this slice.
5. **V1 (command-bar text overlaps the magnifier).** See "V1" below.

## V1: why the earlier fix did not take effect

The N1 fix subclassed `NSSearchFieldCell` and overrode `searchTextRect(forBounds:)`. The real host showed no effect (screenshot recfix `03-commandbar.png`: text at x=118, magnifier at 124 to 136), so the override is not in the path that positions the field editor while typing: a borderless search cell lays the editor out from `drawingRect(forBounds:)`/`edit(withFrame:)`, not from the search-text rect, and the factory initialiser may also bypass an overridden `cellClass`. The unit-level cause was not isolated (no reproduction outside the host). Rather than override more cell methods, the command bar now uses a plain `NSTextField` plus its own `NSImageView` magnifier laid out side by side in a stack, so the text cannot overlap the glyph by construction.

## Verification plan (real host)

Wrappers `tmp/launch-m2-v1.py` (baseline, done) and `launch-m2-v2.py` (post-build), `--use-mock-keychain`, receipt guard `logs/recfix-v5-exit.json` then the previous run, quit only via "Quit Chromium". Fixtures: `downloads.html` plus `downloads_server.py` (port 18768: small, slow 8 MB, large 48 MB, failing), `permissions.html`, `protocols.html`.

1. V1 glyph clearance (Cmd-T, type a long query).
2. Downloads regression plus per-Profile isolation.
3. Permission prompts, page-info revocation, per-origin and per-Profile isolation; page info "Site settings" now creates a tracked row.
4. Settings > Privacy Manage button opens the tracked row; the row survives relaunch.
5. `mailto:`/`tel:` show Chromium's dialog (cancel; no OS app is launched); unregistered scheme.
6. Default browser: `lsregister -dump` shows `http`/`https` claimed; Settings shows the status; the Make Bato Default button is present but NOT clicked (system default is never changed). `open -a <app> http://...` (does not change defaults) creates a tracked row.
