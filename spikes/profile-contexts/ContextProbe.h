#ifndef BATO_CONTEXT_PROBE_H_
#define BATO_CONTEXT_PROBE_H_

#include "include/cef_client.h"

void BatoCreateContextBrowsers(CefRefPtr<CefClient> client);
void BatoContextBrowserCreated(CefRefPtr<CefBrowser> browser);
void BatoContextBrowserClosing(CefRefPtr<CefBrowser> browser);

#endif
