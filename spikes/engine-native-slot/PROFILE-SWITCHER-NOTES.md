# Profile switcher, New Profile and Rename Profile

Status: implemented and unit-tested; not yet staged into the engine tree, not host-verified. No commit, no browser launch, no native_slot.py build.

## UX flow
- **Header switcher** (top sidebar row, replaces the plain workspace label): colored dot of the workspace plus its name; click opens a menu of workspaces. With more than one Profile the menu is grouped under Profile headers (Profile color dot; other Profiles read "<Name> · opens in its own window"). A check marks the current workspace; Control-1..9 are shown and also work from the sidebar (numbered in the grouped order). Footer items: New Workspace, New Profile…, Rename Profile… (current Profile).
- **Footer Profile button** (replaces the static Profile label): Profile color dot and name; menu lists Profiles (check = current; choosing one opens its first workspace), New Profile…, Rename Profile….
- **New Profile sheet**: name, color (palette with dots; defaults to the first color no Profile uses), first workspace name (empty = Profile name). Duplicate names (trimmed, case-insensitive) are refused in the sheet. Create saves the Profile and its workspace in one transaction and selects the workspace with engine work deferred until the sheet has closed (same pattern as Find Page). The first page opened there (Cmd-T) creates that Profile's window through the existing engine routing.
- **Rename sheet**: name and color; the Profile id, and so its engine storage, is unchanged.
- Switching to a workspace of another Profile is the existing runtime path (engine activates that Profile; a page opens or raises its window). A workspace with no selected page only changes the sidebar, not the window.
- Delete: deliberately not added. The engine exports have no context/data destroy call, so deleting would orphan cookies and site data on disk, and live pages/windows would need closing first. The launch Profile (first in `profiles`) must never be deletable regardless. Workspace deletion also does not exist yet.

## Reference mapping (private captures, never copied)
- `dia/2026-11-01/33-profile-switcher.jpg` (+ `.ax.txt`): dropdown from the top-left name, color dot per row, checkmark on current, Ctrl-N hints, "New Profile…" row below a separator. Mapped to the header switcher menu.
- `11-settings-profiles.jpg`: Profile list/names, used for the Profile naming/rename sheet scope.
- Ardia (GPL-3.0) swipe-to-switch was read as an idea only; not implemented, no code used.

## Files
- `app/Sources/BatoCore/BrowserState.swift`: `BrowserProfile.color` (optional, omitted from JSON when nil so old documents keep their bytes, validated when present), `createProfile`, `updateProfile`, `isProfileNameAvailable`, `hasMultipleProfiles`, `profileGroups` (`ProfileGroup`), `switcherWorkspaceIDs`, `switcherWorkspaceID(forShortcut:)`, `displayColor(of:)`, error `duplicateProfileName`. Name uniqueness is enforced only by the new mutations, not `validate()`, so imported documents stay loadable.
- `app/Sources/BatoRuntime/PageRuntime.swift`: `createProfile(…deferPageSelection:)` (create + activate in one `change`, refused and unsaved if the engine cannot open the Profile) and `updateProfile` (no selection reconcile).
- `app/Sources/BatoBrowserUI/NativeWorkspaceController.swift`: switcher button, Profile button/menus, `ProfileEditor` sheet, shared `sidebarColorPalette` and `colorDot`, Control-digit key equivalents. AX: "Current workspace" (value "<workspace>, Profile <name>"), "Profile", ids `bato-space-name`, `bato-profile-button`, `bato-profile-name`, `bato-profile-color`, `bato-profile-first-workspace`, `bato-profile-save`, `bato-profile-cancel`, `bato-profile-error`.
- Tests: `app/Tests/BatoCoreTests/ProfileSwitcherTests.swift` (6: create atomicity, validation, rename, legacy bytes, grouping/shortcut order, display color), `app/Tests/BatoRuntimeTests/ProfileSwitcherRuntimeTests.swift` (4: refused-unsaved, create/activate/route, deferral, rename keeps selection).
- No new compiled files, so `compile_native_slot.py`, `client.json` file list and `cef/BUILD.gn` need no changes. Three existing mirrors changed: BrowserState.swift, PageRuntime.swift, NativeWorkspaceController.swift.
- Full suite: 148 Testing + 117 XCTest tests pass; log `/Volumes/Mahesh/personal/bato-build/logs/profile-switcher-swift-tests.log`.

## Not done: client patch regeneration
`native_slot.py check` currently fails on WorkspaceSlot.swift, and nine mirrors differ from the staged tree because the concurrent blocking agent also changed WorkspaceSlot.swift, ImportPlan.swift, ArcImportController.swift, BlockingHostExports/Service/Controls and added BlockingProfiles.swift (a new compiled file needing the compile list, client.json and BUILD.gn). `regenerate-workspace-client.py` asserts every mirror equals its staged file, so it must run once, after both agents finish: copy the changed mirrors (list above plus theirs) into SSD cef/tests/cefsimple/bato, add their new file, then regenerate and run `native_slot.py check`. I did not touch the staged tree to avoid capturing their half-finished work.

## Verify on the real host
1. Switcher menu opens from the header, drawn under the traffic-light row, keyboard-reachable (Tab to button, Space opens); VoiceOver reads workspace + Profile.
2. Control-1..9 reach the sidebar while Chromium owns focus (the host key router may swallow them; only the sidebar view handles them).
3. New Profile: sheet attaches, Create dismisses cleanly, sidebar shows the empty new workspace, Cmd-T then opens a new window on a fresh `<cache>/<UUID>`; storage isolated from the launch Profile.
4. Selecting a workspace of another Profile with pages opens/raises that window; one with no pages only changes the sidebar (confirm this is acceptable or open a tab automatically).
5. Rename keeps cookies/storage; relaunch persists name and color; old documents without color load and show the first workspace's color.
6. Quit with an extra Profile window still has the known D8 hang, unrelated to this change.
