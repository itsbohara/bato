# Milestone 3 results: window polish

Run 2026-11-07. Plan: MILESTONE3-PLAN.md. Not committed. No Ardia code; no images in the repo (screenshots on the SSD, `logs/m3-shots/`).

## Process

- `native_slot.py check` passed (66 files), `test_patch.py` 4 OK, `swift test` 161 XCTest + 176 Swift Testing, 0 failures (`logs/m3-swift-tests.log`; 7 new tests in `TabCommandsRuntimeTests`). Two `build --execute` runs succeeded (segment `logs/m3-build-segment.log`, last run only). Engine overlay now 19 files; client patch 46 files.
- To make the concurrent downloads agent's `NativeWorkspaceController` compile, I registered its 5 Downloads Swift files in `client.json`, the compile script and staged `BUILD.gn` inputs. They are compiled but unwired (no engine hook yet).
- Real host, `--use-mock-keychain`, quit only via "Quit Chromium": `tmp/launch-m3-v1.py` (baseline, old binary, exit 0), `v2` (first m3 binary; crashed entering fullscreen, exit -6, `logs/m3-v2-crash.json`), `v3` (fixed binary, exit 0), `v5` and `v6` (Apple Event link tests, exit 0). States `runtime/m3-state-v1..v4,v6` are distinct copies of `m2-state-v1`. v3, v5, v6 show `cef-shutdown-complete` once and no profile refused/mismatch.

## Results

| # | Item | Result |
| --- | --- | --- |
| 1 | F3 sidebar behind sheets | PASS (v2). Cmd-P print sheet: the full sidebar stays rendered behind it (`c02c.png`). Engine no longer hides the host for sheets. |
| 2 | Popups | PASS (v2). `window.open('popup,width=420,height=320')` is a 420x386 stock popup (title, read-only address, no tab strip, no sidebar slab; `c03-popup.png`); `postMessage` reply and `window.close()` still work. |
| 3 | Tab menu | PASS (v3). Duplicate Tab adds a tab on the same address; Pin Tab pins (and unpins); New Tab to the Right opens the command bar; Close Other Tabs closed all temporary tabs (pins kept); Move Tab to New Window consumed, no window. All logged as `workspace-chrome-command` 31/32/1/33/99. History > Recently Closed items are disabled. Not exercised: Close Tabs to the Right, Group Tab (same code path, covered by unit tests / hook only). |
| 4 | Cold-launch links | PASS with caveat. The hook now installs at client registration (log shows `external-url-routing-installed` before registration); a GetURL Apple Event sent 1-2 s after spawn (v6) opened a tracked "Bato compatibility fixtures" row; warm delivery (v5) also works. A true LaunchServices cold launch could not be driven: `open -a <app> --args ...` fails with -10810 and `open` toward a wrapper-launched pid starts a stray second instance (killed). Queueing for a busy workspace (sheet open) is code-only. |
| 5 | Second Cmd-W | PASS (v2). Three consecutive Cmd-W closed the selected tab each time and selected the next sidebar neighbour. Cause was the model clearing selection while Chromium picked its own neighbour or the about:blank anchor. |
| 6 | Fullscreen tab strip | PASS (v3): only the toolbar shows (`d01-fullscreen.png`), exit restores the window. Needed an extra engine fix: v2 crashed because `ImmersiveModeControllerMac::SetEnabled` sized an empty tab-overlay widget when no strip is drawn; it now skips that for sidebar-owning windows. |
| 7 | Window drag | PASS (v3). Baseline: CGEvent drags did not move the window. Now an empty sidebar area and the top row (new drag spacer; the switcher button no longer stretches across the row) move it. A drag from the Chromium toolbar was not retested. |

## Defects and open items

1. Fullscreen has no sidebar reveal and no tab switching UI except keys (Dia/Arc reveal the sidebar on hover).
2. The fullscreen toolbar is Chromium's stock bar (no Bato styling).
3. `target=_blank` links with an opener still create a stock normal window (now without the empty reservation); not retested after the reservation change.
4. Cmd-W with an unloaded neighbour creates its page at once; no setting for "select previous".
5. History > Recently Closed is disabled, not mapped; Recently Visited items still navigate Chromium directly.
6. A macOS prompt ("cefsimple would like to access files on a removable volume") appeared on Cmd-P; I clicked Don't Allow. Print still rendered.
7. Real LaunchServices cold launch, queueing behind a sheet, Close Tabs to the Right and Group Tab were not exercised on the host.
8. Split pointer divider untouched.
