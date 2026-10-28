#include "ContextProbe.h"

#include <cstdio>
#include <map>
#include <string>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"
#include "include/wrapper/cef_helpers.h"

namespace {

// Fixed diagnostic labels only. This handler owns no context/browser/client refs.
class ProbeContextHandler : public CefRequestContextHandler {
 public:
  explicit ProbeContextHandler(const char* label) : label_(label) {}
  const std::string& label() const { return label_; }

  void OnRequestContextInitialized(
      CefRefPtr<CefRequestContext> context) override {
    CEF_REQUIRE_UI_THREAD();
    fprintf(stderr,
            "{\"event\":\"context-ready\",\"label\":\"%s\",\"global\":%s}\n",
            label_.c_str(), context->IsGlobal() ? "true" : "false");
  }

 private:
  const std::string label_;
  IMPLEMENT_REFCOUNTING(ProbeContextHandler);
};

// IDs never persist; there are no global owning CEF references at shutdown.
std::map<std::string, int> browser_ids;
bool compared = false;

const char* Bool(bool value) { return value ? "true" : "false"; }

void CompareContexts() {
  if (compared || browser_ids.size() != 3) return;
  auto a1_browser = CefBrowserHost::GetBrowserByIdentifier(browser_ids.at("A1"));
  auto a2_browser = CefBrowserHost::GetBrowserByIdentifier(browser_ids.at("A2"));
  auto b_browser = CefBrowserHost::GetBrowserByIdentifier(browser_ids.at("B"));
  if (!a1_browser || !a2_browser || !b_browser) return;
  auto a1 = a1_browser->GetHost()->GetRequestContext();
  auto a2 = a2_browser->GetHost()->GetRequestContext();
  auto b = b_browser->GetHost()->GetRequestContext();
  const bool distinct = !a1->IsSame(a2);
  const bool shares = a1->IsSharingWith(a2) && a2->IsSharingWith(a1);
  const bool isolated = !a1->IsSharingWith(b) && !a2->IsSharingWith(b) &&
                        !b->IsSharingWith(a1) && !b->IsSharingWith(a2);
  fprintf(stderr,
          "{\"event\":\"context-relationships\",\"phase\":\"browsers-created\","
          "\"a1_a2_distinct\":%s,\"a1_a2_shared\":%s,\"b_isolated\":%s,"
          "\"matches_expected\":%s}\n",
          Bool(distinct), Bool(shares), Bool(isolated),
          Bool(distinct && shares && isolated));
  compared = true;
}

}  // namespace

void BatoCreateContextBrowsers(CefRefPtr<CefClient> client) {
  CEF_REQUIRE_UI_THREAD();
  const auto root = CefCommandLine::GetGlobalCommandLine()
                        ->GetSwitchValue("cache-path").ToString();
  CefRequestContextSettings a_settings;
  CefString(&a_settings.cache_path) = root + "/profile-a";
  CefRequestContextSettings b_settings;
  CefString(&b_settings.cache_path) = root + "/profile-b";

  auto a1 = CefRequestContext::CreateContext(a_settings,
                                           new ProbeContextHandler("A1"));
  auto a2 = CefRequestContext::CreateContext(a1, new ProbeContextHandler("A2"));
  auto b = CefRequestContext::CreateContext(b_settings,
                                          new ProbeContextHandler("B"));
  const std::pair<const char*, CefRefPtr<CefRequestContext>> entries[] = {
      {"A1", a1}, {"A2", a2}, {"B", b}};
  for (const auto& [label, context] : entries) {
    CefWindowInfo window;
    window.runtime_style = CEF_RUNTIME_STYLE_CHROME;
    CefBrowserSettings settings;
    const std::string url =
        std::string("http://127.0.0.1:18765/storage.html?label=") + label;
    const bool accepted = context && CefBrowserHost::CreateBrowser(
        window, client, url, settings, nullptr, context);
    fprintf(stderr,
            "{\"event\":\"context-browser-request\",\"label\":\"%s\","
            "\"accepted\":%s}\n", label, Bool(accepted));
  }
}

void BatoContextBrowserCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  const auto context = browser->GetHost()->GetRequestContext();
  const auto handler = context->GetHandler();
  // Every non-null handler in this isolated sample is our own fixed-label type.
  // The global/default context has no handler and is not part of this matrix.
  const auto* probe = handler ? static_cast<ProbeContextHandler*>(handler.get())
                              : nullptr;
  const std::string label = probe ? probe->label() : "global";
  if (label == "A1" || label == "A2" || label == "B") {
    browser_ids.emplace(label, browser->GetIdentifier());
  }
  fprintf(stderr,
          "{\"event\":\"context-browser-created\",\"label\":\"%s\","
          "\"browser_id\":%d,\"global\":%s}\n",
          label.c_str(), browser->GetIdentifier(), Bool(context->IsGlobal()));
  CompareContexts();
}

void BatoContextBrowserClosing(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  for (auto it = browser_ids.begin(); it != browser_ids.end();) {
    if (it->second == browser->GetIdentifier()) it = browser_ids.erase(it);
    else ++it;
  }
  fprintf(stderr,
          "{\"event\":\"context-browser-closing\",\"browser_id\":%d,"
          "\"tracked_remaining\":%zu}\n",
          browser->GetIdentifier(), browser_ids.size());
}
