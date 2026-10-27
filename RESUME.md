# Resume Bato

Checkpoint: 2026-10-27, before the user compacts this chat.

## Authorization and working location

The user approved DESIGN.md and the feasibility experiment, requested subagent-driven development, and selected public MIT licensing. Continue engineering without repeating settled product questions or asking for design approval again.

Repository: `https://github.com/itsbohara/bato`.
Working directory: `/Users/itsbohara/code/project-bato/bato` on the agreed Apple Silicon Mac mini. The parent `project-bato/` folder is not the Git checkout.

Read AGENTS.md, TASK.md, FEASIBILITY-RESULTS.md, and spikes/native-composition/SPLIT-INVESTIGATION.md first. Historical concept/memory lives under `/Users/itsbohara/code/ideastorm/concepts/bato/` and `/Users/itsbohara/code/ideastorm/memory/project-bato.md`.

## Verified checkpoint

- Pinned CEF156.0.14 / Chromium156.0.8078.48 official arm64 samples compiled and ran. No Chromium source checkout.
- Actual Bitwarden Web Store installation survives restart. Real action popup works; vault autofill remains untested.
- AdGuard custom network/cosmetic rules work; network evidence shows ERR_BLOCKED_BY_CLIENT. Per-site exception survives restart.
- MetaMask injects its provider and answers read-only account/network requests. No wallet approval or signing pass.
- A/B cookie and localStorage markers isolate and survive same-sample restarts. Cross-sample cookie continuity was not observed; do not overstate validation.
- Native Chromium split works inside ONE Chrome BrowserView. Synthetic action popup targets distinct focused-pane tab IDs and paths. Divider dragging and saved-pair restore remain unverified.
- Swift/AppKit accessory controls work in the test runtime. Clean layout in Views-hosted cefclient, but toolbar overlap in full native Chrome. Combined native controls + split + real Bitwarden welcome popup were observed; no production native-shell pass.
- Four Python HTTP tests, wallet request-gating test, popup sanitization/targeting test, script syntax and local document links passed.

## Next bounded work

Use subagents with explicit file ownership. Prioritize an explicit supported Swift/Objective-C++ lifecycle and geometry bridge to the Chrome-native runtime. Reserve native sidebar/command-bar surfaces, fix native-window overlap, and verify shutdown/focus/popup behavior. Diagnostic dylib injection is not the production bridge. Preserve Swift-native + Chromium; do not switch to WebKit/Electron or infer split requires a Chromium fork from the BrowserView-count limit.

Then verify native split control/restoration and real per-pane extension behavior, complete disposable-vault/wallet checks, and review the remaining foundation gate before implementing application slices. Current task details are in TASK.md.

## Local runtime state

Owned sample/browser and fixture-server processes were stopped. No test debug listener is intentionally left running. Engine builds, developer packages, disposable Profiles and logs remain outside Git under `$HOME/.cache/bato` and can be reused. Recheck disk before builds; no full Chromium checkout.

New fixture default: `http://127.0.0.1:18765/`. Historical evidence used8765. Port8765 is used by an existing local service; leave that service untouched. The fixture alternate-origin link now preserves the current port. See spikes/fixtures/README.md and spikes/cef-baseline/README.md for commands.

All work was committed and pushed; the working tree was clean before this checkpoint. No actual Bato browser application has been delivered yet.
