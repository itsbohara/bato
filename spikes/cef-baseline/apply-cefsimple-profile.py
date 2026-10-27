#!/usr/bin/env python3
"""Apply the bounded profile-path plumbing patch to the pinned upstream sample.

Upstream sample copyright belongs to the Chromium Embedded Framework Authors
and Chromium Authors. The adjacent CEF-LICENSE.txt applies to upstream code.
This patch does not modify CEF itself.
"""
from pathlib import Path

version = '156.0.14+g4fa4ab5+chromium-156.0.8078.48'
source = Path.home() / f'.cache/bato/cef-baseline/cef_binary_{version}_macosarm64/tests/cefsimple/cefsimple_mac.mm'
text = source.read_text()
marker = '    // Bato experiment: never use an implicit/default browser profile.\n'
if marker not in text:
    before = '    CefSettings settings;\n'
    after = before + '''
    // Bato experiment: never use an implicit/default browser profile.
    if (!command_line->HasSwitch("cache-path")) {
      NSLog(@"Bato cefsimple requires an explicit disposable --cache-path");
      return 1;
    }
    const CefString cache_path = command_line->GetSwitchValue("cache-path");
    CefString(&settings.root_cache_path) = cache_path;
    CefString(&settings.cache_path) = cache_path;
    NSLog(@"Bato disposable CEF Profile: %s", cache_path.ToString().c_str());
'''
    if text.count(before) != 1:
        raise SystemExit('Pinned sample shape changed; refuse to patch')
    source.write_text(text.replace(before, after))
    print('Applied explicit disposable Profile mapping to cefsimple sample')
else:
    print('Profile mapping patch already present')
