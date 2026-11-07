# Alpha gaps

Refreshed 2026-11-07 against main (9d4c57e) plus the uncommitted Swift batch 6 (search provider, workspace delete, Peek polish, About and notices). Walks DESIGN.md "Proposed alpha acceptance scope" and the personal-alpha milestone, re-evaluated against the results docs in `spikes/engine-native-slot/` and git log. Paths below are relative to `spikes/engine-native-slot/` unless they start with `app/` or the repo root.

Status: **done** (real-host evidence), **partial**, **missing**, **unverified** (code or tests exist, never seen on the real host). "Code-only" means unit-tested Swift that has not run on the host; see SWIFT-BATCH6-NOTES.md for the checks it needs. Effort: S under a day, M a few days, L a week or more. "Engine" means a Chromium/CEF rebuild.

## Daily-use baseline (DESIGN.md "Proposed alpha acceptance scope")

| Item | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Back/forward/reload/stop, loading/failure state | done | NAV-HEADER-RESULTS.md; COMMANDS-RESULTS.md #11 (Cmd-R reloads the active page) | Failure tint clears within seconds on auto-reload (S, client) |
| Editable URL display and copy | done | NAV-HEADER-RESULTS.md, COPY-LINK-RESULTS.md | Cmd-Shift-C needs a physical-key check (S) |
| Page find (open pages) | done | COMMAND-BAR-RESULTS.md, page-search-evidence.json | None |
| In-page find (Cmd-F) | done | COMMANDS-RESULTS.md #12 | None |
| Zoom | done | COMMANDS-RESULTS.md #13 | None |
| History | done | ESSENTIALS-POLISH-RESULTS.md, F1-RESULTS.md | None |
| Reopen closed temporary tabs | done | COMMANDS-RESULTS.md #5, #6; MILESTONE4-RESULTS.md #3 (Recently Closed position 0) | Stack is in memory per Profile, not kept across relaunch; Recently Closed rows older than Bato's stack do nothing |
| Downloads: destination, progress, failure | done | DOWNLOADS-RESULTS.md #1-10 (sidebar button, popover, pause/resume/cancel, failure + Resume, per-Profile, Finder/Open); MILESTONE4-RESULTS.md #6 (popover sizing); MILESTONE2-RESULTS.md #2-5 | Dangerous/insecure warning with Keep/Discard never triggered on the host (#11, no file-type danger policy in this build); no Save As prompt, files go to ~/Downloads |
| File upload, file chooser | done | COMMANDS-RESULTS.md #15 | None |
| Printing | done | COMMANDS-RESULTS.md #14 (dialog, preview, Esc) | Save as PDF not exercised (S) |
| Configurable search provider | unverified (code-only) | app/Sources/BatoPersistence/AppPreferencesStore.swift, Settings > General, command bar footer picker; app/Tests/BatoPersistenceTests/AppPreferencesStoreTests.swift | Host check: choose provider in Settings, relaunch, command bar searches with it (S) |
| Redirects/auth/OAuth, window.open, JS dialogs | partial | COMMANDS-RESULTS.md #16 (OAuth-style popup + postMessage + window.close); MILESTONE3-RESULTS.md #2 (compact popup); PEEK-RESULTS.md (beforeunload) | HTTP auth dialog, alert/confirm/prompt, real OAuth provider never exercised (M) |
| Permissions tied to origin + Profile, revocable | done | MILESTONE2-RESULTS.md #6-10 (prompts, revoke, per-origin, per-Profile, Settings > Privacy Manage) | Geolocation not exercised (OS prompt); no Bato-owned permission UI, Chromium's pages are used |
| External-protocol requests, default browser | partial | MILESTONE2-RESULTS.md #11-12, #14-15 (mailto launches handler, unknown scheme silent, http(s) claimed, `open -a` routed); MILESTONE3-RESULTS.md #4; PACKAGING-RESULTS.md #5 (LaunchServices cold launch tracked) | "Make Bato Default" never clicked on the host; Chromium's confirmation for non-allowlisted schemes never seen; `tel:` not run |
| Certificate interstitials preserved | done | COMMANDS-RESULTS.md #17 | Advanced > proceed and HSTS not covered |
| Multi-window / Profile windows | done | PERPROFILE-SWITCHER-RESULTS.md, POLISH3-RESULTS.md | E2/E3 below |
| Keyboard focus among chrome, command bar, content, popups, Peek, splits | partial | Hidden-sidebar shortcuts done (GEOMETRY-RESULTS.md); Peek AX labels added (code-only, SWIFT-BATCH6-NOTES.md); split focus open (SPLIT-PAIRS-RESULTS.md) | Peek focus order on host; split focus; Tab traversal lands on the native address field (RESUME) (M-L, may need engine) |
| Accessible labels, reduced motion, appearance | partial | Light/dark live switch verified (MILESTONE4-RESULTS.md "Also checked"); contrast-safe tints (LIGHTMODE-NOTES.md); sidebar AX controls | Increase Contrast and Reduce Transparency live toggles and the six-point LIGHTMODE checklist not run on host; reduced motion not addressed; Chromium's own toolbar is stock |
| Hidden sidebar keyboard reachable | done | GEOMETRY-RESULTS.md | None |

## Personal-alpha milestone (DESIGN.md step 5)

| Item | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Import copied Arc fixture | done (synthetic) | spikes/arc-import/RESULTS.md, RESUME integrate-v2/v3 | Run against a real copied Arc profile (S) |
| Saved-URL reopening | done | SPLIT-PAIRS-RESULTS.md, saved-destination-evidence.json | None |
| Archive controls | done | MILESTONE4-RESULTS.md "Archive (v2)" (launch sweep, sheet, Restore at old index); ARCHIVE-UBLOCK-NOTES.md | beforeunload Cancel on an archived loaded page, 5-minute sweep timing, Settings pane layout unexercised; no Arc-style sidebar section; archive unbounded |
| Splits | partial | Menu resize and persistence (SPLIT-PAIRS-RESULTS.md); pointer divider drag PASS with a physical drag (MILESTONE4-RESULTS.md #5) | Keyboard resize, focus, divider with an extension loaded |
| Peek | partial | PEEK-RESULTS.md (present, input block, scrim, beforeunload, promotion, shift-click); Swift batch 6: AX labels and group role on Peek controls, distinct "Peek already open" status (code-only) | Context-menu "Open in Peek" needs an engine hook (no export carries a link context menu; see SWIFT-BATCH6-NOTES.md); focus order; Cmd-click background-tab spot-check inconclusive; second-Peek refusal only visible via link trigger |
| Blocker exceptions | done | PER-PROFILE-NOTES.md, PERPROFILE-SWITCHER-RESULTS.md | E1 unfiltered first load in a fresh Profile (S-M) |
| Extensions | partial / deferred | spikes/EXTENSION-TEST-PLAN.md, FEASIBILITY-RESULTS.md | User deferred; Bitwarden/MetaMask popups open (L, may need engine) |
| Restart / crash recovery | done (host-verified for engine crash) | RECOVERY-RESULTS.md (kill -9, sheet before pages, Keep/Restore, no crash loop, rolling backups, staged restore, clean quit) and its "Fix verification" | Renderer-process kill, daily rollover/prune, blocking-settings restore (R4), `version 9` text unverified |

## Open gates

| Gate | Status | Evidence | Remaining |
| --- | --- | --- | --- |
| Split pointer divider drag | done | MILESTONE4-RESULTS.md #5 | Earlier "no movement" was synthetic instant drags |
| Fullscreen shows stock tab strip | done | MILESTONE3-RESULTS.md #6; MILESTONE4-RESULTS.md #2 (edge reveal of the sidebar) | Revealed sidebar keeps the traffic-light gap, no animation |
| Window drag | done | MILESTONE3-RESULTS.md #7 | Drag from the Chromium toolbar not retested |
| Cosmetic filtering / scriptlets | partial | MILESTONE4-RESULTS.md #4 (per-frame hide rules, generic class/id rules, same exceptions as request blocking) | No scriptlets, procedural filters or generic rules in subframes (L) |
| uBlock first-run offer | unverified (code-only) | ARCHIVE-UBLOCK-NOTES.md (opt-in uBlock list download, not the extension) | First-run timing against the recovery notice, real download and engine rebuild after Add Lists |
| Sidebar grey behind sheets (F3) | done | MILESTONE3-RESULTS.md #1 (Cmd-P keeps sidebar) | Recovery/launch sheets not re-checked since (RECOVERY-RESULTS.md R2 predates the fix) |
| Chrome menu/keyboard commands reach Bato | partial | COMMANDS-RESULTS.md (Ctrl-Tab, Cmd-1..9, Shift-Cmd-T, Cmd-N, New/Close Tab); MILESTONE3-RESULTS.md #3 (Duplicate, Pin, Close Others, New Tab to the Right, Move to Window) | Close Tabs to the Right, Group Tab, Dock-menu New Window/Reopen (no Browser to offer the command to) |
| Command-bar glyph overlap (N1) | done | MILESTONE2-RESULTS.md #1 | None |
| Increase Contrast read only at launch (N2) | unverified (code-only) | LIGHTMODE-NOTES.md (AppearanceWatcher) | Live toggle on host |
| Footer picker out of sync (E2), Create leaves workspace in launch window (E3) | open | PERPROFILE-SWITCHER-RESULTS.md; superseded UI is the switcher popover (MILESTONE4-RESULTS.md) but E3 (engine window per Profile on create) has no later evidence | Recheck E2 against the popover (S); E3 (M, engine) |
| Profile delete | done | MILESTONE4-RESULTS.md #1 (confirm sheet, window closed, data dir gone, snapshot) | Blocking-settings removal and a Profile with a live download unexercised |
| Workspace delete | unverified (code-only) | `BrowserState.deleteWorkspace`, `PageRuntime.deleteWorkspace` (pre-delete snapshot via `snapshotCommit`), workspace actions menu "Delete Workspace…"; app/Tests/BatoCoreTests/WorkspaceDeleteTests.swift, app/Tests/BatoRuntimeTests/WorkspaceDeleteRuntimeTests.swift | Host check; last workspace of a Profile is refused |
| Pin/Favorite title, copies wording (D5/D6) | done | PER-PROFILE-NOTES.md | None |
| Chromium security updates ownership | missing | DESIGN.md gate 3 | Process decision (L) |
| Signing, notarization, packaging, updates | partial | PACKAGING-RESULTS.md (Bato.app, `com.itsbohara.bato`, placeholder icon, ad-hoc signed, promos suppressed, `open -a` cold launch) | Developer ID, notarization, hardened runtime, updater; titles/omnibox chips still say Chromium; mock keychain mandatory; paths still on the SSD (L) |
| Licenses/notices | partial | NOTICES.md (Chromium, CEF, adblock-rust MPL-2.0, EasyList/EasyPrivacy and uBlock list terms); Settings > About (version from bundle, which carries VERSION; link to notices) | NOTICES.md is not yet copied into the app bundle's Resources (About falls back to the GitHub URL); transitive Rust crate licenses not enumerated; About not seen on host |

## Remaining for personal alpha

1. Run the Swift batch 6 host checks (SWIFT-BATCH6-NOTES.md) in the next real-host cycle: search provider, workspace delete, Peek AX and refusal message, About.
2. Daily-driver trust items still unseen: HTTP auth and JS dialogs, "Make Bato Default" end to end, dangerous-download warning, Increase Contrast live, renderer-crash behaviour.
3. Peek context-menu "Open in Peek": one engine hook (context-menu link callback) then a Swift handler.
4. Ship NOTICES.md and CEF-LICENSE.txt in the bundle Resources (packaging script).
5. Cosmetic leftovers: failure tint persistence, E2/E3, Close Tabs to the Right and Group Tab routing, closed-tab history across relaunch.
6. Move state off the SSD and resolve the production Keychain item before the app is anyone's only browser.
7. Deferred behind these: extensions acceptance, scriptlets, Developer ID/notarization/updater, Chromium refresh cadence.
