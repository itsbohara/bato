#ifndef BATO_SAMPLE_NATIVE_SLOT_CLIENT_H_
#define BATO_SAMPLE_NATIVE_SLOT_CLIENT_H_
#include <vector>
#include "include/cef_browser.h"
#include "include/cef_command_line.h"
// Called once after loading the matching framework, before CefInitialize.
bool BatoRegisterNativeSlotClient(CefRefPtr<CefCommandLine> command_line);
// All hooks run on the CEF UI thread. Strings are copied before deferred delivery.
bool BatoWorkspaceChromeCommand(CefRefPtr<CefBrowser> browser, int command_id);
bool BatoWorkspaceIsAnchor(CefRefPtr<CefBrowser> browser);
void BatoWorkspaceBrowserCreated(CefRefPtr<CefBrowser> browser);
void BatoWorkspaceBrowserAddressChanged(CefRefPtr<CefBrowser> browser,
                                        const CefString& url);
void BatoWorkspaceBrowserTitleChanged(CefRefPtr<CefBrowser> browser,
                                      const CefString& title);
void BatoWorkspaceBrowserFaviconChanged(CefRefPtr<CefBrowser> browser,
                                        const std::vector<CefString>& urls);
void BatoWorkspaceBrowserClosed(CefRefPtr<CefBrowser> browser);
// Peek client entry points for the Swift workspace. Main/CEF UI thread only.
// Present returns a nonzero engine generation, or 0 when refused. End takes
// that generation; restore_parent != 0 reactivates the parent. Parent and
// preview must both be bound workspace pages. See bato_native_slot.h.
extern "C" uint64_t BatoWorkspacePeekPresent(uint64_t token, int parent_browser_id,
                                              int preview_browser_id);
extern "C" int BatoWorkspacePeekEnd(uint64_t token, uint64_t generation, int restore_parent);
#endif
