# Downloads in the sidebar: results

Run 2026-11-07. Plan: DOWNLOADS-SIDEBAR-PLAN.md (decisions below supersede its "open question"). Not committed. Screenshots on the SSD (`logs/dl-shots/`), none in the repo.

## What changed

- Engine ABI (`bato_native_slot.h`, new exports only; every earlier table and signature unchanged): `bato_native_slot_register_download_callbacks_v1`, `bato_native_slot_download_snapshot_v1`, `bato_native_slot_download_action_v1`. `BatoDownloadInfoV1` is the plan's struct plus `warning` (0 none, 1 dangerous, 2 insecure, 3 needs a scan decision, e.g. a password-protected archive). Actions are the plan's 0-5 plus 6 keep and 7 discard.
- Engine (`chrome_content_browser_client_cef_mac.mm`): one `DownloadManager` observer per regular Profile that owns a slot window (hooked at slot attach and in the snapshot export, so Profiles created later are covered), one `DownloadItem` observer per download. Progress is throttled to 4/s per item; any change of state, warning, file name, resumability or file existence is emitted at once. Only downloads that are in progress when seen are reported, so history items stay in `chrome://downloads` and do not light the sidebar dot on launch (session-only list). `profile_key` is the Profile directory name (`Default` becomes `""`); the client maps `""` to the launch key and back through the same `ProfileKeys()` table the blocking key uses. Keep calls `ValidateInsecureDownload` / `ValidateDangerousDownload` (and completes a pending scan prompt first); Discard calls `Remove()`. Nothing is ever kept automatically.
- Engine (`download_toolbar_ui_controller.cc`, new overlay file, manifest now 20 files): `Show`, `UpdateDownloadIcon` (which also drives the started animation), `ShowDetails`, `ShowBubble` and `ShouldShowExclusiveAccessBubble` do nothing in a normal workspace window (`--bato-workspace-state` and not refused). The predicate is deliberately not `NativeSidebarOwnsTabs`: a recent download from the last session would otherwise show the button while the window is created, before the sidebar attaches. The manager, history and `chrome://downloads` are untouched.
- Client: `native_slot_client.mm` registers the callbacks (additive, resolved by dlsym), copies strings, posts to the UI task queue, and hands Swift Bato Profile keys; `WorkspaceSlot.swift` adds `NativeDownloadsEngine` (a `DownloadsEngine`), one `DownloadsController` per process created with the first workspace controller, and `attachDownloads`.
- Swift: `DownloadWarning`, `.keep`/`.discard` actions, `engineCode`, `DownloadItem(engineProfileKey:...)`, warning status text ("May harm your computer", "Not downloaded securely", "Couldn't be scanned for threats"), a warning marks the Profile as needing attention; the popover row shows red text with Keep and Discard buttons instead of the icon actions.
- Fixture: `spikes/fixtures/downloads_server.py` gained `/slower.bin` (24 MB), `/danger.*`, Range/ETag/Last-Modified, `/fail-ok` and `/fail-reset` (failure only until `/fail-ok`), `--verbose`; `www/downloads.html` links them, plus auto-start (no user gesture) pages.
- Concurrent work: I registered the other agent's Archive and uBlock files (5 mirrors, compile list, staged `BUILD.gn`); client patch is now 51 files, 46 mirrors. Until that agent finished, `native_slot.py check`, `swift test` and the first build ran from a snapshot of HEAD plus my files (its half-edited tree did not compile).

## Process

`native_slot.py check` passed (72 files) on the final tree; `swift test`: 162 XCTest + 192 Swift Testing, 0 failures (`logs/dl-swift-tests.log`; new `DownloadsWarningTests`). Builds: first (snapshot) and final both succeeded; segment `logs/dl-build-segment.log` (the shared `build.log` also holds earlier attempts). Real host `tmp/launch-dl-v1.py` (`--use-mock-keychain`, guard `logs/m3-v6-exit.json`, state `runtime/dl-state-v1`, a fresh copy of `m3-state-v6`), Bato frontmost before every keypress, quit via "Quit Chromium": exit 0 (`logs/dl-v1-exit.json`), one `cef-shutdown-complete`, no `refused`/`mismatch`. Log shows `native-downloads-watching` with key `""` and later the Arc Profile key.

## Results (real host)

| # | Check | Result |
| --- | --- | --- |
| 1 | No Chromium bubble, toolbar button or started animation | PASS: slow, small, failing and 3 concurrent downloads; the toolbar shows only avatar and menu. |
| 2 | Sidebar button with progress ring on a slow download | PASS (`03-slow.png`); unseen-finish dot after completion. |
| 3 | Popover list, live progress ("6.8 MB of 8.4 MB · 511 KB/s") | PASS (`05-popover.png`). |
| 4 | Pause, Resume | PASS (paused at 21.6 of 25.2 MB, resumed to done). |
| 5 | Cancel, Remove from list | PASS (row shows Cancelled, then disappears). |
| 6 | Failure state and Resume | PASS: "Failed · can resume"; Chromium restarts rather than ranges (no Range header was sent), so with the fixture still cutting it failed again; after `/fail-ok` the same Resume click finished (4.2 MB, Done). |
| 7 | Show in Finder | PASS: Finder frontmost with the file selected. |
| 8 | Open | PASS: double-click opened `small-download.txt` in TextEdit (then quit). |
| 9 | Per-Profile isolation | PASS: Arc Profile window had no button until its own download; its popover lists only its download; Personal's list is unchanged; `chrome://downloads` per Profile. |
| 10 | Download History / `chrome://downloads` | PASS: Shift-Cmd-J opens the tracked row listing the Profile's download. |
| 11 | Dangerous, insecure or password-protected warning with Keep and Discard | NOT TRIGGERED on the host. `.dmg`, `.jar`, `.command` and `.exe`, by click and by script (no user gesture), all completed without a warning: this build has no download protection or file-type danger policy active. The path is covered by compile, `DownloadsWarningTests` and code review only; Keep/Discard rows were never seen on screen. Needs a Safe Browsing or policy-enabled build, or an HTTPS page fetching HTTP (insecure), to verify. |

Compared with Arc/Dia (no downloads capture in the Dia library; Arc by memory): footer ring button and a rounded popover with newest-first rows match the plan's layout; icon actions appear on hover only.

## Defects and open items

1. The popover keeps its largest height after the list shrinks (empty area under the rows, `11-removed.png`, `30-arc-popover.png`); needs `contentSize` refit on reload.
2. The popover is clipped and AX reports its controls as offscreen when it extends below the window bottom; physical clicks work.
3. Two rows can share a name (`failing-download.bin` twice) when a failed item is retried.
4. Pinned-toolbar action `kActionShowDownloads` is not hidden: if a user pins it the button would still be listed in the overflow. Not exercised.
5. Item 11 above. Also the engine treats `warning` only while the item is in progress; blocked downloads arrive as `failed`.
6. Real-host Profile windows sit at a different screen offset than the launch window, so physical-click coordinates differ per window (test-harness note).

## Archive and uBlock (other agent's work, checked on this run)

- uBlock offer card: appeared once about 2 s after launch ("Add uBlock Origin filter lists?"); I chose Not Now. `blocking/list-choices.json` now reads `declined`; no lists were added (`01-launch.png`).
- Archive sheet: command bar "Archive" opens the sheet with search field, empty-state text, Delete/Done/Restore (`32-archive-sheet.png`).
- Settings > Archive pane renders: global period (Never), per-workspace overrides, Open Archive (`33-settings-archive.png`).
- Not exercised: sweep, archiving a loaded page, restore, Add Lists.

## Cleanup

Downloaded test files were removed from `~/Downloads` (only the 11 created here: slow, slower, small (x2), failing, `bato-danger*` (x6)); the listing again equals `logs/dl-downloads-before.txt`. The fixture server on 18768 was started and stopped by this run; 18765 was left running.
