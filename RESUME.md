# Resume Bato

Checkpoint: 2026-10-28. Product/design approval, public MIT repository and subagent-driven development remain authorized. Continue engineering without repeating settled product questions.

## Working locations

Application Git checkout: `/Users/itsbohara/code/project-bato/bato`, public `https://github.com/itsbohara/bato`. The parent folder is not Git. Concept/private memory remains in `/Users/itsbohara/code/ideastorm`; never publish private reference captures or browser data.

The user selected the external SSD personal folder for engine work: **`/Volumes/Mahesh/personal/bato-build`**. This supersedes the earlier temporary prebuilt-only choice. APFS USB SSD, approximately167GiB initially free; host16GiB RAM, Xcode26.3/macOS SDK26.2. The pinned Chromium source allows minimum SDK15; its official SDK26.5 is a separate official-build setting. Use one developer ARM64 component configuration with bounded disk usage, not production packaging. Keep tools/caches/temp/output under the dedicated SSD root. No unrelated SSD files were inspected or changed.

Read AGENTS.md, TASK.md, FEASIBILITY-RESULTS.md, spikes/linked-native-bridge/RESULTS.md and QUIT-PATH.md, spikes/native-composition/SPLIT-CONTROL.md and ENGINE-SEAM.md before continuing.

## Demonstrated runtime

- Pinned CEF156.0.14 / Chromium156.0.8078.48 prebuilt arm64 framework; source-built samples, no engine-core rebuild yet.
- Earlier narrow Bitwarden store-install persistence, AdGuard custom filtering/site exception, MetaMask provider/read-only requests and A/B test markers remain recorded. Full vault autofill/wallet approvals are unpassed.
- Explicit linked Swift/Objective-C++ callbacks now replace injection for the new experiment. Actual native panel action/text input, browser activation, supported split-command dispatch, shared-window tab tracking, detach and completed CEF shutdown passed.
- The normal Chrome companion is a separate diagnostic panel, not Bato's sidebar. Views layout reserved260px left/44px top with Swift sibling surfaces and no visual page overlap; real input/accessibility in that arrangement remains unverified.
- Normal-window extension API pairing, separation, re-pairing and saved fixed-URL reconstruction passed across a confirmed clean restart with fresh IDs and two visible fixture pages. First-run close-all hung; later successful closes do not erase that failure. Divider resizing remains unverified.
- Views popup second-tab creation redirected to a normal window; moving tabs back was rejected. No demonstrated host yet combines native sidebar input, native split and real extension UI.

## Keychain and quit findings

Changing development executables initially rendered blank pages and hit a teardown watchdog, even with exact stock source. Framework/resources and logic matched baseline. A process sample showed a Keychain-decryption wait; the same failing binary rendered and closed with `--use-mock-keychain` in a fresh dedicated test Profile.

Use mock Keychain ONLY in dedicated disposable Profiles created with it, on EVERY restart of those Profiles. Never toggle it on existing baseline A/B or personal Profiles. No production encryption/signing pass follows. Raw samples, browser data and logs stay outside Git.

The distinct native `IDC_EXIT` test crashed because stock SimpleApplication terminate assumed NSApp.delegate was SimpleAppDelegate, but Chrome installed AppController. The revised sample calls the explicit known CEF handler directly; it compiles. **Runtime verification of this correction is pending.**

## Ready experiments and current blockers

- `spikes/profile-contexts/` compiles a three-native-window sharing/isolation probe. A1/A2 request shared storage; B isolated. `python3 spikes/profile-contexts/run.py` uses its fixed dedicated mock-Profile root. Actual contexts/storage/restart checks are pending.
- New fixture `/storage.html?label=A1|A2|B` exercises explicit namespaced localStorage, CookieStore, IndexedDB, CacheStorage and tab-scoped sessionStorage. HTTP tests and Node fixture tests pass. It is served by the existing static server without restarting it.
- `spikes/engine-reservation/` contains a one-file opt-in Chromium layout patch sketch plus exact source hashes. Hash checks and patch dry-run pass; uncompiled and not a native hosting contract.
- SSD bootstrap has only small pinned official tooling/docs under its bootstrap/ folder. `spikes/engine-build/` scaffolding is being prepared; inspect its status before launching expensive checkout/build. No full Chromium checkout/build has started at this checkpoint.
- **Mac UI is locked.** Computer control reported automatic unlock failed; the user was asked to unlock manually. Do not bypass the lock or claim UI tests complete. CLI source/build work can continue.

## Process and source-control state

No owned sample browser/debug listener remains. The root-owned synthetic fixture server is still on127.0.0.1:18765. Leave the unrelated existing service on8765 untouched. Engine samples/cache remain under `~/.cache/bato`; preserve them for repeatable tests.

New reviewed commits include split-control probe7145275, reservation/boundary researchcd45acb, storage fixtures74b4ecf, linked native bridge6bcc8f1 and context probea12f614. Remaining report/checkpoint and SSD build-scaffold changes may still be uncommitted; inspect Git status and agent status before integration. Do not repeat builds or overwrite a running executable. No production foundation, complete Bato application, engine fork or release has been selected.
