# Empty Space results (2026-11-08)

Uncommitted. Real host: `cefsimple` test instance, `--use-mock-keychain`, SSD paths only (wrapper `tmp/launch-empty-v1.py`, states `runtime/empty-state-v{1,2,3}`, profiles `runtime/profiles/empty-v*`, logs `logs/empty-v*`), windows chosen by pid, every instance quit through the app menu (exit 0: `logs/empty-v{1,2,3}-exit.json`). dist/Bato.app untouched. Builds: `logs/empty-build1.log`, `empty-build2.log`. Screenshots in `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/empty-*.png`. `swift test`: 219 Swift Testing + XCTest, 0 failures; `test_patch.py` OK.

## Root causes

1. Creating a Space: the engine refuses to change its selection while the New Space sheet is attached (log: `native-slot-rejected attached-sheet`, `workspace-adapter-rejected available-slot`). `separateSplit`/`select(nil)` were rejected, `showSelection` returned false (`creationRejected` footer) and the old page stayed. P2's "empty workspace has no page to show" diagnosis was wrong: a plain switch to an empty Space already worked (blank anchor tab, no error, `empty-repro-switch.png`) but showed an about:blank omnibox page rather than an Arc-like card.
2. E3: `select(nil)` falls back to the launch Profile's window and nothing asked for the new Profile's window; windows were only requested when a page was created.
3. Close Tabs to the Right: enable state is Chrome's (`CanCloseTabsToRight`, strip order).

## Fixes by layer

- Core: `BrowserState.showsEmptySpace`.
- Runtime: `PageEngine.requestWindowIfMissing(for:)` (default false), used only by the explicit empty-selection path of `showSelection` (never by engine-side closes, so closing a Profile window is not undone); `showSelection` clears a stale `lastError` on success; `canCloseTemporaryTabsBelowSelection`.
- UI: `ContentCardFrameView.showsEmptyState` draws a workspace-tinted card with "Press ⌘T to open a tab", swallows clicks over the card; `createSpace` resumes the committed selection after the sheet ends; `makeCardFrame` initialises the flag for late windows.
- Client: `WorkspaceEngine.requestWindowIfMissing`, `CloseTabsBelowItem` retargets the Tab menu item (no engine change; engine patch untouched). Mirrors staged, `client.patch`/`client.json` regenerated (59 files, 54 mirrors), `native_slot.py check` ok.
- Tests: `EmptySpaceRuntimeTests` (4), `EmptyCardStateTests` (in `ShowSidebarButtonTests.swift`).

## Pass/fail

| # | Check | Result | Evidence |
|---|---|---|---|
| 1a | Repro before fix: create Space leaves stale page, footer error | reproduced | empty-repro-before |
| 1b | Create Space after fix: empty card, no error, no stale page | PASS | empty-create-space |
| 1c | Switch Research and back to the empty Space | PASS | empty-switch-research, empty-switch-back |
| 1d | Cmd-T from the empty card opens a tab, card goes away | PASS | empty-open-tab (the typed host without scheme loaded https and failed, unrelated) |
| 2a | New empty Profile gets its own window with the empty card | PASS | empty-new-profile-window (first build showed the blank about:blank page because the late window's card missed the flag; fixed by `makeCardFrame`) |
| 2b | Cmd-T in that window opens a tab in the new Profile | PASS | empty-new-profile-open-tab |
| 3a | Close Tabs to the Right enabled for a mid-sidebar tab that is last in Chrome's strip | PASS | menu read via System Events |
| 3b | Disabled for the last sidebar tab | PASS | menu read |
| 3c | Invoking it closes the temporary tab below | PASS | empty-close-right |

## Open

- Light mode and Increase Contrast of the empty card not screenshotted; the card reuses the sidebar tint with an 8% lift.
- Close Other Tabs has the same strip-order enable logic (not changed).
- The retarget matches the English menu title.
- Not exercised: closing the new Profile window then switching back to its empty Space (should request a fresh window by design).
- Also a stray "About This Mac" menu click occurred during quit (harmless, closed).
