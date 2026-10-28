# Native reservation source-build experiment

**Reviewable patch sketch; not compiled or run.** It does not select CEF/fork ownership or establish native hosting/input. This directory changes no current engine or baseline sample.

## Concrete change

[`native-reservation.patch`](native-reservation.patch) changes one exact Chromium156 file: `chrome/browser/ui/views/frame/layout/browser_view_layout_delegate_impl.cc`, in `BrowserViewLayoutDelegateImpl::GetBrowserLayoutParams`, at its final return after converting frame parameters to local coordinates.

The proposed change stores the existing local parameters, then applies `BrowserLayoutParams::Inset(gfx::Insets::TLBR(44, 260, 0, 0))` only when all of these hold:

- macOS build;
- explicit `--bato-native-reservation` test switch;
- `TYPE_NORMAL` browser;
- normal or maximized window state.

All other paths return the existing parameters. Fullscreen/immersive behavior is deliberately left stock for this first experiment. Do not show test native surfaces in fullscreen on the assumption that reservation continues there.

This supplies the **same** reduced rectangle to the normal layout's consumers before layout computation; it does not set internal NSView frames after layout. It keeps the toolbar, tab strip, extension UI and `MultiContentsView` under Chromium ownership. It removes or reparents none of those children. Their correct resulting positions/anchors still require runtime verification; this patch is not a claim that every consumer respects the returned rectangle.

The44px top and260px left apply to the browser's visual client area, not a promised NSWindow frame origin. A future native host must receive verified rectangles and coordinate conversions. This patch provides no native view slot, callbacks, lifecycle contract, Swift input, accessibility, or production CEF API.

## Why this insertion point

The pinned [delegate implementation](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_layout_delegate_impl.cc) obtains frame layout parameters and converts them to BrowserView-local coordinates. The patch adjusts that result once per query, rather than changing only one page child or double-insetting the layout's subsequent recomputation.

[`BrowserLayoutParams::Inset`](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_layout_params.cc) reduces the rectangle, clamps negative dimensions to zero and updates the existing leading/trailing frame exclusion areas. It is preferable to manually changing rectangle fields and forgetting caption-control exclusions.

The shared [layout entry](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/chrome/browser/ui/views/frame/layout/browser_view_layout_impl.cc) queries this delegate before pre-layout and again when a separate top container changes geometry. This makes the delegate result a concrete candidate seam. Minimum-size calculations, background/frame painting, modal positioning and detached top containers remain reasons to reject or revise the sketch after a source build.

## Provenance and dry-run

Chromium tag `156.0.8078.48`, CEF revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`. [`sources-lock.json`](sources-lock.json) pins exact decoded SHA256 and byte counts for the target plus three supporting source files. The lock records source text hashes, not engine/archive authenticity.

Run from this repository:

```sh
python3 spikes/engine-reservation/check.py
```

The checker fetches only those four files from their exact tag URLs, checks their hashes, and runs `git apply --check` in a temporary source tree. It removes that temporary tree on completion. It creates no Git checkout, installs nothing and compiles nothing.

Coordinator/subagent verification: all four hashes matched and the unified diff passed its dry-run. No compile/link/runtime result follows from that check. No full upstream source is vendored here. The patch leaves upstream source notices intact; see [Chromium license](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/LICENSE) for the existing source's terms. Bato's MIT license does not replace upstream licensing.

## Next source-build experiment

Only after a separately provisioned matching CEF/Chromium build environment is available, apply this patch to its Chromium `src` root and build a matching CEF framework. Do not apply it to the current prebuilt framework or assume recompiling cefsimple changes the engine. No checkout or framework build has been performed or requested by this artifact.

Use the existing linked sample against that framework with a fresh disposable Profile, no extensions initially, and explicit test-only mock keychain. First compare switch absent/present with no Swift surfaces attached. Record actual BrowserView/client/toolbar/page rectangles on a large normal window, then resize and maximize. A correct gap with clipped controls is a failure.

Next create a native split with two controlled origins and test focus indication, divider resize and popup/permission anchors while retaining Chrome's toolbar/security UI. Add real extension popup checks only after the basic geometry is correct. Test fullscreen separately: reservation must turn off and restore consistently. Do not infer restored minimum-window sizes, crash recovery or Profile persistence from these checks.

Only afterward test app-owned native controls in the reserved region, with explicit window callbacks, coordinate conversion, accessibility and native-to-page focus. The current separate companion is not proof of an in-window host.

If any required child/anchor bypasses these parameters, stop and enumerate that owner before broadening the patch. Do not fix it with compositor reparenting, private NSView traversal, or an overlay covering origin/security UI. See [engine seam alternatives](../native-composition/ENGINE-SEAM.md) for the wider decision.
