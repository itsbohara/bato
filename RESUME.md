# Resume Bato

Checkpoint: 2026-10-29, after successful source compilation and unlocked runtime tests. Product/design approval, public MIT repository and subagent-driven development remain authorized. Continue engineering without repeating settled product questions.

## Latest checkpoint: source-engine Quit V3 passed

Read `spikes/engine-quit/RESULTS.md` and runtime-evidence.json first. The flagged source experiment now passes client veto, actual armed beforeunload Cancel (same process/page, counter2→3), repeated standard application-menu Quit → Leave, real loop return, CEF shutdown and natural exit0 with the synthetic controller and native split pair open. Earlier failures below remain retained evidence. Command-Q sent once produced no visible request; keyboard warning/hold behavior remains unresolved. No-window/download/active-app/system-shutdown and production behavior are unpassed.

V3 restores normal AppController startup/cleanup under the experiment flag and handles cancellation inside the framework. Hash-locked patches cover seven CEF and two Chromium files. Incremental build90.83s;31 engine-build tests +2 patch tests +fixture test pass. Downloaded source currently has V3 applied and the successful binary matches it. Never rerun checkout/configure over these patches. Mock Profile `quit-mock-v3` contains test data and must be preserved, with the same provider on every restart. Raw log SSD `logs/quit-v3.log`; no owned browser/build remains. Fixture server127.0.0.1:18765 was restarted during this session.

Next: review/implement `spikes/native-composition/NATIVE-SLOT-PLAN.md` as a bounded framework adapter; input/accessibility with native Chrome split and extension UI remains the foundation gate. No production foundation selected.

## Working locations

Application Git checkout: `/Users/itsbohara/code/project-bato/bato`, public `https://github.com/itsbohara/bato`. The parent folder is not Git. Concept/private memory remains in `/Users/itsbohara/code/ideastorm`; never publish private reference captures or browser data.

The user selected the external SSD personal folder for engine work: **`/Volumes/Mahesh/personal/bato-build`**. This supersedes the earlier temporary prebuilt-only choice. APFS USB SSD, approximately167GiB initially free; host16GiB RAM, Xcode26.3/macOS SDK26.2. The pinned Chromium source allows minimum SDK15; its official SDK26.5 is a separate official-build setting. Use one developer ARM64 component configuration with bounded disk usage, not production packaging. Keep tools/caches/temp/output under the dedicated SSD root. No unrelated SSD files were inspected or changed.

Read AGENTS.md, TASK.md, FEASIBILITY-RESULTS.md, spikes/linked-native-bridge/RESULTS.md and QUIT-PATH.md, spikes/native-composition/SPLIT-CONTROL.md and ENGINE-SEAM.md before continuing.

## Demonstrated runtime

- Pinned CEF156.0.14 / Chromium156.0.8078.48 prebuilt arm64 framework for earlier runtime tests; a separate full ARM64 component source build has now succeeded.
- Earlier narrow Bitwarden store-install persistence, AdGuard custom filtering/site exception, MetaMask provider/read-only requests and A/B test markers remain recorded. Full vault autofill/wallet approvals are unpassed.
- Explicit linked Swift/Objective-C++ callbacks now replace injection for the new experiment. Actual native panel action/text input, browser activation, supported split-command dispatch, shared-window tab tracking, detach and completed CEF shutdown passed.
- The normal Chrome companion is a separate diagnostic panel, not Bato's sidebar. Views layout reserved260px left/44px top with Swift sibling surfaces and no visual page overlap; real input/accessibility in that arrangement remains unverified.
- Normal-window extension API pairing, separation, re-pairing and saved fixed-URL reconstruction passed across a confirmed clean restart with fresh IDs and two visible fixture pages. First-run close-all hung; later successful closes do not erase that failure. Divider resizing remains unverified.
- Views popup second-tab creation redirected to a normal window; moving tabs back was rejected. No demonstrated host yet combines native sidebar input, native split and real extension UI.

## Keychain and quit findings

Changing development executables initially rendered blank pages and hit a teardown watchdog, even with exact stock source. Framework/resources and logic matched baseline. A process sample showed a Keychain-decryption wait; the same failing binary rendered and closed with `--use-mock-keychain` in a fresh dedicated test Profile.

Use mock Keychain ONLY in dedicated disposable Profiles created with it, on EVERY restart of those Profiles. Never toggle it on existing baseline A/B or personal Profiles. No production encryption/signing pass follows. Raw samples, browser data and logs stay outside Git.

The distinct native `IDC_EXIT` test crashed because stock SimpleApplication terminate assumed NSApp.delegate was SimpleAppDelegate, but Chrome installed AppController. The revised sample's direct-handler route now passes the former exception point but **still fails graceful application quit**: tracked browsers close, loop/shutdown completion is absent and bounded owned-process TERM was required. See QUIT-PATH.md for the missing Chrome application-controller lifecycle. No client private selectors or forced-exit fallback are accepted fixes.

## Ready experiments and current blockers

- `spikes/profile-contexts/` passed actual four-store sharing A1/A2, B isolation and persistence across a confirmed clean restart. Session storage remained tab-scoped and reset. Both runs completed shutdown without signals. Actual host contexts A1/A2 were identical (`IsSame`), so the distinct-identity expectation is false; preserve that observation separately from successful storage behavior. Raw logs and mock Profiles stay outside Git; sanitized evidence is committed.
- New fixture `/storage.html?label=A1|A2|B` exercises explicit namespaced localStorage, CookieStore, IndexedDB, CacheStorage and tab-scoped sessionStorage. HTTP tests and Node fixture tests pass. It is served by the existing static server without restarting it.
- Read `spikes/native-composition/NATIVE-INPUT-AUDIT.md`: exact source shows both normal Chrome and Views use `BridgedContentView`, whose custom hit-test/accessibility behavior can exclude arbitrary added Swift children. Runtime class/hit testing remains unmeasured; reservation alone does not establish a native input contract.
- `spikes/engine-reservation/` contains a one-file opt-in Chromium layout patch sketch plus exact source hashes. Hash checks, compilation and narrow visual normal/zoom/fullscreen checks pass; native hosting/input remains open.
- The pinned Chromium/CEF checkout completed successfully, with its completion marker verified. Initial configure applied116 upstream CEF patches and skipped one, then failed because depot_tools' separate Python shim was uninitialized. A new guarded `bootstrap` phase initialized the exact manifest-pinned interpreter without updating tooling. Twelve guard/provenance tests passed. Configuration retry succeeded:36640 targets generated from5030 files for only Debug_GN_arm64. Both local reservation and sample-runtime patches then applied successfully.
- **Initial engine build succeeded** in5h38m14s, exit0. Former owned worker groups are absent; ARM64 layout/sample patched objects independently verified. Original log/state preserved as SSD `logs/build-initial-success.log` and `build-initial-success-state.json`. SSD free space113GiB at runtime testing; reserve guard remains20GiB.
- **Mac UI was manually unlocked.** Quit and context tests were exercised. Source-built control launch PID9591 failed with SIGABRT before usable UI: missing Aperitif helper caused sandbox/GPU launch failure, followed by a debug blocking assertion in cache teardown. Separate code-sign clone EXDEV is explicitly nonfatal in pinned source. Reservation was not attempted until that startup failure was repaired; later v2 results are below. All owned diagnostic source/prebuilt processes were cleaned up; do not treat control failure as a layout failure.
- `spikes/engine-build/runtime.py` is a read-only post-build checker and control/reservation launch preview, with no execution option. Both previews resolved523 ARM64 images against the initial completed build. Xcode otool parenthesized-helper parsing and runtime-loaded-library rpath inheritance were corrected;26 guard/runtime-plan tests pass. It did not check Aperitif helper bundles because the initial CEF GN list omitted them. The reviewed helper packaging correction was then applied and rebuilt successfully in15.76s. The checker requires all seven bundles and resolved526 ARM64 images. Control/reservation v2 both rendered and exited0 on native window close; visual normal/zoom/fullscreen reservation passed narrowly, with fullscreen edge fidelity still open. See engine-build/RESULTS.md. Retain failed control-mock-v1 Profile; never delete it to bypass the fresh-profile gate.
- Read `spikes/engine-build/PROCESS-LIFECYCLE.md` before any build stop. Pinned Siso uses separate helper/action groups and normally cancels them via parent-socket EOF, but the wrapper verifies only its original group. Explicitly inspect owned worker survivors after any disk/error/cancel stop; never signal stale recorded IDs or unrelated processes.

## Process and source-control state

No owned sample browser/debug listener remains. The root-owned synthetic fixture server is still on127.0.0.1:18765. Leave the unrelated existing service on8765 untouched. Engine samples/cache remain under `~/.cache/bato`; preserve them for repeatable tests.

Reviewed source and reports include the build/checker, retained quit failure and clean-restart context evidence. Inspect Git status and recent commits before integration; the final helper/layout checkpoint may be newer than earlier recorded commit IDs. No production foundation, complete Bato application or release has been selected.

## First action after compaction

Inspect Git status and `python3 spikes/engine-build/engine.py status` before any command. Both initial and helper-repair builds completed; no owned browser/build process remains. Never rerun checkout or the upstream configure hook over patched source. Read `spikes/engine-build/RESULTS.md`, RUNTIME.md and helper-packaging manifest before later engine work. The separate manifest leaves the original lock.json checkout digest unchanged.

Both fixed v2 mock Profiles now contain tested data. The preview checker deliberately refuses nonempty Profiles; preserve them and review the known same-provider history before any restart/extension experiment. Do not change providers or delete files to bypass its gate. For later UI selection, wait for the explicitly launched sample to initialize, then select its exact app path. Early CUA selection during library loading caused an unconfigured duplicate activation process, which was explicitly stopped.

Next bounded gates are minimum sizes/arbitrary resize/fullscreen edge fidelity, split/divider and extension/permission anchors in the source host, followed by explicit native input/accessibility integration (NativeViewHost adapter candidate). The source reservation test had no Swift surfaces or extensions. The source-built control and reservation closes exited naturally with code0; this does not fix the separate extension-loaded application Quit failure.

The next application-quit fix requires the full native Chrome controller lifecycle inside a supported framework boundary. The direct-handler sample correction only removed the selector crash; do not report graceful application quit as passed. Context storage sharing/isolation across a clean restart passed separately, with host identity canonicalization recorded.
