#!/usr/bin/env python3
"""Create an isolated, reproducible sample overlay; never edit baseline source."""
from pathlib import Path
import shutil
import subprocess
import os

HERE = Path(__file__).resolve().parent
VERSION = '156.0.14+g4fa4ab5+chromium-156.0.8078.48'
BASE = Path.home() / f'.cache/bato/cef-baseline/cef_binary_{VERSION}_macosarm64'
OUT = Path.home() / '.cache/bato/linked-native-bridge'
SOURCE = OUT / 'source'


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise SystemExit(f'Pinned source shape changed: {before[:80]!r}')
    return text.replace(before, after)


def write_changed(path, text):
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


if not BASE.is_dir():
    raise SystemExit('Pinned standard distribution missing; run baseline prepare first')
SOURCE.mkdir(parents=True, exist_ok=True)
for item in BASE.iterdir():
    if item.name != 'tests' and not (SOURCE / item.name).exists():
        (SOURCE / item.name).symlink_to(item, target_is_directory=item.is_dir())
(SOURCE / 'tests').mkdir(exist_ok=True)
for item in (BASE / 'tests').iterdir():
    if item.name != 'cefsimple' and not (SOURCE / 'tests' / item.name).exists():
        (SOURCE / 'tests' / item.name).symlink_to(item, target_is_directory=item.is_dir())
sample = SOURCE / 'tests/cefsimple'
sample.mkdir(exist_ok=True)
for item in (BASE / 'tests/cefsimple').iterdir():
    destination = sample / item.name
    if item.is_dir():
        shutil.copytree(item, destination, dirs_exist_ok=True)
    else:
        write_changed(destination, item.read_text())

if os.environ.get('BATO_STOCK_SAMPLE') == 'ON':
    print(f'Stock sample isolation (existing baseline Profile patch preserved): {SOURCE}')
    raise SystemExit(0)

path = sample / 'simple_handler.cc'
text = path.read_text()
text = replace_once(text, '#include <sstream>', '#include <cstdio>\n#include <sstream>')
text = replace_once(text, 'namespace {\n', '''#if defined(OS_MAC) && defined(BATO_LINK_NATIVE_BRIDGE)
void BatoBridgeAfterCreated(CefRefPtr<CefBrowser> browser);
void BatoBridgeBeforeClose(CefRefPtr<CefBrowser> browser);
void BatoBridgeGotFocus(CefRefPtr<CefBrowser> browser);
#endif

namespace {
''')
text = replace_once(text, '  browser_list_.push_back(browser);', '''  browser_list_.push_back(browser);
  fprintf(stderr, "{\\"event\\":\\"sample-browser-count\\",\\"phase\\":\\"created\\",\\"count\\":%zu}\\n", browser_list_.size());
#if defined(OS_MAC) && defined(BATO_LINK_NATIVE_BRIDGE)
  BatoBridgeAfterCreated(browser);
#endif''')
text = replace_once(text, '  // Remove from the list of existing browsers.', '''#if defined(OS_MAC) && defined(BATO_LINK_NATIVE_BRIDGE)
  BatoBridgeBeforeClose(browser);
#endif
  // Remove from the list of existing browsers.''')
text = replace_once(text, '  if (browser_list_.empty()) {\n    // All browser windows have closed.', '''  fprintf(stderr, "{\\"event\\":\\"sample-browser-count\\",\\"phase\\":\\"closed\\",\\"count\\":%zu}\\n", browser_list_.size());
  if (browser_list_.empty()) {
    // All browser windows have closed.''')
text = replace_once(text, '    CefQuitMessageLoop();', '''    fprintf(stderr, "{\\"event\\":\\"sample-quit-message-loop-requested\\"}\\n");
    CefQuitMessageLoop();
    fprintf(stderr, "{\\"event\\":\\"sample-quit-message-loop-returned\\"}\\n");''')
write_changed(path, text)

path = sample / 'simple_handler.h'
text = path.read_text()
text = replace_once(text, '#include "include/cef_client.h"', '#include "include/cef_client.h"\n#include "include/cef_command_line.h"')
text = replace_once(text, 'public CefLoadHandler {', 'public CefLoadHandler, public CefFocusHandler {')
text = replace_once(text, '  // CefDisplayHandler methods:', '''  CefRefPtr<CefFocusHandler> GetFocusHandler() override {
#if !defined(BATO_LINK_NATIVE_BRIDGE)
    return nullptr;
#else
    if (CefCommandLine::GetGlobalCommandLine()->HasSwitch("bato-disable-bridge")) return nullptr;
    return this;
#endif
  }
  void OnGotFocus(CefRefPtr<CefBrowser> browser) override;

  // CefDisplayHandler methods:''')
write_changed(path, text)

path = sample / 'simple_handler.cc'
text = path.read_text()
text += '''
void SimpleHandler::OnGotFocus(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
#if defined(OS_MAC) && defined(BATO_LINK_NATIVE_BRIDGE)
  BatoBridgeGotFocus(browser);
#endif
}
'''
write_changed(path, text)

path = sample / 'cefsimple_mac.mm'
text = path.read_text()
text = replace_once(text, '''  SimpleAppDelegate* delegate =
      static_cast<SimpleAppDelegate*>([NSApp delegate]);
  [delegate tryToTerminateApplication:self];''', '''  // Bato sample-only: native Chrome can replace NSApp.delegate with its
  // AppController, which does not implement the sample delegate selector.
  // Route through the known CEF handler rather than messaging an unchecked
  // delegate type. Never call super: NSApplication's default exits directly.
  SimpleHandler* handler = SimpleHandler::GetInstance();
  fprintf(stderr, "{\\"event\\":\\"sample-terminate-requested\\",\\"handlerAvailable\\":%s}\\n", handler ? "true" : "false");
  if (handler && !handler->IsClosing()) {
    handler->CloseAllBrowsers(false);
  }''')
text = replace_once(text, '    CefSettings settings;\n', '''    if (command_line->HasSwitch("bato-views-layout") && command_line->HasSwitch("use-native")) {
      fprintf(stderr, "Views reservation requires the Views host; remove --use-native\\n");
      return 1;
    }
    CefSettings settings;
''')
if 'Bato experiment: never use an implicit/default browser profile.' not in text:
    text = replace_once(text, '    CefSettings settings;\n', '''    CefSettings settings;
    if (!command_line->HasSwitch("cache-path")) return 1;
    const CefString cache_path = command_line->GetSwitchValue("cache-path");
    CefString(&settings.root_cache_path) = cache_path;
    CefString(&settings.cache_path) = cache_path;
''')
text = replace_once(text, '    CefRunMessageLoop();', '''    CefRunMessageLoop();
    fprintf(stderr, "{\\"event\\":\\"cef-message-loop-exited\\"}\\n");''')
text = replace_once(text, '    CefShutdown();', '''    CefShutdown();
    fprintf(stderr, "{\\"event\\":\\"cef-shutdown-complete\\"}\\n");''')
write_changed(path, text)

path = sample / 'CMakeLists.txt'
text = path.read_text()
text += f'''
# Bato linked-only browser-process bridge. Helpers remain upstream.
option(BATO_LINK_NATIVE_BRIDGE "Link the explicit Swift bridge" ON)
if(OS_MAC AND BATO_LINK_NATIVE_BRIDGE)
  target_compile_definitions(cefsimple PRIVATE BATO_LINK_NATIVE_BRIDGE=1)
  target_sources(cefsimple PRIVATE "{HERE / 'Bridge.mm'}" "{OUT / 'NativeBridge.o'}")
  target_link_directories(cefsimple PRIVATE "${{BATO_SWIFT_LIBRARY_DIR}}")
  target_link_options(cefsimple PRIVATE "-Wl,-rpath,/usr/lib/swift")
endif()
'''
write_changed(path, text)
print(SOURCE)
subprocess.run(['python3', str(HERE.parent / 'views-layout/apply.py'), str(SOURCE)], check=True)
