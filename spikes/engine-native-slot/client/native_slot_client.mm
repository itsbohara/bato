#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <cstdio>
#include "include/cef_browser.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/internal/bato_native_slot.h"
#include "tests/cefsimple/native_slot_client.h"

extern "C" void* BatoSwiftNativeSlotCreate(uint64_t token);
extern "C" void* BatoSwiftNativeSlotFocusTarget(uint64_t token);
extern "C" void BatoSwiftNativeSlotDetached(uint64_t token);
extern "C" void BatoSwiftNativeSlotSetActions(int (*focus)(uint64_t),
                                              int (*advance)(uint64_t, int),
                                              int (*navigate)(uint64_t, const char*));

namespace {
using ActiveBrowserId = decltype(&bato_native_slot_active_browser_id_v1);
ActiveBrowserId g_active_browser_id = nullptr;

// Synchronous native action only. The Swift UTF-8 pointer is copied before it
// leaves this call; no URL, credentials or field contents are logged.
int NavigateCurrentPage(uint64_t token, const char* utf8_url) {
  if (!NSThread.isMainThread || !CefCurrentlyOn(TID_UI) ||
      !g_active_browser_id || !utf8_url) return 0;
  const CefString url(utf8_url);
  CefURLParts parts;
  if (!CefParseURL(url, parts)) return 0;
  const auto scheme = CefString(&parts.scheme).ToString();
  if ((scheme != "http" && scheme != "https") || parts.host.length == 0 ||
      parts.username.length != 0 || parts.password.length != 0) return 0;
  const int identifier = g_active_browser_id(token);
  if (identifier <= 0) return 0;
  auto browser = CefBrowserHost::GetBrowserByIdentifier(identifier);
  if (!browser || !browser->IsValid()) return 0;
  auto frame = browser->GetMainFrame();
  if (!frame || !frame->IsValid()) return 0;
  frame->LoadURL(url);
  return 1;  // Request submitted; this does not report successful page load.
}

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
  auto active_browser_id = reinterpret_cast<ActiveBrowserId>(
      dlsym(loaded, "bato_native_slot_active_browser_id_v1"));
  dlclose(loaded);  // CefScopedLibraryLoader retains the framework until shutdown.
  if (!registration || !focus || !advance || !active_browser_id) {
    fprintf(stderr, "{\"event\":\"slot-client-abi-unavailable\"}\n");
    return false;
  }
  BatoNativeSlotCallbacksV1 callbacks = {};
  callbacks.size = sizeof(callbacks);
  callbacks.version = 1;
  callbacks.create = Create;
  callbacks.detached = Detached;
  callbacks.focus_target = FocusTarget;
  g_active_browser_id = active_browser_id;
  BatoSwiftNativeSlotSetActions(focus, advance, NavigateCurrentPage);
  const bool registered = registration(&callbacks) == 1;
  fprintf(stderr, "{\"event\":\"slot-client-registration\",\"success\":%s}\n",
          registered ? "true" : "false");
  return registered;
}
