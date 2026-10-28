# Request-context sharing experiment

This is a **prebuilt-engine sample experiment**, not Bato's Profile/workspace implementation. It uses the existing official CEF `156.0.14+g4fa4ab5+chromium-156.0.8078.48` arm64 distribution. No Chromium checkout or engine build is required.

## Public API under test

The pinned [`CefRequestContext`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/cef_request_context.h) exposes two creation forms:

- `CreateContext(settings, handler)` requests a storage context at an explicit cache path.
- `CreateContext(other, handler)` creates another context object sharing the first context's storage.

`IsSame` reports context identity; `IsSharingWith` reports shared storage. The experiment requests three native Chrome windows:

| Label | Requested context | Dedicated cache |
| --- | --- | --- |
| A1 | New context with explicit settings | `profiles/profile-a` |
| A2 | New context sharing A1 | A1 storage |
| B | New isolated context with explicit settings | `profiles/profile-b` |

All paths are below `~/.cache/bato/profile-contexts/`; the installation/global cache root is its `profiles/` directory. The pinned [`CefRequestContextSettings.cache_path`](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/internal/cef_types.h) requires equal/child paths under `CefSettings.root_cache_path`. The global Profile is not one of the three test windows.

After all three browsers exist, the diagnostic compares the **actual contexts returned by their hosts**, rather than treating requested paths as runtime evidence. Its expected matrix is distinct A1/A2 context identities, shared A1/A2 storage, and B sharing with neither. A JSON `context-relationships` event reports every boolean and `matches_expected`. No runtime pass follows from the source or compilation alone.

## Build

```sh
sh spikes/profile-contexts/build.sh
```

The preparer copies only the small cefsimple sample into a separate cache source tree and symlinks unchanged distribution files. It requires the baseline sample's explicit root/global Profile mapping and fails closed if that patch is absent; build baseline cefsimple first when preparing a fresh cache. It adds `ContextProbe.cc` to that sample; the baseline and linked-native-bridge source/build are untouched. The build compiles the CEF wrapper and sample against the existing prebuilt framework, with sandbox support on. Sample code retains the upstream [CEF license](../cef-baseline/CEF-LICENSE.txt).

The macOS sample termination override calls its explicit `SimpleHandler` directly. It does not assume the current `NSApp.delegate` remains `SimpleAppDelegate`: native Chrome can replace it with `AppController`. This sample correction does not replace Chrome's delegate or force process exit. Engine message-loop return and completed `CefShutdown` have separate diagnostic events.

## Coordinator launch and UI acceptance

Close other owned cefsimple experiments before launching. Never rebuild a running executable. The fixture server must serve `http://127.0.0.1:18765/storage.html` (see [fixtures](../fixtures/README.md)). Then:

```sh
python3 spikes/profile-contexts/run.py
```

The launcher has no arbitrary Profile/URL input and enables no debug listener. The main executable refuses a different cache root, Alloy/Views mode, extensions, or absence of the mock-Keychain flag. This experiment is intentionally limited to synthetic pages and storage. Three windows use `?label=A1`, `?label=A2`, and `?label=B`; the storage fixture renders these fixed labels.

**Mock Keychain is required only for this dedicated diagnostic.** These Profiles must be created with that provider and use it on every restart. Never mix them with baseline Profile A/B, personal browser data, or production encryption claims. No real credentials, wallets, Keychain items or extension storage are inspected.

The coordinator must verify actual JSON context relationships plus page behavior:

1. Read all three before writing; record their synthetic empty state.
2. In A1 explicitly write a `bato-` test marker. Read A2 and B: A2 should observe A1's localStorage, persistent cookie, IndexedDB record and CacheStorage entry; B should remain empty. SessionStorage is window/tab scoped and is **not** expected to share.
3. Write a different `bato-` marker in B. Read A1/A2 again; they should retain the A marker while B reports its own.
4. Close all three through actual UI, confirm message-loop exit, `cef-shutdown-complete` and process exit. A close request alone is not a clean-shutdown pass.
5. Relaunch the same executable, dedicated root and mock provider. Explicitly read again; verify persistence and isolation. SessionStorage should be fresh; this test does not change its transient semantics.

All raw logs and Profiles remain outside Git. `runtime.log` records only fixed labels, ephemeral browser IDs, counts and relationship booleans; CEF's own diagnostic output may include disposable local paths. The implementation retains no global owning CEF references: its comparison map holds browser IDs, resolves temporary references after creation, then lets them go. Closing removes the IDs.

## Evidence limits

Build status and runtime evidence must be reported separately. There is no runtime launch by the implementation agent. This experiment does not implement workspace switching, tab moves across Profiles, extension-state isolation, service workers, real encrypted storage, crash recovery, signing or distribution. Equal API storage relationships alone do not prove every storage type; the synthetic fixture checks are necessary. The initial labels/paths are fixed and are not a proposed Bato persistence format.
