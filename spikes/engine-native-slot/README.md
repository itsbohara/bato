# Registered native slot source experiment

Prepared against CEF `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f` and Chromium `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`. This bounded experiment follows the [native-slot plan](../native-composition/NATIVE-SLOT-PLAN.md). Compilation and bounded native input/focus/lifecycle acceptance now pass; read [results and remaining limits](RESULTS.md).

## Boundary and ownership

[`bato_native_slot.h`](bato_native_slot.h) is a new, explicitly versioned **experiment ABI**, not an existing upstream CEF API. The engine patch installs it at `cef/include/internal/bato_native_slot.h`. Register once, on the main thread before `CefInitialize`, using the loaded framework's specifically named exports. Registration refuses missing callbacks, wrong size/version, repeated calls and initialized CEF. No website endpoint or private-symbol discovery is introduced.

The sample supplies a newly allocated, unparented `NSView` and a callback identifying a focusable child. The engine retains a new adapter containing that view; the sample may keep its own reference until `detached`. Tokens are process-local generation numbers per attempted window slot, never browser IDs or persistent state. Focus exports accept only a live, visible, unblocked token. They target the known active WebContents or explicitly advance the Views FocusManager from the slot host. No browser native view is inspected, migrated or reparented.

The engine owns a standard `views::NativeViewHost` child of the existing normal `BrowserView`. Its newly allocated AppKit wrapper conforms to `ViewsHostable` and owns the adapter's root. The existing NativeViewHostMac attachment path registers hit testing and accessibility. The adapter reports a native accessible group with its recorded Views parent, converts authoritative widget coordinates to AppKit coordinates and removes its own root/parent link on detach. The client field remains normal AppKit UI.

The callback enters through the existing internal `cef::BrowserDelegate` virtual boundary. Chromium's UI component never directly links to a new libcef function. Normal BrowserView layout, blocking changes, fullscreen preparation and widget teardown notify that delegate. The CEF implementation and export storage live in an already compiled Objective-C++ source, avoiding duplicate component registration storage or GN source additions.

## Geometry, lifecycle and refusal

Both `--bato-native-slot` and `--bato-native-reservation` are required. The left region comes from the same original visual-client rectangle used by the reservation inset:260 points wide, below the44-point top margin. It does not infer geometry from a private NSView tree. Native minimum size includes these margins. Chrome retains ownership of toolbar, origin UI, tabs, split content and extension anchors.

Only normal local Chrome windows with a matching registered factory can attach. Views-hosted, popup/DevTools and remote-Cocoa application topologies are refused. An invalid or already parented factory view is refused. One attempt per window prevents repeated factory calls during layout; extra tabs and split members share their existing window's slot.

The slot hides in fullscreen and during will-enter/will-exit transitions. Final transition notifications invalidate normal layout so geometry is recalculated before restoration. Browser tab-blocked updates refresh the slot; every native hit and exported focus request also checks the current tab/web-modal state and AppKit modal/sheet state. This source policy still requires real modal acceptance.

Widget teardown hides and detaches the host before deleting browser WebContents. A destructor fallback handles an early window failure. Observers are removed, the host child is destroyed, accessibility parent cleared and the token erased before the client detach callback. Generation checks also handle a factory callback that invalidates its window. Client callbacks must not return a child which they already destroyed.

## Provenance and checking

[`engine.patch`](engine.patch) applies from the Chromium source root; embedded CEF paths include `cef/`. Its [manifest](manifest.json) pins every original and final file hash. Existing before hashes include the current reservation and Quit V3 changes. The new header uses `original_sha256: null`, requiring absence before application. This overlay must not overwrite unknown source or replace the successful base checkout marker.

```sh
python3 spikes/engine-native-slot/check.py
python3 -m unittest discover -s spikes/engine-native-slot -p 'test_*.py'
```

The checker is read-only. Two tests exercise tampered artifact refusal and actual forward/reverse application in temporary copies, including new-file absence and partial-state refusal. The coordinating pipeline checks both engine and client overlays before source mutation and verifies all resulting hashes before compilation. Never rerun upstream checkout/configure over local patches.

## Required runtime acceptance

Use only dedicated synthetic mock-Keychain Profiles. Verify one slot per window; actual native AX button/field and frame; real click counter and field editing; Tab/Shift-Tab and browser focus return; modal blocking; resize/zoom/minimum/fullscreen; native split/divider and extension anchors; multiwindow tab moves; detach once and actual CEF shutdown. Stop and record any failed prerequisite. A visible root, successful compile or synthetic programmatic click does not establish native input or the production foundation.

## Guarded overlay commands

From the application repository, use the dedicated runner after Quit V3 and the reservation/helper guards are present:

```sh
python3 spikes/engine-build/native_slot.py check
python3 spikes/engine-build/native_slot.py patch --execute
python3 spikes/engine-build/native_slot.py build --execute
python3 spikes/engine-build/native_slot.py artifacts
```

Both engine and client patches apply from Chromium src. The runner verifies source pins and all preserved Quit/helper/reservation guard hashes, refuses conflicting new files or mixed states, checks both patches before writing either, and uses the existing SSD lock, reserve guard and two-job build. It never runs checkout/configure. The original engine.py build/runtime preview correctly refuses the changed overlay; use this runner while it is applied. Existing mock Profiles must keep the same provider on restart.

The client build adds one contained Swift library in the sample app's Frameworks folder. The pinned Mac toolchain lacks a Swift tool, so a scoped GN action invokes Xcode's compiler into the dedicated SSD output. Framework registration uses RTLD_NOLOAD on the exact already-loaded framework and only the three authored ABI symbols. No extra framework is loaded and no private symbol is guessed.
