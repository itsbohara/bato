#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <cstdio>
#include "include/internal/bato_native_slot.h"
#include "tests/cefsimple/native_slot_client.h"

extern "C" void* BatoSwiftNativeSlotCreate(uint64_t token);
extern "C" void* BatoSwiftNativeSlotFocusTarget(uint64_t token);
extern "C" void BatoSwiftNativeSlotDetached(uint64_t token);
extern "C" void BatoSwiftNativeSlotSetActions(int (*focus)(uint64_t),
                                              int (*advance)(uint64_t, int));

namespace {
void* Create(void*, uint64_t token) { return BatoSwiftNativeSlotCreate(token); }
void Detached(void*, uint64_t token) { BatoSwiftNativeSlotDetached(token); }
void* FocusTarget(void*, uint64_t token) { return BatoSwiftNativeSlotFocusTarget(token); }
}

bool BatoRegisterNativeSlotClient() {
  if (![NSThread isMainThread]) {
    return false;
  }
  // This is the declared, matching experiment ABI at the exact bundle loaded
  // by CefScopedLibraryLoader. No private symbol names or window discovery.
  NSString* path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
      @"Contents/Frameworks/Chromium Embedded Framework.framework"];
  NSString* binary = [[path stringByAppendingPathComponent:@"Chromium Embedded Framework"]
      stringByResolvingSymlinksInPath];
  void* loaded = dlopen(binary.fileSystemRepresentation, RTLD_NOW | RTLD_NOLOAD);
  if (!loaded) {
    fprintf(stderr, "{\"event\":\"slot-client-framework-unavailable\"}\n");
    return false;
  }
  auto registration = reinterpret_cast<decltype(&bato_native_slot_register_v1)>(
      dlsym(loaded, "bato_native_slot_register_v1"));
  auto focus = reinterpret_cast<decltype(&bato_native_slot_focus_browser_v1)>(
      dlsym(loaded, "bato_native_slot_focus_browser_v1"));
  auto advance = reinterpret_cast<decltype(&bato_native_slot_advance_focus_v1)>(
      dlsym(loaded, "bato_native_slot_advance_focus_v1"));
  dlclose(loaded);  // CefScopedLibraryLoader retains the framework until shutdown.
  if (!registration || !focus || !advance) {
    fprintf(stderr, "{\"event\":\"slot-client-abi-unavailable\"}\n");
    return false;
  }
  BatoNativeSlotCallbacksV1 callbacks = {};
  callbacks.size = sizeof(callbacks);
  callbacks.version = 1;
  callbacks.create = Create;
  callbacks.detached = Detached;
  callbacks.focus_target = FocusTarget;
  BatoSwiftNativeSlotSetActions(focus, advance);
  const bool registered = registration(&callbacks) == 1;
  fprintf(stderr, "{\"event\":\"slot-client-registration\",\"success\":%s}\n",
          registered ? "true" : "false");
  return registered;
}
