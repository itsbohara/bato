# Work plan

Status: research reports and design draft reviewed; user design approval and runtime experiment pending, 2026-10-27.

## Source of requirements

Local authoritative concept: `/Users/itsbohara/code/ideastorm/concepts/bato/README.md`.
Project memory: `/Users/itsbohara/code/ideastorm/memory/project-bato.md`.
Public product behavior is captured in DESIGN.md; do not publish private reference screenshots.

## 1. Research and design

- [x] Review Chromium integration report, especially native window embedding, extension popups, and split pairs.
- [x] Review Arc import and blocker report.
- [x] Consolidate and review DESIGN.md, distinguishing proposals from agreed requirements.
- [ ] Approve the concrete design and feasibility experiment before an implementation plan.

## 2. Bounded engine feasibility experiment

Define exact runtime/build and extension versions before execution. Prove native Swift/AppKit integration, installation and persistence, extension popups, Bitwarden autofill, MetaMask page-provider behavior using a disposable test wallet, AdGuard filtering, and shared/isolated Profile storage. Prove two-page split feasibility. Never use real wallet assets or secrets in tests.

A failure must be reported as a blocker; do not replace required behavior with a visual mock. Only choose CEF or another Chromium integration after reviewing the evidence.

## 3. Personal alpha implementation (after gate)

Plan bounded vertical slices for durable browser state, native shell and command bar, workspace/Profile lifecycle, tabs/pins/folders, split pairs/Peek, extensions, Arc import, built-in blocking, and daily-use essentials. Add recovery, migration, and restart acceptance checks. Make each slice reviewable before integration.

## 4. Daily-use acceptance

Run the agreed behavior checklist from the design against a real Apple Silicon build. Record failures and limits. Public alpha distribution and update ownership must be decided before wider release.
