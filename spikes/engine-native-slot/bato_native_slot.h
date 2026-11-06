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
#ifdef __cplusplus
}
#endif
#endif
