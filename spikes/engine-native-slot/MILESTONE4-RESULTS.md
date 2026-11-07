# Milestone 4 results

Run 2026-11-07. Plan: MILESTONE4-PLAN.md. Not committed. No Ardia code; no images in the repo (screenshots under SSD `logs/m4-shots/`).

## Process

- `native_slot.py check` passed (74 files; engine patch 8 files, client patch 53 files, 48 mirrors), `cargo test` 11 passed, `swift test` 167 XCTest + 198 Swift Testing, 0 failures (`logs/m4-swift-tests.log`; new `ProfileDeleteRuntimeTests`, reopen-by-position test). Four `build --execute` rounds; last segment `logs/m4-build-segment.log`. Also registered the light-mode agent's `AppearanceWatcher.swift` and `SwitcherPopover.swift` (client.json, compile script, staged `BUILD.gn`).
- Real host, `--use-mock-keychain`, quit only via "Quit Chromium": `tmp/launch-m4-v1.py` (items 1, 2, 3, 5, 6, light-mode checks; exit 0), `v2` (archive; exit 0), `v3` (crashed, exit -6, `logs/m4-v3-exit.json`, see cosmetic below), `v4` (cosmetic; exit 0; its receipt guard chained from `m4-v2-exit.json`). States `runtime/m4-state-v1..v4`, fresh copies. No `refused`/`mismatch` in v1, v2, v4; one `cef-shutdown-complete` each.

## Results

| # | Item | Result |
| --- | --- | --- |
| 1 | Profile delete | PASS (v1). New engine export `bato_native_slot_delete_profile_v1` (UUID directory names only, never `Default`; closes the Profile's browsers without beforeunload, then Chromium's `DeleteProfileHelper`). Throwaway Profile "Throwaway M4" created in the test state, a page opened (window + `<cache>/0B495C57-...` on disk, 3.3 MB). Settings > Profiles > Delete... shows a confirm sheet listing 1 workspace, 1 page, 0 favorites, 0 archived tabs. Delete Profile: its window closed, selection moved to the launch Profile, the directory was gone within seconds (not deferred to the next launch), the Profile left `Local State`'s info cache, the organization lost the Profile and `organization.snapshot.pre-delete.json` holds the previous document (Recovery lists it as "Before last Profile delete"). The launch Profile row has no Delete button; `deleteProfile` also refuses it in the model. Unit tests cover refusal, snapshot order, engine refusal restoring the organization and selection fallback. Not exercised: its blocking settings directory (the throwaway had none yet, so `BlockingProfiles.removeProfile` is code and unit-compile only), cancelling the sheet, a Profile with a running download. |
| 2 | Fullscreen sidebar reveal | PASS (v1). Ctrl-Cmd-F: only Chromium's toolbar shows; moving the pointer to the left edge reveals the full sidebar over the page (no reservation), leaving hides it, Cmd-S toggles it in both directions, exit restores the docked 260 pt sidebar. Engine: fullscreen keeps the host visible as a 6 pt edge or the overlay, `set_sidebar` accepted in fullscreen via a separate `fullscreen_reveal` flag that never touches the stored mode. Rough edges: the revealed sidebar keeps the traffic-light clearance gap at its top; no animation. |
| 3 | History > Recently Closed | PASS (v1). Items are enabled; a click sends command `1000100 + position` to the client, which reopens that entry of Bato's closed-tab stack (newest first). Closed "cos", clicked the first Recently Closed row: tab reopened and selected, log `workspace-chrome-command 1000100 -> 40`. Only position 0 was exercised on the host (positions >0 in unit tests). Chrome's menu also lists older closed tabs from before the launch; those rows do nothing when Bato's stack is shorter. |
| 4 | Cosmetic filtering | PASS (v4) with scope limits. adblock FFI now exposes `bato_adblock_cosmetic_script` and `bato_adblock_cosmetic_generic`. Per frame (`OnLoadStart`, http/https): page-specific hide selectors injected as one adopted stylesheet. Generic class/id rules: an injected harvester reports the top document's class and id names (a cancelled request to `bato.invalid` plus a console line; whichever arrives first) and the engine answers with the matching rules, including elements added after load. Same enabled flag and site exceptions as request blocking (a Profile with `enabled:false` showed everything, back to `true` hid again). Verified on the real host: host-specific rule hid `.bato-fixture-ad`; on a non-excluded host (`http://[::1]:18770`) the static and a late-added `.bato-generic-ad` were both `display:none`, control stayed visible. EasyList deliberately exempts `127.0.0.1`, `localhost` and private ranges from generic hiding, so the fixture's generic rule only shows on other hosts. Not supported: scriptlets (adblock needs resources, none are loaded, so `+js()` filters never emit), procedural and `:style()` filters, generic rules inside subframes. First attempt (v3) crashed: `CefURIDecode` aborts on an empty string (empty `i=` list); fixed and covered by v4. Fixtures: `bato-fixture-list.txt` and `blocking-network.html` gained generic targets. |
| 5 | Split pointer divider | PASS on this host (v1). A physical drag of the divider (`agent-desktop drag --duration 800 --headed`, 758,430 to 958,430) moved it and the observed ratio 0.5 -> 0.7457 was saved to the organization. The earlier "no movement" came from instantaneous synthetic drags; no engine change was needed. Not re-tested: divider drag with a loaded extension, keyboard resize, fast flicks. |
| 6 | Downloads popover | PASS (v1). The popover opens on the side of the button with more screen room (above it for the footer button) and caps its list to that room; `contentSize` is refit on every reload. With one in-progress and three finished rows, Clear left the in-progress row and the popover shrank to one row with no empty area. Controls were fully inside the screen near the window bottom. |

## Also checked (light-mode agent, v1)

- Workspace switcher popover opens from the header (`bato-space-name`) and a click on another workspace switched it (header and tint changed). `bato-profile-button` present.
- Settings back/forward arrows and the section headings render (Profiles to Privacy to Archive and Back landed on Privacy then forward). AX press on the sidebar rows did not change the pane; physical clicks did.
- macOS appearance Dark -> Light: sidebar and Settings both re-coloured live (screenshots 26/27); restored to Dark afterwards.

## Archive (v2)

State copy with period 12 hours and two idle temporary tabs (`lastActiveAt` three days old): the launch sweep archived exactly those two (selected and fresh tabs stayed), the Archive sheet (command bar "Archive") listed both ("1 min ago"), selecting one and Restore returned it at its old index in its workspace and selected it; the other stayed archived. Beforeunload Cancel on an archived loaded page, and the 5-minute sweep timing, were not exercised.

## Open items

1. Profile delete: the blocking-settings removal and a Profile with a live download are unexercised; the Profile deleted while the window was key was the only case.
2. Fullscreen: revealed sidebar keeps the traffic-light inset; no animation; text fields in the revealed sidebar were not typed into.
3. Cosmetic: no scriptlets, procedural filters or generic rules in subframes; a page's CSP cannot stop the console channel but can stop the request one (the other still reports). The engine rebuilds only when list files change.
4. Recently Closed rows beyond Bato's stack do nothing silently.
5. Real LaunchServices/other items from earlier milestones remain as recorded.
