# Alpha gaps

Written 2026-11-07 against main (d643668). Walks DESIGN.md "Proposed alpha acceptance scope" and the personal-alpha milestone, plus open gates recorded in RESUME.md and the results docs. Status: done (real-host evidence), partial, missing, unverified (code or plumbing exists, never exercised). Effort: S under a day, M a few days, L a week or more. "Engine" means a Chromium/CEF source rebuild is needed (hours of build plus a real-host cycle).

## Daily-use baseline (DESIGN.md "Proposed alpha acceptance scope")

| Item | Status | Evidence | Effort / engine |
| --- | --- | --- | --- |
| Back/forward/reload/stop, loading/failure state | done | spikes/engine-native-slot/NAV-HEADER-RESULTS.md (failure tint clears within seconds on auto-reload) | done; failure persistence S, client |
| Editable URL display and copy | done | NAV-HEADER-RESULTS.md, COPY-LINK-RESULTS.md; Cmd-Shift-C physical-key check unconfirmed | S, client |
| Page find (find open pages) | done | COMMAND-BAR-RESULTS.md, page-search-evidence.json | done |
| In-page find (Cmd-F) | unverified | Stock Chromium chrome; no Bato result doc | S to verify, no engine |
| Zoom | unverified | Stock Chromium; no result doc | S to verify |
| History | done | ESSENTIALS-POLISH-RESULTS.md, F1-RESULTS.md (per Profile, restores) | done |
| Reopen closed temporary tabs | missing | No result doc or UI; Cmd-Shift-T behaviour with Bato rows unknown | M, Swift (closed-tab stack in BrowserState); no engine |
| Downloads with destination/progress/failure | partial | Chromium bubble, progress, failure/Resume and destination work per Profile (MILESTONE2-RESULTS.md). User wants Dia/Arc-style downloads in the left sidebar instead of Chromium's top-right bubble | M, engine export for download events + Swift sidebar surface; suppress Chromium bubble |
| File upload, file chooser | unverified | Not in any result doc | S to verify |
| Printing / save page | unverified | Not in any result doc | S to verify |
| Configurable search provider | partial | Session-local provider only (PROGRESS.md command bar row); Settings Privacy/Advanced panes exist | S-M, Swift persistence |
| Redirects/auth/OAuth, window.open, JS dialogs | partial | beforeunload Leave/Cancel and Peek popups verified; OAuth and auth dialogs never exercised | M to verify |
| Permissions (clipboard, camera/mic, notifications, fullscreen/media) tied to origin + Profile, revocable | unverified | Stock Chromium UI per Profile context; no check and no Bato settings surface | M verify, L if Bato UI wanted |
| External-protocol requests, default browser registration | missing | No evidence | M (default-browser is Swift/Info.plist; protocol prompt maybe engine) |
| Certificate interstitials preserved | unverified | Stock engine; never checked | S |
| Multi-window / Profile windows | done | PERPROFILE-SWITCHER-RESULTS.md, polish3-v1 (4 windows quit clean) | done |
| Keyboard focus among chrome/command bar/content/popups/Peek/splits | partial | Peek focus/AX unpolished (PEEK-RESULTS.md); split focus open (SPLIT-PAIRS-RESULTS.md); Tab traversal lands on native address field (RESUME) | M-L, may need engine |
| Accessible labels, reduced motion, appearance | partial | AX controls on sidebar; Increase Contrast read at launch only (POLISH3 N2); light mode never verified | M |
| Hidden sidebar keyboard reachable | done | GEOMETRY-RESULTS.md (Cmd-S, menu) | done |

## Personal-alpha milestone (DESIGN.md step 5)

| Item | Status | Evidence | Effort / engine |
| --- | --- | --- | --- |
| Import copied Arc fixture | done | spikes/arc-import/RESULTS.md, RESUME integrate-v2/v3 (synthetic data only) | real Arc data check S |
| Saved-URL reopening | done | SPLIT-PAIRS-RESULTS.md, saved-destination-evidence.json | done |
| Archive controls | missing | DESIGN.md Archive row; PROGRESS "not implemented" | M-L, Swift core + UI, no engine |
| Splits | partial | Menu-driven ratio and persistence verified; pointer divider drag and focus not (see below) | M-L |
| Peek | partial | PEEK-RESULTS.md; focus/AX, context-menu Open in Peek, second-Peek refusal open | M |
| Blocker exceptions | done | PER-PROFILE-NOTES.md, PERPROFILE-SWITCHER-RESULTS.md (E1 unfiltered first load in fresh Profile open) | E1 S-M |
| Extensions | partial / deferred | spikes/EXTENSION-TEST-PLAN.md, FEASIBILITY-RESULTS.md; user deferred broad testing; Bitwarden/MetaMask real popups open | L, may need engine |
| Restart / crash recovery | partial | Clean restart verified widely; renderer-crash reload action and engine-crash relaunch not implemented (DESIGN failure table); another agent is currently editing Swift recovery code | M, in progress |

## Open gates from RESUME / results docs

| Gate | Status | Evidence | Effort / engine |
| --- | --- | --- | --- |
| Split pointer divider drag and focus | missing | RESUME: pointer drag produced no movement, AX slider no resize; menu resize works | M-L; likely engine (divider hit-testing in MultiContentsView) |
| Fullscreen shows stock tab strip | open | COMPACT-FOLDERS-RESULTS.md | M, engine |
| Window drag (compact top) | unverified | COMPACT-FOLDERS-RESULTS.md "window drag unconfirmed" | S verify; M if broken (engine) |
| Cosmetic filtering / scriptlets | missing | spikes/blocking/RESULTS.md, PROGRESS Blocking row | L; client (adblock FFI already wired) plus injection hook, maybe engine |
| uBlock first-run offer / optional download | missing | PROGRESS Blocking row | S-M, Swift sheet plus list fetch |
| Sidebar grey behind sheets/command bar (F3) | open | POLISH2-RESULTS.md, POLISH3-RESULTS.md | M, Swift (sheet is a separate window/layer); possibly engine |
| Reload and other menu commands bypass OnChromeCommand | partial | F1-RESULTS.md: only History/Downloads/Settings fixed at chrome_pages; Reload and View menu never reached the handler (logs/f1-v1.log) | M, engine (hook the action layer); gates any new Bato-owned command |
| Command-bar glyph overlap (N1) | open | POLISH3-RESULTS.md | S, Swift |
| Footer picker out of sync (E2), Create leaves workspace in launch window (E3) | open | PERPROFILE-SWITCHER-RESULTS.md | S / M (E3 needs engine window-per-Profile on create) |
| Profile delete | missing | PROFILE-SWITCHER-NOTES.md: no engine data-destroy export; launch Profile must be undeletable; workspace delete also absent | M-L, engine (context/data destroy export) |
| Pin/Favorite title, copies wording (D5/D6) | done | PER-PROFILE-NOTES.md, perprofile-v2 | done |
| Chromium security updates ownership | missing | DESIGN.md gate 3 | L, process decision |
| Signing, notarization, packaging, updates | missing | PROGRESS Distribution row; production Keychain vs mock keychain unresolved (TASK.md) | L; Sparkle-style updater plus Chromium refresh cadence |
| Licenses/notices | partial | CEF-LICENSE.txt in spikes; no shipped notices bundle | S |

## Recommended next three milestones (by daily-use value)

1. **Chrome command completeness plus recovery.** Route Reload and the remaining menu/keyboard commands through Bato (engine action-layer hook, one engine build), add reopen-closed-tab, and land the renderer/engine crash recovery already underway. These are the things that break daily trust first: a command that silently opens untracked Chromium state, or a page that dies with no way back. Includes the cheap S verifications (Cmd-F, zoom, upload, print, certificate page, OAuth) in the same real-host cycle.
2. **Downloads, permissions and default browser.** Verify and fix download progress/destination/failure, origin+Profile permission prompts and revocation, external-protocol links, and default-browser registration. Without these Bato cannot be the only browser on the machine. Mostly Swift and verification; at most one engine touch.
3. **Window polish gates: F3, fullscreen tab strip, window drag, split pointer divider.** Fixes the visible rough edges of an everyday session (grey sidebar behind Cmd-T, stock strip in fullscreen, dragging the window, resizing splits with the mouse). Needs one combined engine build; do F3 and N1 first because they are Swift-only.

Deferred behind these: archive (design default Off), cosmetic filtering and the uBlock offer, extensions acceptance, Profile delete, signing/update pipeline (becomes first priority only when a second user is wanted).
