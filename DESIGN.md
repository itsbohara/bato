# Bato — personal-alpha design

Date: 2026-10-27. Status: approved by the user on 2026-10-27; feasibility work authorized. The user authorized provisional alpha implementation on2026-10-30 while remaining compatibility checks continue. That authorization does not establish compatibility or production foundation readiness.

Source of product decisions: the local ideastorm planning checkout, under `/Users/itsbohara/code/ideastorm/concepts/bato/` (`README.md`, `HANDOFF.md`, and `references.md`). These private-workspace references are not part of this public repository; confirmed product behavior is captured below. **Confirmed** means the user has decided it. **Proposed** labels below identify recommendations in the original draft. The user approved this draft and its proposed defaults/experiment on 2026-10-27. Approval authorizes the work; it does not demonstrate engine or extension compatibility.

## Goal and scope

**Confirmed:** deliver a native Swift macOS browser over Chromium that Mahesh can use daily on Apple Silicon. Preserve the Arc-style organization and interactions he depends on. The first milestone is a personal alpha on his Mac mini; public release follows reliability work.

AI chat is V2. Sync is deferred to V2/V3. Intel, Little Arc, automatic workspace routing, and layouts beyond two-page splits are deferred. CEF, a custom Chromium integration, a blocker implementation, and minimum macOS version are not yet selected. The user selected the MIT license for Bato.

## Confirmed browsing experience

| Area | Required behavior |
| --- | --- |
| Visual direction | Closely follow Arc’s layout, proportions, rounded page area, spacing, and motion, with Bato branding and customizable workspace colors. |
| Workspaces and Profiles | Each workspace selects one Profile. Workspaces sharing a Profile share cookies/login state; different Profiles isolate them. |
| Sidebar | Profile-wide Favorites, then workspace-specific pins/folders, then temporary tabs. Resizable, permanently visible or revealed from the hidden state by left-edge hover. `Cmd+S` toggles visibility. |
| Saved entries | `Cmd+W` unloads a Favorite or pinned page while preserving its sidebar entry. Reopening loads its saved URL. Removing a saved entry requires an explicit remove/unpin action. |
| Archive | Optional inactivity-based archival with a configurable period in Settings. Excludes Favorites and pins. Archived tabs can be found and restored. |
| Command bar | `Cmd+T` opens floating URL entry, web search, open-tab search across workspaces, direct switching, and browser commands. |
| Split | Two pages side by side with a draggable divider; save a pair as a pinned item. |
| Peek | Dismissible link-preview overlay that can be promoted to a normal tab. Exact trigger behavior is proposed below. |
| External links | Open in the current workspace. |
| Extensions | Chrome extension installation and use. Bitwarden, AdGuard AdBlocker, and MetaMask are first-alpha compatibility targets. |
| Blocking | Built in and enabled by default; persistent per-site exceptions and an enable/disable control. Capability similar to uBlock Origin is desired, not yet proven. |
| Import | Import Arc Spaces, folders, Favorites, pins, and organization. No promise to transfer passwords, logins, or cookies. |
| Storage | Local on one Mac; no V1 sync. |
| Development | Delegate bounded research and implementation tasks to subagents; keep decisions, integration, review, and concise results in the main chat. |

## Architecture proposal and selection gate

**Proposed:** Swift owns the application model, navigation orchestration, sidebar, command bar, settings, and workspace organization. Use AppKit at the native browser-view boundary; consider SwiftUI for appropriate chrome/settings surfaces after focus, accessibility, and embedding tests. This division is a proposal, not a locked framework choice.

A narrow engine adapter should expose Profile creation, page creation/navigation, title/favicon/load state, permission and download events, popup/new-window requests, extension UI, and renderer lifecycle. The adapter must preserve the engine’s process and sandbox model. It must not reproduce web security logic in Swift.

The Chromium integration remains deliberately unresolved. Review [Chromium feasibility](CHROMIUM-FEASIBILITY.md) before selecting it. Current research flags a material CEF constraint: the native parent-view embedding path and the Chrome-style extension UI path may not provide the same capabilities. Resolve this against the selected CEF version and an actual experiment; do not assume an adapter can combine them. A small native integration experiment must demonstrate:

1. Real native page embedding, keyboard focus, input, resizing, fullscreen, and popup/new-window handling.
2. Persistent Profile storage; shared login within a Profile and isolation across Profiles, including Peek and split views.
3. Bitwarden installation, popup, unlock, content-script operation, and actual autofill after restart.
4. AdGuard installation, rules/filter operation, popup/settings, and persisted configuration.
5. MetaMask installation/onboarding, lock/unlock, origin-specific connection prompt, and an explicitly initiated test-only signing flow. No real funds or production seed phrases are needed to validate compatibility.
6. Engine process shutdown/restart and a distributable Apple Silicon application bundle.

An extension loading successfully is not a pass for its behavior. Record the exact engine and extension versions and reproducible steps. A failed gate leads to a revised integration proposal rather than silent feature reduction.

## Proposed state model

Stable IDs identify Profiles, workspaces, saved entries, temporary tabs, splits, and archive records. A Profile owns engine data and Favorites. A workspace owns pins, ordered folders, temporary tabs, color, and active selection. A saved entry has a saved URL independent of its loaded page’s current URL. A split contains two page references and a divider ratio.

Engine cookies, credentials, and site data stay in engine-managed Profile storage. Application organization and preferences use a versioned local store; SQLite is a candidate, not a selected dependency. Do not copy engine credential databases into exports or invent a password store.

Persist ordering, saved URLs, active workspace, split relationships, archive state, and blocker exceptions. Temporary tabs persist their most recent navigated URL. Changes should commit transactionally; a renderer crash must not remove its sidebar entry.

**Proposed saved-tab details:** navigating within a loaded saved tab updates the session URL without changing the saved URL. An explicit “Update saved URL” action changes the saved destination. Switching away and back retains the live page; unloading and reopening uses the saved destination. Saved split pairs reopen both saved destinations. Closing the focused side of a split unloads/removes that page according to whether its backing entry is saved or temporary, and leaves the surviving page usable; exact split controls should be reviewed in the UI design.

## Proposed alpha defaults

| Topic | Recommendation | Reason |
| --- | --- | --- |
| Archive initial setting | Off; offer a configurable inactivity period when enabled. | Avoid unexpectedly moving the first user’s imported or newly opened tabs. |
| Peek trigger | Explicit context-menu “Open in Peek” and `Shift`-click on eligible normal HTTP(S) links. Normal and `Cmd`-click retain ordinary navigation/new-tab behavior. | Predictable starting behavior without automatically intercepting arbitrary site links. Validate modifier behavior on real sites. |
| Peek lifecycle | Same Profile as its parent page, one overlay per window; Escape/outside dismissal closes it; promotion retains its live page and Profile. | Keep authentication and navigation continuity. Prompt when a page reports unsaved work. |
| First launch | One local Profile and workspace; optional Arc import. | Provide a usable browser without a setup interview. |
| Restore | Restore organization and last active workspace, with inactive pages loaded lazily. Temporary pages reopen at their latest URL; unloaded saved entries stay unloaded. | Recover the working set without loading everything immediately. |
| Crash recovery | Offer last-session recovery after abnormal termination; retain the previous recovery snapshot until a successful subsequent launch. | Avoid overwriting the only recoverable state on a crash loop. |
| Backup | Transaction-consistent snapshots of app organization/settings; retain seven rolling daily snapshots and one pre-import/pre-migration snapshot. | Bound storage while preserving recovery points. Engine data backup remains a separate design problem. |
| Export/import | Explicit versioned organization/settings export and import, with clear scope. No passwords, cookies, extension secrets, or guarantee of live page state. | Make the export understandable and safe to restore. |
| First-alpha distribution | Run a local development `.app` on Mahesh’s mini. Broader distribution waits for signing/notarization, update handling, and release review. | Match the first-user milestone. |
| Minimum macOS | Initially build/test on the mini’s installed OS; establish the supported deployment floor after selecting the engine/SDK. | Do not make an unsupported compatibility promise. |
| Blocker controls | Keep the confirmed per-site control; add a global Settings switch and managed filter updates. | Make failures diagnosable and blocking maintainable. Update verification and failure policy depend on the selected engine. |

The user approved these defaults together with the design on 2026-10-27. Do not repeat already answered product questions individually.

## Extension and blocker behavior

**Proposed:** scope extension installation, settings, and permissions to the selected Profile. Expose extension management and an action menu that can show required popups without leaving the native browsing surface. Display the active Profile wherever an extension approval could otherwise be ambiguous.

Built-in blocking and AdGuard are separate controls. A Bato per-site exception must not claim to disable AdGuard; AdGuard’s exception must not imply that Bato blocking is disabled. Both may be active. Diagnose double filtering with explicit controls and verify behavior with each alone and both together. Do not silently disable a required extension or the confirmed default-on built-in blocker. See [import and blocking research](IMPORT-AND-BLOCKING.md) before choosing the blocker backend.

Only deliberate user interaction can authorize extension permission grants, wallet connections, signing, or unlocking protected credentials. Popups and permission prompts must remain correctly associated with their originating Profile and page even when workspace selection changes.

## Arc import proposal

Read a user-selected Arc data file or copied fixture without modifying Arc’s originals. Parse into a staging model, show an organization preview and unsupported-data summary, then apply the accepted import as a transaction. Preserve folder ordering, Spaces/workspaces, Profile associations, Favorites, and pins where the format supports them. Report unsupported or malformed items rather than dropping them silently.

Create a pre-import snapshot. Import into newly created Bato organization by default to avoid overwriting existing content. A second import should not silently duplicate or replace the first; offer a preview and an explicit choice. Cookie/password/session migration is outside this importer’s promise.

## Daily-use browser baseline

**Proposed alpha acceptance scope:** back/forward/reload/stop, editable URL display and copy, page find, zoom, history, reopen closed temporary tabs, downloads with destination/progress/failure state, file upload, printing/save-page support if exposed by the engine, and a visible loading/error state. Search provider must be configurable; the initial provider remains to be selected during design review.

Handle HTTP redirects, authentication, redirects from OAuth flows, ordinary `window.open`, file chooser dialogs, JavaScript dialogs, clipboard permissions, camera/microphone, notifications, fullscreen/media, and OS external-protocol requests. Associate permissions with origin and Profile; permit later revocation. Preserve engine certificate validation and security interstitials. Extension or wallet popups must never be presented as ordinary trusted application commands.

Support a single primary browsing window initially; define subsequent-window requests deterministically through the engine/window coordinator. Window and multiwindow behavior must be checked in the feasibility experiment before promising daily-use readiness. Registering Bato as the default browser should be an explicit user action.

Keyboard focus must move correctly among chrome, command bar, web content, extension popups, Peek, and split sides. Provide accessible labels and native menu equivalents. Follow system appearance and reduced-motion settings. A hidden sidebar must be reachable with the keyboard as well as hover.

## Failure and recovery behavior

| Failure | Proposed behavior |
| --- | --- |
| Renderer termination | Keep organization and selection; show a reload action for the affected page. Unaffected pages continue where engine isolation permits. |
| Engine crash | Preserve committed app state; restart or relaunch with a clear recovery path. Do not enter an automatic crash loop. |
| Store migration error | Leave the prior store intact, retain the pre-migration snapshot, show actionable recovery details. |
| Disk full / failed save | Surface the failed persistence operation; avoid claiming changes are saved; preserve a recoverable prior transaction. |
| Broken filter update | Keep the last verified usable filter set and report stale/update state. |
| Import error | Abort the uncommitted import or report partial unsupported items before user acceptance; never modify Arc’s source. |
| Extension failure | Show the affected extension/Profile and allow reload/disable through management; do not erase its state automatically. |
| Failed navigation/download | Present an error and retry action; retain destination and relevant metadata without logging secrets. |

Diagnostics should record versions, operation type, and sanitized errors. Full URLs, page content, browsing history, extension secrets, and private reference screenshots should not be published in bug reports by default.

## Review and delivery gates

On2026-10-30, the user approved starting provisional application implementation alongside remaining engine/extension acceptance. This changes implementation sequencing; the compatibility and daily-use requirements below remain in force.

1. **Design review — complete:** the user approved this draft’s proposed behavior and architecture experiment on 2026-10-27. Keep requirements fixed unless the user changes them.
2. **Feasibility:** native embedding and the three required extensions meet the explicit gates above; Profile isolation and persistence pass. Record limitations with evidence.
3. **Foundation selection:** choose the Chromium integration and blocker with maintenance, license, binary size, storage, and update constraints understood. Name the owner of Chromium security refreshes before broader distribution.
4. **Application implementation:** use the application repository at [itsbohara/bato](https://github.com/itsbohara/bato), locally `/Users/itsbohara/code/project-bato/bato`, then deliver incremental usable browser behavior with focused subagents and integrated verification. The application is MIT-licensed; dependencies retain their own terms.
5. **Personal alpha:** import a copied Arc fixture, complete daily-use workflows, validate saved-URL reopening, archive controls, splits/Peek, blocker exceptions, extensions, and restart/crash recovery on the mini.
6. **Public-release readiness:** address distribution, signing/notarization, supported OS floor, engine/application updates, licenses/notices, and wider compatibility before making public support claims.

The coordinator verified the current build host as `mahi.local`, Apple Silicon, macOS 27.0.1, with Xcode selected and approximately 13 GiB disk available. This is an observation on 2026-10-27, not a supported deployment target. Recheck space before fetching engine binaries; a full Chromium source/build route needs a separate storage feasibility decision.

No pass is inferred from a README, a screenshot, source inspection, or an extension merely appearing in a list.
