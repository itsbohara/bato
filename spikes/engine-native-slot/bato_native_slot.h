// Bato bounded source experiment ABI v1. Not an upstream CEF API.
#ifndef BATO_NATIVE_SLOT_V1_H_
#define BATO_NATIVE_SLOT_V1_H_
#include <stddef.h>
#include <stdint.h>
#include "include/internal/cef_export.h"
#ifdef __cplusplus
extern "C" {
#endif
// Register once on the main thread before CefInitialize. Callbacks remain valid
// until CefShutdown returns. create returns a newly allocated, unparented NSView
// as an unretained pointer; engine retains it until detach, client may retain too.
// focus_target returns a child of that root (not arbitrary browser/UI state).
// token is process-local, unique per attempted window slot and never persisted.
typedef struct BatoNativeSlotCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  void* (*create)(void* context, uint64_t token);
  void (*detached)(void* context, uint64_t token);
  void* (*focus_target)(void* context, uint64_t token);
} BatoNativeSlotCallbacksV1;
CEF_EXPORT int bato_native_slot_register_v1(const BatoNativeSlotCallbacksV1* callbacks);
// Returns the active page's process-local CEF browser identifier, or 0 when
// the slot is unavailable/blocked. Main thread only; never persist this value.
CEF_EXPORT int bato_native_slot_active_browser_id_v1(uint64_t token);
// Page callbacks are separate from slot lifetime. Register once before
// CefInitialize; function/context remain valid until CefShutdown returns.
typedef struct BatoPageCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  void (*close_cancelled)(void* context, uint64_t token, int browser_id);
  // Selection changed to a CEF page in this normal window; browser_id is > 0.
  void (*active_changed)(void* context, uint64_t token, int browser_id);
} BatoPageCallbacksV1;
CEF_EXPORT int bato_native_slot_register_page_callbacks_v1(const BatoPageCallbacksV1* callbacks);
// Creates one normal tab in the known slot window; returns its process-local
// CEF identifier after synchronous insertion, or 0 when creation is refused.
CEF_EXPORT int bato_native_slot_new_tab_v1(uint64_t token);
// Requests a normal, cancellable close only for a page in this slot window.
// Returns request acceptance, not completed closure; use CEF OnBeforeClose.
CEF_EXPORT int bato_native_slot_request_close_v1(uint64_t token, int browser_id);
// Split notifications are observational, including fullscreen, and may run inside
// a tab-model mutation. Clients must defer work and revalidate live generations.
typedef struct BatoSplitCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  // Zero IDs mean the previously managed pair no longer exists. No raw split IDs.
  void (*changed)(void* context, uint64_t token, int left, int right, double ratio);
} BatoSplitCallbacksV1;
CEF_EXPORT int bato_native_slot_register_split_callbacks_v1(const BatoSplitCallbacksV1* callbacks);
CEF_EXPORT int bato_native_slot_present_split_v1(uint64_t token, int left, int right, int focused, double ratio);
CEF_EXPORT int bato_native_slot_separate_split_v1(uint64_t token);
// Like present_split_v1 with an explicit arrangement: stacked 0 places `left` left of
// `right`; stacked 1 places `left` above `right`. The ratio is the first pane's share.
CEF_EXPORT int bato_native_slot_present_split_v2(uint64_t token, int left, int right, int focused,
                                                 double ratio, int stacked);
// Pane frames while a pair is displayed, in the window content view's flipped (top-left origin)
// points, including each pane's toolbar band. in_split 0 means no pair is displayed.
// May run inside a Views layout pass: clients must defer view mutation.
typedef struct BatoSplitLayoutCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  void (*changed)(void* context, uint64_t token, int in_split, int stacked,
                  double x0, double y0, double w0, double h0,
                  double x1, double y1, double w1, double h1);
} BatoSplitLayoutCallbacksV1;
CEF_EXPORT int bato_native_slot_register_split_layout_callbacks_v1(const BatoSplitLayoutCallbacksV1* callbacks);
// Requests Views focus ownership for the native host. Returns 1 when the live
// host owns Views focus; the client may then focus/select its editable field.
CEF_EXPORT int bato_native_slot_focus_native_v1(uint64_t token);
// Main/CEF UI thread only. Per-window sidebar geometry: mode 0 retains a
// six-point tracking edge, 1 docks/reserves width, 2 overlays without reservation.
// Width is clamped to 220..400 points; host bounds may shrink in narrow windows.
// Returns 1 after guarded layout acceptance, 0 for blocked/invalid tokens/modes.
CEF_EXPORT int bato_native_slot_set_sidebar_v1(uint64_t token, int width, int mode);
CEF_EXPORT int bato_native_slot_focus_browser_v1(uint64_t token);
CEF_EXPORT int bato_native_slot_advance_focus_v1(uint64_t token, int reverse);
// Peek: an engine-owned, tab-owned link preview. The preview must already be a
// normal tab in the same window and request context as its parent. Only one
// presentation exists per window. All Peek functions are main/CEF UI thread only.
// Ended reasons (BatoPeekCallbacksV1::ended):
enum {
  BATO_PEEK_ENDED_PREVIEW_CLOSED = 1,
  BATO_PEEK_ENDED_SELECTION_CHANGED = 2,
  BATO_PEEK_ENDED_FULLSCREEN = 3,
  BATO_PEEK_ENDED_MODAL = 4,
  BATO_PEEK_ENDED_SPLIT = 5,
  BATO_PEEK_ENDED_TEARDOWN = 6,
  BATO_PEEK_ENDED_PARENT_CLOSED = 7,
  BATO_PEEK_ENDED_CLOSING = 8,
};
typedef struct BatoPeekCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  // Engine-initiated end only, possibly inside a tab-model mutation or layout:
  // clients must defer work and revalidate. Not called for bato_native_slot_peek_end_v1.
  // generation is the value returned by present; tabs may still be live.
  void (*ended)(void* context, uint64_t token, uint64_t generation,
                int parent_id, int preview_id, int reason);
} BatoPeekCallbacksV1;
// Register once before CefInitialize, like the other callback tables.
CEF_EXPORT int bato_native_slot_register_peek_callbacks_v1(const BatoPeekCallbacksV1* callbacks);
// Presents preview as an inset above a dimmed, live parent; the preview becomes
// the active tab and the parent is mounted (not selected) beneath a scrim. Returns a nonzero process-local generation,
// or 0 when refused: guarded/blocked/fullscreen/closing slot, unknown or equal
// identities, different request context, either tab in a split, an existing
// split layout or presentation, or no peek callbacks registered.
CEF_EXPORT uint64_t bato_native_slot_peek_present_v1(uint64_t token, int parent_id, int preview_id);
// Ends the exact presentation. restore_parent != 0 reactivates the parent;
// 0 leaves the preview active as an ordinary tab (promotion). Returns 0 for an
// unknown/stale generation, 1 when ended (parent restored if requested), 2 when
// ended but the requested parent restoration was not possible.
CEF_EXPORT int bato_native_slot_peek_end_v1(uint64_t token, uint64_t generation, int restore_parent);
// Peek interactions are separate from BatoPeekCallbacksV1 so that table keeps its
// exact v1 size. Register once before CefInitialize; both callbacks are required.
// While a Peek is presented the parent tab is mounted live beneath a scrim that
// swallows pointer input; the engine never dismisses on its own.
typedef struct BatoPeekInteractionCallbacksV1 {
  size_t size;
  uint32_t version;
  void* context;
  // A left click on the scrim outside the preview. May run inside Views input
  // handling: clients must defer work and revalidate. Dismiss through the normal
  // beforeunload-respecting path; the engine keeps the presentation until then.
  void (*scrim_clicked)(void* context, uint64_t token, uint64_t generation,
                        int parent_id, int preview_id);
  // A Shift-click on an eligible HTTP(S) link in the active, unsplit page of a
  // live normal window with no Peek presented. Called synchronously inside the
  // navigation request: return nonzero to take ownership (the engine suppresses
  // Chromium's new-window navigation) or 0 to leave default behavior. Do only
  // pure checks and copy url_utf8 (valid during the call); defer all real work.
  // Plain click, Command-click, popups, script clicks and context-menu commands
  // never reach this callback.
  int (*link_requested)(void* context, uint64_t token, int parent_id,
                        const char* url_utf8);
} BatoPeekInteractionCallbacksV1;
CEF_EXPORT int bato_native_slot_register_peek_interaction_callbacks_v1(
    const BatoPeekInteractionCallbacksV1* callbacks);
// Downloads. Separate tables and exports so every earlier table keeps its exact v1 size.
// Register once on the main thread before CefInitialize. Callbacks run on the CEF UI
// thread, possibly inside a download or tab-model mutation: clients must copy every
// string during the call and defer real work. Only this session's downloads are
// reported; history items stay in chrome://downloads.
// state: 0 in progress, 1 paused, 2 completed, 3 failed (interrupted or blocked), 4 cancelled.
// warning: 0 none, 1 dangerous, 2 insecure, 3 needs a scan decision (for example a
// password-protected archive). A warned download is held by Chromium until it is kept
// (action 6) or discarded (action 7); the engine never keeps one by itself.
typedef struct BatoDownloadInfoV1 {
  size_t size;               // sizeof(BatoDownloadInfoV1)
  // The Profile directory name under the cache root: empty for the launch Profile
  // (<root>/Default), otherwise the key Swift gave that Profile's window.
  const char* profile_key;
  const char* id;            // DownloadItem::GetGuid(), stable for the item's life
  const char* filename;      // basename of the target, or the suggested name until chosen
  const char* path;          // GetFullPath() when complete, else the target path; "" before known
  int64_t received_bytes;
  int64_t total_bytes;       // -1 unknown
  int64_t bytes_per_second;  // 0 unknown
  int32_t state;
  int32_t can_resume;        // 1 when CanResume() (failed or paused)
  int32_t file_exists;       // 0 when completed but the file was moved or deleted
  int32_t warning;
} BatoDownloadInfoV1;
typedef struct BatoDownloadCallbacksV1 {
  size_t size;
  uint32_t version;          // 1
  void* context;
  // Creation, progress, state change, completion, failure, cancellation: one snapshot
  // callback. Progress is throttled to about 4 per second per item; any change of state,
  // warning, name or resumability is delivered immediately.
  void (*upserted)(void* context, const BatoDownloadInfoV1* info);
  // Removed from history, by the remove or discard action, or from chrome://downloads.
  void (*removed)(void* context, const char* profile_key, const char* id);
} BatoDownloadCallbacksV1;
CEF_EXPORT int bato_native_slot_register_download_callbacks_v1(const BatoDownloadCallbacksV1* callbacks);
// Replays every watched download of every live Profile through upserted. Main thread.
CEF_EXPORT int bato_native_slot_download_snapshot_v1(void);
// action: 0 pause, 1 resume, 2 cancel, 3 open, 4 show in Finder, 5 remove (file untouched),
// 6 keep a warned download, 7 discard a warned download (removes it and its partial file).
// Returns 1 when accepted; 0 for an unknown id or Profile or an action invalid for the state.
CEF_EXPORT int bato_native_slot_download_action_v1(const char* profile_key, const char* id, int action);

// Audio state of every tab in a slot window, observed from Chromium's own audible and muted
// flags (the ones behind the stock tab speaker badge). Delivered on the UI thread, possibly
// inside a tab-model mutation: clients copy the values and defer real work. A tab inserted
// into a slot window replays its state once. browser_id is the process-local CEF identifier.
typedef struct BatoAudioCallbacksV1 {
  size_t size;
  uint32_t version;  // 1
  void* context;
  void (*changed)(void* context, int browser_id, int audible, int muted);
} BatoAudioCallbacksV1;
CEF_EXPORT int bato_native_slot_register_audio_callbacks_v1(const BatoAudioCallbacksV1* callbacks);
// Mutes or unmutes one tab by its CEF identifier. Returns 1 when the page exists. UI thread only.
CEF_EXPORT int bato_native_slot_set_muted_v1(int browser_id, int muted);

// Closes every window of the Profile directory `profile_key` (a 36-character UUID directory name
// under the user data dir) without beforeunload prompts, wipes its browsing data and removes its
// directory (Chromium's profile deletion: immediately when the Profile can be released, otherwise
// at the next launch). Refuses the launch Profile ("Default"), any other name and an unknown
// Profile. Returns 1 when deletion was scheduled. UI thread only.
CEF_EXPORT int bato_native_slot_delete_profile_v1(const char* profile_key);
#ifdef __cplusplus
}
#endif
#endif
