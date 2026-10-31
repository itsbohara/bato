# Native Cmd+T command bar

Date: 2026-11-01. Status: source verification, bounded command-bar workflows and same-provider restart passed; initial v1 rendering anomaly retained.

Cmd+T and the native New Tab action now present a rounded, borderless AppKit panel through the owned browser window's sheet lifecycle. This is a floating visual surface with modal sheet behavior, not an independent free-floating child window. Chromium continues to own browser content, origin UI and extension controls. The existing sheet/modal, hidden-host, fullscreen and lifecycle guards remain intact; no engine API or organization schema changes are introduced.

The bar combines HTTP(S) navigation, web search, current-Profile organization search across workspaces, direct page activation and three browser commands: Find Page, Toggle Sidebar and Close Current Page. Results retain stable identities as page state changes. Arrow keys select, Return/Open accepts, and Escape/Cancel dismisses. Unsupported commands are filtered from the connected host's results. Existing-page actions revalidate entry and workspace identities through PageRuntime.

Input classification and result construction are local. Typing sends no query or page data to a search provider. Search begins only when its result is accepted. DuckDuckGo is the proposed alpha default; a visible picker also offers Google. Provider choice is session-local and is not saved to organization. HTTP(S) inputs reject credentials, unsupported schemes, control characters and malformed network destinations. Search query encoding preserves Unicode, delimiters and literal plus signs through form decoding.

An accepted action is captured without changing organization while the sheet is open. After dismissal, the existing CEF UI scheduling callback restores the owner window and native focus before executing page work. Pending actions are bound to that owner and consumed before restoration guards; stale or blocked presentation cancels the intent rather than executing it on a later callback. Failed saves retain the query and reopen the bar with an error. A page-creation failure after a successful organization save does not create a duplicate entry. The preexisting sidebar HTTP(S) address field and separate Find Page picker remain available.

## Verification

Independent source review found and corrected pending-intent retention across rejected restoration callbacks; final review found no blocking source defects. Seven focused command-bar model tests passed, covering URL/search classification, rejected inputs, provider selection, form query encoding, Profile boundaries and stable result identities. Six native-slot tests and two additional patch tests passed. The final Swift package build passed in 5.59 seconds.

The source host built in 37.57 seconds/seven steps initially and 20.19 seconds/seven steps after final corrections. Actual compiler output is retained on the SSD as `logs/command-bar-initial-compiler.log` and `logs/command-bar-final-compiler.log`; focused test output is `logs/command-bar-core-tests.log`. The fifteen-file client patch roundtrip, eleven source mirrors and twenty-three overlay checks passed. Engine ABI remains nine authored exports and ten WorkspaceConfigure arguments. Compiler inputs and source mirrors now include the separate command-bar model and UI files. No engine change or broad extension retest was needed.

## Initial real-host run

Synthetic run `command-bar-v1`, PID 50531, demonstrated that holding Cmd+T for 1100 ms opens one bar; Cmd+W and Cmd+S leave that open sheet intact. Unicode paste produced a local result preview. Choosing Google persisted across reopening the bar within the session. Escape left exact organization bytes unchanged. Hidden-sidebar Cmd+T opened the bar, and accepting a local HTTP URL with `?command-bar=1` created a real third browser and temporary entry. Arrow selection and Return executed Close Current Page after dismissal and returned to the original modal page.

The original modal renderer then remained black while its title, toolbar and sidebar were present. Sidebar selection, reload and switching native tabs did not restore its page area. The initial bar had shown the real page behind dimming, so this was not an accepted rendering baseline. An earlier `WidgetHost` message 7 rejection is retained in the raw log, before the first sheet-ended event; its relationship to the black page is unknown. No engine fix or sheet-presentation cause is claimed.

A newly opened Favorite login page rendered. A Google search for `bato synthetic + query & sample` navigated to real rendered results with `%2B` and `%26` in the accepted search URL; Cmd+W closed it. Unloading the affected saved modal page and finding it from Research via Cmd+T, Down and Return opened the real page in Personal. It rendered correctly and its activity counter advanced 0→1. Repeating that query and activation reused the live page with counter 1 and no additional browser creation. Repeating local URL creation with `?command-bar=2`, then Close Current Page, returned to the rendered modal page with counter 1. The initial black-page anomaly did not reproduce after recreation in this same binary; it remains unexplained rather than marked repaired.

V1 completed normal application-menu Quit with exit 0 and exactly one native detach, message-loop return and CEF shutdown. The coordinator verified final organization bytes exactly equal the pre-run bytes. Raw log, exit receipt and snapshots are SSD `logs/command-bar-v1.log`, `logs/command-bar-v1-exit.json` and `logs/command-bar-v1-*.json`.

## Same-provider restart

V2 restarted the same binary, synthetic organization and synthetic engine Profile with `--use-mock-keychain` again, PID 65495. The original modal page visibly rendered at baseline, and activity advanced 0→1. Cmd+T showed DuckDuckGo again, confirming the previous Google choice was session-local. Accepting local HTTP `login.html?command-bar=restart` opened a new page. Cmd+T, Close Current Page, Down and Return closed it and returned to the rendered original modal page with counter 1. The v1 black-page behavior did not reproduce in this restart; no engine change, root-cause attribution or repair claim follows.

The final Cmd+T query `tab-modal` selected the existing-page result with Down; the coordinator retained `logs/command-bar-v2-final.png`, then dismissed with Escape. Normal application-menu Quit exited 0 with exactly one native detach, message-loop return and CEF shutdown. The coordinator verified exact pre-run/final organization-byte equality. V2 logs, exit receipt and organization snapshots use `logs/command-bar-v2*`. No owned browser or build remains; the owned loopback fixture server on 18765 remains running.

## Current limits

The initial v1 rendering anomaly remains open despite successful repetition after recreation and restart. Runtime observations accept only the recorded command-bar workflows. Find Page and Toggle Sidebar command execution have source review but no new runtime acceptance here. Search-provider persistence, fullscreen, light appearance, broad accessibility/window coverage, complete Arc-style chrome and daily-use readiness remain outside this checkpoint. Raw screenshots, logs, browser data and organization snapshots stay outside Git under `/Volumes/Mahesh/personal/bato-build/`.

See [structured evidence](command-bar-evidence.json).
