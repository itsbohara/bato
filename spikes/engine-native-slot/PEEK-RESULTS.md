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
