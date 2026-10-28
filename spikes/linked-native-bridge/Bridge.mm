#import <Cocoa/Cocoa.h>
#include <map>
#include <set>
#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_id_mappers.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_closure_task.h"
#include "tests/cefsimple/simple_handler.h"

extern "C" void BatoSwiftAttach(void*, int, void (*)(int, int), int);
extern "C" void BatoSwiftDetach(int);
extern "C" void BatoSwiftFocus(int);
namespace {
std::map<int, CefRefPtr<CefBrowser>> browsers;
std::set<int> attached;
void Action(int identifier, int action);
bool Enabled() {
  return !CefCommandLine::GetGlobalCommandLine()->HasSwitch("bato-disable-bridge");
}
void TryAttach(int identifier, int attempts) {
  CEF_REQUIRE_UI_THREAD();
  auto found = browsers.find(identifier);
  if (found == browsers.end() || attached.count(identifier)) return;
  NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(found->second->GetHost()->GetWindowHandle());
  NSWindow* window = view.window;
  if (!window) {
    if (attempts > 0) {
      // Only the integer ID is captured. OnBeforeClose erases the owning ref;
      // pending retries then become no-ops and cannot retain a closed browser.
      CefPostDelayedTask(TID_UI, base::BindOnce(&TryAttach, identifier, attempts - 1), 50);
    } else {
      fprintf(stderr, "{\"event\":\"bridge-window-unavailable\"}\n");
    }
    return;
  }
  attached.insert(identifier);
  int reserved = CefCommandLine::GetGlobalCommandLine()->HasSwitch("bato-views-layout") ? 1 : 0;
  BatoSwiftAttach((__bridge void*)window, identifier, Action, reserved);
}
void Action(int identifier, int action) {
  CEF_REQUIRE_UI_THREAD();
  auto found = browsers.find(identifier);
  if (found == browsers.end()) return;
  auto host = found->second->GetHost();
  if (action == 1) host->SetFocus(true);
  if (action == 2) SimpleHandler::GetInstance()->CloseAllBrowsers(false);
  if (action == 3) {
    int command = cef_id_for_command_id_name("IDC_NEW_SPLIT_TAB");
    bool enabled = command >= 0 && host->CanExecuteChromeCommand(command);
    fprintf(stderr, "{\"event\":\"split-command\",\"enabled\":%s}\n", enabled ? "true" : "false");
    if (enabled) host->ExecuteChromeCommand(command, CEF_WOD_CURRENT_TAB);
  }
  if (action == 4) {
    const int command = cef_id_for_command_id_name("IDC_EXIT");
    const bool enabled = command >= 0 && host->CanExecuteChromeCommand(command);
    fprintf(stderr, "{\"event\":\"quit-application-command\",\"enabled\":%s}\n", enabled ? "true" : "false");
    if (enabled) {
      host->ExecuteChromeCommand(command, CEF_WOD_CURRENT_TAB);
      fprintf(stderr, "{\"event\":\"quit-application-command-dispatched\"}\n");
    }
  }
}
}

void BatoBridgeAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (!Enabled()) { fprintf(stderr, "{\"event\":\"bridge-disabled\"}\n"); return; }
  // Permission and extension popup windows keep their own Chrome UI geometry.
  if (browser->IsPopup()) return;
  int identifier = browser->GetIdentifier();
  browsers[identifier] = browser;
  TryAttach(identifier, 40);
}

void BatoBridgeBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (attached.erase(browser->GetIdentifier())) BatoSwiftDetach(browser->GetIdentifier());
  browsers.erase(browser->GetIdentifier());
  fprintf(stderr, "{\"event\":\"bridge-browser-released\",\"remainingBrowsers\":%zu}\n", browsers.size());
}

void BatoBridgeGotFocus(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  if (!Enabled()) return;
  TryAttach(browser->GetIdentifier(), 0);
  BatoSwiftFocus(browser->GetIdentifier());
}
