# Sidebar navigation header real-host check

Checked 2026-11-06 against the client build that adds the sidebar navigation header (Back, Forward, Reload/Stop, host pill with loading bar and failure state, Cmd-L, Cmd-Shift-C). Bounded run on synthetic loopback fixtures; no engine change. Fresh `runtime/nav-header-state-v1` cloned from the preserved split-pair organization, wrapper `launch-nav-header-v1.py`, owned PID 61383, existing synthetic Profile with `--use-mock-keychain`. UI was driven through the accessibility tree plus pointer and keyboard input. The fixture server does not support delays, so a throwaway local server on another loopback port that answers after 15 seconds was run for the slow-load check and stopped afterwards; it is not in the repository.

## Results

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Back / Forward | Pass | Both start disabled on a fresh page. After a link navigation Back was enabled and Forward disabled; Back returned to the previous page and enabled Forward; Forward returned. The pill AX value tracked each URL. |
| 2 | Reload, Stop, loading bar | Pass | During a slow main-frame load the Reload button became "Stop loading" and a thin bar appeared under the pill; after completion it returned to "Reload page". A reload of the slow page showed Stop again. While loading, the pill AX value still showed the previous page's URL (pending URL is not shown). |
| 3 | Failed load | Partial | A refused-connection navigation showed the red warning-triangle pill about one second after Enter. By five seconds, after Chromium's error page committed, the pill had returned to the normal state, so the subsequent error-page commit does clear it and the failure state is transient. An unsafe-port navigation (port 1) was refused by Chromium before any request and was not observed to show the failure state; I did not capture the first second of that case. While an error page is shown the pill, its AX value and the saved entry URL keep the last good URL, and Back after the failure landed on the earlier error page rather than a normal page. |
| 4 | Pill click and Cmd-L | Pass | Both opened the command bar prefilled with the current URL, with the first result "Go to <host>". Enter navigated the current page; organization differed only by that entry's `lastURL` and `title` (no new entry). Cmd-L during Peek did not open the Bato bar and fell through to Chromium's own address field (no Bato page selected case not otherwise reachable). In one instance after a pill click the Enter key did not submit until the Open button was used; not reproduced and possibly a focus artifact. |
| 5 | Cmd-Shift-C | Fail (not verified) | Four attempts, with web content focused and after clicking in the sidebar, left the clipboard empty. The key equivalent may be consumed before it reaches the sidebar (Chromium maps this chord to an inspector command) or the copy guard may reject the page; cause not established. Some attempts also followed a loss of keyboard focus to another application, so the first failures are weak evidence; the later ones were made with the browser frontmost. |
| 6 | During Peek | Pass | Back, Forward, Reload and the pill were AX-disabled and dimmed while a Peek was presented; Cmd-L did not open the Bato command bar. Organization bytes were unchanged. |
| 7 | Split | Pass | In the saved split the pill and a prefilled Cmd-L followed the focused side. Navigating the focused right pane changed only that entry, and Back acted on that pane while the left pane and its saved entry were untouched. |
| 8 | Quit | Pass | Native-menu Quit exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final organization bytes equal pre-quit bytes; the preserved source organization is unchanged. |

## Visual comparison with Dia and Arc references

Compared Bato's non-split sidebar header with a live capture of the installed Dia (1.55.1) and the earlier private Dia and Arc sidebar captures. Observed from screenshots only; sizes are approximate.

1. Placement differs structurally. In both references Back, Forward and Reload sit in a top toolbar level with the traffic lights, to the right of the sidebar toggle. Arc centers a link icon plus the host in the top bar above content. Bato stacks them as a third row under the title and workspace name, which pushes tab content down about 90 points. Action: move the controls up into the title row beside the sidebar toggle, or accept the stacked layout deliberately.
2. Redundant address field. Bato shows both the pill and the "Enter a website address" field. Neither Dia nor Arc has a second field; they have a New Tab row. Action: remove the field and keep "+ New Tab" (and Find) as the only entry rows, with the command bar as the single entry path.
3. Pill treatment. Bato's pill is a full-width bordered 32-point rounded rectangle with a bold white host. Arc's is borderless, host in regular weight, muted, with the link glyph, in the toolbar. Action: drop the border, use a subtle filled capsule only on hover, regular weight, secondary color.
4. Navigation icon weight and size. Bato's arrows are about 16-point lighter strokes in a row that is left-aligned at the sidebar's text margin; Dia's are slightly larger thin chevrons spaced about 36 points apart. Action: use chevron symbols, 17 to 18 point, regular weight, wider spacing, consistent hit areas.
5. Disabled state. Bato's disabled buttons are dim grey, close to Dia's, but the disabled pill during Peek loses contrast along with the label; keep label legible.
6. Loading bar and failure state. The 2-point bar is barely visible on the dark pill; the red failure state is clear but transient. Action: raise bar contrast and consider keeping a persistent failure indicator until the next successful commit.
7. Traffic-light alignment. Bato's title row starts below the traffic lights with its own baseline; Dia puts the workspace name on the same row as the lights. Action: align the title and sidebar toggle with the traffic-light centerline to recover about 40 points of height.
8. Radii and spacing. Bato's pill radius (about 10 points) matches its other rows but Dia's rows use larger (about 12 points) corner radii with 8-point side insets; tile and row spacing is tighter in Dia. Action: unify radii and insets with a single token set.
9. Colors. Dia tints the sidebar with a per-space hue and uses a darker selected row; Bato's header has no tint of its own. Low priority.

Observation: after the failure case the favorite tile title became the bare host, since Chromium's error page title replaced the saved title in the entry; the saved URL was not replaced.

Not covered: Cmd-L with no Bato page selected, a failure state in a split pane, fullscreen or modal-sheet behavior of the header, hover tooltips, and a keyboard-only pass. No daily-use readiness is claimed. No owned browser or throwaway server remains; the fixture server remains running. Private evidence (logs, screenshots) is under `/Volumes/Mahesh/personal/bato-build/logs/nav-header-v1*`.

## v2 after the header fixes

Checked 2026-11-06 with the fixed client build. Fresh `runtime/nav-header-state-v2`, wrapper `launch-nav-header-v2.py`, owned PID 91877; a throwaway 15-second delay server was used again and removed. v1 results above are retained.

| Check | Result | Evidence |
| --- | --- | --- |
| (a) Cmd-Shift-C | Fail | With the browser frontmost and a live Bato page selected, the key chord (synthetic CGEvent, System Events keystroke and key code) left the clipboard empty and the `workspace-key-routed` line never appeared in stderr, so the local key monitor either did not see the chord or its guards rejected it before logging; cause not established. Page > Copy URL from the menu bar did copy the exact URL. |
| (b) Failure state | Fail | The red warning pill appeared in one of three refused-connection attempts, for about a second, and the pill was back to normal within about 14 seconds; in the others it was not observed. It did not persist beyond Chromium's error-page commit and retry (a Stop state appeared during Chromium's automatic retry, then Reload). Because the failing and previous hosts were both `127.0.0.1`, whether the pill shows the attempted host could not be distinguished; the AX address stayed on the last good URL. Header Reload, Cmd-R and history-back clearing were not meaningfully testable since nothing stuck. |
| (c) Slow load shows attempted URL | Pass | During the 15-second load the pill AX value was the attempted slow URL and the button was "Stop loading", then "Reload page" afterward. |
| (d) New layout and Enter | Pass | Back, Forward, Reload sit in the top row beside the sidebar toggle, the redundant address field is gone, and the pill is borderless. Cmd-L (twice) and a pill click opened the prefilled bar and Enter submitted directly 3 of 3 times, loading in the current page with no new organization entry. The earlier Enter flake did not recur. |
| (e) Regression | Pass | Back and Forward enabled and acted correctly; during a Peek all four header controls were AX-disabled, Cmd-L opened no Bato bar, and organization bytes were unchanged. Quit via the app menu exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; final bytes equal pre-quit bytes; the preserved source organization is unchanged. |

### Remaining visual deltas against Dia and Arc

Resolved: controls moved into the top row beside the sidebar toggle (about 90 points of height recovered), the redundant field removed, a borderless muted pill. Remaining, approximate from screenshots:
1. Bato's toolbar row sits below the traffic lights; Dia and Arc share one row with them. Aligning the toggle and nav buttons with the traffic-light centerline would recover another 40 points.
2. Nav chevrons are still tighter than Dia's (about 36-point pitch there); increase spacing and size slightly.
3. The pill remains a filled capsule at rest; Arc shows it unfilled until hover.
4. The loading bar contrast and the transient red failure state remain weak, as noted in v1; the failure state should persist until a successful commit.
5. No per-space tint on the sidebar; low priority.
6. Saved entry title becomes the bare host after a failed load (carried from v1).

Not covered: Cmd-L with no Bato page selected, split in v2, fullscreen/modal header behavior. No daily-use readiness is claimed. No browser or throwaway server remains; the fixture server remains running.

## v3 after fix 2

Checked 2026-11-06. Fresh `runtime/nav-header-state-v3`, wrapper `launch-nav-header-v3.py`, owned PID 11906. v1 and v2 results above are retained.

| Check | Result | Evidence |
| --- | --- | --- |
| (a) Cmd-Shift-C | Fail | Several synthetic presses of the chord with the browser frontmost (including after clicking page content) still left the clipboard empty and logged no `workspace-key-routed` line. Cmd-Option-C produced no visible Inspect either, so synthetic modified key presses may not reach the application's key monitor the way a physical press does; this check needs a physical keyboard pass. The Peek variant was not reached: the Peek was not presented in that attempt (command-bar result selection went wrong), so no copy-during-Peek result. |
| (b) Failure state | Fail | The red pill showed the attempted host (`localhost`) in the one attempt sampled at 1 second, which confirms attempted-host display, but it was gone by 3 seconds in every other sample and by 30 seconds in the long sample, so it is not 3 of 3 and does not persist across Chromium's auto-reload. The pill then returned to the previous host (`127.0.0.1`) while the page still showed the error page for `localhost`. Clearing by a successful navigation was not separately tested. |
| (c) Visual | Pass for hover and rest | The pill is unfilled at rest and shows a fill on hover (verified by moving the pointer over it). Chevron spacing is slightly wider than v2. |
| (d) Regression | Mostly pass | Cmd-L plus Enter loaded the new URL in the current page with the pill value updated. Back and Forward clicks both worked but landed on equivalent URLs, so the history direction was not discriminated. Quit via the app menu exited 0; one each of native detach, slot-client detach, message-loop exit and CEF shutdown; pre-quit bytes equal final bytes; the preserved source organization is unchanged. |

Remaining visual deltas versus Dia and Arc: the toolbar row still sits below the traffic lights instead of sharing their row; chevron pitch is still narrower than Dia's roughly 36 points; the loading bar contrast is weak; there is no per-space tint; and the failure state is transient. Run notes: a mis-sequenced command bar interaction typed stray characters into Chromium's address field, but nothing was submitted, and one pre-quit snapshot had to be retaken. No browser remains; the fixture server remains running.
