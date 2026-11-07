# Compact top and nested folders: real-host results

Run `compact-folders-v1` on 2026-11-07, uncommitted build, synthetic state cloned from split-pairs-state-v1, mock Keychain. Natural Quit via application menu: exit 0, one native detach, one CEF message-loop exit and one CEF shutdown; pre-quit and final organization bytes equal. Evidence: `compact-folders-evidence.json`. Raw logs and private captures are on the SSD under `logs/compact-folders-v1*`.

## 1. Compact top
Chromium toolbar (back, forward, reload, split button, omnibox with site info, profile, menu) shares the row with the traffic lights; no empty title row; page begins directly below (toolbar about 46 points). Docked: toolbar starts at the sidebar edge. Hidden (physical Cmd-S): toolbar starts after the traffic lights. Fullscreen enter/exit restores 260-point docked layout. Deltas: omnibox reads "or " until first navigation; traffic lights sit about 16 points above toolbar centre; the stock Chromium tab strip shows in fullscreen. Window drag from empty toolbar or sidebar strip was not observed with synthetic drags, so it is unaccepted.

## 2. Sidebar top row and navigation
Only toggle, edit workspace and workspace actions remain. Cmd-L opens the command bar prefilled with the current URL ("Go to"); Enter navigated the current page and updated the existing entry in place with no new organization entry. Chromium back/forward act on the active page, including the right split side after activating it. Peek is refused while a split exists; after Separate, Cmd-T offers "Open ... in Peek"; the toolbar then shows the peeked page and back was disabled. Note: `agent-desktop press cmd+s` hits the Save Page menu item; use a physical keystroke.

## 3. Nested folders
New Subfolder created levels 2-4 with about 12.5 points of indent each; AX labels carry the level. At level 4 New Subfolder is disabled. Move into Folder excludes self and disables descendants and the current parent. Collapse is written to the file. Rename at depth works. Dissolving level 3 then 2 moved their pins and child folders up one level with order kept. File version stayed 1 until the first subfolder and became 2 afterwards. Move into Folder was not executed, only its menu validity.

## 4. Visual comparison with Dia
Live Dia could not be captured; compared with private reference 02-new-tab.jpg. Remaining deltas: Dia places sidebar toggle, back, forward and reload next to the traffic lights in one row with the space name, while Bato keeps a separate sidebar toggle row below an empty strip and the toolbar starts at the sidebar edge; Bato toolbar is Chromium-styled with a pill omnibox and star; lights are not centred on the toolbar; no space-name label beside lights; no top bookmark/folder row; sidebar uses a flat grey strip rather than the tinted space background; page has no rounded inset card against the sidebar background at the top edge.

## 5. Quit
Clean, as above. Fixture server on 18765 left running; no browser left running.
