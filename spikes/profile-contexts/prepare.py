#!/usr/bin/env python3
"""Stage only a small sample; the pinned prebuilt engine remains unchanged."""
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
VERSION = '156.0.14+g4fa4ab5+chromium-156.0.8078.48'
BASE = Path.home() / f'.cache/bato/cef-baseline/cef_binary_{VERSION}_macosarm64'
CACHE = Path.home() / '.cache/bato/profile-contexts'
SOURCE = CACHE / 'source'


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise SystemExit('Pinned sample shape changed: ' + before[:70])
    return source.replace(before, after)


def write_changed(path, content):
    if not path.exists() or path.read_text() != content:
        path.write_text(content)


if not BASE.is_dir():
    raise SystemExit('Pinned standard distribution missing; prepare baseline first')
SOURCE.mkdir(parents=True, exist_ok=True)
for entry in BASE.iterdir():
    if entry.name != 'tests' and not (SOURCE / entry.name).exists():
        (SOURCE / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
(SOURCE / 'tests').mkdir(exist_ok=True)
for entry in (BASE / 'tests').iterdir():
    if entry.name != 'cefsimple' and not (SOURCE / 'tests' / entry.name).exists():
        (SOURCE / 'tests' / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
sample = SOURCE / 'tests/cefsimple'
sample.mkdir(exist_ok=True)
for entry in (BASE / 'tests/cefsimple').iterdir():
    target = sample / entry.name
    if entry.is_dir():
        shutil.copytree(entry, target, dirs_exist_ok=True)
    else:
        write_changed(target, entry.read_text())

path = sample / 'simple_app.cc'
source = path.read_text()
source = replace_once(source, '#include <string>',
                      f'#include <string>\n#include "{HERE / "ContextProbe.h"}"')
start = source.index('void SimpleApp::OnContextInitialized() {')
end = source.index('\nCefRefPtr<CefClient> SimpleApp::GetDefaultClient()', start)
source = source[:start] + '''void SimpleApp::OnContextInitialized() {
  CEF_REQUIRE_UI_THREAD();
  CefRefPtr<SimpleHandler> handler(new SimpleHandler(false));
  BatoCreateContextBrowsers(handler);
}
''' + source[end:]
write_changed(path, source)

path = sample / 'simple_handler.cc'
source = path.read_text()
source = replace_once(source, 'namespace {\n',
                      f'#include "{HERE / "ContextProbe.h"}"\n\nnamespace {{\n')
source = replace_once(source, '  browser_list_.push_back(browser);',
                      '  browser_list_.push_back(browser);\n  BatoContextBrowserCreated(browser);')
source = replace_once(source, '  // Remove from the list of existing browsers.',
                      '  BatoContextBrowserClosing(browser);\n\n  // Remove from the list of existing browsers.')
write_changed(path, source)

path = sample / 'cefsimple_mac.mm'
source = path.read_text()
for required in ['CefString(&settings.root_cache_path) = cache_path;',
                 'CefString(&settings.cache_path) = cache_path;']:
    if required not in source:
        raise SystemExit('Baseline explicit Profile mapping missing; build baseline cefsimple first')
before = '''  SimpleAppDelegate* delegate =
      static_cast<SimpleAppDelegate*>([NSApp delegate]);
  [delegate tryToTerminateApplication:self];'''
source = replace_once(source, before, '''  // Chrome native mode may replace NSApp.delegate with AppController.
  // Use our explicit sample client instead of assuming the delegate's class.
  SimpleHandler* handler = SimpleHandler::GetInstance();
  if (handler && !handler->IsClosing()) handler->CloseAllBrowsers(false);''')
source = replace_once(source, '    CefSettings settings;', '''    if (!command_line->HasSwitch("use-native") ||
        !command_line->HasSwitch("use-mock-keychain") ||
        command_line->HasSwitch("use-alloy-style") ||
        command_line->HasSwitch("load-extension")) {
      fprintf(stderr, "Context diagnostic requires native Chrome + mock Keychain, no extensions\\n");
      return 1;
    }
    const std::string expected_root = std::string([NSHomeDirectory() UTF8String]) +
        "/.cache/bato/profile-contexts/profiles";
    if (command_line->GetSwitchValue("cache-path").ToString() != expected_root) {
      fprintf(stderr, "Context diagnostic requires its dedicated disposable cache root\\n");
      return 1;
    }
    CefSettings settings;''')
source = replace_once(source, '    CefRunMessageLoop();', '''    CefRunMessageLoop();
    fprintf(stderr, "{\\"event\\":\\"cef-message-loop-exited\\"}\\n");''')
source = replace_once(source, '    CefShutdown();', '''    CefShutdown();
    fprintf(stderr, "{\\"event\\":\\"cef-shutdown-complete\\"}\\n");''')
write_changed(path, source)

path = sample / 'CMakeLists.txt'
source = path.read_text() + f'\n# Bato request-context sample only; no engine changes.\ntarget_sources(cefsimple PRIVATE "{HERE / "ContextProbe.cc"}")\n'
write_changed(path, source)
print('Staged dedicated request-context sample:', SOURCE)
