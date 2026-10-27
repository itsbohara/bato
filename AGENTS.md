# Bato development

## Product invariants

Native Swift interface over Chromium, macOS and Apple Silicon first. Preserve the agreed V1 scope in DESIGN.md. Do not substitute WebKit or Electron, or assume CEF satisfies extension compatibility. AI and sync are deferred.

## Workflow

Use subagents for bounded research and implementation. Give each agent explicit file ownership, context, acceptance criteria, and a request for concise findings. The coordinating agent reviews and verifies results before integration. Keep the main chat focused on decisions and outcomes.

Distinguish confirmed requirements, proposed defaults, and demonstrated capabilities. No extension, import, security, or performance claim without evidence. Keep research sources and version details in the relevant report.

## Privacy and source control

Never commit real browser profiles, cookies, tokens, wallet material, personal tab names, or private screenshots. Use synthetic fixtures. One commit per logical change. No generated-by or co-author attribution footers. Preserve unrelated work.

## Current gate

Complete design review and establish a viable Chromium/native-window/extension path before implementing the application. Use TASK.md for current acceptance gates. Do not download a full Chromium checkout without checking available disk space and an explicit need.
