# Source-built sample runtime handoff

The guarded ARM64 component engine build completed successfully in5h38m14s. The read-only checker then resolved523 ARM64 images in the completed output tree and produced the control launch preview. These are build and artifact-inspection results; no source-built browser runtime, layout or native Swift hosting acceptance follows. This handoff supplies a **launch preview**, with no execution option.

After the guarded build finishes, run:

```sh
python3 spikes/engine-build/runtime.py
python3 spikes/engine-build/runtime.py --reservation
```

The first command previews stock control mode; the second adds only `--bato-native-reservation`. Each uses its own fixed fresh mock-Keychain Profile under the authorized SSD `runtime/profiles/` namespace. The checker creates no Profile, writes no workspace files and launches no process. It accepts no arbitrary paths, URLs, browser switches or debugging listener flags. JSON contains argument arrays and a working directory for the coordinator to review, not shell text to execute blindly.

The checker refuses an active workspace lock or a run-state record other than a completed successful exact `autoninja ... cefsimple` build. It then checks existing workspace/checkout/tooling/source pins through `engine.py`, the applied reservation patch, the sample guard hash and exact generated ARM64 Debug/component settings. It checks the main executable, bundled framework, four helper variants and their non-system Mach-O dependency closure with `otool` and `lipo`, retaining the component output tree in place. Weak non-system loads are checked conservatively too; a missing weak dependency is a review point. This is a loader-path sanity check, not code signing or runtime acceptance. The checker opens each image read-only and passes its descriptor to `otool` through `/dev/fd/N`; this avoids Xcode classic otool treating helper names such as `cefsimple Helper (Renderer)` as archive-member syntax. The installed `llvm-otool` alias delegates to that same classic tool on this host. Dependency paths are still resolved using the original image location, and descriptors close on success or failure. No image is copied or changed. Runtime-loaded images inherit their executable's runpaths, and each distinct loader context is resolved separately. Read-only Mach-O metadata and architecture results are cached per image within one check to avoid repeated tool invocations across helper contexts.

The actual pinned macOS GN definitions in `cef/BUILD.gn` bundle `libcef_sandbox.dylib`, `libvk_swiftshader.dylib` and `libvulkan.dylib`. ANGLE defaults to static in `ui/gl/features.gni`; separate `libEGL.dylib` and `libGLESv2.dylib` are required only if the generated build graph selects CEF's conditional ANGLE bundle target. The framework's component rpath points six levels back to the root output directory. Do not copy this framework into a prebuilt distribution or move the app away from its component dylibs.

The fixed initial URL is the synthetic fixture `http://127.0.0.1:18765/login.html`. The coordinator must verify that the owned fixture server is still serving it, that the Mac is unlocked, and that no other owned sample browser is running before manually launching. Keep mock Keychain enabled for every launch of any Profile created with it. This first handoff deliberately refuses nonempty existing Profiles because it has no trusted provider-history journal; later restart tests need an explicit reviewed extension to that policy. Never delete Profile data simply to satisfy the checker.

## First runtime acceptance

1. Run the control case without native surfaces or extensions. Verify page rendering, visible ordinary toolbar/origin UI, and clean close/process exit.
2. Run the reservation case with its separate fresh mock Profile. At a large normal window, verify the expected260px left/44px top space and unclipped toolbar/page. Compare actual rectangles; an empty gap alone is insufficient.
3. Resize, maximize and test minimum sizes. Exact source can fall back to full host bounds when insetting produces an empty rectangle. Record that case rather than claiming universal reservation.
4. Enter/exit fullscreen. Reservation is intentionally disabled there; confirm stock geometry and restoration on return.
5. Only after basic geometry passes, exercise the native split, divider, focus indication and popup/permission anchors. Real extension checks and app-owned Swift input/accessibility remain later gates.
6. Record failures separately from later successes. Verify completed shutdown and absence of the owned process; a close request alone is not completion.

Tests use synthetic temporary trees and mocked Mach-O metadata. They check refusal of active/failed/wrong-stage builds, GN comments/duplicate settings, dependency resolution/escape, architecture, fresh Profile policy, fixed flags and absence of launch/write effects. They do not compile or run Chromium.
