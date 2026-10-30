# Native organization preview

This is Bato’s first provisional application slice: a native Swift/AppKit + SwiftUI shell over a versioned organization model. **It does not render web pages yet.** Adding/selecting a tab currently exercises local organization and displays its destination. The existing source-built Chromium/native-slot experiment will supply the browser connection in the next slice; no WebKit or Electron substitute is used.

## Run

Requires macOS and Xcode’s Swift6 toolchain. The package declares macOS15 as its build floor; runtime acceptance currently covers only this Apple Silicon Mac on macOS27.0.1/Xcode26.3. It is not a supported-OS or distribution claim.

From the repository root:

```sh
python3 app/tools/dev.py test
python3 app/tools/dev.py build
python3 app/tools/dev.py run --state-directory /Volumes/Mahesh/personal/bato-build/runtime/alpha-shell-manual
```

Build output, Swift caches, module caches and temporary files default to the authorized SSD directory `/Volumes/Mahesh/personal/bato-build/alpha-swift`. Override with `--output-root /absolute/path` when needed. `build` produces `Bato Shell Preview.app`, locally ad-hoc signed. `run` waits for normal app exit. Quit an existing preview before rebuilding its bundle. Without `--state-directory`, the application uses `~/Library/Application Support/Bato Shell Preview`, separate from engine test Profiles and future product data.

## Implemented behavior

- One initial Personal Profile/workspace, stable IDs and ordered entries.
- Profile-wide Favorites; workspace-specific pins and temporary entries.
- Cmd+T opens address entry. Enter adds an HTTP(S) destination; no navigation or search is claimed. Embedded URL credentials are rejected.
- Right-click a temporary entry to pin it or add it to Favorites.
- Cmd+W removes a temporary entry, or clears selection of a saved entry while preserving it and restoring its saved destination. This preview has no live engine page to unload.
- Workspace menu creates/switches workspaces sharing the current Profile. Cmd+S toggles the sidebar.
- Version1 JSON organization storage, private files, advisory write locking, stale-writer rejection, atomic replacement and previous-good backup. The shell publishes a mutation only after its save commits.
- Invalid/unsupported documents stop editing and remain intact. A stale writer must reopen the preview to load the latest document.

The default Profile here is an organization record, not a new engine data directory. These tests do not establish cookie or credential isolation. Engine-owned site data and extension secrets are not part of this document format.

## Boundaries

`BatoCore` owns the Codable organization and validated transactional commands. `BatoPersistence` reads/writes the whole small document; versioning permits later migrations or a different backend. `BatoShell` owns the native preview and commit-before-publication session. Live engine pages and loaded/unloaded state are intentionally outside Codable organization.

`BatoRuntime` now supplies the main-actor live-page coordinator for the upcoming engine adapter. It loads selected entries lazily, separates process-local generations from saved IDs, and waits for confirmed engine closure before changing organization. Its fake-engine tests cover persistence failures, cancelled closes and late callbacks. The preview does not use this coordinator yet; see [the exact adapter contract and remaining connection work](ENGINE-ADAPTER.md).

The previous-good file is one rollback candidate. Seven daily backups, migration/pre-import snapshots, abnormal-exit recovery and an automatic recovery UI remain future slices. Directory metadata syncing is best effort; power-loss durability is not established. Locking coordinates cooperating local writers, not a hostile filesystem.

Folders, saved splits, Peek, archive, import, blocker controls, Profile creation/settings UI, workspace customization, page rendering and extension integration remain unimplemented application features. Required engine/extension checks continue alongside application work, as authorized on2026-10-30. See [acceptance results](RESULTS.md) and [the work plan](../TASK.md).
