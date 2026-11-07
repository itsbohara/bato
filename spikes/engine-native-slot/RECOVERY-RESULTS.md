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

## Fix verification

Run 2026-11-07 ~19:25-19:30 on the uncommitted build (`libBatoNativeSlot.dylib` 19:11, newer than the Swift fixes at 19:03-19:09), `agent-desktop` plus System Events keys; AX presses for sheet buttons. Wrappers `tmp/launch-recfix-v1.py` .. `-v5.py` (copied from `launch-commands-v2.py`, guard chain from `logs/commands-v2-exit.json`, `--use-mock-keychain`), state `runtime/recfix-state-v1` copied fresh from `runtime/recovery-state-v1`. v1 and v2 were practice launches (clean quits, exit 0) in which the 10 s window was missed or Cmd-W had no active entry; v3 is the crash run (kill -9 of the wrapper-launched pid 63949 only, command line verified, record `logs/recfix-v3-kill.json`, receipt exit -9), v4 the recovery/settings/command-bar run, v5 the no-restore relaunch. Quits through "Quit Chromium" only: v1, v2, v4, v5 exit 0, v4 markers `profile-contexts-released` x2 and `cef-shutdown-complete`. Logs `logs/recfix-v{1..5}.log`, `-exit.json`, org copies `logs/recfix-v3-before.json`, `recfix-v3-crashed-org.json`, `recfix-v4-final-org.json`; screenshots `logs/recfix-shots/` (SSD only).

| # | Check | Result |
| --- | --- | --- |
| 1a | Sheet layout after crash relaunch | PASS. Card 320 x 197 pt (window bounds), SF Symbol circular-arrow header, bold title, secondary body, two equal-width side-by-side buttons (Keep Current primary blue, Restore Session grey). Sheet showed before pages loaded. |
| 1b | Copy | PASS. "...go back to how it was when your last full session began, 7 Nov 2026 at 19:26." (19:26 is the v3 launch capture time). |
| 1c | Restore Session = state at launch start, not the 10 s edit | PASS. v3: Cmd-9 then Cmd-W at 5 s after launch closed History (edit inside first 10 s; `pending-session` existed and was byte-identical to `recfix-v3-before.json`; promoted `last-session` after confirmation equals the launch state, History still present). Then Cmd-1 at about 25 s changed the selection, kill -9. After Restore Session the org is byte-identical to `recfix-v3-before.json` (History present, no active entry) and differs from the crashed org. |
| 2a | Restore from backup... attaches to Settings | PASS. Sheet appears in the Settings window's tree and on screen over Settings (picker, Cancel, Restore on Relaunch); the History browser window has no sheet. The follow-up "Later / Quit Bato" sheet also attached to Settings. |
| 2b | Staged row and cancel | PASS. After Later, Advanced > Backup shows "Restore staged: 'Start of last session, 7 Nov 2026 at 19:26' will replace your organization the next time Bato opens." with Cancel staged restore. Cancel removed the row and `recovery-pending-restore.json`. |
| 2c | Relaunch after cancel applies nothing | PASS. After cancelling I closed History (org differs from the backup), quit; v5 launched with no sheet, org byte-identical to `recfix-v4-final-org.json`, no pending file. |
| 3 | Command bar text vs magnifier | FAIL. With "example.test/some/long/typed/text" typed (Cmd-T), the first glyph still sits on top of the magnifier (screenshot `03-commandbar.png`: text starts at x=118, magnifier at 124-136, and the magnifier sits lower than the text baseline). The 8 pt inset from N1 did not take effect. |
| 4a | Shift-Cmd-T reopens a closed tab | PASS (Cmd-9, Cmd-W, Shift-Cmd-T: History row removed, then back and selected). |
| 4b | Clean quit | PASS (exit 0, markers present). |

### Defects

- **V1 (medium, N1 not fixed):** command-bar typed text overlaps the magnifier icon; see row 3.
- **V2 (low, R2 still open):** the sidebar is still a flat grey slab behind the recovery sheet; the window is otherwise empty (about:blank), so the card floats over blank chrome.
- **V3 (info):** the first-10 s edit is only provably excluded when it happens after the window attaches; my first two practice runs missed the window (launch to key press took more than 10 s once). Not a product defect.
- **V4 (info):** the selected History entry showed an empty title right after Cmd-9 before loading (state script), not investigated.

Dia comparison (`dia/2026-11-01/01-connect-slack-prompt.jpg`): width and shape now match well. Both are small dark rounded cards with an icon header, bold left-aligned title, two-line-ish secondary body and two compact side-by-side pills with the primary on the right in Dia, on the left in Bato (Keep Current is the default, so primary-left is deliberate but opposite to Dia's order). Dia's card is a lighter translucent material with a keycap return hint on the primary and a checkbox row; Bato's has neither. Bato's body is 4 lines, Dia's 3. Remaining gap: Dia's header is a brand image plus mark; Bato's is a small system glyph, fine for a recovery prompt.

Not verified this run: blocking-settings restore (R4), repeated crash counter wording, second-day rollover.
