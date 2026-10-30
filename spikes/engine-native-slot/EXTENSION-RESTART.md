# Extension restart failure investigation

On 2026-10-30, the native-slot source sample first launched with three real extensions supplied by `--load-extension` and later exited naturally with code0. Restarting the same dedicated mock-Keychain Profile aborted in declarative network request (DNR) allocation accounting. The first-run extension observations do not establish persistence across restart.

## Exact engine and observed failure

- CEF156.0.14+g4fa4ab5, revision `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f`.
- Chromium156.0.8078.48, commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c`.
- ARM64 Debug component build with the recorded Quit, reservation, helper and native-slot patches.
- Retained local log: `/Volumes/Mahesh/personal/bato-build/logs/native-slot-v5-restart.log`. Its fatal check is `global_rules_tracker.cc:112`: `allocated_global_rule_count_ >= old_allocated_rule_count`, with values0 and40804. The stack enters through `RulesMonitorService::OnInitialRulesetsLoadedFromDisk`.

Read-only inspection of the dedicated synthetic test Profile confirmed that the AdGuard entry retained a DNR allocation of40804 and manifest location8. No Profile contents, extension settings or raw logs are included here. Location8 is explicitly `kCommandLine` in the pinned `extensions/common/mojom/manifest.mojom`.

## Source-backed mechanism

All paths below are relative to the pinned Chromium source root at `/Volumes/Mahesh/personal/bato-build/source/chromium/src`:

- `extensions/browser/unpacked_installer.cc`, `LoadFromCommandLine`: assigns `ManifestLocation::kCommandLine` for `--load-extension`. The asynchronous UI load path instead assigns `kUnpacked` in `LoadWithFileAccessOnFileThread`.
- `extensions/browser/api/declarative_net_request/global_rules_tracker.cc`, `CalculateInitialAllocatedGlobalRuleCount`: explicitly excludes `kCommandLine` entries when summing persisted allocations at service construction. Its comment says command-line extensions should not persist across browser restart.
- In the same file, `OnExtensionRuleCountUpdated` reads the individual extension's old persisted allocation without applying that exclusion, then asserts that the global total covers it. This matches the observed zero global total and nonzero old allocation.
- `extensions/browser/api/declarative_net_request/rules_monitor_service.cc`, `OnInitialRulesetsLoadedFromDisk`: loads the enabled extension's matchers and updates allocation accounting. `ShouldReleaseAllocationOnUnload` releases allocations for selected disable/blocklist cases; ordinary shutdown is not a release case.
- `chrome/browser/extensions/installed_loader.cc`, `LoadAllExtensions`: likewise skips command-line entries during automatic startup loading. Supplying the command-line extension again follows a separate loading path.

These facts strongly support a mismatch between startup accounting and a repeatedly command-line-loaded extension's retained DNR allocation. They do **not** prove that CEF, native-slot integration, or unmodified Chromium is the ultimate cause. Startup ordering, duplicate context initialization and the complete loading lifecycle still require controlled comparison. Earlier CacheStorage/network warnings are not established causes of this assertion.

## Safe next comparison

First compare the same Profile and same extension inputs with the native-slot/reservation flags omitted, retaining the same mock-Keychain provider, executable and assertions. The control (native-slot-v5-control, log `logs/native-slot-v5-control.log`) also aborted naturally with SIGABRT/exit-6 at the identical assertion and values0/40804. The native-slot factory was not enabled. This establishes that enabling the native slot/reservation is not required to reproduce the failure; it does not isolate all earlier engine patches.

Then use a **new, named dedicated mock Profile** and the same verified official extension files. Install AdGuard through `chrome://extensions` → Load unpacked so its location is `kUnpacked`; do not supply that extension through `--load-extension`. Complete a natural Quit, restart with the same mock provider and without the command-line extension flag, and check extension presence, popup behavior, DNR filtering and natural shutdown. This tests the persisted unpacked installation path independently of the command-line reload path. It does not establish Web Store update behavior.

Preserve the failed Profile and logs. Do not clear allocation preferences, delete the Profile, lower rule counts, disable DNR or remove the assertion to obtain a successful restart. If a source correction becomes necessary, preserve both control outcomes and add a focused regression case before modifying allocation lifecycle behavior.

## Persisted-unpacked comparison result

The separate v6 Profile installed the same verified AdGuard5.5.3.3 through Load unpacked. Read-only inspection confirmed location4 and allocation40804. First launch and restart both completed natural exit0 with actual loop return, CEF shutdown and one native-slot detach. Restart supplied no extension loading flag, restored the toolbar action, and rendered the real AdGuard popup. First-run actual popup input changed Actions→Statistics; native mouse actions worked after popup dismissal on both runs. Logs remain SSD `logs/native-slot-v6.log` and `logs/native-slot-v6-restart.log`.

This comparison supports a command-line reload/accounting issue for the retained v5 case and demonstrates the persisted-unpacked path separately. It does not establish a general upstream fix, Web Store persistence/updates, filtering correctness or other extensions' acceptance. No assertion, rule allocation or engine source was modified.
