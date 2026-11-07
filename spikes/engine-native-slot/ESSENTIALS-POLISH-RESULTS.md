# Essentials + polish: real-host results

Run 2026-11-07 on the uncommitted build (client + Swift dylib rebuilt 17:38), driven with `agent-desktop` plus `osascript` System Events for real key chords. Wrappers `tmp/launch-essentials-v1.py` (guard `logs/perprofile-v2-exit.json`, state `runtime/essentials-state-v1` copied from `perprofile-state-v2`) and `tmp/launch-essentials-v2.py` (guard `logs/essentials-v1-exit.json`, state `-v2` copied from v1 final); both `--use-mock-keychain`, cache path `profiles/workspace-v3`. Logs and screenshots live on the SSD (`logs/essentials-v1*`, `logs/essentials-v2*`, `logs/essentials-v1-shots/`); none are in the repo. Fixture servers 18765/18766 were already up. Bato was confirmed frontmost before each key chord. Nothing built, edited or committed.

| # | Check | Result |
| --- | --- | --- |
| 1a | Cmd-Y / Shift-Cmd-J / Cmd-, with page focused | FAIL (F1). Chromium handled all three itself. |
| 1b | App menu (History > Show full history, Window > Downloads, Chromium > Settings...) | FAIL (F1), same behaviour as 1a. |
| 1c | Command bar History / Downloads / Settings | PASS. History and Downloads: Bato-tracked row, org JSON updated, restore data saved. Settings: native window opened. |
| 2 | History per Profile | PASS. Visited `storage.html?label=essentials-A` only in Clients; Clients History listed it (2 entries); Personal History search for `essentials-A` returned "No search results", and the two lists are otherwise disjoint. |
| 3 | Essential tabs close and restore | PASS. Closing Download History by its row X removed the row, org entry and browser (count 9 to 8). After quit and relaunch (essentials-v2) History and Downloads rows came back, Downloads active and loaded; Personal's History tab is in the restored org JSON. |
| 4 | Settings panes | PASS. Profiles, Privacy, Import, Shortcuts, Advanced all render. Privacy switch read ON (settings file `enabled: true`, exception 127.0.0.1); clicking it wrote `enabled: false`, back wrote `true`, and the switch value followed. |
| 5 | Polish side by side | Done, see gaps. |
| 6 | Clean quit with 2 Profile windows | PASS. Chromium > Quit: exit 0 twice (`logs/essentials-v1-exit.json`, `-v2-exit.json`); `native-slot-detached`, `profile-contexts-released`, `cef-shutdown-complete` each as expected (2, 2, 1); no `refused`/`mismatch`/`Cannot create profile`; org sha identical before and after v1 quit. |

## Defects

- **F1 (high): Cmd-Y, Shift-Cmd-J, Cmd-, and the matching app-menu items bypass Bato.** Chromium opens its own untracked tab (chrome://history, chrome://downloads, chrome://settings): no sidebar row, org JSON unchanged, the previous row stays selected, Cmd-W closes the Chromium tab (browser count 4 to 3) and Cmd-, shows chrome://settings, not the native window. The same page opened from the command bar is tracked. `BatoWorkspaceChromeCommand` does exist in the built binary, `OnChromeCommand` is called for every command, and no log marker appears for these commands. I did not find the cause; likely candidates are an early `return false` in the active-browser checks or the ids not reaching the handler. Needs engine-side logging. The Shortcuts pane and command-bar footers advertise keys that therefore do not work as designed.
- **F2 (low): Settings rail rows are not accessible.** The AX tree lists only buttons and text; rail items have no role or label, so they cannot be driven or read by AT. The Settings window also needs to be made key first (clicks while the browser window was key did nothing).
- **F3 (low): sidebar content is blank while a sheet or the command bar is up.** New Profile sheet and command bar show a grey empty sidebar behind them (verified in a full-screen capture, so not a window-capture artefact). Dia keeps the sidebar visible.
- **F4 (low): control alignment inside Settings rows.** After a re-render, Rename, Remove and the shortcut chords hug the row text instead of right-aligning, and the switch sits right after the title (Dia right-aligns all of them).
- **F5 (info): launch window of an inactive Profile shows an empty grey sidebar** (the same as E3 in the per-Profile results); only the active workspace's window carries sidebar content.
- **F6 (info): command bar ranks "Search DuckDuckGo" above an exact command match** ("History" typed: search row selected, command second).

## Visual gaps vs Dia (ranked by impact)

1. **G1 Sidebar tint.** Green Personal and blue Clients workspaces read as near-neutral dark grey; Dia (33, 17) has a strong translucent workspace colour. Largest remaining difference.
2. **G2 Settings window scale and layout** (10, 11, 16). Bato is 780x540 with ~13pt text and ~54pt rows; Dia is ~17pt text, ~86pt rows, wider rail with larger rows and icons, back/forward title bar. Row actions and switches should right-align; add inset hairlines under the icon column and a "Advanced Settings"-style trailing button.
3. **G3 Selected row.** Still has an accent outline on the selected tab and on the focused favourite; Dia is a neutral lifted pill with no stroke. Hover (7% fill) is subtle but correct.
4. **G4 Section headings** "Tabs 4", "Favorites 3", "Pinned 2", "Saved pairs" still shown; Dia has none. Top actions remain two buttons ("New tab", "Find page") instead of one "+ New Tab" row at the end of the list.
5. **G5 Favorites tiles.** 3-up layout and close button work, but fixtures show the star fallback (no favicons), the X is always visible at the top-right, and tiles are shorter and flatter than Dia's roomy icon tiles (the real favicon case is untested here).
6. **G6 Command bar** (17). Bato: radius ok, inset rounded selection ok, but Cancel/Open footer, small subtitle line per row, no globe/leading icon colouring, narrower and shorter than Dia; Dia has a larger input row, a "Go" pill and one-line rows.
7. **G7 Footer workspace picker.** Borderless now, but renders as "Personal" with a tiny stepper arrow beside a plus and a second dim label; Dia uses a dot pager. At the narrowest sidebar the header workspace name collapses to an ellipsis and the picker stays unchanged.
8. **G8 Profile switcher** is a native NSMenu (checkmark, ^N hints work, dim group headers); Dia is a custom dark popover with larger dots and a "Profile Settings" gear row.
9. **G9 New Profile sheet**: height fits content, but 11pt hint, small inputs and a small sheet versus the Settings-like roomy rows in Dia; no direct reference capture.
10. **G10 Narrowest sidebar (about 215pt):** tab titles truncate with an ellipsis correctly and the close X stays visible; header workspace name truncates to "...".

## Not verified

- Cmd-, with the Settings window already key; Settings with fullscreen, a sheet or Peek.
- Dark versus light mode (the host was dark only).
- Personal's History tab after relaunch was checked in the org JSON, not on screen; Downloads restore was seen on screen in Clients.
- Create Profile, Rename and Import from inside Settings (sheets) were not exercised; only the New Profile sheet from the switcher.
- F1 root cause; whether the real accelerators are intercepted in some other focus state (only page content focus and the app menu were tried).
- Favicon-backed favourites, and hover on favourite tiles.
- The agent cursor overlay shows a small sparkle over the "New tab" glyph in several shots; it is the automation cursor, not UI.
- Keys used real System Events chords for 1a; `agent-desktop press` was observed to AXPress the menu item instead of sending the chord, so it was only used as a menu check.
