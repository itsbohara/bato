# Archive and uBlock Origin first-run offer

Swift only (`app/`). No engine build or real-host run; both features are covered by unit tests and a clean `swift build`, not yet seen on screen. Test log: `/Volumes/Mahesh/personal/bato-build/logs/archive-ublock-swift-tests.log` (192 tests in the Swift Testing run plus XCTest, 0 failures).

## 1. Archive

- **Model** (`BatoCore/Archive.swift`): `ArchivePeriod` (12h, 24h, 7d, 30d, never), `ArchiveRecord` (tab identity, Profile, workspace, title, URL, position, archived time) and `ArchiveState` (global period plus records). Per-workspace override is `Workspace.archivePeriod`; it wins over the global period. Default is Never, per DESIGN.md.
- **Schema**: version 3, following the nested-folders v1/v2 precedent. Nothing new is encoded until the archive is used (`archive` key, `Workspace.archivePeriod` and `PageEntry.lastActiveAt` are all omitted when empty), and `stampActivity` does nothing while every workspace is Never, so existing documents stay byte-identical (tested through `OrganizationStore`). A document below version 3 that carries archive data fails validation, like a v1 document with nested folders. Version 4 is still rejected.
- **Idle rule**: a temporary tab is idle when `now - lastActiveAt >= period`. `lastActiveAt` is written before every runtime change (so a tab you just left keeps its last-used time) and by the sweep. A tab with no stamp starts its clock at the first stamp, so turning the archive on never archives anything immediately. Never archived: Favorites, pins, the selected tab of the current workspace, split members.
- **Runtime** (`PageRuntime`): `clock` is an injectable time source; `archiveTab`, `archiveIdleTabs`, `restoreArchivedTab`, `deleteArchivedTab`, `setArchivePeriod`. A loaded page is archived when the engine reports it closed (a cancelled close, e.g. beforeunload Cancel, keeps the tab). Archived tabs do not enter the Cmd-Shift-T closed-tab stack. Restore reuses the tab id, puts it back at its old index in its original workspace, or the first workspace of the same Profile if that is gone, and selects it.
- **UI** (new files `ArchiveSheet.swift`, `ArchiveController.swift`): a sweep every 5 minutes plus one at launch; an Archive sheet (search by title/address/URL, Restore, Delete, relative age) scoped to the current Profile. Entry points: command bar "Archive" and "Archive Current Tab", tab row context menu "Archive Tab", and a new Settings > Archive pane (global period, per-workspace override, Open Archive). Restore defers page work until the sheet closes, like Find Page.
- **Limits**: no Arc-style sidebar section for archived tabs; the archive is unbounded; the 5-minute sweep means the "last used" time of a tab can lag by at most one runtime change.

## 2. uBlock Origin first-run offer

**Which meaning:** PLAN.md ("Optional uBlock Origin download") describes downloading the official extension zip with a pinned SHA-256. I did not implement that: the engine cannot load it (needs the MV2 gate, `--allow-legacy-extension-manifests`, and a real-host load-order check), and a pin cannot be verified without that run. I implemented the part that works today with the shipped adblock-rust engine: the uBlock Origin project's own filter lists (uBlock filters, Privacy, Badware risks, Unbreak, from `ublockorigin.github.io/uAssets`, GPL-3.0), downloaded by the existing `FilterListUpdater`. The extension download stays design-only in PLAN.md.

- `FilterListSource` gained `requiresHeader` (uBlock lists start with `!` comments, not `[`); source sizes and minimum rule counts were set from a live download (filters ~24k rules, privacy ~1.9k, badware ~4.9k, unbreak ~2.6k).
- `UBlockListsChoice` (`list-choices.json` in the blocking root, machine-wide because lists are shared by Profiles): undecided, enabled, declined. `BlockingProfiles` adds `shouldOfferUBlockLists`, `declineUBlockLists`, `enableUBlockLists` (consent, then download; returns per-list outcomes) and `disableUBlockLists` (deletes the files). Nothing is fetched while undecided or declined; once enabled, the daily update keeps them fresh and retries failures. The host already builds its engine from every `lists/*.txt`.
- UI (`UBlockOffer.swift`, reusing the compact Dia-style `RecoverySheet` card): offered 2 s after launch if still undecided and no sheet is open; Not Now or Escape records "dismissed" so it shows once; Add Lists downloads and shows a success or retry-later result. Settings > Privacy has an "uBlock Origin filter lists" row with Add… (re-offers) or Remove.

## Edits outside new files

`BrowserState.swift`, `PageRuntime.swift` (additive), `CommandBar.swift` (two commands), `SettingsModel.swift` (Archive pane), `SettingsWindowController.swift`, `FilterListUpdater.swift`, `BlockingProfiles.swift`, and small localized edits to `NativeWorkspaceController.swift` (archive controller property, Settings hooks, start-up call, command-bar cases, context-menu item). An earlier set of my edits to that file was overwritten by a concurrent write and re-applied; recheck it still contains `archiveController` after merging.

## Real-host checks still to do

First-run sheet timing against the recovery notice; Settings Archive pane layout; Archive sheet appearance and Restore focus; archiving a loaded page and beforeunload Cancel; 12h sweep behaviour over a real session; a real list download and engine rebuild after Add Lists.
