# Crash recovery and backups: real-host results

Run 2026-11-07 on the uncommitted build (`libBatoNativeSlot.dylib` 18:53, contains the recovery code), driven with `agent-desktop` plus osascript System Events menu clicks. Nothing built, edited or committed. Logs and screenshots are on the SSD (`logs/recovery-v*`, `logs/recovery-shots/`); none are in the repo. Wrappers `tmp/launch-recovery-v1.py` .. `-v7.py` (guard chain from `logs/polish3-v2-exit.json`; v1 copies `runtime/polish3-state-v2` to `runtime/recovery-state-v1`, later runs reuse it). All use `--use-mock-keychain`; fixture servers 18765/18766 were already up (HTTP 200). Bato was frontmost before every keypress; quits via "Quit Chromium" (`tmp/rec-quit.sh`, aborts unless the target pid is frontmost).

Abnormal terminations: `kill -9` of exactly the wrapper-launched browser pid, verified by command line (`--bato-workspace-state=.../recovery-state-v1`) and recorded in `logs/recovery-v{2,4,5}-kill.json` (pids 50217, 55731, 56960). Wrapper receipts show exit -9; the guard of the next wrapper accepts -9 only when that kill record exists. No helper processes were left behind.

## Results

| # | Check | Result |
| --- | --- | --- |
| 1 | `session.marker` written at launch, removed after clean quit; no sheet on next launch | PASS (v1 marker pid 45403; gone after menu quit, exit 0; v2, v4, v7 launched without a sheet after clean quits) |
| 2a | Org change, >10 s, kill -9, relaunch: sheet before pages, Keep Current | PASS (v2 closed the History row, kill; v3 sheet over an empty window with no pages; Keep Current: org byte-identical to the crashed org, pages loaded) |
| 2b | Restore Session Start | PASS (v4 closed Download History, kill; v6 Restore: org byte-identical to the pre-edit state, `organization.snapshot.pre-restore.json` written, pages loaded) |
| 2c | No crash loop, snapshot not overwritten by a crashed launch | PASS. `backups/last-session` hash unchanged across the crashed v3-style launch and the v5 launch killed at the sheet; after Keep Current it was replaced 10 s later and `failures` reset to 0 |
| 2d | Repeated crash counter | PASS: v5 killed unanswered, v6 sheet says "happened 2 times in a row" |
| 3 | Daily backup with org + per-Profile blocking settings | PASS: `backups/daily-2026-11-07/{organization.json,manifest.json,files/blocking/<UUID>/blocking-settings.json}` and the same for `last-session`, created on first launch. Only one Profile (Clients) has a settings file; the others have none to copy |
| 4 | Settings > Advanced > Restore from backup…, stage, quit, relaunch | PASS: picker lists "Start of last session", "Before last restore", "Daily backup"; staged `recovery-pending-restore.json`; Later then menu quit (exit 0); v7 applied it (org equals the daily copy, History row back, pending file removed, "Before last restore" = prior org, no sheet) |
| 5 | Clean quit with 2 Profile windows | PASS: v1, v3, v6, v7 exit 0; `profile-contexts-released` 2, `cef-shutdown-complete` 1, no refused/mismatch |

## Defects

- **R1 (low): Restore sheets attach to the focused browser window, not the Settings window.** "Restore from backup…" and "Quit Bato to finish restoring" opened on the Download History browser window while Settings stayed in front.
- **R2 (low): the sidebar is a blank grey slab behind every recovery/restore sheet** (known F3). The sheet floats over empty chrome, which makes the first-launch recovery sheet feel unfinished.
- **R3 (low): recovery sheet wording.** "when that session started, 18:56" is really the time of the 10 s launch confirmation, not session start. The snapshot also never contains edits made in the first 10 s, so a crash before confirm restores to the state after the previous confirmed session; both are fine but the copy overstates it.
- **R4 (info): blocking restore not discriminated.** The daily and live per-Profile blocking files were identical, so restoring settings was not proven; only organization was. Needs a run with a changed exception before restore.
- **R5 (info): pending restore file lingers** after staging plus quit until the next launch (expected), but "Later" leaves it staged silently with no indication in Settings.

Not verified: daily rollover on a second calendar day and the 7-copy prune, renderer-process kill, `"version": 9` unavailable text, `kill -9` while the Settings window is open, concurrent-marker case.

## Dia comparison

Reference `dia/2026-11-01/01-connect-slack-prompt.jpg`. Both are small centered dark translucent cards with a bold left-aligned title and short body. Bato is close in tone and wording is plain and calm. Differences: Bato's buttons are stacked full-width pills (primary blue), Dia's are compact side-by-side pills with a keycap hint; Bato's body is longer (up to 7 lines in the second-crash variant) and the card is only 260 pt wide, so it reads tall; Dia has an icon/art header, Bato has none. Suggest a wider card (about 320 pt) and side-by-side buttons.
