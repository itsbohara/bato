#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <cctype>
#include <cstdio>
#include <cmath>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>
#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_id_mappers.h"
#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_task.h"
#include "include/internal/bato_native_slot.h"
#include "include/wrapper/cef_closure_task.h"
#include "tests/cefsimple/native_slot_client.h"
#include "tests/cefsimple/simple_handler.h"

extern "C" void* BatoSwiftNativeSlotCreate(uint64_t token);
extern "C" void* BatoSwiftNativeSlotFocusTarget(uint64_t token);
extern "C" void BatoSwiftNativeSlotDetached(uint64_t token);
extern "C" void BatoSwiftNativeSlotSetActions(int (*focus)(uint64_t),
                                              int (*advance)(uint64_t, int),
                                              int (*navigate)(uint64_t, const char*));
extern "C" void BatoSwiftWorkspaceConfigure(const char* state_directory,
    int (*create)(uint64_t, const char*, const char*, int), int (*select)(uint64_t, int),
    int (*close)(uint64_t, int), int (*active)(uint64_t),
    int (*native_focus)(uint64_t), int (*command_id)(int),
    void (*schedule_selection)(uint64_t),
    int (*sidebar_geometry)(uint64_t, int, int), int (*page_focus)(uint64_t));
extern "C" void BatoSwiftWorkspaceConfigureSplits(
    int (*present)(uint64_t, int, int, int, double), int (*separate)(uint64_t));
// Peek hooks are optional Swift exports, resolved with dlsym at registration.
using SwiftConfigurePeek = void (*)(uint64_t (*)(uint64_t, int, int), int (*)(uint64_t, uint64_t, int));
using SwiftPeekEnded = void (*)(uint64_t, uint64_t, int, int, int);
// Peek interaction hooks are optional Swift exports, resolved with dlsym.
// ScrimClicked(token, generation, parent, preview): deferred notification.
// LinkEligible(token, parent, url): synchronous and side-effect free; nonzero
// when Swift will open the link in Peek. LinkRequested(token, parent, url):
// deferred open after a nonzero eligibility answer.
using SwiftPeekScrimClicked = void (*)(uint64_t, uint64_t, int, int);
using SwiftPeekLinkEligible = int (*)(uint64_t, int, const char*);
using SwiftPeekLinkRequested = void (*)(uint64_t, int, const char*);
extern "C" void BatoSwiftWorkspaceSplitChanged(uint64_t token, int left, int right, double ratio, int removed);
extern "C" void BatoSwiftWorkspaceCommand(uint64_t token, int command, int browser_id);
extern "C" void BatoSwiftWorkspacePageEvent(uint64_t token, int browser_id,
    int kind, const char* url, const char* title);

// Navigation is an optional Swift export, resolved with dlsym.
// ConfigureNavigation(navigate): navigate(token, browser, url) loads url in that page.
using SwiftConfigureNavigation = void (*)(int (*)(uint64_t, int, const char*));

// Multi-Profile hooks are optional Swift exports, resolved with dlsym.
// ConfigureProfiles(open): open(profile_key, launch) asks for a window in that Profile's context.
// ProfileWindowReady(token, profile_key, ok): the requested window is bound (ok != 0) or failed.
using SwiftConfigureProfiles = void (*)(int (*)(const char*, int));
using SwiftProfileWindowReady = void (*)(uint64_t, const char*, int);

// Download hooks are optional Swift exports, resolved with dlsym at registration.
// DownloadsConfigure(snapshot, act): act(profile_key, id, action) with the Bato Profile key.
// DownloadUpserted/Removed deliver engine events with Bato Profile keys, on the main thread.
using SwiftDownloadsConfigure = void (*)(int (*)(), int (*)(const char*, const char*, int));
using SwiftDownloadUpserted = void (*)(const char*, const char*, const char*, const char*,
                                       int64_t, int64_t, int64_t, int, int, int, int);
using SwiftDownloadRemoved = void (*)(const char*, const char*);
// ConfigureProfileDelete(destroy): destroy(profile_key) closes the Profile's windows and wipes its data.
using SwiftConfigureProfileDelete = void (*)(int (*)(const char*));

extern "C" void BatoSwiftWorkspacePageIcon(uint64_t token, int browser_id,
    const unsigned char* png, size_t size);

namespace {
using ActiveBrowserId = decltype(&bato_native_slot_active_browser_id_v1);
using NewTab = decltype(&bato_native_slot_new_tab_v1);
using RequestClose = decltype(&bato_native_slot_request_close_v1);
ActiveBrowserId g_active_browser_id = nullptr;
NewTab g_new_tab = nullptr;
RequestClose g_request_close = nullptr;
using PresentSplit = decltype(&bato_native_slot_present_split_v1);
using SeparateSplit = decltype(&bato_native_slot_separate_split_v1);
PresentSplit g_present_split = nullptr;
SeparateSplit g_separate_split = nullptr;
using PeekPresent = decltype(&bato_native_slot_peek_present_v1);
using PeekEnd = decltype(&bato_native_slot_peek_end_v1);
PeekPresent g_peek_present = nullptr;
PeekEnd g_peek_end = nullptr;
decltype(&bato_native_slot_download_snapshot_v1) g_download_snapshot = nullptr;
decltype(&bato_native_slot_download_action_v1) g_download_action = nullptr;
decltype(&bato_native_slot_delete_profile_v1) g_delete_profile = nullptr;
SwiftDownloadUpserted g_swift_download_upserted = nullptr;
SwiftDownloadRemoved g_swift_download_removed = nullptr;
SwiftPeekEnded g_swift_peek_ended = nullptr;
SwiftPeekScrimClicked g_swift_peek_scrim_clicked = nullptr;
SwiftPeekLinkEligible g_swift_peek_link_eligible = nullptr;
SwiftPeekLinkRequested g_swift_peek_link_requested = nullptr;
SwiftProfileWindowReady g_swift_profile_ready = nullptr;
bool g_workspace_enabled = false;
int g_initial_browser_id = 0;

struct BoundPage {
  CefRefPtr<CefBrowser> browser;
  std::string url;
  std::string title;
  uint64_t icon_revision = 0;
};
struct WorkspaceSlot {
  CefRefPtr<CefBrowser> anchor;
  CefRefPtr<CefRequestContext> context;
  std::map<int, BoundPage> pages;
  std::set<int> pending_close;
  // Empty for the launch window; otherwise the Profile key the window was requested for.
  std::string profile_key;
  int split_left = 0;
  int split_right = 0;
  uint64_t split_revision = 0;
  uint64_t split_observation = 0;
  // Transient Peek binding; the engine generation is the only authority.
  uint64_t peek_generation = 0;
  int peek_parent = 0;
  int peek_preview = 0;
  CefRefPtr<CefBrowser> peek_parent_browser;
  CefRefPtr<CefBrowser> peek_preview_browser;
};
// One window and request context per Bato Profile: a Chrome Browser has exactly one Profile.
// Contexts are created lazily and kept for the process, so a closed Profile window reopens
// on the same storage. At most one window request is in flight; the engine binds the window's
// blank anchor to this request, never by guessing from window order.
struct WindowRequest {
  std::string key;
  bool launch = false;
  CefRefPtr<CefRequestContext> context;
  uint64_t serial = 0;
};
// Intentionally leaked: CEF refs must not be destroyed at process exit.
WindowRequest& PendingWindow() {
  static auto* request = new WindowRequest;
  return *request;
}
uint64_t g_window_serial = 0;
bool g_primary_slot_created = false;
std::map<std::string, CefRefPtr<CefRequestContext>>& ProfileContexts() {
  static auto* contexts = new std::map<std::string, CefRefPtr<CefRequestContext>>;
  return *contexts;
}
constexpr int64_t kProfileWindowTimeoutMs = 20000;

// Main-thread-only process storage. Entries and all CEF refs are explicitly
// released on detach; a process-lifetime container avoids exit-time CEF calls.
std::map<uint64_t, WorkspaceSlot>& WorkspaceSlots() {
  static auto* slots = new std::map<uint64_t, WorkspaceSlot>;
  return *slots;
}

bool ValidDestination(const char* utf8_url) {
  if (!utf8_url) return false;
  CefURLParts parts;
  if (!CefParseURL(CefString(utf8_url), parts)) return false;
  const auto scheme = CefString(&parts.scheme).ToString();
  return (scheme == "http" || scheme == "https") && parts.host.length != 0 &&
      parts.username.length == 0 && parts.password.length == 0;
}

// Settings' site-permission subtree: "/content" and the pages below it, mirroring BrowserEssential.
bool IsSiteSettingsPath(const std::string& path) {
  if (path == "/content") return true;
  if (path.rfind("/content/", 0) != 0) return false;
  for (char c : path.substr(9)) {
    if (!isalnum(static_cast<unsigned char>(c)) && c != '/') return false;
  }
  return true;
}

// Page creation also accepts the exact Chromium pages Bato offers as browser essentials.
// Navigation, Peek and icon requests keep the web-only rule.
bool ValidCreateDestination(const char* utf8_url) {
  if (ValidDestination(utf8_url)) return true;
  if (!utf8_url) return false;
  CefURLParts parts;
  if (!CefParseURL(CefString(utf8_url), parts)) return false;
  const auto scheme = CefString(&parts.scheme).ToString();
  const auto host = CefString(&parts.host).ToString();
  const auto path = CefString(&parts.path).ToString();
  if (scheme != "chrome" || parts.username.length != 0 || parts.password.length != 0) return false;
  const auto query = CefString(&parts.query).ToString();
  if (host == "settings" && IsSiteSettingsPath(path)) {
    return query.empty() || (query.rfind("site=", 0) == 0 && query.find('&') == std::string::npos);
  }
  return (host == "history" || host == "downloads" || host == "settings") &&
      (path.empty() || path == "/") && query.empty();
}

bool SameWindow(CefRefPtr<CefBrowser> first, CefRefPtr<CefBrowser> second) {
  NSView* first_view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(first->GetHost()->GetWindowHandle());
  NSView* second_view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(second->GetHost()->GetWindowHandle());
  return first_view && second_view && first_view.window &&
      first_view.window == second_view.window;
}

CefRefPtr<CefBrowser> CurrentPeer(uint64_t token, const WorkspaceSlot& slot) {
  CefRefPtr<CefBrowser> peer = slot.anchor;
  if (!peer || !peer->IsValid()) {
    const int identifier = g_active_browser_id(token);
    if (identifier <= 0) return nullptr;
    peer = CefBrowserHost::GetBrowserByIdentifier(identifier);
  }
  return peer && peer->IsValid() && slot.context &&
      peer->GetHost()->GetRequestContext()->IsSame(slot.context) ? peer : nullptr;
}

// Fixed diagnostic values only: never include tokens, browser identifiers,
// destinations, titles, or other browsing data in rejection records.
enum class WorkspaceRejection {
  kWorkspaceDisabled,
  kNotMainThread,
  kNotCefUI,
  kActiveCallbackUnavailable,
  kActiveBrowserUnavailable,
  kSlotMissing,
  kActiveBrowserInvalid,
  kInitialBrowserMismatch,
  kInitialFrameMissing,
  kInitialDestinationMismatch,
  kContextMismatch,
  kDestinationInvalid,
  kNewTabCallbackUnavailable,
  kAvailableSlotRejected,
  kPeerUnavailable,
  kNewTabRejected,
  kCreatedBrowserMissing,
  kCreatedBrowserInvalid,
  kCreatedSlotMissing,
  kCreatedBrowserIsPeer,
  kCreatedWindowMismatch,
  kCreatedContextMismatch,
  kProfileMismatch,
  kCreatedProfileMismatch,
  kCreatedFrameInvalid,
  kPageAlreadyBound,
  kPageInsertionFailed,
  kSlotLostAfterNavigation,
  kPageLostAfterNavigation,
};

void LogWorkspaceRejection(const char* operation, WorkspaceRejection reason) {
  const char* value = "unknown";
  switch (reason) {
    case WorkspaceRejection::kWorkspaceDisabled:
      value = "workspace-disabled";
      break;
    case WorkspaceRejection::kNotMainThread:
      value = "not-main-thread";
      break;
    case WorkspaceRejection::kNotCefUI:
      value = "not-cef-ui";
      break;
    case WorkspaceRejection::kActiveCallbackUnavailable:
      value = "active-callback-unavailable";
      break;
    case WorkspaceRejection::kActiveBrowserUnavailable:
      value = "active-browser-unavailable";
      break;
    case WorkspaceRejection::kSlotMissing:
      value = "slot-missing";
      break;
    case WorkspaceRejection::kActiveBrowserInvalid:
      value = "active-browser-invalid";
      break;
    case WorkspaceRejection::kInitialBrowserMismatch:
      value = "initial-browser-mismatch";
      break;
    case WorkspaceRejection::kInitialFrameMissing:
      value = "initial-frame-missing";
      break;
    case WorkspaceRejection::kInitialDestinationMismatch:
      value = "initial-destination-mismatch";
      break;
    case WorkspaceRejection::kContextMismatch:
      value = "context-mismatch";
      break;
    case WorkspaceRejection::kDestinationInvalid:
      value = "destination-invalid";
      break;
    case WorkspaceRejection::kNewTabCallbackUnavailable:
      value = "new-tab-callback-unavailable";
      break;
    case WorkspaceRejection::kAvailableSlotRejected:
      value = "available-slot-rejected";
      break;
    case WorkspaceRejection::kPeerUnavailable:
      value = "peer-unavailable";
      break;
    case WorkspaceRejection::kNewTabRejected:
      value = "new-tab-rejected";
      break;
    case WorkspaceRejection::kCreatedBrowserMissing:
      value = "created-browser-missing";
      break;
    case WorkspaceRejection::kCreatedBrowserInvalid:
      value = "created-browser-invalid";
      break;
    case WorkspaceRejection::kCreatedSlotMissing:
      value = "created-slot-missing";
      break;
    case WorkspaceRejection::kCreatedBrowserIsPeer:
      value = "created-browser-is-peer";
      break;
    case WorkspaceRejection::kCreatedWindowMismatch:
      value = "created-window-mismatch";
      break;
    case WorkspaceRejection::kProfileMismatch:
      value = "profile-mismatch";
      break;
    case WorkspaceRejection::kCreatedProfileMismatch:
      value = "created-profile-mismatch";
      break;
    case WorkspaceRejection::kCreatedContextMismatch:
      value = "created-context-mismatch";
      break;
    case WorkspaceRejection::kCreatedFrameInvalid:
      value = "created-frame-invalid";
      break;
    case WorkspaceRejection::kPageAlreadyBound:
      value = "page-already-bound";
      break;
    case WorkspaceRejection::kPageInsertionFailed:
      value = "page-insertion-failed";
      break;
    case WorkspaceRejection::kSlotLostAfterNavigation:
      value = "slot-lost-after-navigation";
      break;
    case WorkspaceRejection::kPageLostAfterNavigation:
      value = "page-lost-after-navigation";
      break;
  }
  fprintf(stderr,
          "{\"event\":\"workspace-adapter-rejected\",\"operation\":\"%s\",\"reason\":\"%s\"}\n",
          operation, value);
}

void LogProfileRefusal(const char* reason) {
  fprintf(stderr, "{\"event\":\"profile-window-refused\",\"reason\":\"%s\"}\n", reason);
}

std::string ResolvePath(const std::string& path) {
  if (path.empty()) return "";
  NSString* text = [NSString stringWithUTF8String:path.c_str()];
  return std::string(text.stringByStandardizingPath.stringByResolvingSymlinksInPath.UTF8String ?: "");
}

// The --cache-path root, which is Chrome's user data dir and the parent of every Profile directory.
std::string CacheRoot() {
  return ResolvePath(CefCommandLine::GetGlobalCommandLine()->GetSwitchValue("cache-path").ToString());
}

// Where each Profile's context must live. The launch Profile is always <root>/Default, which
// startup pins with --profile-directory; any other Profile is a direct child named by its key.
std::string ExpectedProfilePath(const std::string& key, bool launch) {
  const auto root = CacheRoot();
  if (root.empty()) return "";
  return launch ? root + "/Default" : root + "/" + key;
}

bool ContextPathIs(CefRefPtr<CefRequestContext> context, const std::string& path) {
  return context && !path.empty() && ResolvePath(context->GetCachePath().ToString()) == path;
}

// Request filtering runs on the IO thread, where the slot tables (main-thread only) are off
// limits, so each browser's Profile key is recorded here when it is created. The launch
// Profile's browsers have no key of their own: their value is empty and resolves to the key
// Swift last used for the launch Profile. Intentionally leaked like the other process tables.
struct BrowserProfileKeys {
  std::mutex mutex;
  std::map<int, std::string> by_browser;
  std::string launch_key;
};
BrowserProfileKeys& ProfileKeys() {
  static auto* keys = new BrowserProfileKeys;
  return *keys;
}

void RememberLaunchProfileKey(const std::string& key) {
  std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
  ProfileKeys().launch_key = key;
}

// The Profile directory name of a request context path under the cache root: empty for the
// launch Profile (<root>/Default), the key for <root>/<key>. False for any other location.
bool ProfileKeyOfContext(CefRefPtr<CefRequestContext> context, std::string* key) {
  const auto root = CacheRoot();
  if (!context || root.empty()) return false;
  const auto path = ResolvePath(context->GetCachePath().ToString());
  if (path == root + "/Default") {
    key->clear();
    return true;
  }
  if (path.size() <= root.size() + 1 || path.compare(0, root.size() + 1, root + "/") != 0) return false;
  const auto name = path.substr(root.size() + 1);
  if (name.find('/') != std::string::npos) return false;
  *key = name;
  return true;
}

void RecordBrowserProfileKey(CefRefPtr<CefBrowser> browser) {
  std::string key;
  if (!ProfileKeyOfContext(browser->GetHost()->GetRequestContext(), &key)) return;
  std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
  ProfileKeys().by_browser[browser->GetIdentifier()] = key;
}

void PostProfileWindowResult(uint64_t token, const std::string& key, bool ok) {
  if (!g_swift_profile_ready) return;
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, std::string key, bool ok) {
        if (g_swift_profile_ready) g_swift_profile_ready(token, key.c_str(), ok ? 1 : 0);
      }, token, key, ok));
}

// Seeds an unbound slot from its window's blank anchor. The first window is the launch
// Profile; any later one must use the context of the single outstanding window request.
// Returns false when the browser is neither, leaving the slot unbound.
bool BindAnchor(uint64_t token, WorkspaceSlot& slot, CefRefPtr<CefBrowser> browser) {
  const int identifier = browser->GetIdentifier();
  auto context = browser->GetHost()->GetRequestContext();
  const bool initial = identifier == g_initial_browser_id;
  if (!initial && (PendingWindow().key.empty() || !context->IsSame(PendingWindow().context))) return false;
  // Absolute check: a window is only ever bound to the directory its Profile owns.
  const bool launch = initial || PendingWindow().launch;
  const auto expected = ExpectedProfilePath(initial ? "" : PendingWindow().key, launch);
  if (!ContextPathIs(context, expected)) {
    fprintf(stderr, "{\"event\":\"profile-window-refused\",\"reason\":\"anchor-context-path\",\"token\":%llu,"
            "\"browser\":%d,\"context\":\"%s\",\"expected\":\"%s\"}\n",
            static_cast<unsigned long long>(token), identifier,
            context->GetCachePath().ToString().c_str(), expected.c_str());
    return false;
  }
  if (!initial) {
    // The launch Profile's window carries no key: it is the global context, never a Profile directory.
    const std::string key = PendingWindow().key;
    slot.profile_key = PendingWindow().launch ? "" : key;
    PendingWindow() = WindowRequest();
    PostProfileWindowResult(token, key, true);
  }
  slot.anchor = browser;
  slot.context = context;
  fprintf(stderr, "{\"event\":\"profile-window-bound\",\"token\":%llu,\"browser\":%d,\"key\":\"%s\",\"context\":\"%s\"}\n",
          static_cast<unsigned long long>(token), identifier, slot.profile_key.c_str(),
          context->GetCachePath().ToString().c_str());
  return true;
}

WorkspaceSlot* AvailableSlot(uint64_t token) {
  auto reject = [](WorkspaceRejection reason) -> WorkspaceSlot* {
    LogWorkspaceRejection("available-slot", reason);
    return nullptr;
  };
  if (!g_workspace_enabled)
    return reject(WorkspaceRejection::kWorkspaceDisabled);
  if (!NSThread.isMainThread)
    return reject(WorkspaceRejection::kNotMainThread);
  if (!CefCurrentlyOn(TID_UI))
    return reject(WorkspaceRejection::kNotCefUI);
  if (!g_active_browser_id)
    return reject(WorkspaceRejection::kActiveCallbackUnavailable);
  const int identifier = g_active_browser_id(token);
  if (identifier <= 0)
    return reject(WorkspaceRejection::kActiveBrowserUnavailable);
  auto found = WorkspaceSlots().find(token);
  if (found == WorkspaceSlots().end())
    return reject(WorkspaceRejection::kSlotMissing);
  auto active = CefBrowserHost::GetBrowserByIdentifier(identifier);
  if (!active || !active->IsValid())
    return reject(WorkspaceRejection::kActiveBrowserInvalid);
  auto& slot = found->second;
  if (!slot.context) {
    // Only the initial browser or the requested Profile window's first browser can seed a
    // blank anchor. A new tab can also briefly have an empty URL, so emptiness alone is insufficient.
    if (identifier != g_initial_browser_id && PendingWindow().key.empty())
      return reject(WorkspaceRejection::kInitialBrowserMismatch);
    auto frame = active->GetMainFrame();
    if (!frame)
      return reject(WorkspaceRejection::kInitialFrameMissing);
    const auto initial_url = frame->GetURL().ToString();
    if (!initial_url.empty() && initial_url != "about:blank")
      return reject(WorkspaceRejection::kInitialDestinationMismatch);
    if (!BindAnchor(token, slot, active))
      return reject(WorkspaceRejection::kInitialBrowserMismatch);
  }
  // An anchor closed by Chrome does not change the bound engine Profile. A real
  // page may prove same-window ownership, but must never become the blank anchor.
  if (!active->GetHost()->GetRequestContext()->IsSame(slot.context))
    return reject(WorkspaceRejection::kContextMismatch);
  return &slot;
}

// 0 is the protected placeholder; negative means Chrome-owned/unavailable.
int ActiveWorkspacePage(uint64_t token) {
  auto* slot = AvailableSlot(token);
  if (!slot) return -1;
  const int identifier = g_active_browser_id(token);
  if (slot->anchor && slot->anchor->GetIdentifier() == identifier) return 0;
  return slot->pages.contains(identifier) ? identifier : -1;
}

int WorkspaceCommandId(int command) {
  if (!CefCurrentlyOn(TID_UI)) return -1;
  return cef_id_for_command_id_name(command == 1 ? "IDC_NEW_TAB" : "IDC_CLOSE_TAB");
}

void ScheduleWorkspaceSelection(uint64_t token) {
  // AppKit sheet completion runs on the main thread, but not necessarily in
  // CEF's UI task scope. Post before entering the guarded page adapter APIs.
  if (!g_workspace_enabled || !NSThread.isMainThread ||
      !WorkspaceSlots().contains(token)) return;
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token) {
        if (!g_workspace_enabled || !WorkspaceSlots().contains(token)) return;
        fprintf(stderr,
                "{\"event\":\"workspace-selection-dispatched\",\"cef_ui\":%s}\n",
                CefCurrentlyOn(TID_UI) ? "true" : "false");
        BatoSwiftWorkspaceCommand(token, 3, 0);
      }, token));
}

void PostPageState(uint64_t token, int identifier, BoundPage& page) {
  // Strings are copied before posting; no borrowed callback buffers escape.
  const auto url = page.url;
  const auto title = page.title;
  CefRefPtr<CefBrowser> browser = page.browser;
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int identifier, CefRefPtr<CefBrowser> browser,
         const std::string& url, const std::string& title) {
        auto slot = WorkspaceSlots().find(token);
        if (slot == WorkspaceSlots().end()) return;
        auto found = slot->second.pages.find(identifier);
        if (found == slot->second.pages.end() ||
            !found->second.browser->IsSame(browser)) return;
        BatoSwiftWorkspacePageEvent(token, identifier, 1, url.c_str(), title.c_str());
      }, token, identifier, browser, url, title));
}

// Page-owned favicon delivery uses CEF's image decoder and request context.
// No separate service, URLSession request, persistent icon store or URL logging.
void PostPageIcon(uint64_t token, int identifier, CefRefPtr<CefBrowser> browser,
                  uint64_t revision, std::vector<unsigned char> png) {
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int identifier, CefRefPtr<CefBrowser> browser,
         uint64_t revision, const std::vector<unsigned char>& png) {
        auto slot = WorkspaceSlots().find(token);
        if (slot == WorkspaceSlots().end()) return;
        auto page = slot->second.pages.find(identifier);
        if (page == slot->second.pages.end() || !browser->IsValid() ||
            !page->second.browser->IsSame(browser) ||
            page->second.icon_revision != revision) return;
        BatoSwiftWorkspacePageIcon(token, identifier,
                                  png.empty() ? nullptr : png.data(), png.size());
      }, token, identifier, browser, revision, std::move(png)));
}

class WorkspaceIconDownload final : public CefDownloadImageCallback {
 public:
  WorkspaceIconDownload(uint64_t token, int identifier,
                        CefRefPtr<CefBrowser> browser, uint64_t revision)
      : token_(token), identifier_(identifier), browser_(browser), revision_(revision) {}
  void OnDownloadImageFinished(const CefString&, int,
                               CefRefPtr<CefImage> image) override {
    if (!CefCurrentlyOn(TID_UI) || !image || image->IsEmpty()) return;
    int width = 0, height = 0;
    auto bytes = image->GetAsPNG(1.0f, true, width, height);
    if (!bytes || width <= 0 || height <= 0 || width > 128 || height > 128 ||
        bytes->GetSize() > 256 * 1024) return;
    std::vector<unsigned char> png(bytes->GetSize());
    if (bytes->GetData(png.data(), png.size(), 0) != png.size()) return;
    PostPageIcon(token_, identifier_, browser_, revision_, std::move(png));
  }
 private:
  const uint64_t token_;
  const int identifier_;
  const CefRefPtr<CefBrowser> browser_;
  const uint64_t revision_;
  IMPLEMENT_REFCOUNTING(WorkspaceIconDownload);
};

// The context a page of this Profile must run in: the launch Profile (empty key) uses the global
// context, every other Profile its own. Null when that context does not exist.
CefRefPtr<CefRequestContext> ProfileContext(const std::string& key, bool launch) {
  if (launch) return CefRequestContext::GetGlobalContext();
  auto found = ProfileContexts().find(key);
  return found == ProfileContexts().end() ? nullptr : found->second;
}

// A page may only be created in a window whose context is its Profile's. Diagnostic records carry
// identifiers and cache paths only, never destinations or titles.
bool WindowMatchesProfile(uint64_t token, const WorkspaceSlot& slot, const std::string& key, bool launch) {
  auto expected = ProfileContext(key, launch);
  const bool match = expected && slot.context && slot.context->IsSame(expected) &&
      (launch ? slot.profile_key.empty() : slot.profile_key == key) &&
      ContextPathIs(slot.context, ExpectedProfilePath(key, launch));
  if (!match) {
    fprintf(stderr,
            "{\"event\":\"profile-window-mismatch\",\"token\":%llu,\"slot_key\":\"%s\",\"page_key\":\"%s\","
            "\"launch\":%s,\"slot_context\":\"%s\",\"expected_context\":\"%s\"}\n",
            static_cast<unsigned long long>(token), slot.profile_key.c_str(), key.c_str(),
            launch ? "true" : "false",
            slot.context ? slot.context->GetCachePath().ToString().c_str() : "",
            expected ? expected->GetCachePath().ToString().c_str() : "");
  }
  return match;
}

int CreateWorkspacePage(uint64_t token, const char* utf8_url, const char* utf8_profile_key, int launch) {
  auto reject = [](WorkspaceRejection reason) {
    LogWorkspaceRejection("create-page", reason);
    return 0;
  };
  if (!ValidCreateDestination(utf8_url))
    return reject(WorkspaceRejection::kDestinationInvalid);
  if (!g_new_tab)
    return reject(WorkspaceRejection::kNewTabCallbackUnavailable);
  auto* slot = AvailableSlot(token);
  if (!slot)
    return reject(WorkspaceRejection::kAvailableSlotRejected);
  const std::string profile_key = utf8_profile_key ? utf8_profile_key : "";
  if (!WindowMatchesProfile(token, *slot, profile_key, launch != 0))
    return reject(WorkspaceRejection::kProfileMismatch);
  if (launch != 0) RememberLaunchProfileKey(profile_key);
  // Copy URL and retain the same-window peer/context across Chrome callbacks.
  const CefString url(utf8_url);
  CefRefPtr<CefBrowser> peer = CurrentPeer(token, *slot);
  CefRefPtr<CefRequestContext> context = slot->context;
  if (!peer)
    return reject(WorkspaceRejection::kPeerUnavailable);
  const int identifier = g_new_tab(token);
  if (identifier <= 0)
    return reject(WorkspaceRejection::kNewTabRejected);
  auto browser = CefBrowserHost::GetBrowserByIdentifier(identifier);
  auto current_slot = WorkspaceSlots().find(token);
  if (!browser)
    return reject(WorkspaceRejection::kCreatedBrowserMissing);
  if (!browser->IsValid())
    return reject(WorkspaceRejection::kCreatedBrowserInvalid);
  if (current_slot == WorkspaceSlots().end())
    return reject(WorkspaceRejection::kCreatedSlotMissing);
  if (browser->IsSame(peer))
    return reject(WorkspaceRejection::kCreatedBrowserIsPeer);
  if (!SameWindow(peer, browser))
    return reject(WorkspaceRejection::kCreatedWindowMismatch);
  if (!browser->GetHost()->GetRequestContext()->IsSame(context))
    return reject(WorkspaceRejection::kCreatedContextMismatch);
  // The tab itself must also run in the Profile's context, whatever the slot believes.
  auto expected = ProfileContext(profile_key, launch != 0);
  if (!expected || !browser->GetHost()->GetRequestContext()->IsSame(expected) ||
      !ContextPathIs(browser->GetHost()->GetRequestContext(), ExpectedProfilePath(profile_key, launch != 0))) {
    fprintf(stderr, "{\"event\":\"profile-page-mismatch\",\"token\":%llu,\"browser\":%d,\"page_key\":\"%s\","
            "\"page_context\":\"%s\"}\n", static_cast<unsigned long long>(token), identifier,
            profile_key.c_str(),
            browser->GetHost()->GetRequestContext()->GetCachePath().ToString().c_str());
    browser->GetHost()->CloseBrowser(true);
    return reject(WorkspaceRejection::kCreatedProfileMismatch);
  }
  auto frame = browser->GetMainFrame();
  if (!frame || !frame->IsValid())
    return reject(WorkspaceRejection::kCreatedFrameInvalid);
  auto& pages = current_slot->second.pages;
  if (pages.contains(identifier))
    return reject(WorkspaceRejection::kPageAlreadyBound);
  auto [found, inserted] = pages.emplace(identifier, BoundPage{browser, url.ToString(), ""});
  if (!inserted)
    return reject(WorkspaceRejection::kPageInsertionFailed);
  frame->LoadURL(url);
  // Navigation can reenter client code. Never keep an iterator across it.
  auto still_live = WorkspaceSlots().find(token);
  if (still_live == WorkspaceSlots().end())
    return reject(WorkspaceRejection::kSlotLostAfterNavigation);
  auto bound = still_live->second.pages.find(identifier);
  if (bound == still_live->second.pages.end())
    return reject(WorkspaceRejection::kPageLostAfterNavigation);
  // Bato's Swift generation binding is established when this call returns.
  PostPageState(token, identifier, bound->second);
  return identifier;
}

int SelectWorkspacePage(uint64_t token, int identifier) {
  auto* slot = AvailableSlot(token);
  if (!slot) return 0;
  CefRefPtr<CefBrowser> peer = CurrentPeer(token, *slot);
  CefRefPtr<CefRequestContext> context = slot->context;
  if (!peer) return 0;
  CefRefPtr<CefBrowser> browser = slot->anchor;
  if (identifier != 0) {
    auto found = slot->pages.find(identifier);
    if (found == slot->pages.end()) return 0;
    browser = found->second.browser;
  } else if (!browser) {
    // The user can close the blank tab through Chrome UI. Replace it lazily;
    // the engine's new-tab gate refuses shutdown/window-close transitions.
    if (!g_new_tab) return 0;
    const int replacement = g_new_tab(token);
    browser = replacement > 0 ? CefBrowserHost::GetBrowserByIdentifier(replacement) : nullptr;
    auto current_slot = WorkspaceSlots().find(token);
    if (!browser || !browser->IsValid() || current_slot == WorkspaceSlots().end() ||
        !SameWindow(peer, browser) ||
        !browser->GetHost()->GetRequestContext()->IsSame(context)) return 0;
    auto frame = browser->GetMainFrame();
    if (!frame || !frame->IsValid()) return 0;
    current_slot->second.anchor = browser;
    frame->LoadURL("about:blank");
    // No borrowed map reference survives navigation or focus callbacks.
    auto still_live = WorkspaceSlots().find(token);
    if (still_live == WorkspaceSlots().end() || !still_live->second.anchor ||
        !still_live->second.anchor->IsSame(browser)) return 0;
  }
  if (!browser || !browser->IsValid() || !SameWindow(peer, browser) ||
      !browser->GetHost()->GetRequestContext()->IsSame(context)) return 0;
  browser->GetHost()->SetFocus(true);
  return 1;
}

int CloseWorkspacePage(uint64_t token, int identifier) {
  auto* slot = AvailableSlot(token);
  if (!slot || !g_request_close) return 0;
  auto found = slot->pages.find(identifier);
  if (found == slot->pages.end()) return 0;
  if (!slot->pending_close.insert(identifier).second) return 1;
  const bool accepted = g_request_close(token, identifier) == 1;
  if (!accepted) {
    auto still_live = WorkspaceSlots().find(token);
    if (still_live != WorkspaceSlots().end()) still_live->second.pending_close.erase(identifier);
  }
  return accepted ? 1 : 0;
}

int PresentWorkspaceSplit(uint64_t token, int left, int right, int focused, double ratio) {
  auto* slot = AvailableSlot(token);
  if (!slot || !g_present_split || left == right ||
      (focused != left && focused != right) || !std::isfinite(ratio) ||
      ratio <= 0 || ratio >= 1) return 0;
  for (int identifier : {left, right}) {
    auto found = slot->pages.find(identifier);
    if (found == slot->pages.end() || !found->second.browser->IsValid() ||
        slot->pending_close.contains(identifier)) return 0;
  }
  auto a = slot->pages.at(left).browser, b = slot->pages.at(right).browser;
  if (!SameWindow(a, b) || !slot->context ||
      !a->GetHost()->GetRequestContext()->IsSame(slot->context) ||
      !b->GetHost()->GetRequestContext()->IsSame(slot->context)) return 0;
  if (g_present_split(token, left, right, focused, ratio) != 1) return 0;
  auto current = WorkspaceSlots().find(token);
  if (current == WorkspaceSlots().end() || !current->second.pages.contains(left) ||
      !current->second.pages.contains(right) ||
      !current->second.pages.at(left).browser->IsSame(a) ||
      !current->second.pages.at(right).browser->IsSame(b)) return 0;
  ++current->second.split_revision;
  current->second.split_left = left;
  current->second.split_right = right;
  return 1;
}
int SeparateWorkspaceSplit(uint64_t token) {
  auto* slot = AvailableSlot(token);
  if (!slot || !g_separate_split || g_separate_split(token) != 1) return 0;
  auto current = WorkspaceSlots().find(token);
  if (current == WorkspaceSlots().end()) return 0;
  ++current->second.split_revision;
  current->second.split_left = current->second.split_right = 0;
  return 1;
}
void SplitChanged(void*, uint64_t token, int left, int right, double ratio) {
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end()) return;
  const int a = slot->second.split_left, b = slot->second.split_right;
  if (!a || !b || !slot->second.pages.contains(a) || !slot->second.pages.contains(b)) return;
  const bool removed = left == 0 && right == 0;
  if (!removed && (left != a || right != b || !std::isfinite(ratio) || ratio <= 0 || ratio >= 1)) return;
  const uint64_t revision = slot->second.split_revision;
  const uint64_t observation = ++slot->second.split_observation;
  auto first = slot->second.pages.at(a).browser, second = slot->second.pages.at(b).browser;
  // Chromium may omit an unchanged final ratio event; debounce all observations.
  CefPostDelayedTask(TID_UI, base::BindOnce(
      [](uint64_t token, int a, int b, double ratio, bool removed, uint64_t revision, uint64_t observation,
         CefRefPtr<CefBrowser> first, CefRefPtr<CefBrowser> second) {
        auto current = WorkspaceSlots().find(token);
        if (current == WorkspaceSlots().end() || current->second.split_revision != revision ||
            current->second.split_observation != observation ||
            current->second.split_left != a || current->second.split_right != b ||
            !current->second.pages.contains(a) || !current->second.pages.contains(b) ||
            !current->second.pages.at(a).browser->IsSame(first) ||
            !current->second.pages.at(b).browser->IsSame(second)) return;
        if (removed) {
          current->second.split_left = current->second.split_right = 0;
          ++current->second.split_revision;
        }
        BatoSwiftWorkspaceSplitChanged(token, a, b, ratio, removed ? 1 : 0);
      }, token, a, b, ratio, removed, revision, observation, first, second), removed ? 0 : 200);
}

void PostLifecycleEvent(uint64_t token, int identifier, int kind) {
  // A lifecycle callback may run inside TabStripModel mutation. Swift can
  // select a tab, so deliver only after the engine's callback stack unwinds.
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int identifier, int kind) {
        // Anchor loss/readiness may otherwise restart selection during Quit.
        // Consult the authoritative owned-slot gate before asking Swift to
        // recover; FindSlot rejects shutdown, close-all and blocked topology.
        if ((kind == 5 || kind == 7) &&
            (!g_active_browser_id || g_active_browser_id(token) <= 0)) return;
        if (WorkspaceSlots().contains(token))
          BatoSwiftWorkspacePageEvent(token, identifier, kind, "", "");
      }, token, identifier, kind));
}

void CloseCancelled(void*, uint64_t token, int identifier) {
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end() || !slot->second.pages.contains(identifier) ||
      slot->second.pending_close.erase(identifier) == 0) return;
  PostLifecycleEvent(token, identifier, 3);
}

void ActiveChanged(void*, uint64_t token, int identifier) {
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int identifier) {
        // Several tab-strip changes can occur before this task runs. Ignore
        // older notifications rather than restoring a superseded selection.
        auto slot = WorkspaceSlots().find(token);
        if (slot == WorkspaceSlots().end() || !g_active_browser_id ||
            g_active_browser_id(token) != identifier) return;
        // The presented preview is transient, never an organization selection.
        if (slot->second.peek_generation && slot->second.peek_preview == identifier) return;
        int selected = identifier;
        if (slot->second.anchor && slot->second.anchor->GetIdentifier() == identifier) {
          selected = 0;
        } else if (!slot->second.pages.contains(identifier)) {
          return;  // Untracked Chrome pages do not select a Bato entry.
        }
        BatoSwiftWorkspacePageEvent(token, selected, 6, "", "");
      }, token, identifier));
}

// Engine Profile keys name the directory under the cache root: empty is the launch Profile,
// whose Bato key Swift supplied when it asked for that window. Same mapping as blocking.
std::string BatoKeyForEngineKey(const std::string& engine_key) {
  if (!engine_key.empty()) return engine_key;
  std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
  return ProfileKeys().launch_key;
}

std::string EngineKeyForBatoKey(const std::string& key) {
  std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
  return !key.empty() && key == ProfileKeys().launch_key ? std::string() : key;
}

struct DownloadSnapshotCopy {
  std::string profile_key, id, filename, path;
  int64_t received, total, bytes_per_second;
  int state, can_resume, file_exists, warning;
};

// Runs inside a download update, possibly under a tab-model mutation: copy and defer.
void DownloadUpserted(void*, const BatoDownloadInfoV1* info) {
  if (!info || info->size != sizeof(BatoDownloadInfoV1) || !info->profile_key || !info->id) return;
  DownloadSnapshotCopy copy{info->profile_key, info->id, info->filename ? info->filename : "",
                            info->path ? info->path : "", info->received_bytes, info->total_bytes,
                            info->bytes_per_second, info->state, info->can_resume, info->file_exists,
                            info->warning};
  CefPostTask(TID_UI, base::BindOnce([](DownloadSnapshotCopy copy) {
    if (!g_swift_download_upserted) return;
    const std::string key = BatoKeyForEngineKey(copy.profile_key);
    g_swift_download_upserted(key.c_str(), copy.id.c_str(), copy.filename.c_str(), copy.path.c_str(),
                              copy.received, copy.total, copy.bytes_per_second, copy.state,
                              copy.can_resume, copy.file_exists, copy.warning);
  }, std::move(copy)));
}

void DownloadRemoved(void*, const char* profile_key, const char* id) {
  if (!profile_key || !id) return;
  CefPostTask(TID_UI, base::BindOnce([](std::string profile_key, std::string id) {
    if (!g_swift_download_removed) return;
    const std::string key = BatoKeyForEngineKey(profile_key);
    g_swift_download_removed(key.c_str(), id.c_str());
  }, std::string(profile_key), std::string(id)));
}

int RequestDownloadSnapshot() { return g_download_snapshot ? g_download_snapshot() : 0; }

int PerformDownloadAction(const char* profile_key, const char* id, int action) {
  if (!g_download_action || !profile_key || !id) return 0;
  return g_download_action(EngineKeyForBatoKey(profile_key).c_str(), id, action);
}

void PeekEnded(void*, uint64_t token, uint64_t generation, int parent, int preview, int reason) {
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end() || slot->second.peek_generation != generation) return;
  slot->second.peek_generation = 0;
  slot->second.peek_parent = slot->second.peek_preview = 0;
  slot->second.peek_parent_browser = slot->second.peek_preview_browser = nullptr;
  // Runs inside a tab-model mutation or layout; Swift may select/close tabs.
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, uint64_t generation, int parent, int preview, int reason) {
        if (g_swift_peek_ended && WorkspaceSlots().contains(token))
          g_swift_peek_ended(token, generation, parent, preview, reason);
      }, token, generation, parent, preview, reason));
}

void PeekScrimClicked(void*, uint64_t token, uint64_t generation, int parent, int preview) {
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end() || slot->second.peek_generation != generation) return;
  // Runs inside Views input handling; Swift may end the Peek and select tabs.
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, uint64_t generation, int parent, int preview) {
        auto slot = WorkspaceSlots().find(token);
        if (!g_swift_peek_scrim_clicked || slot == WorkspaceSlots().end() ||
            slot->second.peek_generation != generation) return;
        g_swift_peek_scrim_clicked(token, generation, parent, preview);
      }, token, generation, parent, preview));
}

// Runs synchronously inside the engine's navigation request: answer only from
// bound state and the pure Swift predicate, then defer the real work.
int PeekLinkRequested(void*, uint64_t token, int parent, const char* utf8_url) {
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end() || !g_swift_peek_link_eligible ||
      !g_swift_peek_link_requested || slot->second.peek_generation ||
      !ValidDestination(utf8_url)) return 0;
  auto page = slot->second.pages.find(parent);
  if (page == slot->second.pages.end() || !page->second.browser->IsValid() ||
      slot->second.pending_close.contains(parent) ||
      parent == slot->second.split_left || parent == slot->second.split_right) return 0;
  if (!g_swift_peek_link_eligible(token, parent, utf8_url)) return 0;
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int parent, std::string url) {
        if (g_swift_peek_link_requested && WorkspaceSlots().contains(token))
          g_swift_peek_link_requested(token, parent, url.c_str());
      }, token, parent, std::string(utf8_url)));
  return 1;
}

// Acts only on the visible, focused page: its identifier must equal the engine's
// active browser, which also refuses blocked/modal/fullscreen slots and a presented
// Peek (whose active page is the transient preview).
int NavigateWorkspacePage(uint64_t token, int identifier, const char* utf8_url) {
  auto* slot = AvailableSlot(token);
  if (!slot || g_active_browser_id(token) != identifier || slot->peek_generation ||
      slot->pending_close.contains(identifier)) return 0;
  auto found = slot->pages.find(identifier);
  if (found == slot->pages.end() || !found->second.browser->IsValid()) return 0;
  auto frame = found->second.browser->GetMainFrame();
  if (!ValidDestination(utf8_url) || !frame || !frame->IsValid()) return 0;
  frame->LoadURL(CefString(utf8_url));
  return 1;
}

// Synchronous diagnostic action only. No URL, credentials or field text logged.
int NavigateCurrentPage(uint64_t token, const char* utf8_url) {
  if (!NSThread.isMainThread || !CefCurrentlyOn(TID_UI) ||
      !g_active_browser_id || !ValidDestination(utf8_url)) return 0;
  const CefString url(utf8_url);
  const int identifier = g_active_browser_id(token);
  if (identifier <= 0) return 0;
  auto browser = CefBrowserHost::GetBrowserByIdentifier(identifier);
  if (!browser || !browser->IsValid()) return 0;
  auto frame = browser->GetMainFrame();
  if (!frame || !frame->IsValid()) return 0;
  frame->LoadURL(url);
  return 1;
}

// The first window is the launch Profile's; later windows are accepted only while a Profile
// window request is outstanding. Any other window keeps stock Chrome UI with no sidebar.
void* Create(void*, uint64_t token) {
  if (g_workspace_enabled) {
    if (g_primary_slot_created && PendingWindow().key.empty()) return nullptr;
    g_primary_slot_created = true;
    WorkspaceSlots().try_emplace(token);
    void* view = BatoSwiftNativeSlotCreate(token);
    if (!view) WorkspaceSlots().erase(token);
    return view;
  }
  return BatoSwiftNativeSlotCreate(token);
}

bool ValidProfileKey(const std::string& key) {
  if (key.size() != 36) return false;
  for (size_t i = 0; i < key.size(); ++i) {
    const char c = key[i];
    const bool dash = i == 8 || i == 13 || i == 18 || i == 23;
    if (dash ? c != '-' : !((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
  }
  return true;
}

// Destroys a non-launch Profile: the engine closes its windows and removes its storage; the cached
// context is dropped so a later Profile with the same key (never reused in practice) starts clean.
int DeleteProfileData(const char* utf8_key) {
  if (!g_workspace_enabled || !NSThread.isMainThread || !CefCurrentlyOn(TID_UI) ||
      !g_delete_profile || !utf8_key) return 0;
  const std::string key = utf8_key;
  if (!ValidProfileKey(key) || !PendingWindow().key.empty()) return 0;
  if (g_delete_profile(key.c_str()) != 1) return 0;
  ProfileContexts().erase(key);
  {
    std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
    for (auto it = ProfileKeys().by_browser.begin(); it != ProfileKeys().by_browser.end();) {
      it = it->second == key ? ProfileKeys().by_browser.erase(it) : std::next(it);
    }
  }
  fprintf(stderr, "{\"event\":\"profile-delete-scheduled\",\"key\":\"%s\"}\n", key.c_str());
  return 1;
}

// Requests a Chrome window whose Browser uses the Profile's own request context. The
// Chrome runtime pairs a Browser with exactly one Profile, so pages of different Profiles
// can never share a window. Returns 1 when the request was accepted; completion arrives
// through BatoSwiftWorkspaceProfileWindowReady. launch != 0 reopens the launch Profile's
// window on the original global context.
int OpenProfileWindow(const char* utf8_key, int launch) {
  if (!g_workspace_enabled || !NSThread.isMainThread || !CefCurrentlyOn(TID_UI) ||
      !g_active_browser_id || !g_swift_profile_ready || !utf8_key) return 0;
  const std::string key = utf8_key;
  if (!ValidProfileKey(key) || !PendingWindow().key.empty()) return 0;
  CefRefPtr<CefRequestContext> context;
  if (launch) {
    RememberLaunchProfileKey(key);
    context = CefRequestContext::GetGlobalContext();
    if (!ContextPathIs(context, ExpectedProfilePath("", true))) {
      LogProfileRefusal("launch-context-not-default");
      return 0;
    }
  } else {
    auto& contexts = ProfileContexts();
    auto found = contexts.find(key);
    if (found == contexts.end()) {
      // CEF persists a Chrome-style context only as a direct child of its user data dir, which is
      // the --cache-path root. Any other location silently becomes an in-memory profile, so
      // refuse instead of losing storage.
      const std::string path = ExpectedProfilePath(key, false);
      if (path.empty()) {
        LogProfileRefusal("cache-root-unavailable");
        return 0;
      }
      CefRequestContextSettings settings;
      CefString(&settings.cache_path) = path;
      context = CefRequestContext::CreateContext(settings, nullptr);
      if (!ContextPathIs(context, path)) {
        LogProfileRefusal("context-path-rejected");
        return 0;
      }
      found = contexts.emplace(key, context).first;
    }
    context = found->second;
  }
  PendingWindow().key = key;
  PendingWindow().launch = launch != 0;
  PendingWindow().context = context;
  const uint64_t serial = ++g_window_serial;
  PendingWindow().serial = serial;
  CefWindowInfo window_info;
  CefBrowserSettings browser_settings;
  if (!CefBrowserHost::CreateBrowser(window_info, SimpleHandler::GetInstance(), "about:blank",
                                     browser_settings, nullptr, context)) {
    PendingWindow() = WindowRequest();
    return 0;
  }
  CefPostDelayedTask(TID_UI, base::BindOnce(
      [](uint64_t serial) {
        if (PendingWindow().serial != serial || PendingWindow().key.empty()) return;
        const std::string key = PendingWindow().key;
        PendingWindow() = WindowRequest();
        PostProfileWindowResult(0, key, false);
      }, serial), kProfileWindowTimeoutMs);
  return 1;
}
void Detached(void*, uint64_t token) {
  WorkspaceSlots().erase(token);
  BatoSwiftNativeSlotDetached(token);
}
void* FocusTarget(void*, uint64_t token) { return BatoSwiftNativeSlotFocusTarget(token); }
}  // namespace

uint64_t BatoWorkspacePeekPresent(uint64_t token, int parent, int preview) {
  auto* slot = AvailableSlot(token);
  if (!slot || !g_peek_present || slot->peek_generation || parent <= 0 ||
      preview <= 0 || parent == preview) return 0;
  for (int identifier : {parent, preview}) {
    auto found = slot->pages.find(identifier);
    if (found == slot->pages.end() || !found->second.browser->IsValid() ||
        slot->pending_close.contains(identifier)) return 0;
    // Never adopt a page that belongs to the managed split pair.
    if (identifier == slot->split_left || identifier == slot->split_right) return 0;
  }
  auto parent_browser = slot->pages.at(parent).browser;
  auto preview_browser = slot->pages.at(preview).browser;
  if (!slot->context || !SameWindow(parent_browser, preview_browser) ||
      !parent_browser->GetHost()->GetRequestContext()->IsSame(slot->context) ||
      !preview_browser->GetHost()->GetRequestContext()->IsSame(slot->context)) return 0;
  const uint64_t generation = g_peek_present(token, parent, preview);
  if (!generation) return 0;
  // The engine call selects tabs and runs layout; revalidate before binding.
  auto current = WorkspaceSlots().find(token);
  if (current == WorkspaceSlots().end() || current->second.peek_generation ||
      !current->second.pages.contains(parent) || !current->second.pages.contains(preview) ||
      !current->second.pages.at(parent).browser->IsSame(parent_browser) ||
      !current->second.pages.at(preview).browser->IsSame(preview_browser)) {
    if (g_peek_end) g_peek_end(token, generation, 0);
    return 0;
  }
  current->second.peek_generation = generation;
  current->second.peek_parent = parent;
  current->second.peek_preview = preview;
  current->second.peek_parent_browser = parent_browser;
  current->second.peek_preview_browser = preview_browser;
  return generation;
}

int BatoWorkspacePeekEnd(uint64_t token, uint64_t generation, int restore_parent) {
  if (!NSThread.isMainThread || !CefCurrentlyOn(TID_UI) || !g_peek_end || !generation) return 0;
  auto slot = WorkspaceSlots().find(token);
  if (slot == WorkspaceSlots().end() || slot->second.peek_generation != generation) return 0;
  const int result = g_peek_end(token, generation, restore_parent);
  auto current = WorkspaceSlots().find(token);
  if (result != 0 && current != WorkspaceSlots().end() &&
      current->second.peek_generation == generation) {
    current->second.peek_generation = 0;
    current->second.peek_parent = current->second.peek_preview = 0;
    current->second.peek_parent_browser = current->second.peek_preview_browser = nullptr;
  }
  return result;
}

std::string BatoWorkspaceBlockingProfileKey(int browser_id) {
  if (!g_workspace_enabled) return "default";
  std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
  const auto found = ProfileKeys().by_browser.find(browser_id);
  if (found == ProfileKeys().by_browser.end()) return "";
  return found->second.empty() ? ProfileKeys().launch_key : found->second;
}

void BatoWorkspaceBrowserCreated(CefRefPtr<CefBrowser> browser) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const int identifier = browser->GetIdentifier();
  RecordBrowserProfileKey(browser);
  if (g_initial_browser_id == 0) g_initial_browser_id = identifier;
  if (identifier != g_initial_browser_id && PendingWindow().key.empty()) return;
  // OnAfterCreated precedes SetBrowser/tab-strip attachment. Only the posted
  // task may inspect the active window identity or request lazy restoration.
  CefPostTask(TID_UI, base::BindOnce(
      [](CefRefPtr<CefBrowser> browser) {
        if (!browser->IsValid() || !g_active_browser_id) return;
        auto frame = browser->GetMainFrame();
        if (!frame) return;
        const auto initial_url = frame->GetURL().ToString();
        if (!initial_url.empty() && initial_url != "about:blank") return;
        const int identifier = browser->GetIdentifier();
        for (auto& [token, slot] : WorkspaceSlots()) {
          if (slot.context || g_active_browser_id(token) != identifier) continue;
          if (!BindAnchor(token, slot, browser)) continue;
          PostLifecycleEvent(token, 0, 7);
          return;
        }
      }, browser));
}

void BatoWorkspaceBrowserAddressChanged(CefRefPtr<CefBrowser> browser,
                                        const CefString& url) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const int identifier = browser->GetIdentifier();
  for (auto& [token, slot] : WorkspaceSlots()) {
    auto found = slot.pages.find(identifier);
    if (found == slot.pages.end()) continue;
    found->second.url = url.ToString();
    ++found->second.icon_revision;
    PostPageIcon(token, identifier, browser, found->second.icon_revision, {});
    PostPageState(token, identifier, found->second);
    return;
  }
}

void BatoWorkspaceBrowserFaviconChanged(CefRefPtr<CefBrowser> browser,
                                        const std::vector<CefString>& urls) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI) || !browser->IsValid()) return;
  const int identifier = browser->GetIdentifier();
  for (auto& [token, slot] : WorkspaceSlots()) {
    auto found = slot.pages.find(identifier);
    if (found == slot.pages.end() || !found->second.browser->IsSame(browser)) continue;
    const auto revision = ++found->second.icon_revision;
    PostPageIcon(token, identifier, browser, revision, {});
    // Only the first usable advertised HTTP(S) icon is requested. Browser-owned
    // decoding is size-bounded; cookies are neither sent nor accepted for favicons.
    for (const auto& url : urls) {
      const auto value = url.ToString();
      if (!ValidDestination(value.c_str())) continue;
      browser->GetHost()->DownloadImage(url, true, 32, false,
          new WorkspaceIconDownload(token, identifier, browser, revision));
      break;
    }
    return;
  }
}

void BatoWorkspaceBrowserTitleChanged(CefRefPtr<CefBrowser> browser,
                                      const CefString& title) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const int identifier = browser->GetIdentifier();
  for (auto& [token, slot] : WorkspaceSlots()) {
    auto found = slot.pages.find(identifier);
    if (found == slot.pages.end()) continue;
    found->second.title = title.ToString();
    PostPageState(token, identifier, found->second);
    return;
  }
}

void BatoWorkspaceBrowserClosed(CefRefPtr<CefBrowser> browser) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const int identifier = browser->GetIdentifier();
  {
    std::lock_guard<std::mutex> lock(ProfileKeys().mutex);
    ProfileKeys().by_browser.erase(identifier);
  }
  for (auto& [token, slot] : WorkspaceSlots()) {
    if (slot.anchor && slot.anchor->IsSame(browser)) {
      slot.anchor = nullptr;
      // Keep the original Profile identity for safe lazy anchor replacement.
      PostLifecycleEvent(token, 0, 5);
    }
    auto found = slot.pages.find(identifier);
    if (found == slot.pages.end()) continue;
    const bool requested = slot.pending_close.erase(identifier) != 0;
    // Drop all refs/bindings before Swift can synchronously select/create again.
    slot.pages.erase(found);
    PostLifecycleEvent(token, identifier, requested ? 2 : 4);
    return;
  }
}

void BatoWorkspaceReleaseProfileContexts() {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const size_t released = ProfileContexts().size();
  ProfileContexts().clear();
  PendingWindow() = WindowRequest();
  fprintf(stderr, "{\"event\":\"profile-contexts-released\",\"count\":%zu}\n", released);
}

bool BatoWorkspaceIsAnchor(CefRefPtr<CefBrowser> browser) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI) || !browser) return false;
  for (const auto& [token, slot] : WorkspaceSlots()) {
    if (slot.anchor && slot.anchor->IsSame(browser)) return true;
  }
  return false;
}

// Chromium binds Shift-Cmd-C to Inspect Element wherever it consumes the chord (its
// accelerator table, command dispatcher or menu), and every route ends in this command
// callback. Only a key event of exactly that chord counts: Cmd-Option-C and the menu
// item keep Inspect.
static bool IsCopyUrlChord() {
  NSEvent* event = NSApp.currentEvent;
  constexpr unsigned short kKeyCodeC = 8;
  const auto flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                            NSEventModifierFlagControl | NSEventModifierFlagOption);
  return event.type == NSEventTypeKeyDown && event.keyCode == kKeyCodeC &&
         flags == (NSEventModifierFlagCommand | NSEventModifierFlagShift);
}

bool BatoWorkspaceChromeCommand(CefRefPtr<CefBrowser> browser, int command_id) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return false;
  int command = 0;
  if (command_id == cef_id_for_command_id_name("IDC_NEW_TAB")) command = 1;
  if (command_id == cef_id_for_command_id_name("IDC_CLOSE_TAB")) command = 2;
  if (command_id == cef_id_for_command_id_name("IDC_DEV_TOOLS_INSPECT") && IsCopyUrlChord()) command = 4;
  // Not reached through Chrome's command controller: the engine offers these three from
  // chrome::ShowHistory/ShowDownloads/ShowSettings, which every menu and key route ends in.
  if (command_id == cef_id_for_command_id_name("IDC_SHOW_HISTORY")) command = 5;
  if (command_id == cef_id_for_command_id_name("IDC_SHOW_DOWNLOADS")) command = 6;
  if (command_id == cef_id_for_command_id_name("IDC_OPTIONS")) command = 7;
  // Not a Chromium command: the engine's chrome_pages.cc offers this id for page info's
  // "Site settings" link and content-settings sub-pages (kBatoCommandShowSiteSettings).
  if (command_id == 1000001) command = 30;
  // Same hook shape for Chrome's tab-strip and window chords: Bato pages live in the sidebar, so
  // Chrome's restore service, window creation and tab selection must not act on them.
  // New Window opens the command bar because each Profile has exactly one window.
  if (command_id == cef_id_for_command_id_name("IDC_NEW_WINDOW")) command = 1;
  if (command_id == cef_id_for_command_id_name("IDC_RESTORE_TAB")) command = 8;
  // History > Recently Closed rows: the engine offers 1000100 + position (history_menu_cocoa_controller.mm).
  if (command_id >= 1000100 && command_id < 1000120) command = 40 + (command_id - 1000100);
  if (command_id == cef_id_for_command_id_name("IDC_SELECT_NEXT_TAB") ||
      command_id == cef_id_for_command_id_name("IDC_CYCLE_TO_NEXT_TAB")) command = 9;
  if (command_id == cef_id_for_command_id_name("IDC_SELECT_PREVIOUS_TAB") ||
      command_id == cef_id_for_command_id_name("IDC_CYCLE_TO_PREV_TAB")) command = 10;
  static const char* const kSelectTabNames[] = {
      "IDC_SELECT_TAB_0", "IDC_SELECT_TAB_1", "IDC_SELECT_TAB_2", "IDC_SELECT_TAB_3",
      "IDC_SELECT_TAB_4", "IDC_SELECT_TAB_5", "IDC_SELECT_TAB_6", "IDC_SELECT_TAB_7"};
  for (int i = 0; i < 8; ++i) {
    if (command_id == cef_id_for_command_id_name(kSelectTabNames[i])) command = 21 + i;
  }
  if (command_id == cef_id_for_command_id_name("IDC_SELECT_LAST_TAB")) command = 29;
  // Tab menu items act on Chrome's tab strip, which holds only the pages Bato created.
  // New Tab to the Right is New Tab, Pin Tab pins or unpins the selection, and the
  // grouping and window-moving items have no sidebar meaning, so they are consumed.
  if (command_id == cef_id_for_command_id_name("IDC_NEW_TAB_TO_RIGHT")) command = 1;
  if (command_id == cef_id_for_command_id_name("IDC_DUPLICATE_TAB")) command = 31;
  if (command_id == cef_id_for_command_id_name("IDC_WINDOW_PIN_TAB")) command = 32;
  if (command_id == cef_id_for_command_id_name("IDC_WINDOW_CLOSE_OTHER_TABS")) command = 33;
  if (command_id == cef_id_for_command_id_name("IDC_WINDOW_CLOSE_TABS_TO_RIGHT")) command = 34;
  if (command_id == cef_id_for_command_id_name("IDC_MOVE_TAB_TO_NEW_WINDOW") ||
      command_id == cef_id_for_command_id_name("IDC_WINDOW_GROUP_TAB")) command = 99;
  fprintf(stderr, "{\"event\":\"workspace-chrome-command\",\"id\":%d,\"command\":%d}\n", command_id, command);
  if (!command || !browser || !browser->IsValid()) return false;
  for (const auto& [token, slot] : WorkspaceSlots()) {
    auto* available = AvailableSlot(token);
    if (!available) continue;
    auto peer = CurrentPeer(token, *available);
    if (!peer || !SameWindow(peer, browser) ||
        !browser->GetHost()->GetRequestContext()->IsSame(available->context)) continue;
    // A same-window callback is not sufficient authority to target a Bato page.
    // Resolve the actual active tab, leaving Chrome-owned tabs to Chrome.
    const int active_identifier = g_active_browser_id(token);
    if (active_identifier <= 0 || browser->GetIdentifier() != active_identifier)
      return false;
    const int identifier = ActiveWorkspacePage(token);
    if (identifier < 0) return false;
    // Not while a Peek is presented: Swift refuses the copy and Inspect would be lost.
    if (command == 4 && (identifier == 0 || available->peek_generation)) return false;
    CefPostTask(TID_UI, base::BindOnce(
        [](uint64_t token, int command, int identifier, int active_identifier) {
          // Selection can change before this task runs. Never reselect/close a
          // background page on behalf of an obsolete command.
          if (g_active_browser_id(token) != active_identifier ||
              ActiveWorkspacePage(token) != identifier) return;
          BatoSwiftWorkspaceCommand(token, command, identifier);
        }, token, command, identifier, active_identifier));
    return true;
  }
  return false;
}

constexpr int kMenuIdOpenLinkInPeek = MENU_ID_USER_FIRST + 1;

// The workspace slot that holds this browser as a page, or false for any other browser.
static bool FindWorkspacePage(CefRefPtr<CefBrowser> browser, uint64_t* token) {
  if (!g_workspace_enabled || !browser) return false;
  for (const auto& [candidate, slot] : WorkspaceSlots()) {
    if (slot.pages.contains(browser->GetIdentifier())) {
      *token = candidate;
      return true;
    }
  }
  return false;
}

void BatoWorkspaceContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefContextMenuParams> params,
                              CefRefPtr<CefMenuModel> model) {
  uint64_t token = 0;
  if (!g_swift_peek_link_eligible || !(params->GetTypeFlags() & CM_TYPEFLAG_LINK) ||
      !FindWorkspacePage(browser, &token)) return;
  const std::string url = params->GetLinkUrl().ToString();
  if (!ValidDestination(url.c_str()) || !g_swift_peek_link_eligible(token, browser->GetIdentifier(), url.c_str())) return;
  const int new_tab_index = model->GetIndexOf(cef_id_for_command_id_name("IDC_CONTENT_CONTEXT_OPENLINKNEWTAB"));
  if (new_tab_index < 0) return;
  model->InsertItemAt(new_tab_index + 1, kMenuIdOpenLinkInPeek, "Open Link in Peek");
}

bool BatoWorkspaceContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefContextMenuParams> params,
                                     int command_id) {
  uint64_t token = 0;
  if (command_id != kMenuIdOpenLinkInPeek) return false;
  if (!FindWorkspacePage(browser, &token)) return true;
  // Same checks and deferral as a Shift-clicked link; a refusal leaves the menu action a no-op.
  PeekLinkRequested(nullptr, token, browser->GetIdentifier(), params->GetLinkUrl().ToString().c_str());
  return true;
}

// Chromium would open these in a stock window outside the sidebar. Only links without an opener
// reach here (window.open with an opener goes through AddWebContents), so nothing is lost by
// opening a Bato tab instead.
bool BatoWorkspaceOpenLinkInTab(CefRefPtr<CefBrowser> browser, const std::string& url,
                                cef_window_open_disposition_t disposition) {
  using SwiftOpenLinkInTab = void (*)(uint64_t, int, const char*);
  static const auto open_link = reinterpret_cast<SwiftOpenLinkInTab>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceOpenLinkInTab"));
  uint64_t token = 0;
  if ((disposition != CEF_WOD_NEW_FOREGROUND_TAB && disposition != CEF_WOD_NEW_BACKGROUND_TAB) ||
      !open_link || !CefCurrentlyOn(TID_UI) || !FindWorkspacePage(browser, &token) ||
      !ValidDestination(url.c_str())) return false;
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int parent, std::string url) {
        if (WorkspaceSlots().contains(token)) open_link(token, parent, url.c_str());
      }, token, browser->GetIdentifier(), url));
  return true;
}

bool BatoRegisterNativeSlotClient(CefRefPtr<CefCommandLine> command_line) {
  if (![NSThread isMainThread] || !command_line) return false;
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
  auto native_focus = reinterpret_cast<decltype(&bato_native_slot_focus_native_v1)>(
      dlsym(loaded, "bato_native_slot_focus_native_v1"));
  auto active_browser_id = reinterpret_cast<ActiveBrowserId>(
      dlsym(loaded, "bato_native_slot_active_browser_id_v1"));
  auto new_tab = reinterpret_cast<NewTab>(dlsym(loaded, "bato_native_slot_new_tab_v1"));
  auto request_close = reinterpret_cast<RequestClose>(
      dlsym(loaded, "bato_native_slot_request_close_v1"));
  auto register_pages = reinterpret_cast<decltype(&bato_native_slot_register_page_callbacks_v1)>(
      dlsym(loaded, "bato_native_slot_register_page_callbacks_v1"));
  auto sidebar_geometry = reinterpret_cast<decltype(&bato_native_slot_set_sidebar_v1)>(
      dlsym(loaded, "bato_native_slot_set_sidebar_v1"));
  auto present_split = reinterpret_cast<PresentSplit>(dlsym(loaded, "bato_native_slot_present_split_v1"));
  auto separate_split = reinterpret_cast<SeparateSplit>(dlsym(loaded, "bato_native_slot_separate_split_v1"));
  auto register_splits = reinterpret_cast<decltype(&bato_native_slot_register_split_callbacks_v1)>(
      dlsym(loaded, "bato_native_slot_register_split_callbacks_v1"));
  auto register_peeks = reinterpret_cast<decltype(&bato_native_slot_register_peek_callbacks_v1)>(
      dlsym(loaded, "bato_native_slot_register_peek_callbacks_v1"));
  auto peek_present = reinterpret_cast<PeekPresent>(dlsym(loaded, "bato_native_slot_peek_present_v1"));
  auto peek_end = reinterpret_cast<PeekEnd>(dlsym(loaded, "bato_native_slot_peek_end_v1"));
  auto swift_configure_peek = reinterpret_cast<SwiftConfigurePeek>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceConfigurePeek"));
  auto swift_peek_ended = reinterpret_cast<SwiftPeekEnded>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspacePeekEnded"));
  auto register_peek_interactions =
      reinterpret_cast<decltype(&bato_native_slot_register_peek_interaction_callbacks_v1)>(
          dlsym(loaded, "bato_native_slot_register_peek_interaction_callbacks_v1"));
  auto swift_scrim_clicked = reinterpret_cast<SwiftPeekScrimClicked>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspacePeekScrimClicked"));
  auto swift_link_eligible = reinterpret_cast<SwiftPeekLinkEligible>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspacePeekLinkEligible"));
  auto swift_link_requested = reinterpret_cast<SwiftPeekLinkRequested>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspacePeekLinkRequested"));
  auto swift_configure_navigation = reinterpret_cast<SwiftConfigureNavigation>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceConfigureNavigation"));
  auto register_downloads = reinterpret_cast<decltype(&bato_native_slot_register_download_callbacks_v1)>(
      dlsym(loaded, "bato_native_slot_register_download_callbacks_v1"));
  auto download_snapshot = reinterpret_cast<decltype(&bato_native_slot_download_snapshot_v1)>(
      dlsym(loaded, "bato_native_slot_download_snapshot_v1"));
  auto download_action = reinterpret_cast<decltype(&bato_native_slot_download_action_v1)>(
      dlsym(loaded, "bato_native_slot_download_action_v1"));
  auto delete_profile = reinterpret_cast<decltype(&bato_native_slot_delete_profile_v1)>(
      dlsym(loaded, "bato_native_slot_delete_profile_v1"));
  auto swift_configure_profile_delete = reinterpret_cast<SwiftConfigureProfileDelete>(
      dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceConfigureProfileDelete"));
  auto swift_configure_downloads = reinterpret_cast<SwiftDownloadsConfigure>(
      dlsym(RTLD_DEFAULT, "BatoSwiftDownloadsConfigure"));
  auto swift_download_upserted = reinterpret_cast<SwiftDownloadUpserted>(
      dlsym(RTLD_DEFAULT, "BatoSwiftDownloadUpserted"));
  auto swift_download_removed = reinterpret_cast<SwiftDownloadRemoved>(
      dlsym(RTLD_DEFAULT, "BatoSwiftDownloadRemoved"));
  dlclose(loaded);  // CefScopedLibraryLoader retains framework until shutdown.
  if (!registration || !focus || !advance || !active_browser_id) {
    fprintf(stderr, "{\"event\":\"slot-client-abi-unavailable\"}\n");
    return false;
  }
  const auto directory = command_line->GetSwitchValue("bato-workspace-state").ToString();
  g_workspace_enabled = command_line->HasSwitch("bato-workspace-state");
  if (g_workspace_enabled) {
    if (directory.empty() || directory.front() != '/' || !new_tab || !native_focus ||
        !request_close || !register_pages || !sidebar_geometry ||
        command_line->GetSwitchValue("url").ToString() != "about:blank") {
      fprintf(stderr, "{\"event\":\"workspace-client-configuration-refused\"}\n");
      return false;
    }
    BatoPageCallbacksV1 page_callbacks = {};
    page_callbacks.size = sizeof(page_callbacks);
    page_callbacks.version = 1;
    page_callbacks.close_cancelled = CloseCancelled;
    page_callbacks.active_changed = ActiveChanged;
    if (register_pages(&page_callbacks) != 1) return false;
    if (!present_split || !separate_split || !register_splits) return false;
    BatoSplitCallbacksV1 split_callbacks = {};
    split_callbacks.size = sizeof(split_callbacks);
    split_callbacks.version = 1;
    split_callbacks.changed = SplitChanged;
    if (register_splits(&split_callbacks) != 1) return false;
    g_present_split = present_split;
    g_separate_split = separate_split;
    BatoSwiftWorkspaceConfigureSplits(PresentWorkspaceSplit, SeparateWorkspaceSplit);
    // Peek is additive: a framework or Swift library without it keeps working.
    if (register_peeks && peek_present && peek_end && swift_configure_peek && swift_peek_ended) {
      BatoPeekCallbacksV1 peek_callbacks = {};
      peek_callbacks.size = sizeof(peek_callbacks);
      peek_callbacks.version = 1;
      peek_callbacks.ended = PeekEnded;
      if (register_peeks(&peek_callbacks) == 1) {
        g_peek_present = peek_present;
        g_peek_end = peek_end;
        g_swift_peek_ended = swift_peek_ended;
        swift_configure_peek(BatoWorkspacePeekPresent, BatoWorkspacePeekEnd);
        // Scrim dismissal and Shift-click links are further additive layers.
        if (register_peek_interactions && swift_scrim_clicked && swift_link_eligible &&
            swift_link_requested) {
          BatoPeekInteractionCallbacksV1 interactions = {};
          interactions.size = sizeof(interactions);
          interactions.version = 1;
          interactions.scrim_clicked = PeekScrimClicked;
          interactions.link_requested = PeekLinkRequested;
          if (register_peek_interactions(&interactions) == 1) {
            g_swift_peek_scrim_clicked = swift_scrim_clicked;
            g_swift_peek_link_eligible = swift_link_eligible;
            g_swift_peek_link_requested = swift_link_requested;
          }
        }
      }
    }
    // Downloads are additive: without the engine exports Chromium's own UI stays the only one.
    if (register_downloads && download_snapshot && download_action && swift_configure_downloads &&
        swift_download_upserted && swift_download_removed) {
      BatoDownloadCallbacksV1 downloads = {};
      downloads.size = sizeof(downloads);
      downloads.version = 1;
      downloads.upserted = DownloadUpserted;
      downloads.removed = DownloadRemoved;
      if (register_downloads(&downloads) == 1) {
        g_download_snapshot = download_snapshot;
        g_download_action = download_action;
        g_swift_download_upserted = swift_download_upserted;
        g_swift_download_removed = swift_download_removed;
        swift_configure_downloads(RequestDownloadSnapshot, PerformDownloadAction);
      }
    }
    if (swift_configure_navigation) swift_configure_navigation(NavigateWorkspacePage);
    g_new_tab = new_tab;
    g_request_close = request_close;
    // Multi-Profile windows are additive: without the Swift hooks only the launch Profile opens.
    auto swift_configure_profiles = reinterpret_cast<SwiftConfigureProfiles>(
        dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceConfigureProfiles"));
    auto swift_profile_ready = reinterpret_cast<SwiftProfileWindowReady>(
        dlsym(RTLD_DEFAULT, "BatoSwiftWorkspaceProfileWindowReady"));
    if (swift_configure_profiles && swift_profile_ready) {
      g_swift_profile_ready = swift_profile_ready;
      swift_configure_profiles(OpenProfileWindow);
      // Profile delete is additive: without the engine export the Delete button stays refused.
      if (delete_profile && swift_configure_profile_delete) {
        g_delete_profile = delete_profile;
        swift_configure_profile_delete(DeleteProfileData);
      }
    }
    BatoSwiftWorkspaceConfigure(directory.c_str(), CreateWorkspacePage,
                                 SelectWorkspacePage, CloseWorkspacePage,
                                 ActiveWorkspacePage, native_focus, WorkspaceCommandId,
                                 ScheduleWorkspaceSelection, sidebar_geometry, focus);
    // Links that macOS hands the app while it starts arrive before any window exists.
    if (auto install_router = reinterpret_cast<void (*)()>(
            dlsym(RTLD_DEFAULT, "BatoSwiftInstallExternalURLRouter"))) {
      install_router();
    }
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
