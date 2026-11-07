# Per-Profile blocking + Profile switcher: real-host results

Run 2026-11-07 on the uncommitted build, via `agent-desktop`. Wrappers `tmp/launch-perprofile-v1.py` (guard `logs/profiles-v9-exit.json`) and `tmp/launch-perprofile-v2.py` (guard `logs/perprofile-v1-exit.json`), states `runtime/perprofile-state-v1` (copied from profiles-state-v9) and `-v2` (copied from v1 final), flags `--use-mock-keychain --bato-blocking-log` plus `--bato-blocking=<fixture list>` and `--bato-blocking-lib` (so the fixture rows block deterministically). Logs and screenshots under SSD `logs/perprofile-v1*`, `logs/perprofile-v2*`, `logs/perprofile-v1-shots/`. Nothing built, committed or edited in source. Startup selection was Side (Arc - Profile 1) with the launch window.

| # | Check | Result |
|---|---|---|
| 1 | Header switcher menu | PASS. `bato-space-name` opens a menu grouped by Profile ("Personal/Arc · opens in its own window"), check mark on Side, Ctrl-1..5 hints, New Workspace / New Profile… / Rename Profile… (`shots/02-switcher-menu.png`). |
| 2 | New Profile "Work" + Cmd-T | PASS. Sheet (name, colour, first workspace) with Ocean chosen; Create dismissed cleanly (log `native-slot-sheet-ended`), saved colour `#527FAD`. Cmd-T opened the command bar; opening the fixture created a new window with `profile-window-bound key=2FD29BCA-... context=<cache>/2FD29BCA-...` and that directory exists with real profile data. |
| 3 | Per-Profile blocking | PASS (caveat E1). Work: Page menu "Blocking: On for this site", 10 blocked; toggled off, reload: all rows executed, `blocking/<WorkUUID>/blocking-settings.json` holds exception `127.0.0.1`. Side (other Profile), same fixture: all expected-blocked rows failed after reload (`shots/09-side-after-reload.png`), no settings file for Side. Log has exactly one `ready`; lists only in `<state>/blocking/lists` (updated 17:24), no per-Profile lists. |
| 4 | Rename + relaunch | PASS. Renamed Work to "Clients", colour Rose (`#B47879`), profile id unchanged. After quit + relaunch (v2): footer button "Clients", org JSON name/colour kept, Page menu "Blocking: Off for this site / 0 blocked", fixture rows all executed, settings file unchanged. |
| 5 | Pin title (D5) | PASS. Pinned "Bato network blocking fixture (done)", navigated to storage.html in the pin: organization shows `lastURL` updated, `savedURL` and `title` unchanged; sidebar row kept the saved title. |
| 6 | Quit with 2+ Profile windows | PASS. Quit via app menu ("Quit Chromium") with three windows (launch, Side, Work): natural exit 0 (`logs/perprofile-v1-exit.json`), markers once each (`sample-native-quit-requested`, 6 browsers closed to 0, `profile-contexts-released` count 2 then 0, three `native-slot-detached`, `cef-shutdown-complete`); organization sha before == after. v2 quit (2 windows) also exit 0. No `refused`, `mismatch` or `Cannot create profile` in either log. |

## Defects
- **E1 (low, matches PER-PROFILE-NOTES design): first load in a Profile's window is unfiltered.** In Side (first page ever opened in that Profile this run), 4 expected-blocked rows executed (script-tracker, script-important, script-domain-only, xhr-beacon; others failed); reload blocked everything. Repro: open the fixture as the first page in a Profile window. Settings are null until the first poll.
- **E2 (low): footer workspace picker out of sync.** In the Side window the footer picker (`bato-workspace-picker`) reads "Work" while the header says Side; in the Work/Clients window it is empty. Repro: with two Profile windows open, compare footer picker with header (`shots/08-side-blocking.png`, `13-renamed.png`).
- **E3 (info): Create leaves the new workspace in the launch window until a page opens.** After Create the new Work sidebar appears in the existing about:blank launch window; the Profile's own window only appears on Cmd-T plus navigation. Matches the notes (engine work deferred), recorded because log shows `workspace-adapter-rejected ... active-browser-unavailable` at that moment.

## Not verified / caveats
- Cmd-T opens the command bar sheet, not directly a window; window creation happened on submitting a URL.
- Ctrl-N shortcuts were seen in the menu but not exercised. Check mark and hints were read from a screenshot (not in the AX tree).
- Copied state kept a legacy `blocking/default/lists` (not migrated, as documented); not used.
- Third-party fixture server on 18766 was not running at the start (only 18765); I started `spikes/fixtures/server.py --port 18766` (log `logs/perprofile-v1-fixture-18766.log`) and left it running. Before that, the first Work load had failing controls, so that first load is not evidence.
- Around 17:27 the cmux terminal took keyboard focus once; two synthetic key presses (Return) may have reached it instead of Bato before I added a frontmost check. Bato state was unaffected.
- D6 and the popup/DevTools key resolution items from PER-PROFILE-NOTES were not exercised.
