# Peek real-host check

Checked 2026-11-06 against the already-built Peek engine and client (no rebuild, no source change). This is a bounded real-host acceptance run on synthetic loopback fixtures, not a broader browser acceptance pass. Peek is opened from the floating command bar (Cmd-T, then the second result "Open <host> in Peek"). Dismiss is Escape, Cmd-W or the sidebar Close; promotion is the sidebar "Open as Tab".

The run used a fresh `runtime/peek-state-v1` clone of the preserved split-pair organization, the existing explicitly bound synthetic engine Profile with `--use-mock-keychain`, and the fixture server on loopback port 18765 (it was not running at the start and was restarted). The owned browser PID was 93465. UI was driven through the macOS accessibility tree for the native sidebar and command bar, and through screenshots plus pointer/keyboard input for Chromium content. The first selection change in the run (choosing the Storage favorite as parent) legitimately changed the active entry, so the Peek baseline was taken after it.

## Results

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Present | Pass | `index.html` preview rendered inset over a dark backdrop above the parent; sidebar showed a Peek row with Open as Tab / Close; organization bytes unchanged (same SHA-256 before and after). |
| 2 | Input and origin | Pass | A real click and paste into the preview's marker field showed the typed text; the Chromium address field showed `127.0.0.1:18765/index.html`, and the page's own output reported the same origin. |
| 3 | Escape dismiss | Pass | Escape removed the Peek row; the parent (Storage favorite) showed its earlier field value and write-result output without reload; organization bytes unchanged. |
| 4 | Second request refused | Not demonstrated (see defect 1) | The command bar cannot be used while Peek is presented without ending it. The refusal exists in source (`canOpenPeek` and the command-bar result filter) but was never reached through the UI. |
| 5 | beforeunload | Pass | `quit.html` armed with a real click; Cmd-W showed "Leave site?". Cancel kept the Peek and the page; a second Cmd-W then Leave closed the preview, removed the row and restored the parent live. Organization unchanged. |
| 6 | Promotion | Pass | Typed marker text in the preview survived "Open as Tab" with no reload. Organization gained exactly one temporary entry (the former preview, `lastURL` `index.html`) and it became active; no additional browser was created (browser count rose only for the preview itself). The preview UUID is not exposed before promotion, so identity equality was inferred from the absence of a second creation, not compared directly. |
| 7 | Workspace switch | Pass | Switching to the Research workspace via the sidebar picker removed the Peek row; organization differed only in `activeWorkspaceID`. Switching back restored the pre-switch bytes exactly and the Personal page state; no stray preview was visible. |
| 8 | Split refusal | Pass (UI level) | With the saved pair active, the command bar did not offer the Peek result (only Open and the existing-tab result). The pair stayed active and organization bytes were unchanged. The runtime guard itself was not invoked directly. |
| 9 | Clean Quit | Pass | Quit through the native app menu ("Quit Chromium"): exit 0; exactly one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final organization bytes equal the pre-quit bytes. The preserved `split-pairs-state-v1` organization is byte-identical to its snapshot. |

## Defects and observations

1. Opening the command bar while a Peek is presented ends the Peek but leaves the preview page mounted. The attached sheet is reported to the runtime as a modal end; the runtime selects the parent and requests close, but the native slot rejects selection/close while the sheet is attached (`attached-sheet` rejections appear in the log, followed by `active-browser-unavailable`). After the sheet was cancelled, the sidebar showed no Peek and the Storage favorite selected, yet the preview page filled the content area with its URL in the address field. Selecting another entry and then the parent restored the correct page. No browser-closed event was logged for the preview, so it may remain live until teardown. This also makes check 4 unreachable through the UI. Not fixed, per the run rules.
2. Opening a plain tab for a URL already held by a temporary tab activates that existing entry (title refreshed) rather than creating a second tab, and a Peek presented at the time is ended by that selection change. This looks like existing deduplication behavior and is recorded only because it interrupted the first attempt at check 4.
3. A Chromium Memory Saver promotion bubble appeared once over the preview and made the accessibility snapshot fail until it was dismissed with "No Thanks". It is engine UI, not a Bato fault.
4. Existing diagnostics were retained: duplicate Objective-C classes, cross-volume code-sign clone and quarantine messages, and attached-sheet slot rejections during command-bar presentation.
5. The agent-desktop clipboard helper was refused by the host (untrusted directory in its path), so text was entered with the system `pbcopy` plus Cmd-V. No clipboard behavior is claimed.

Defect 1 above was observed in the v1 run and is retained as recorded; the v2 section below covers the Swift-side fix.

Not covered: fullscreen and modal-sheet transitions during a Peek, preview stacking with native content beyond a visual check, focus traversal, accessibility of the Chromium content, stale-parent refusal, and failed-promotion save. No daily-use readiness is claimed.

Private SSD evidence is under `/Volumes/Mahesh/personal/bato-build/logs/`: `peek-v1.log`, `peek-v1-exit.json`, organization snapshots (`peek-v1-before*.json`), and window screenshots (`peek-v1-s*.png`, private, never in the repo). The wrapper is `tmp/launch-peek-v1.py`. No owned browser remains; the fixture server remains running.

## v2 re-run after the Cmd-T fix

Checked 2026-11-06 with the Swift-side fix (the command bar now ends an active Peek, restoring the parent and closing the preview, before presenting its sheet; rejected cleanups are retried when the sheet ends). Engine unchanged. Fresh `runtime/peek-state-v2` cloned from the same preserved source, wrapper `launch-peek-v2.py`, owned PID 30859, same flags and discipline as v1.

| Check | Result | Evidence |
| --- | --- | --- |
| A. Peek, then Cmd-T | Pass, with one caveat | The command bar opened with the parent behind it and no Peek; after cancelling, the sidebar showed no Peek row and the Storage favorite selected, and the content area showed the parent with its earlier field value and write output intact (no stray preview, unlike v1). The browser-count log shows the preview closed. Organization bytes unchanged. Caveat: the log still has one `attached-sheet` slot rejection during the sheet (v1 had about two per sheet); the preview close completed afterwards, so it did not leave a stray page. |
| B1. Present and Escape | Pass | Parent restored with state intact; organization bytes unchanged. |
| B2. Promotion | Pass | Text typed in the preview survived "Open as Tab" without reload; exactly one temporary entry was added and made active; the preview's browser was not recreated. |
| C. Quit | Pass | Native-menu Quit exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final organization bytes equal the pre-quit bytes; the preserved source organization is unchanged. |

Second-Peek refusal (check 4) remains unexercised on the real host: Cmd-T now ends the Peek by design, so the refusal is covered only by the runtime guard and unit tests. The remaining v1 "not covered" items still apply. No owned browser remains; the fixture server remains running.

## v3 Peek polish

Checked 2026-11-06 against the polished engine and client build. Fresh `runtime/peek-state-v3` from the same preserved source, wrapper `launch-peek-v3.py`, owned PID 96491. No Bato source was changed. One fixture was added: `spikes/fixtures/www/peek-parent.html`, a synthetic parent page with a fixed top bar showing a once-per-second tick counter, a note field, a click counter, counters for clicks and wheel events landing on the bar, and normal `<a href>` links to `index.html` and `quit.html`. It sends and stores nothing. The fixture server on loopback port 18765 was revalidated and serves it.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Live dimmed parent under Peek | Pass | The parent's top bar stays visible, dimmed, above and around the inset preview, and its tick counter advanced between screenshots while the Peek was presented (22 to 26, and later 23 to 37). The first fixture version had no content outside the inset and could not show this; the bar was added for the check. |
| 2 | Parent input blocked | Fail | A real wheel event over the dimmed bar incremented the parent's wheel counter, and a real click on the bar incremented its click counter. Input reaches the dimmed parent. |
| 3 | Scrim click dismisses | Fail | Pointer clicks on the dimmed bar and on the left margin did not dismiss the Peek (the sidebar Peek row stayed). The beforeunload variant (scrim, then Cancel) was therefore not run. |
| 4 | Shift-click a link | Pass | `mouse-click --modifiers shift` on a parent link presented that page in Peek; the window list still showed one window; organization bytes unchanged. A plain click navigated the parent tab normally. A Command-click showed hover/visited feedback but added no entry to organization and no Peek; no baseline for the earlier background-tab behavior was captured in this run, so this spot-check is inconclusive. |
| 5 | Promote with sidebar hidden | Pass | With the sidebar hidden by Cmd-S, Cmd-Option-Return promoted the Peek; text typed in the preview survived without reload, and exactly one temporary entry was added and made active. The Peek menu's "Open as Tab" did the same with the sidebar shown. |
| 6 | Regression | Pass | Escape restored the parent live with state intact and unchanged organization bytes. Cmd-T during Peek ended it: after cancelling the command bar the parent was shown, the preview browser was closed, and organization bytes were unchanged. One `attached-sheet` rejection remains in the log for the whole run. |
| 7 | Quit | Pass | Native-menu Quit exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final organization bytes equal pre-quit bytes; the preserved source organization is unchanged. |

The earlier stated limitation that there is no live parent underneath is demonstrated as resolved. The limitation that the scrim does not block parent input or dismiss the Peek is demonstrated to remain. Because the parent sits dimmed under a scrim that passes input through, a click or scroll in that area acts on the parent page; this should be treated as a defect.

Run notes: early keystrokes went to another application while the browser window was not frontmost (one pasted URL and Return, possibly a harmless GET to the loopback fixture); automation was retried after explicitly focusing the browser. Window screenshots vary in size with focus, so click offsets were derived per capture. `find` on the menu bar timed out once the History menu grew; the menu was driven through a menubar snapshot instead. Not covered: Peek during fullscreen or an alert sheet, real stacking of native overlays, keyboard focus traversal, and the beforeunload scrim path.

## v4 scrim fix

Checked 2026-11-06 against the engine rebuilt with the scrim fix (the scrim takes part in hit testing; the parent page ignores input while the Peek is mounted). Fresh `runtime/peek-state-v4`, wrapper `launch-peek-v4.py`, owned PID 23519, same fixture and discipline as v3. The v3 failures for checks 2 and 3 are retained above as observed.

| Check | Result | Evidence |
| --- | --- | --- |
| Parent input blocked | Pass | With the Peek presented, a real wheel event and a real click over the dimmed parent bar left the parent's wheel and bar-click counters at 0 (they became 1 in v3). The parent's tick counter kept advancing. |
| Scrim click dismisses | Pass | A click on the dimmed bar removed the Peek row and restored the parent live (ticking, note and counters intact). Organization bytes unchanged. |
| beforeunload scrim path | Pass | With `quit.html` armed by a real click, a scrim click showed "Leave site?". Cancel kept the Peek; a second scrim click then Leave closed the preview and restored the parent; the preview browser close was logged. Organization unchanged. |
| Regressions | Pass | Shift-click on a parent link presented it in Peek with one window listed; the preview accepted typed input (the first attempt lost its paste, the retry showed the text); the dimmed parent kept ticking under the Peek; Escape restored the parent with organization bytes unchanged. |
| Quit | Pass | Native-menu Quit exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final bytes equal pre-quit bytes; the preserved source organization is unchanged; no `attached-sheet` rejection occurred in this run. |

The stale limitation that the scrim passes input through is resolved on the real host. Not covered: Peek during fullscreen or alert sheets, keyboard focus traversal, native overlay stacking beyond a visual check, and the Command-click background-tab spot-check. No daily-use readiness is claimed. No owned browser remains; the fixture server remains running.
