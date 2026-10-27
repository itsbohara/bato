# Required-extension feasibility matrix

Date: 2026-10-27. This file defines reproducible tests and artifact provenance. It does not claim an overall compatibility pass. Runtime observations belong in the baseline/native experiment reports.

## Pinned official diagnostic artifacts

GitHub's authenticated release API supplied the exact release assets and SHA-256 digests. Downloaded ZIP hashes were independently calculated and matched; extracted manifests were inspected. They are cached outside the repo under `~/.cache/bato/extensions/`. No third-party extension code or binaries are copied into this public repository. Full observed manifest capability lists are recorded in [extensions-lock.json](fixtures/extensions-lock.json).

| Extension | Official release | ZIP / inspected manifest version | SHA-256 |
| --- | --- | --- | --- |
| Bitwarden | [browser-v2026.10.0](https://github.com/bitwarden/clients/releases/tag/browser-v2026.10.0) | `dist-chrome-2026.10.0.zip` / MV3 `2026.10.0` | `7b9ec650b87dd8975e87a0e0bdd0c1f1a0fcf5b0a8da5ae759ec14cdffaad35d` |
| AdGuard AdBlocker | [v5.5.3.3](https://github.com/AdguardTeam/AdguardBrowserExtension/releases/tag/v5.5.3.3) | `chrome-mv3.zip` / MV3 `5.5.3.3` | `628b5da9749cf6b4730cf8ffe28b6afdb2b3e029c1acd918c73d7c4b2e90986e` |
| MetaMask | [v13.54.0](https://github.com/MetaMask/metamask-extension/releases/tag/v13.54.0) | `metamask-chrome-13.54.0.zip` / MV3 `13.54.0.0` | `14f73006fc9b0b185b645fcd96f52e23fba5cc1d71d3a091b6dfb04f83fdfe2b` |

These pin downloaded diagnostic artifacts, not store-installed builds. Record actual store version and install method independently. Bitwarden's [deployment documentation](https://bitwarden.com/help/browserext-deploy/) identifies Chrome store ID `nngceckbapebfimnlniiiahkandclblb`; its [store page](https://chromewebstore.google.com/detail/bitwarden-password-manage/nngceckbapebfimnlniiiahkandclblb) is a separate installation path. Official [AdGuard MV3 documentation](https://kb.adguard.com/kb/adguard-browser-extension/mv3-version/) identifies `chrome-mv3.zip` builds. Never substitute MetaMask Flask for the regular build.

Manifest evidence explains why a synthetic MV3 probe is insufficient: Bitwarden requests `offscreen`, `sidePanel`, `webRequestAuthProvider`, scripting, and other APIs; AdGuard requests `declarativeNetRequest`, `declarativeNetRequestFeedback`, `userScripts`, scripting and request/navigation APIs; MetaMask requests `offscreen`, `identity`, `sidePanel`, scripting, request and cookie APIs. The probe intentionally covers only action popup, content script, background worker messaging, and local storage.

## Execution order and evidence

1. Record CEF/Chromium/build architecture, macOS, runtime style, exact launch flags, Profile/cache path, extension version/ID and install method. Keep logs/captures free of user data. Use fresh disposable Profiles and no existing real vault/wallet.
2. Start the [fixture server](fixtures/README.md). Install the synthetic probe unpacked and visit the index. Confirm content marker and worker response, open the actual toolbar action popup, increment its count, close/reopen the popup, then restart the browser. Record persisted count and errors separately. Opening popup HTML as a tab is a diagnostic, not a toolbar-action pass.
3. Install each required official extension separately. Check its service worker and real toolbar popup, options/onboarding, disable/remove/re-enable, and restart. Test normal user installation and update paths independently of developer loading. Downloading or successfully unpacking is not installation evidence.
4. Run the specific behaviors below, first on stock Chrome-style baseline and then again with native composition, both split panes and Peek. No required feature is accepted solely because it worked in a separate diagnostic Chrome window.
5. Use Profile A from two workspaces and isolated Profile B. Check extension installation/settings, dummy account state, cookie/localStorage marker, origin permissions and restart behavior. Existing on-disk state alone does not prove isolation or sharing.

| Target | Required behavior / expected result | Failure or incomplete result |
| --- | --- | --- |
| Bitwarden | In a disposable test vault create the exact fixture-origin entry with documented dummy values. Test toolbar popup unlock, popup autofill, inline UI, keyboard shortcut, navigation and restart. Fixture checks both expected values locally. Then repeat against a controlled HTTPS origin. | Welcome/popup rendering alone does not pass unlock or autofill. No test account means those rows stay untested; never borrow the user's real vault. Desktop biometric/native messaging is separate. |
| AdGuard | In `/blocking.html`, add the two explicit user rules from fixture README. Target script must be blocked, harmless control script must execute, cosmetic target must disappear. Verify popup/site exception and reload, Settings/user rules, filter log, and persisted rules after restart. | Default list matching localhost is not deterministic. Missing target execution without a network/filter-log check can be a page error. Network and cosmetic results must be recorded separately. |
| MetaMask | Onboard an unfunded disposable test wallet. In `/wallet.html`, confirm injected provider, reject then approve account access, inspect chain/account, reject then approve the fixed `personal_sign` message, revoke permission, and reconnect after restart. Compare prompt origin/account. Verify toolbar and dapp-triggered prompts. | Provider discovery or popup rendering alone does not establish account/signing behavior. The fixture checks signature shape only; recover the signer independently for full signature correctness. Do not send transactions or create token approvals. |
| Built-in / AdGuard coexistence | When the built-in engine exists, test all four on/off combinations; use equivalent deterministic rules in each. Each toggle must affect only its own engine. Repeat exceptions after restart and across shared/isolated Profiles. | Built-in engine is not implemented yet; leave this row untested. AdGuard success cannot establish Bato blocker correctness. |

Only page button clicks initiate wallet permission/signing requests. Do not automate approving a wallet connection, signature, or protected-credential unlock. Unsupported `wallet_revokePermissions` must be recorded as an API failure; clearing page state is not a real revocation substitute. The dapp uses [EIP-6963 discovery](https://eips.ethereum.org/EIPS/eip-6963) and fixed [MetaMask `personal_sign`](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/) behavior. Deterministic filter rules follow [AdGuard's own syntax documentation](https://adguard.com/kb/general/ad-filtering/create-own-filters/).

## Fixture validation performed

- Four real-HTTP Python tests passed: loopback binding/resources/no-store headers, parent traversal/listing denial, POST rejection, and synthetic manifest resource existence.
- Node mocked-provider test passed: discovery sends no permission request, signing without an account does not prompt, code `4001` rejection is shown, connection is explicit, the signature payload is the fixed dummy message, and revocation clears mocked permission. No transaction/typed-data/chain-changing method is requested.
- JavaScript syntax checks passed for wallet and service worker scripts.
- These checks establish fixture behavior only. Actual extension installation, native integration, browser restart, cross-Profile behavior, real autofill, and wallet approval/signature acceptance require separate runtime evidence.
