# Bato development

## Product invariants

Native Swift interface over Chromium, macOS and Apple Silicon first. Preserve the agreed V1 scope in DESIGN.md. Do not substitute WebKit or Electron, or assume CEF satisfies extension compatibility. AI and sync are deferred.

## Workflow

Read `RESUME.md` and `PROGRESS.md` when resuming work. Keep the progress checklist and handoff synchronized with demonstrated capabilities, unfinished work, known failures, running processes and the next concrete step. Progress percentages are rough planning estimates, not measured completion.

Prefer larger reviewable application/UI milestones over chains of tiny feature slices. Keep verification proportional: targeted tests and a short affected-workflow host check; repeat heavy engine/dependency checks when integration or dependencies change. Do not reopen the full extension matrix for unrelated application changes.

Use subagents for bounded research and implementation. Give each agent explicit file ownership, context, acceptance criteria, and a request for concise findings. The coordinating agent reviews and verifies results before integration. Keep the main chat focused on decisions and outcomes.

Distinguish confirmed requirements, proposed defaults, and demonstrated capabilities. No extension, import, security, or performance claim without evidence. Keep research sources and version details in the relevant report.

## Privacy and source control

Never commit real browser profiles, cookies, tokens, wallet material, personal tab names, or private screenshots. Use synthetic fixtures. One commit per logical change. No generated-by or co-author attribution footers. Preserve unrelated work.

## Current gate

The user approved the design and experiment on 2026-10-27; do not re-request that approval. On2026-10-30, the user explicitly authorized provisional alpha implementation while the remaining compatibility checks continue. Build incremental application slices now; keep unresolved Chromium/native-window/extension behavior as acceptance requirements before daily-use readiness. The native Chromium split is distinct from multiple CEF BrowserViews; see the runtime evidence before inferring unsupported behavior. Use TASK.md for current acceptance gates. Do not download a full Chromium checkout without checking available disk space and an explicit need.
