# Polish round 2: real-host results

Run 2026-11-07 on the uncommitted build (dylib `libBatoNativeSlot.dylib` 17:54, after the Round 2 Swift edits of 17:53), driven with `agent-desktop` plus `osascript` System Events chords. Wrapper `tmp/launch-polish2-v1.py` (guard `logs/f1-v3-exit.json`, state `runtime/polish2-state-v1` copied from `f1-state-v3`, `--use-mock-keychain`). Logs and screenshots are on the SSD (`logs/polish2-v1*`, `logs/polish2-v1-shots/`); none are in the repo. Fixture servers 18765/18766 were already up. Bato was confirmed frontmost before every key chord (`tmp/p2-key.sh` aborts otherwise). Nothing built, edited or committed. Dark mode only.

| # | Check | Result |
| --- | --- | --- |
| A1 | Cmd-Y, Shift-Cmd-J, Cmd-, route to Bato | PASS. History row selected, Download History row selected, native Settings window (960x700). |
| A2 | Command bar "History" ranks command above web search | PARTIAL. Command row is listed first, but the web-search row is the selected one, so Return would search the web (P1). |
| A3 | Go pill | PASS. Clicking Go opened the typed URL as a row. |
| A4 | Esc cancels | PASS (bar gone, no new row). Not confirmed that the bar was open before Esc by a separate capture. |
| B1 | Strong workspace tint on 2 colours | FAIL/PARTIAL. Orange Work (#FF8000): visible brown sidebar (#312920). Blue Clients/Work (#527FAD): #26272B and green Personal (#6D8B70): #282927, i.e. near neutral (P2). |
| B2 | Selected row neutral pill, no outline | PARTIAL. Fill is neutral (#646567) but a 1-2 px light ring (#B8B8B9) is still drawn around it on every workspace (P3). |
| B3 | No section headings | PASS (folder rows like "Work 2" and "Reading 3" remain; those are folders). |
| B4 | "+ New Tab" row above temporary tabs | PASS. Sits after a hairline, above temps; click opens the command bar. |
| B5 | Favorites tiles | PARTIAL. 58pt tiles with depth, close X only on hover (verified by hover), letter fallback works but shows "1" for 127.0.0.1 hosts and all tiles share one hue (P4). Favicon case untested. |
| B6 | Dot pager switches workspaces | PASS. Dots 2 and 3 switched to the Personal and Arc windows; the pager highlights the active dot. Switching across Profiles opens/raises that Profile's window (a third window was created for Arc). |
| B7 | Name at narrowest width | PASS. Dragged the divider to the minimum (about 214 pt); "Work" and "Personal" are intact, tab titles ellipsize, folder name ellipsizes. |
| C1 | Settings size and type scale | PASS vs Round 1 (960x700, 270 pt rail, large type); still smaller than Dia, see H3. |
| C2 | Right-aligned actions | PASS. Rename, Create Profile, Remove, Open, switch and chords right-align. The Shortcuts card is 16 pt narrower than the other panes because of its scroller (P5, cosmetic). |
| C3 | Rail rows clickable on first click | PASS. With the browser window key, one physical click on Privacy (and then Import/Shortcuts/Advanced) switched the pane. Rail rows are AX buttons. |
| D | Clean quit | PASS with 3 Profile windows (Clients, Personal, Arc). Quit through app menu "Quit Chromium": exit 0 (`logs/polish2-v1-exit.json`); `native-slot-attached`/`-detached` 3/3, `profile-contexts-released` 2, `cef-shutdown-complete` 1, no `refused`/`mismatch`/`Cannot create profile`. |
| E | Side-by-side | Done, see gaps. |

## Defects

- **P1 (medium): command bar selection sticks to the web-search row while typing.** `CommandBarController.swift:145-151` re-selects the previous row by id after each refresh; the search row is selected for the first character and stays selected when "History" becomes the better match. Result: the exact command is first in the list but Return runs the search.
- **P2 (high): muted workspace colours produce an almost neutral sidebar.** Dark mode delta from neutral is about 3-5 levels for blue and green; only saturated colours (orange) read. Dia 33/17 is clearly tinted.
- **P3 (medium): selected row still has a light 1-2 px ring.** Probably the new "hairline" in `SidebarStyle`, not the focus ring; the Round 2 goal was no outline.
- **P4 (low): favorite letter fallback uses the first character of the host** ("1" for IP hosts, so three tiles identical); no title/hue differentiation.
- **P5 (low): Shortcuts card narrower than other Settings cards.**
- **P6 (info): the command bar turns a bare `127.0.0.1:18765/...` into an https URL** (the row offered `https://127.0.0.1:18765`), so local http fixtures need an explicit `http://`.
- **F3 persists (low): sidebar is a blank grey slab behind the command bar** (seen in the history, URL and New Tab captures). Dia keeps the sidebar and tint visible.
- Regressions vs essentials-v1-shots: none found. Cmd-Y/Shift-Cmd-J/Cmd-, now work (F1), F2 and F4 are fixed.

## Remaining gaps vs Dia, ranked by impact

1. **H1 Tint strength** (P2): Dia's sidebar is a translucent, strongly coloured wash; Bato only shows it for saturated colours.
2. **H2 Command bar** (17): Bato is now close (Go pill, one-line rows, rounded selection). Missing: the sidebar staying visible behind it (F3), the leading globe/search icon in the input, an "Add tabs or files" chip, and the provider picker is a small footer label. Selection bug P1.
3. **H3 Settings** (10, 11, 16): no back/forward title bar, no grouped section headings above cards ("Content blocking"), no trailing "Advanced Settings"-style button, rail icons smaller, the selected rail row is a flat blue where Dia has a lifted pill, window has no toolbar rows. Type scale is about 15 pt vs Dia's ~17 pt.
4. **H4 Selected pill ring** (P3) and no per-row hover animation.
5. **H5 Profile switcher**: still an NSMenu; Dia 33 is a custom dark popover with larger dots and a "Profile Settings" row. Not exercised this run.
6. **H6 Favorites**: Dia uses real favicons on soft rounded tiles; Bato shows letter tiles with borders. Equal width, good depth.
7. **H7 Pager dots**: present and functional, but dim and tiny (6 pt) at the bottom-left, with the profile name beneath; Dia has the same pattern with a larger active dot.
8. **H8 Traffic-light row**: workspace name and sidebar toggle sit in the title row (matches Dia); the top bar of the page area is still Chromium's stock omnibox/toolbar rather than Dia's slim bar (out of scope).

## Not verified

- Light mode, translucency, contrast on all workspace colours (only orange, blue, green were sampled).
- Favicon-backed favorites; sheets (New Profile, Import) after the Round 2 change; the Settings Profiles actions (Rename/Create sheets).
- Cmd-, while the Settings window is already key; keyboard-focus visibility of rows now that focus rings are off.
- Whether the Esc test had the bar open at the moment of Esc (inferred from the following Go-button search count of 0 and the unchanged tab list).
- The first command-bar chord in each run was real Cmd-T; the "+ New Tab" click used AXPress rather than a physical click.
- Window moving/resizing of the browser windows was used to expose the Settings window for the first-click test (min browser size 760x800) and restored for window 1 only.
