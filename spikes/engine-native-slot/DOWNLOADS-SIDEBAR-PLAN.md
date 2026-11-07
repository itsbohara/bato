# Plan: downloads in the sidebar instead of Chromium's bubble

Written 2026-11-07. Supersedes decision 1 of MILESTONE2-PLAN.md ("no Bato surface"), which deferred this until engine download events existed. Swift side is implemented; the engine side is not started.

## References

The Dia 1.55.1 captures (`dia/2026-11-01/`) contain no downloads surface, and the earlier Arc captures (`ideastorm/bato-references/`) show only the sidebar, space and command bar. The UX below therefore follows Arc's known behaviour (downloads icon in the sidebar footer, shown only once the Profile has downloads; a popover list with progress, Show in Finder, drag-out) and is styled from `SidebarStyle`. Capture an Arc/Dia downloads popover before visual polish; until then treat the layout as provisional. No Ardia code is used.

## UX

- Footer button in the workspace row (left of "+"), 28 pt, arrow glyph inside a ring. Hidden while the current Profile has no downloads. The ring fills with combined progress of sized active downloads (indeterminate arc when sizes are unknown) and a dot marks a download that finished since the list was last opened.
- Click opens a 320 pt popover: "Downloads" header with Clear (removes finished rows from the list, never files), then rows newest first.
- Row: file icon, name (middle truncation), progress bar while active, status line ("4.2 MB of 48 MB · 1.1 MB/s", "Done · 48 MB", "Paused", "Failed · can resume", "Cancelled", "File moved or deleted"). Hover (or active) reveals icon actions: Pause/Resume, Cancel, Show in Finder, Remove from list. Double-click opens a completed file; dragging a completed row out copies the file (outside the app only).
- Per Profile: the button and list show only the current workspace's Profile, matching Chromium's per-Profile history (MILESTONE2-RESULTS item 5). Switching Profile closes the popover.
- Chromium's toolbar button, bubble and download-started animation are suppressed (below). "Full Download History" and the Downloads essential still open the tracked `chrome://downloads/` row.
- Not in scope: a Settings row (no reference shows one), notifications, Save As prompt (still `~/Downloads`).

## Swift data model (done)

`BatoCore/DownloadsModel.swift`: `DownloadItem`, `DownloadState`, `DownloadEvent`, `DownloadAction`, `DownloadsEngine` protocol, `DownloadsModel` (per-Profile lists, aggregate progress, unseen-finish tracking), `DownloadFormat`. `BatoCore/DownloadsController.swift` binds an engine to the model. UI: `BatoBrowserUI/DownloadsButton.swift`, `DownloadsPopover.swift`, `DownloadsSidebar.swift`; the host calls `NativeWorkspaceController.attachDownloads(_:profileKey:)` once. Tests: `Tests/BatoCoreTests/DownloadsTests.swift` with `FakeDownloadsEngine`.

## Engine to Swift contract

Mirror the existing pattern: a registration export taking a size/version-tagged callback table, separate from the other tables so each keeps its exact v1 size. Register once on the main thread before `CefInitialize`; callbacks run on the CEF UI thread, which is the main thread in this host; the client copies all strings during the call.

```c
typedef struct BatoDownloadInfoV1 {
  size_t size;               // sizeof(BatoDownloadInfoV1)
  const char* profile_key;   // UTF-8; same key the client passes to BlockingControls ("" is the launch/default context)
  const char* id;            // UTF-8, stable for the item's life: DownloadItem::GetGuid()
  const char* filename;      // basename of GetTargetFilePath(), or suggested name until the target is chosen
  const char* path;          // full target path once known (GetFullPath() when complete); "" before
  int64_t received_bytes;
  int64_t total_bytes;       // -1 unknown
  int64_t bytes_per_second;  // 0 unknown
  int32_t state;             // 0 in_progress, 1 paused, 2 completed, 3 failed (interrupted), 4 cancelled
  int32_t can_resume;        // 1 when CanResume() (failed or paused)
  int32_t file_exists;       // 0 when completed but the file was moved/deleted (GetFileExternallyRemoved)
} BatoDownloadInfoV1;

typedef struct BatoDownloadCallbacksV1 {
  size_t size;
  uint32_t version;          // 1
  void* context;
  // Created, progress, state change, completion, failure, cancellation: one snapshot callback.
  // Throttle progress to at most ~4 per second per item; always deliver state changes immediately.
  void (*upserted)(void* context, const BatoDownloadInfoV1* info);
  // Removed from history or by the remove action.
  void (*removed)(void* context, const char* profile_key, const char* id);
} BatoDownloadCallbacksV1;

CEF_EXPORT int bato_native_slot_register_download_callbacks_v1(const BatoDownloadCallbacksV1* callbacks);
// Replays every download of every live Profile through upserted. Main thread.
CEF_EXPORT int bato_native_slot_download_snapshot_v1(void);
// action: 0 pause, 1 resume, 2 cancel, 3 open (OpenDownload / platform open), 4 show in Finder
// (ShowDownloadInContainingFolder), 5 remove (DownloadItem::Remove, file untouched).
// Returns 1 when accepted; 0 for an unknown id/Profile or an action invalid for the state.
CEF_EXPORT int bato_native_slot_download_action_v1(const char* profile_key, const char* id, int action);
```

Swift mapping: `upserted` becomes `DownloadEvent.upsert(DownloadItem)`; `removed` becomes `.removed`; `DownloadsEngine.requestSnapshot` calls the snapshot export; `DownloadsEngine.perform` calls the action export (`DownloadAction` order above). The engine need not distinguish created from updated: the first snapshot for an unknown id creates the row.

Engine rules:
- Observe every Profile's `content::DownloadManager` (`DownloadManager::Observer::OnDownloadCreated`, per-item `DownloadItem::Observer::OnDownloadUpdated/Destroyed`), including Profiles created later by the Profile-window path; resolve `profile_key` through the same map the engine uses for request contexts. Off-the-record is not a Bato concept; skip it.
- Chrome's download path (`ChromeDownloadManagerDelegate`) is in use under this host, not the CEF `CefDownloadHandler`, so hook at the DownloadManager level, not `cef/libcef/browser/download_manager_delegate_impl.cc`. Do not depend on the bubble classes for data (they are filtered: `DownloadItemModel::ShouldShowInBubble`, extension downloads).
- Dangerous or password-protected downloads need Chromium's security prompt, which lived in the bubble. First version: report them as `failed` with `can_resume = 0` only if Chromium cancels; otherwise leave the item `paused` and keep a "Review in Chromium" fallback by routing the Downloads row (`chrome://downloads`) from the status line. Decide before shipping; flag as an open question.

## Suppressing Chromium's UI (read-only pointers into `chromium/src`)

Goal: no toolbar button, bubble or started animation; downloads, history and `chrome://downloads` keep working.

- `chrome/browser/ui/views/download/bubble/download_toolbar_ui_controller.cc`: `DownloadToolbarUIController::Show()/Hide()/UpdateDownloadIcon()/ShowDetails()/OpenPrimaryDialog()` and `ShowPendingDownloadStartedAnimation`. Making `Show`, `UpdateDownloadIcon` and `ShowDetails` no-ops for Bato windows (guard on the existing Bato-window predicate used by the native slot) removes the icon, partial bubble and animation.
- `chrome/browser/download/bubble/download_display_controller.cc` (`DownloadDisplayController`): drives the button's visibility and "download started" pings; the same guard applies if the toolbar controller edit leaves residue.
- `chrome/browser/download/download_ui_controller.cc`: `DownloadBubbleUIControllerDelegate::OnNewDownloadReady` feeds `DownloadBubbleUpdateService`; returning early there stops bubble state for new items. Leave `DownloadHistory` and the manager untouched so chrome://downloads stays complete.
- `chrome/browser/ui/browser_actions.cc` (~line 1997, `kActionShowDownloads`): the pinned-toolbar action that shows the same UI; hide or deny it in Bato windows so the overflow menu has no stale entry.
- `chrome/browser/ui/chrome_pages.cc` `ShowDownloads()` (line ~399): unchanged; it keeps routing "Full Download History" to the tracked row.
- Prefer a single predicate (for example "this browser window is a Bato native-slot window") checked in the first two files, so a future toggle can restore Chromium's UI.

Verify on the real host after the engine milestone: start small, slow (8 MB) and failing downloads from the existing `downloads_server.py` fixture (port 18768); expect no toolbar icon or bubble, ring and rows update live, pause/resume/cancel/Show in Finder/drag-out/remove work, a second Profile shows only its own downloads, Download History still opens the tracked row.

## Swift wiring left for the engine step

Add a `DownloadsEngine` adapter in the client (registers the callback table, converts `BatoDownloadInfoV1` to `DownloadItem`, forwards actions), construct one `DownloadsController` per process, and call `workspace.attachDownloads(controller, profileKey:)` with the same Profile-to-key mapping used for blocking. Do this in `client/*` after the engine milestone; this plan does not touch it.
