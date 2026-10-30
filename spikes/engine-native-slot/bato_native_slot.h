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
// Requests Views focus ownership for the native host. Returns 1 when the live
// host owns Views focus; the client may then focus/select its editable field.
CEF_EXPORT int bato_native_slot_focus_native_v1(uint64_t token);
CEF_EXPORT int bato_native_slot_focus_browser_v1(uint64_t token);
CEF_EXPORT int bato_native_slot_advance_focus_v1(uint64_t token, int reverse);
#ifdef __cplusplus
}
#endif
#endif
