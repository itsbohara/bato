#ifndef BATO_SAMPLE_NATIVE_SLOT_CLIENT_H_
#define BATO_SAMPLE_NATIVE_SLOT_CLIENT_H_
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
void BatoWorkspaceBrowserClosed(CefRefPtr<CefBrowser> browser);
#endif
