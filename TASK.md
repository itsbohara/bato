# Work plan

Status: design and feasibility experiment approved by the user on 2026-10-27. Initial runtime feasibility checkpoints are recorded in FEASIBILITY-RESULTS.md; the production integration gate remains open.

## Source of requirements

Local authoritative concept: `/Users/itsbohara/code/ideastorm/concepts/bato/README.md`.
Project memory: `/Users/itsbohara/code/ideastorm/memory/project-bato.md`.
Public product behavior is captured in DESIGN.md; do not publish private reference screenshots.

## 1. Research and design

- [x] Review Chromium integration report, especially native window embedding, extension popups, and split pairs.
- [x] Review Arc import and blocker report.
- [x] Consolidate and review DESIGN.md, distinguishing proposals from agreed requirements.
- [x] Approve the concrete design and feasibility experiment before an implementation plan. User approval received 2026-10-27.

## 2. Bounded engine feasibility experiment

Define exact runtime/build and extension versions before execution. Prove native Swift/AppKit integration, installation and persistence, extension popups, Bitwarden autofill, MetaMask page-provider behavior using a disposable test wallet, AdGuard filtering, and shared/isolated Profile storage. Prove two-page split feasibility. Never use real wallet assets or secrets in tests.

A failure must be reported as a blocker; do not replace required behavior with a visual mock. Only choose CEF or another Chromium integration after reviewing the evidence.

### Active delegated work

- CEF baseline: pin and verify official Apple Silicon binaries; launch in Chrome style with disposable Profile; collect runtime and extension-management evidence.
- Extension fixtures: controlled login, filtering, and dapp pages plus a synthetic MV3 capability probe; pin real extension targets and document install paths.
- Native composition: test the Swift/AppKit window boundary against the chosen runtime, native keyboard/focus behavior, and split/Peek constraints.

Initial integration evidence is published in [FEASIBILITY-RESULTS.md](FEASIBILITY-RESULTS.md). Sample builds, Bitwarden store persistence, narrow AdGuard/MetaMask behavior, Profile markers, native accessory controls, and native Chrome split targeting have been exercised. Full extension acceptance remains open. A browser executable alone does not pass the foundation gate.

### Latest source-native checkpoint

[Registered native-slot results](spikes/engine-native-slot/RESULTS.md) now establish bounded real Swift input/focus in the normal Chrome window, native split/synthetic extension coexistence, fullscreen restoration and two-window teardown. Follow-up now passes one inward window resize, keyboard split resize and single-pane AdGuard popup/input across persisted-unpacked clean restart. The production gate remains open: pointer divider/arbitrary resize, modal blocking, explicit AX geometry, Bitwarden/MetaMask popups and real extension focused-pane behavior require acceptance. See the retained command-line AdGuard restart failure before reusing its v5 Profile. Use the dedicated native_slot.py overlay runner; original base guards must stay intact.

### Next bounded engineering tasks

1. Extend the explicit linked Swift/Objective-C++ experiment into one supported host combining native input/accessibility, reserved geometry, splits and extension UI. The registered normal-window slot now passes bounded native mouse/field/focus and synthetic split/lifecycle acceptance; complete modal/AX geometry, drag/resize and real extension UI remain open. See spikes/linked-native-bridge/RESULTS.md and spikes/native-composition/ENGINE-SEAM.md. Resolve production Keychain/signing behavior separately from the test-only mock provider.
2. Integrate the demonstrated normal-window split control and clean-restart URL reconstruction into the eventual native host. Prove divider resizing and real-extension focused-pane behavior; controller URL storage is not Bato saved pins. Investigate the first extension-controller close-all hang despite later clean exits. Do not build two Alloy panes merely because the CEF BrowserView count is limited.
3. Exercise Bitwarden autofill with a disposable test vault and controlled HTTPS fixture; exercise MetaMask with an unfunded disposable wallet. Keep real secrets out of artifacts.
4. Extend Profile tests to multiple contexts/workspaces, more storage types, extension state, and clean restart with one consistent application identity. Investigate the cross-sample cookie observation before making broad persistence claims.
5. Select the foundation only after reviewing these results; then begin application slices below.

The exact pinned extension API creates visible splits in normal Chrome windows. It redirects requested tab creation away from a populated Views popup and rejects moves back into it. Do not treat that test as a path combining Swift sidebar geometry with native split support. Engine-facing layout/type changes need an independently built framework and acceptance; the current prebuilt engine does not expose those seams.

The [native input audit](spikes/native-composition/NATIVE-INPUT-AUDIT.md) identifies Chromium's custom content-view hit-testing/accessibility policies in both host modes. Arbitrary Swift child attachment is insufficient; evaluate an explicit engine-owned `NativeViewHost` with an application-owned adapter before considering global content-view overrides. This is source-backed research, not a demonstrated native-host solution.

## Authorized source-build workspace

The user selected the external SSD's personal folder on 2026-10-28. Dedicated engine artifacts, tools, caches and temporary files belong under `/Volumes/Mahesh/personal/bato-build`. The application Git checkout remains here. Initial checks found writable APFS, approximately167GiB free and16GiB host RAM. Prepare a single ARM64 developer component configuration, preserve a20GiB free-space reserve and avoid distribution/multiple-configuration builds. Keep the exact existing CEF/Chromium pins. The reservation patch is a source-build experiment; neither a successful checkout nor its dry-run selects a production foundation.

## 3. Personal alpha implementation (after gate)

Plan bounded vertical slices for durable browser state, native shell and command bar, workspace/Profile lifecycle, tabs/pins/folders, split pairs/Peek, extensions, Arc import, built-in blocking, and daily-use essentials. Add recovery, migration, and restart acceptance checks. Make each slice reviewable before integration.

## 4. Daily-use acceptance

Run the agreed behavior checklist from the design against a real Apple Silicon build. Record failures and limits. Public alpha distribution and update ownership must be decided before wider release.
