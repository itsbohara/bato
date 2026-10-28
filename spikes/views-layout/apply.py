#!/usr/bin/env python3
"""Reserve test geometry using only public CEF Views layout APIs.

Pass a disposable staged CEF source root, never the shared baseline source.
Apply after the linked bridge's sample patch. No engine changes are made.
"""
from pathlib import Path
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("staged_cef_root", type=Path)
args = parser.parse_args()
root = args.staged_cef_root.resolve()
if root.name == "cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_macosarm64":
    parser.error("Refusing shared official distribution; pass a disposable staged copy")
path = root / "tests/cefsimple/simple_app.cc"
source = path.read_text()
marker = "// BATO_VIEWS_RESERVED_LAYOUT"
if marker in source:
    print("Views reservation already applied")
    raise SystemExit(0)
anchor = "    window->AddChildView(browser_view_);"
if source.count(anchor) != 1:
    parser.error("Expected exactly one stock SimpleWindowDelegate child insertion")
source = source.replace('#include <string>', '#include <string>\n#include <cstdio>')
source = source.replace('#include "include/views/cef_browser_view.h"', '#include "include/views/cef_browser_view.h"\n#include "include/views/cef_box_layout.h"')
source = source.replace(anchor, '''    // BATO_VIEWS_RESERVED_LAYOUT: reserve native surfaces without changing
    // Chromium's NSView hierarchy. Layout owns BrowserView size on resize.
    const bool reserve = CefCommandLine::GetGlobalCommandLine()->HasSwitch(
        "bato-views-layout");
    if (reserve) {
      CefBoxLayoutSettings settings;
      settings.horizontal = false;
      settings.inside_border_insets = CefInsets(44, 260, 0, 0);
      settings.cross_axis_alignment = CEF_AXIS_ALIGNMENT_STRETCH;
      auto layout = window->SetToBoxLayout(settings);
      window->AddChildView(browser_view_);
      layout->SetFlexForView(browser_view_, 1);
    } else {
      window->AddChildView(browser_view_);
    }''')
show_anchor = "      window->Show();\n    }\n  }"
if source.count(show_anchor) != 1:
    parser.error("Expected one SimpleWindowDelegate Show boundary")
source = source.replace(show_anchor, """      window->Show();
    }
    if (reserve) {
      // Show establishes native size. Explicit public Layout resolves bounds
      // before the first frame instead of relying on a later resize.
      window->Layout();
      LogReservedBounds("created");
    }
  }

  void OnLayoutChanged(CefRefPtr<CefView> view,
                       const CefRect& bounds) override {
    if (CefCommandLine::GetGlobalCommandLine()->HasSwitch("bato-views-layout")) {
      LogReservedBounds("layout");
    }
  }

  void LogReservedBounds(const char* phase) {
    if (!browser_view_ || !browser_view_->IsValid()) return;
    const auto local = browser_view_->GetBounds();
    const auto screen = browser_view_->GetBoundsInScreen();
    fprintf(stderr,
            "{\\\"event\\\":\\\"cef-reserved-bounds\\\",\\\"phase\\\":\\\"%s\\\","
            "\\\"local\\\":[%d,%d,%d,%d],\\\"screen\\\":[%d,%d,%d,%d]}\\n",
            phase, local.x, local.y, local.width, local.height,
            screen.x, screen.y, screen.width, screen.height);
  }""")
path.write_text(source)
print("Applied public Views layout reservation (opt in: --bato-views-layout)")
