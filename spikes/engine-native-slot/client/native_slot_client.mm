#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <cstdio>
#include <map>
#include <set>
#include <string>
#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_id_mappers.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/internal/bato_native_slot.h"
#include "include/wrapper/cef_closure_task.h"
#include "tests/cefsimple/native_slot_client.h"

extern "C" void* BatoSwiftNativeSlotCreate(uint64_t token);
extern "C" void* BatoSwiftNativeSlotFocusTarget(uint64_t token);
extern "C" void BatoSwiftNativeSlotDetached(uint64_t token);
extern "C" void BatoSwiftNativeSlotSetActions(int (*focus)(uint64_t),
                                              int (*advance)(uint64_t, int),
                                              int (*navigate)(uint64_t, const char*));
extern "C" void BatoSwiftWorkspaceConfigure(const char* state_directory,
    int (*create)(uint64_t, const char*), int (*select)(uint64_t, int),
    int (*close)(uint64_t, int), int (*active)(uint64_t),
    int (*native_focus)(uint64_t), int (*command_id)(int));
extern "C" void BatoSwiftWorkspaceCommand(uint64_t token, int command, int browser_id);
extern "C" void BatoSwiftWorkspacePageEvent(uint64_t token, int browser_id,
    int kind, const char* url, const char* title);

namespace {
using ActiveBrowserId = decltype(&bato_native_slot_active_browser_id_v1);
using NewTab = decltype(&bato_native_slot_new_tab_v1);
using RequestClose = decltype(&bato_native_slot_request_close_v1);
ActiveBrowserId g_active_browser_id = nullptr;
NewTab g_new_tab = nullptr;
RequestClose g_request_close = nullptr;
bool g_workspace_enabled = false;
int g_initial_browser_id = 0;

struct BoundPage {
  CefRefPtr<CefBrowser> browser;
  std::string url;
  std::string title;
};
struct WorkspaceSlot {
  CefRefPtr<CefBrowser> anchor;
  CefRefPtr<CefRequestContext> context;
  std::map<int, BoundPage> pages;
  std::set<int> pending_close;
};
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

WorkspaceSlot* AvailableSlot(uint64_t token) {
  if (!g_workspace_enabled || !NSThread.isMainThread ||
      !CefCurrentlyOn(TID_UI) || !g_active_browser_id) return nullptr;
  const int identifier = g_active_browser_id(token);
  if (identifier <= 0) return nullptr;
  auto found = WorkspaceSlots().find(token);
  if (found == WorkspaceSlots().end()) return nullptr;
  auto active = CefBrowserHost::GetBrowserByIdentifier(identifier);
  if (!active || !active->IsValid()) return nullptr;
  auto& slot = found->second;
  if (!slot.context) {
    // Only the initial browser can seed the original blank anchor. A new tab
    // can also briefly have an empty URL, so emptiness alone is insufficient.
    if (identifier != g_initial_browser_id) return nullptr;
    auto frame = active->GetMainFrame();
    if (!frame) return nullptr;
    const auto initial_url = frame->GetURL().ToString();
    if (!initial_url.empty() && initial_url != "about:blank") return nullptr;
    slot.anchor = active;
    slot.context = active->GetHost()->GetRequestContext();
  }
  // An anchor closed by Chrome does not change the bound engine Profile. A real
  // page may prove same-window ownership, but must never become the blank anchor.
  if (!active->GetHost()->GetRequestContext()->IsSame(slot.context)) return nullptr;
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

int CreateWorkspacePage(uint64_t token, const char* utf8_url) {
  if (!ValidDestination(utf8_url) || !g_new_tab) return 0;
  auto* slot = AvailableSlot(token);
  if (!slot) return 0;
  // Copy URL and retain the same-window peer/context across Chrome callbacks.
  const CefString url(utf8_url);
  CefRefPtr<CefBrowser> peer = CurrentPeer(token, *slot);
  CefRefPtr<CefRequestContext> context = slot->context;
  if (!peer) return 0;
  const int identifier = g_new_tab(token);
  auto browser = identifier > 0 ? CefBrowserHost::GetBrowserByIdentifier(identifier) : nullptr;
  auto current_slot = WorkspaceSlots().find(token);
  if (!browser || !browser->IsValid() || current_slot == WorkspaceSlots().end() ||
      browser->IsSame(peer) || !SameWindow(peer, browser) ||
      !browser->GetHost()->GetRequestContext()->IsSame(context)) return 0;
  auto frame = browser->GetMainFrame();
  if (!frame || !frame->IsValid()) return 0;
  auto& pages = current_slot->second.pages;
  if (pages.contains(identifier)) return 0;
  auto [found, inserted] = pages.emplace(identifier, BoundPage{browser, url.ToString(), ""});
  if (!inserted) return 0;
  frame->LoadURL(url);
  // Navigation can reenter client code. Never keep an iterator across it.
  auto still_live = WorkspaceSlots().find(token);
  if (still_live == WorkspaceSlots().end()) return 0;
  auto bound = still_live->second.pages.find(identifier);
  if (bound == still_live->second.pages.end()) return 0;
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

void PostLifecycleEvent(uint64_t token, int identifier, int kind) {
  // A lifecycle callback may run inside TabStripModel mutation. Swift can
  // select a tab, so deliver only after the engine's callback stack unwinds.
  CefPostTask(TID_UI, base::BindOnce(
      [](uint64_t token, int identifier, int kind) {
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
        int selected = identifier;
        if (slot->second.anchor && slot->second.anchor->GetIdentifier() == identifier) {
          selected = 0;
        } else if (!slot->second.pages.contains(identifier)) {
          return;  // Untracked Chrome pages do not select a Bato entry.
        }
        BatoSwiftWorkspacePageEvent(token, selected, 6, "", "");
      }, token, identifier));
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

void* Create(void*, uint64_t token) {
  if (g_workspace_enabled) WorkspaceSlots().try_emplace(token);
  return BatoSwiftNativeSlotCreate(token);
}
void Detached(void*, uint64_t token) {
  WorkspaceSlots().erase(token);
  BatoSwiftNativeSlotDetached(token);
}
void* FocusTarget(void*, uint64_t token) { return BatoSwiftNativeSlotFocusTarget(token); }
}  // namespace

void BatoWorkspaceBrowserCreated(CefRefPtr<CefBrowser> browser) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return;
  const int identifier = browser->GetIdentifier();
  if (g_initial_browser_id == 0) g_initial_browser_id = identifier;
  if (identifier != g_initial_browser_id) return;
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
          slot.anchor = browser;
          slot.context = browser->GetHost()->GetRequestContext();
          PostLifecycleEvent(token, 0, 7);
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
    PostPageState(token, identifier, found->second);
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

bool BatoWorkspaceIsAnchor(CefRefPtr<CefBrowser> browser) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI) || !browser) return false;
  for (const auto& [token, slot] : WorkspaceSlots()) {
    if (slot.anchor && slot.anchor->IsSame(browser)) return true;
  }
  return false;
}

bool BatoWorkspaceChromeCommand(CefRefPtr<CefBrowser> browser, int command_id) {
  if (!g_workspace_enabled || !CefCurrentlyOn(TID_UI)) return false;
  int command = 0;
  if (command_id == cef_id_for_command_id_name("IDC_NEW_TAB")) command = 1;
  if (command_id == cef_id_for_command_id_name("IDC_CLOSE_TAB")) command = 2;
  if (!command || !browser || !browser->IsValid()) return false;
  for (const auto& [token, slot] : WorkspaceSlots()) {
    auto* available = AvailableSlot(token);
    if (!available) continue;
    auto peer = CurrentPeer(token, *available);
    if (!peer || !SameWindow(peer, browser) ||
        !browser->GetHost()->GetRequestContext()->IsSame(available->context)) continue;
    int identifier = browser->GetIdentifier();
    if (command == 2) {
      if (available->anchor && available->anchor->IsSame(browser)) {
        identifier = 0;  // Closing the blank placeholder never closes a Bato entry.
      } else if (!available->pages.contains(identifier)) {
        return false;  // Let Chrome close its own untracked tab.
      }
    }
    CefPostTask(TID_UI, base::BindOnce(
        [](uint64_t token, int command, int identifier) {
          if (WorkspaceSlots().contains(token))
            BatoSwiftWorkspaceCommand(token, command, identifier);
        }, token, command, identifier));
    return true;
  }
  return false;
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
  dlclose(loaded);  // CefScopedLibraryLoader retains framework until shutdown.
  if (!registration || !focus || !advance || !active_browser_id) {
    fprintf(stderr, "{\"event\":\"slot-client-abi-unavailable\"}\n");
    return false;
  }
  const auto directory = command_line->GetSwitchValue("bato-workspace-state").ToString();
  g_workspace_enabled = command_line->HasSwitch("bato-workspace-state");
  if (g_workspace_enabled) {
    if (directory.empty() || directory.front() != '/' || !new_tab || !native_focus ||
        !request_close || !register_pages ||
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
    g_new_tab = new_tab;
    g_request_close = request_close;
    BatoSwiftWorkspaceConfigure(directory.c_str(), CreateWorkspacePage,
                                 SelectWorkspacePage, CloseWorkspacePage,
                                 ActiveWorkspacePage, native_focus, WorkspaceCommandId);
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
