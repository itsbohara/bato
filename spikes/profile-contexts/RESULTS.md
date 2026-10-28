# Context probe build evidence

Date: 2026-10-28. Build and source checks only; this implementation agent did **not** launch a browser. Runtime acceptance remains with the coordinating agent.

## Verified build

- Pinned official prebuilt framework: CEF `156.0.14+g4fa4ab5`, Chromium `156.0.8078.48`, arm64.
- `build.sh` completed serial CMake sample/wrapper compilation with exit0 and `USE_SANDBOX=ON`. Its lock was removed on completion.
- The output framework binary SHA256 exactly matched the cached official distribution: `9c81eb633abb7c1ebd5058f939061b4ece215d8f56e053114dac7073204800e8`.
- `nm` found all three context-probe entry points in the sample executable.
- Python/shell syntax checks passed. Reapplying preparation produced byte-identical patched sample sources. No baseline or linked-native-bridge source was changed.
- Approximately12GiB was available before compilation. No engine source checkout or engine rebuild occurred.

Executable: `~/.cache/bato/profile-contexts/build/tests/cefsimple/Release/cefsimple.app/Contents/MacOS/cefsimple`. Coordinator launch: `python3 spikes/profile-contexts/run.py`.

The preparer fails closed if the baseline sample's explicit global/root cache mapping is absent. The main executable additionally requires the dedicated root, native Chrome mode and test-only mock Keychain, and rejects extension loading. The launcher supplies those settings and no debug listener. Profiles and raw logs stay outside Git.

## Runtime checks still required

No runtime relationship or storage pass is claimed here. After the three actual hosts are created, look for `context-relationships` with `a1_a2_distinct`, `a1_a2_shared`, `b_isolated` and `matches_expected` all true. If any differs or no event arrives, preserve the observation rather than assuming requested settings were honored.

Then exercise the [storage fixture](../fixtures/README.md) as described in [README.md](README.md): empty initial state; A1 write visible in A2 while B remains empty; independent B marker; completed shutdown; same-provider restart; persistent localStorage, cookie, IndexedDB and CacheStorage values. SessionStorage is separately tab/window scoped. Context relationships alone do not establish those storage outcomes.

The sample uses the corrected explicit handler termination path rather than casting Chrome's current application delegate to the sample delegate. This source correction and a successful build do not establish reliable Quit/close behavior; record actual loop exit, completed CEF shutdown and process exit.

No real vault, wallet, Keychain secret, extension storage, personal Profile or private screenshot was accessed by this implementation work.
