# CEF baseline results

Date: 2026-10-27. Stock CEF experiment on Apple Silicon, macOS27.0.1, Xcode26.3. No Bato browser application has been built and no complete extension-compatibility pass is claimed.

## Pinned artifacts

Selected the newest stable macosarm64 entry available in the [official automated-build index](https://cef-builds.spotifycdn.com/index.json): **CEF156.0.14+g4fa4ab5, Chromium156.0.8078.48**, published 2026-10-24. Archive names use the common prefix `cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_macosarm64`.

| Archive suffix | Bytes | Published SHA1 (verified) | Locally computed SHA256 |
| --- | ---: | --- | --- |
| `_client.tar.bz2` | 135474899 | `a80906135c78d90a564e022989084d741ab1cd9d` | `f9c9761786208ea0727bb5b422b1c4c61eba80122dacf9526225907a06548bbb` |
| `.tar.bz2` (standard) | 312251761 | `dd97a0bf9f25686b135858ea809780dfb9b57006` | `e238aca81208407ddc210f9633577e5f059fc990678fb355b90d2625faea8625` |

The standard archive supplies sample source, headers, prebuilt Chromium framework and supporting libraries. No Chromium source checkout or Chromium build was performed. No archive, built application, real browser data, or private screenshot is committed.

## Build and launch evidence

- CMake configure completed with `CMAKE_BUILD_TYPE=Release`, `PROJECT_ARCH=arm64`, `USE_SANDBOX=ON`.
- `cmake --build ... --target cefclient --parallel 4` exited0 and logged `[100%] Built target cefclient`.
- `file` identifies the resulting main executable as `Mach-O 64-bit executable arm64`. The local development binary is ad-hoc/linker-signed, without a distribution identity or sealed resources; no notarization/distribution claim follows.
- Both the verified prebuilt client and subsequently the locally compiled client launched. The log explicitly reports `Using Chrome style; Views-hosted window; Windowed rendering`.
- CDP `/json/version` reports `Chrome/156.0.8078.48`. The `chrome://extensions/` page renders as `Extensions`; initially `chrome.developerPrivate.getExtensionsInfo` returned an empty array.
- `lsof` confirms the CDP listener is `127.0.0.1:9223`, not an all-interface listener. Sandbox-disabling switches were not used. Sandboxing itself has not undergone a security audit.

The launch includes `--use-views`, a disposable cache path, `--force-renderer-accessibility`, loopback CDP, and an explicit diagnostic URL. Some runs additionally load the separate AppKit diagnostic dylib and developer extensions. Native-composition evidence and constraints belong to the sibling experiment; injection is not the production app architecture.

## Extension load evidence

Official extension developer packages and a synthetic MV3 probe were loaded with `--load-extension` from cache/fixture paths. Initial `getExtensionsInfo` returned all four `ENABLED`, with empty runtime/manifest error arrays at that moment:

| Extension | Runtime-reported version | Initial load |
| --- | --- | --- |
| Bitwarden Password Manager | 2026.10.0 | Enabled |
| AdGuard AdBlocker | 5.5.3.3 | Enabled |
| MetaMask | 13.54.0 | Enabled |
| Bato synthetic MV3 capability probe | 0.1.0 | Enabled |

The coordinator separately used native UI to observe Bitwarden's welcome popup and AdGuard's controls. MetaMask displayed onboarding rather than a validated unlocked-wallet approval flow. Those observations are not full functional acceptance.

**Restart limitation:** restarting the source-built sample with the same Profile but **without** `--load-extension` produced empty extension management. The fixture did not observe the synthetic content script, and `window.ethereum` was undefined. The coordinator also observed empty extension cards through native UI. Command-line loading therefore does not establish persistent user installation. Restoring the flag restored the synthetic content-script/service-worker response. Store installation/update behavior must be tested separately.

## Narrow functional probes

The coordinator used native UI to save two AdGuard user rules for the synthetic fixture, then reload it: a network script rule for `http://127.0.0.1:8765/ads/network-probe.js` and a cosmetic rule for `#bato-cosmetic-ad` on `127.0.0.1`. Native UI showed the cosmetic text absent and the harmless control executed. A separately attached CDP Network observer then recorded the target script failing with **`net::ERR_BLOCKED_BY_CLIENT`**, while `control.js` and the fixture document received HTTP200. This distinguishes actual request blocking from a missing/script-error-only fixture. The coordinator then disabled protection for the test site through AdGuard’s actual popup; reloading restored both the network and cosmetic targets while the harmless control continued. After a later restart with developer loads restored, the coordinator confirmed AdGuard’s global protection remained on while protection for the fixture site remained off; both fixture targets were restored and the control executed. This demonstrates restart persistence of that site exception. This is one custom-rule network/cosmetic and site-toggle check, not a full filter-list or blocker-coexistence pass.

The coordinator also observed MetaMask through the fixture: EIP-6963 discovery reported MetaMask (`io.metamask`), read-only `eth_accounts` returned an empty array, and `eth_chainId` returned `0x1`. This is injected-provider/read-only RPC evidence in an unconfigured test Profile. Wallet creation, unlock, origin approval, account access and signing remain untested.

## Real store-install test

On clean ProfileB, the coordinator navigated to Bitwarden’s [official Chrome Web Store listing](https://chromewebstore.google.com/detail/bitwarden-password-manage/nngceckbapebfimnlniiiahkandclblb), clicked Add to Chrome, and accepted the native extension permission sheet. The stock sample displayed a Save As panel for the CRX download. After saving into the disposable cache, installation completed asynchronously: the native “added to Chromium” notification, welcome page, and enabled extension card were observed with Developer mode off.

Read-only `chrome.developerPrivate.getExtensionsInfo` then reported the official ID `nngceckbapebfimnlniiiahkandclblb`, version2026.10.0, state`ENABLED`, location`FROM_STORE`, and zero runtime/manifest errors at that moment.

The Save As detour is explained by the stock sample’s `ClientHandler::OnBeforeDownload`, which unconditionally continues downloads with `show_dialog=true`; it is not evidence that the installer is absent. A proposed diagnostic change was canceled when installation completed. **No CEF source or sample patch was applied for this store-install/persistence test.**

ProfileB was then restarted using the same unmodified source-built app, no extension startup flags and no native dylib. Its protected preferences retained `from_webstore=true` and the official installed extension path. After restart, native management again showed the enabled card with Developer mode off, and CDP again reported the same official ID/version as `ENABLED` and `FROM_STORE`, with zero runtime/manifest errors at that moment. Thus this actual store installation persisted without startup flags. Store updates and store installation of the other two extensions remain untested.

## Storage evidence

The coordinator saved a non-secret marker `profile-a-controlled` through the fixture UI. After a graceful restart of the source-built application using the same disposable Profile, read-only CDP evaluation observed:

- `localStorage.getItem('bato-profile-marker') === 'profile-a-controlled'`.
- `document.cookie === 'bato_marker=profile-a-controlled'`.
- Synthetic content-script/service-worker messaging responded after developer flags were restored.

A subsequent launch used a fresh ProfileB with no load flags or native injection. Before store testing, its `Default/Preferences` contained zero extension settings and CDP showed no extension service-worker targets.

The coordinator then wrote `profile-b-controlled` through ProfileB’s fixture UI. Returning to ProfileA retained `profile-a-controlled` in both localStorage and the test cookie, so B’s marker did not overwrite A’s state. A final no-flags restart of ProfileB retained `profile-b-controlled` in both mechanisms; the official installed Bitwarden service worker was running. This is basic origin-storage isolation across two engine cache directories and repeated process launches, not proof of Bato’s future workspace/Profile orchestration, all storage types, or multiple request contexts in a single process.

## Not yet passed by this baseline

Bitwarden real test-vault autofill; AdGuard full filter-list/update coverage; MetaMask test wallet/account-access/signing flow; store updates and store installation of AdGuard/MetaMask; all Profile storage isolation; production Swift-owned shell; two fully capable split panes; Peek; crash recovery; signing/notarization; and broad security/performance validation.

The stock client is useful as an extension-runtime diagnostic. It does not resolve CEF's documented Alloy/native-parent versus Chrome-UI composition boundary.

## Local evidence files

All runtime files remain outside Git under `$HOME/.cache/bato/cef-baseline`: `configure.log`, `build.log`, `launch-args.json`, `baseline.log`, `initial-extensions-native.log`, `source-a-without-loadflag.log`, `extension-load-evidence.json`, `adguard-network-evidence.json`, `store-install-evidence.json`, `store-restart-evidence.json`, `profile-b-initial-marker.json`, `profile-b-before-restart.json`, `profile-b-final.json`, `profile-a-final.json`, and `profile-a-before-restart.json`. These paths are a local inventory, not a promise that disposable cache files are durable.

## Additional native-window sample

After completing the stock cefclient store/storage tests, the coordinator authorized compiling `cefsimple` from the same cached distribution to investigate Chromium’s own two-page split within one Chrome BrowserView. This is distinct from embedding two Chrome-style BrowserViews. The sample and C++ wrapper/framework were reused; no additional engine download or Chromium build occurred.

Pinned `cefsimple_mac.mm` does not consume `--cache-path` into CefSettings. Before launching it, the bounded sample-only [profile patch](cefsimple-profile.patch) was applied to explicitly set `settings.root_cache_path` and `settings.cache_path` from the supplied disposable cache path. It refuses to run without the switch and logs the chosen path. The [application script](apply-cefsimple-profile.py) is reproducible, and [CEF’s upstream license](CEF-LICENSE.txt) is preserved. No CEF core code was modified.

The incremental `cefsimple` build exited0 and produced an arm64 application. It launched with `--use-native`, no `--use-views` or Alloy switch, no native dylib, the same ProfileA directory, and the four developer-extension flags. The log confirmed the explicit cache directory, and localStorage retained the A marker. `document.cookie` was empty after switching from cefclient to cefsimple; cross-sample cookie continuity is therefore not a pass and needs separate investigation. The earlier cefclient-only restart-cookie observations remain valid within that sample.

The coordinator owns native split UI tests and integration evidence. See the sibling native-composition reports for current results; this baseline does not infer a production Swift-owned shell or a successful split from source alone.

Future harness launches set their working directory to the disposable cache so Chromium’s `console.log` does not land in the repository. Existing generated console output was moved into the same cache.
