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
CEF_EXPORT int bato_native_slot_focus_browser_v1(uint64_t token);
CEF_EXPORT int bato_native_slot_advance_focus_v1(uint64_t token, int reverse);
#ifdef __cplusplus
}
#endif
#endif
