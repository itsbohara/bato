# Context probe evidence

Build: 2026-10-28. Runtime: 2026-10-29. This records the dedicated prebuilt-engine context probe, not Bato workspace implementation.

## Verified build

- Pinned official prebuilt framework: CEF `156.0.14+g4fa4ab5`, Chromium `156.0.8078.48`, arm64.
- `build.sh` completed serial CMake sample/wrapper compilation with exit0 and `USE_SANDBOX=ON`. Its lock was removed on completion.
- The output framework binary SHA256 exactly matched the cached official distribution: `9c81eb633abb7c1ebd5058f939061b4ece215d8f56e053114dac7073204800e8`.
- `nm` found all three context-probe entry points in the sample executable.
- Python/shell syntax checks passed. Reapplying preparation produced byte-identical patched sample sources. No baseline or linked-native-bridge source was changed.
- Approximately12GiB was available before compilation. No engine source checkout or engine rebuild occurred.

Executable: `~/.cache/bato/profile-contexts/build/tests/cefsimple/Release/cefsimple.app/Contents/MacOS/cefsimple`. Coordinator launch: `python3 spikes/profile-contexts/run.py`.

The preparer fails closed if the baseline sample's explicit global/root cache mapping is absent. The main executable additionally requires the dedicated root, native Chrome mode and test-only mock Keychain, and rejects extension loading. The launcher supplies those settings and no debug listener. Profiles and raw logs stay outside Git.

## Observed runtime

[Sanitized evidence](runtime-evidence.json) records two actual launches of the same executable and dedicated mock-Keychain Profiles. All fixture operations used native accessibility Write/Read controls; windows were selected through the native Window menu. No debug listener or extension was enabled.

| Check | Observation |
| --- | --- |
| Empty baseline | A1, A2 and B each reported `status: ok`, value null for all five stores before any write. |
| A1 to A2 sharing | A1 wrote `bato-context-a-20261029`; A2 explicitly read the same localStorage, persistent cookie, IndexedDB and CacheStorage values. A2 sessionStorage stayed null. |
| B isolation | B explicitly read all null after the A1 write. B then wrote `bato-context-b-20261029`; subsequent A1/A2 reads retained the A marker in all four persistent stores. A1 sessionStorage retained A; A2 remained null. |
| First clean close | Native window close buttons closed A2, A1, B. Diagnostic references reached zero, `cef-message-loop-exited` and `cef-shutdown-complete` appeared, and owned PID95190 was absent. No signal/forced stop. |
| Clean restart persistence | Same executable/Profile root/mock provider relaunched. Explicit reads, without further writes: A1/A2 retained A in all four persistent stores; B retained B. All three sessionStorage values were null. |
| Second clean close | Native window close buttons closed B, A1, A2. References reached zero, loop exit and completed CEF shutdown appeared; owned PID7033 was absent. No signal/forced stop. |

The final accessibility observation after each last-window close timed out because the browser exited. The separate lifecycle events and absent owned PID establish completed shutdown; a close request alone was not used as evidence. These tests exercised native window closes, not the distinct application Quit command.

## Actual context identity differs from the probe expectation

Both launches reported the actual-host matrix:

```json
{"a1_a2_distinct":false,"a1_a2_shared":true,"b_isolated":true,"matches_expected":false}
```

The requested A1/A2 wrappers did not produce distinct contexts when retrieved from the actual browser hosts: `IsSame` reports identity, while storage sharing and B isolation hold. The diagnostic's distinct-host expectation was not met; its false `matches_expected` is preserved without changing the fixture or expected value. This identity result does not invalidate the separately observed store-sharing behavior and is not a requirement that Bato have distinct host context objects for a shared Profile.

## Limits and retained artifacts

The four tested synthetic persistent stores shared and survived one confirmed clean restart with B isolated. This does not establish extension-state isolation, service workers, arbitrary websites, workspace switching, tab movement, crash recovery, production encrypted storage, signing or distribution. The earlier cross-sample cookie observation remains a separate test with a different boundary.

Raw first-run diagnostics are retained outside Git at `~/.cache/bato/profile-contexts/runtime-first-clean.log`; second-run diagnostics remain at `runtime.log`, alongside the dedicated test Profiles. Only fixed labels, ephemeral IDs, relationship booleans and synthetic fixture values are included in the committed evidence. No real vault, wallet, Keychain secret, personal Profile or private screenshot was accessed.
