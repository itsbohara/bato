# Arc parity audit (basic browser features)

Run 2026-11-08, read-only. Bato side: a throwaway test instance (`launch-audit-v1.py`, state `runtime/audit-state-v1` cloned from `sidebar-seed`, `--use-mock-keychain`, pid-selected windows, quit through the app menu, exit 0). Arc side: the installed Arc driven through `agent-desktop` for chrome and behaviour only; only a throwaway `example.com` tab, a Little Arc window and an Incognito window were created and all were closed afterwards. No Arc page contents, tab titles, URLs, spaces or data files are recorded here, and no Arc screenshots are kept. Screenshots of the Bato instance are under `/Volumes/Mahesh/personal/bato-build/tmp/arc-audit/` (outside the repo).

Evidence levels: **observed** (driven on this run), **docs** (earlier RESULTS docs, not re-run), **Arc-menubar** (item present in Arc's menu bar, behaviour not driven), **memory** (Arc behaviour from general knowledge, not driven). Synthetic keys (System Events, CGEvent) do not always reach Bato's key monitor, so "broken" on a key chord means "failed under synthetic input after two methods and a sidebar click"; it still needs one physical-keyboard pass.

Fix owner: **Swift** = app/Sources only; **client** = `native_slot_client.mm` (no Chromium rebuild); **engine** = Chromium/CEF overlay rebuild.

## Prioritized findings

### P0 broken basics

| # | Feature | Arc | Bato (observed) | Status | Fix |
| --- | --- | --- | --- | --- | --- |
| 1 | Switch workspace with Ctrl-1..9 | Ctrl-N jumps to Space N | Ctrl-1 and Ctrl-2 did nothing with two workspaces, from page focus and after clicking a sidebar row (via System Events and CGEvent). The handler is `SidebarView.performKeyEquivalent`, which PROFILE-SWITCHER-NOTES already flagged as possibly swallowed while Chromium owns focus. Dot-pager click switches fine. Settings > Shortcuts labels the chord "Switch Profile ^1-9" although it switches workspaces. | broken (needs physical check) | Swift: register Ctrl-digit as NSMenu key equivalents (Cmd-T and Cmd-W reach Bato through the menu, the view handler does not); fix the Shortcuts label |
| 2 | Copy page URL (Cmd-Shift-C) | Cmd-Shift-C; Edit menu has Copy URL, Copy URL as Markdown, Copy URL as Quote | Clipboard unchanged after Cmd-Shift-C (same as NAV-HEADER-RESULTS, never passed). Bato's Edit menu has no Copy URL item, so the chord has no menu fallback and Chromium maps it to Inspect. | broken (needs physical check) | Swift: add Edit > Copy URL with the key equivalent so it routes like Cmd-T |

### P1 missing or differing basics

| # | Feature | Arc | Bato (observed) | Status | Fix |
| --- | --- | --- | --- | --- | --- |
| 3 | Drag reorder / drag to pin, favorite, folder, workspace | full drag and drop in the sidebar | no drag source or drop target on sidebar rows (only download rows drag); a synthetic drag changed nothing; Move Up / Move Down in the context menu is the only reorder | missing | Swift |
| 4 | Middle-click closes a tab | yes (memory) | middle-click on a row did nothing; no `otherMouse` handler | missing | Swift |
| 5 | Tab context menu | Arc-menubar and memory: Pin, Close, Duplicate, Mute, Copy URL variants, Move to Space, Archive, Open in Peek/Little Arc | Pin Tab, Add to Favorites, Archive Tab, Copy Link, Split with Current Page, Move Up/Down, Move to Workspace. No Close, Duplicate, Reload, Mute, Rename or Open in Peek on the menu (Duplicate exists only in the Tab menu bar item). | missing items | Swift (commands already exist in `PageRuntime`) |
| 6 | Audio indicator and mute | speaker glyph on a playing tab, click to mute | nothing in sidebar rows; only the Chromium Tab > Mute Site menu item | missing | client + Swift (needs an audio-state callback in the ABI, so possibly engine) |
| 7 | New window (Cmd-N) | opens a second window | Cmd-N opens the command bar in the current window; one window per Profile. File > New Window is therefore a no-op for window creation | differs | Swift decision (Little Arc/window model in DESIGN.md) |
| 8 | Private window (Cmd-Shift-N) | Arc-styled window with its own sidebar and an "Incognito Tabs" section | opens a stock Chromium window: horizontal tab strip, light stock toolbar, Google "AI Mode" omnibox chip, Chromium incognito page | differs | engine (opt incognito browsers into the sidebar/slot) then Swift |
| 9 | Menu bar | Spaces, Tabs, Archive, Extensions menus; Show/Hide Sidebar; Next/Previous Space; Pin/Unpin; Clear Unpinned Tabs | stock Chromium bar: Bookmarks menu, a Profiles menu listing leaked Chromium profiles ("Your Bato", "Person 1-4"), View > Always Show Bookmarks Bar, Show Tabs Vertically, Always Show AI Mode; no Spaces menu; History menu shows per-window session groups. The app menu title read "cefsimple" in this test bundle (check the packaged app) | differs | Swift (`MenuBranding` can remove and add menus) |
| 10 | Leftover Chromium toolbar | no toolbar; URL pill lives in the sidebar, no star | Chromium toolbar still shows address field, bookmark star, zoom icon, profile button and three-dot menu above the content card, duplicating the sidebar URL pill. Site info, password and permission bubbles anchor to it, so removing it needs replacements | differs | engine (toolbar views) |
| 11 | Extensions | toolbar icons and an Extensions menu | none visible; Chromium extension UI not exposed (user-deferred, EXTENSION-TEST-PLAN.md) | missing | engine |
| 12 | Right-side sidebar | option exists in Arc's sidebar settings (memory) | no setting (resize grip and Cmd-S exist) | missing | Swift plus layout in engine reservation |

### P2 nice to have / polish

| # | Feature | Arc | Bato | Status | Fix |
| --- | --- | --- | --- | --- | --- |
| 13 | Create workspace | asks for name, icon and theme | one click creates "Workspace 2" with the next palette colour; naming and colour via Workspace actions > Edit Workspace; no icon or gradient theme | differs (works) | Swift |
| 14 | Folders | nest, hold any tab | flat, pins only, no nesting, no folders for today tabs; create/rename/collapse via Workspace/Folder actions (docs) | partial | Swift |
| 15 | DevTools | docked in the page with dock-side buttons | opens as a separate 640x640 window (works, Cmd-Opt-I) | differs | engine (dock inside the slot) |
| 16 | View source (Cmd-Opt-U) | new tab | works but the source tab is invisible in the sidebar (row still shows the previous page, Cmd-W closes the hidden tab) | differs | Swift |
| 17 | History page | Arc-styled history | stock chrome://history opens as a tracked row but shows Chromium's "Sync history" promo although sync does not exist | differs | engine (WebUI) or Swift (inject) |
| 18 | Hover on a tab | hover card with title and site | close button only, no tooltip or card | missing | Swift |
| 19 | Archive | Archive menu, sidebar section, auto-archive | auto-archive with Settings > Archive and Archive Tab; no sidebar section (docs) | partial | Swift |
| 20 | Little Arc | Cmd-Opt-N small floating palette window | none by design (deferred); Peek via command bar and link menu "Open Link in Peek" exists | missing (deferred) | Swift + engine |
| 21 | Copy URL as Markdown/Quote, Capture, Notes, Easel, Boosts | Arc-menubar items (Boosts memory) | none | missing (note only) | Swift for copy variants; rest out of scope |
| 22 | Picture-in-picture | Arc auto-PiP on tab switch (memory) | Chromium PiP not exercised; no auto-PiP | unverified | engine |
| 23 | Keyboard shortcut list | Help > Essential Keyboard Shortcuts | Settings > Shortcuts lists ~8 chords, one mislabeled (see 1); no Ctrl-Tab, Cmd-1..9, Shift-Cmd-T, zoom entries | partial | Swift |
| 24 | Command bar | Cmd-T palette with tabs, history, commands | equivalent: tab switch rows with workspace chips, Open / Open in Peek, Cmd-L selects the URL | ok | none |

## Features that matched (observed on this run)

| Feature | Result |
| --- | --- |
| New tab / palette (Cmd-T), open URL | ok; layout and "Switch to Tab" rows mirror Arc's palette |
| Close tab (Cmd-W), reopen (Shift-Cmd-T) | ok |
| Pin from context menu | ok; pinned row moves above folders |
| Cmd-L | ok; opens the palette with the URL selected |
| Find in page (Cmd-F) with match count | ok (Chromium bar under the toolbar; Arc's sits top right) |
| Zoom in/out/reset | ok; zoom icon appears in the toolbar |
| Print (Cmd-P) with Save as PDF | ok |
| View source, DevTools | work (see 15, 16) |
| New workspace, switch via dot pager | ok; workspace tint changes, Favorites are shared across workspaces |
| Sidebar hide/show (Cmd-S), show-sidebar button, edge-hover reveal | ok |
| Settings (Cmd-,), History (Cmd-Y) | ok; native Settings window with General, Profiles, Privacy, Archive, Import, Shortcuts, Advanced, About |
| Page and link context menus | ok; link menu offers Open Link in New Tab, in Peek, in Split View |
| Quit through the app menu | ok, exit 0 |

## Not driven (docs only, or not reachable)

Downloads, permission prompts (camera, notifications), site info, password autofill and save bubble (the fixture login page blocks navigation, so Chromium never offers to save), multi-Profile windows, swipe between workspaces, duplicate tab, split view layout and pointer divider, Peek presentation, sidebar resize drag, back/forward and reload buttons, audio playback. See ALPHA-GAPS.md and the results docs for their last verified state. Arc's tab context menu, hover card, drag behaviour, Little Arc contents and history were not captured to avoid personal data.

## Summary by owner

- **Swift only:** 1, 2, 3, 4, 5, 9, 12 (setting), 13, 14, 16, 18, 19, 23.
- **client or engine:** 6 (audio callback), 8, 10, 11, 15, 17, 22; 12 needs the engine slot reservation to flip sides.
