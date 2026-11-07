# Arc import plan

Planning only (2026-11-07). The user's real Arc data was not read. Labels: **[V]** verified from public sources or this repo; **[A]** assumption; **[D]** decision for the user.

## Requirements (DESIGN.md, AGENTS.md)
Read a user-selected Arc data file or copied fixture without modifying the original; parse into a staging model; show organization preview plus unsupported-data summary; apply as one transaction; pre-import snapshot; import into new Bato organization by default; a second import must not silently duplicate or replace; no cookies/passwords/sessions. Synthetic fixtures only.

## Where Arc keeps the data
- **[V]** `~/Library/Application Support/Arc/StorableSidebar.json` (Meridian importer https://github.com/Undermove/meridian-browser/blob/main/src/importers/arc.js, MIT; Ardia `packages/import/ios/Core/ArcSidebar.swift`, GPL-3.0, read for approach only, nothing copied). Two independent public importers agree on the layout below. Neither is a schema contract; the installed Arc version is untested **[A]**.
- Layout as observed in those sources: top `sidebar.containers[]`; the container that holds `spaces` and `items` is the one to use (Ardia picks it by position after a `global` marker; Meridian takes the first with an `items` array). `items` and several maps are flat alternating key/value arrays (`[k, v, k, v, ...]`, a Swift-codable artifact); Ardia tolerates plain object lists too, so parse both.
  - **Space**: `id`, `title`, `profile` (`{default}` or `{custom:{_0:{directoryBasename}}}`), `containerIDs` / `newContainerIDs` (pairs: pinned container id, unpinned container id), `customInfo.iconType` (emoji or SF-symbol-like icon), `customInfo.windowTheme` (colors: `primaryColorPalette.midTone`, newer nested gradients).
  - **Favorites**: `topAppsContainerIDs`, pairs of (profile descriptor, container id): Favorites are per Arc profile, matching Bato's `BrowserProfile.favorites`.
  - **Item**: `id`, optional custom `title`, `childrenIds`, and `data` one of `tab {savedURL, savedTitle, timeLastActiveAt (seconds since 2001-01-01)}`, `list` (folder; `automaticLiveFolderData` marks GitHub/Bitbucket live folders), `splitView` (children are tabs).
- **[A]** Not covered by those parsers and treated as unsupported/unknown: Easels, Notes, Boosts, Archive, Little Arc, sync-only state, tab groups beyond folders. Arc may be running and rewriting the file: read a copy, retry once if JSON is truncated.
- Access: user picks the file via an open panel (no broad filesystem permission); offer a "Find Arc data" default path button that only opens the panel at that folder. Hash source bytes before/after.

## Mapping to Bato (`app/Sources/BatoCore/BrowserState.swift`)
| Arc | Bato | Notes / loss |
| --- | --- | --- |
| Arc profile (default / custom dir) | New `BrowserProfile` per distinct Arc profile, named e.g. "Arc" / "Arc - Profile 3" **[D]** (or map to an existing Profile) | Organization metadata only; no cookies/logins (engine data is separate). |
| Space | `Workspace` (name, `color` `#RRGGBB` validated, `profileID`) | Emoji/icon and gradient theme: Bato has one color only; map `midTone`, report dropped icon/gradient. Empty title -> "Space N". |
| Pinned container, tab children | `Workspace.pins` (kind `.pinned`, `savedURL` = `savedURL`, `lastURL` = same, title = custom title else `savedTitle`) | Only http(s) URLs are valid (`validateURL`); `arc:`, `file:`, `chrome:` etc. -> unsupported list. |
| `list` item | `PageFolder` with `parentID`, `pinIDs`, `isCollapsed` | **Depth cap `maxFolderDepth = 4`**: deeper folders hoisted into their depth-4 ancestor, reported. Names 1-80 chars (trim/truncate, report). Bato lists a folder's pins before its subfolders; Arc interleaves, so interleaving order is lost (report once). Empty folders kept. |
| Unpinned (Today) tabs | `Workspace.tabs` (`.temporary`, no `savedURL`) | Opt-in toggle, default on, unloaded/lazy **[D]**. Active/last-used metadata dropped. |
| Favorites | `BrowserProfile.favorites` (`.favorite`) | Order kept; duplicates by URL within a Profile skipped with note. |
| `splitView` | `PageSplit` (two distinct entries, ratio 0.5, `isPinned` iff both pinned) | Exactly 2 children only. 3+ or mixed pinned/temporary: flatten and report. Arc split ratios unknown **[A]**. |
| Live folders | Plain empty folder or skipped | Reported. |
| Cycles / missing child ids / duplicate ids | Skipped with warning (visited-set, depth bound like Ardia/Meridian) | Never crash, never partial write. |

Bato-side gaps found: the model has **no import-source identity** (needed for idempotent re-import) and `BrowserState.validate` only accepts versions 1 and 2. The store keeps a single `organization.last-good.json` (`OrganizationStore.save`), not the dated snapshots in DESIGN.md.

## Design
1. **Parser** (`BatoImport`, new SwiftPM target, pure, no UI/engine): `ArcSidebarParser.parse(Data) -> ArcStaging` with `ArcStaging { profiles, spaces[ pins/folders tree/tabs/splits ], favorites, issues[] }`, `issues` typed (`unsupportedURL`, `depthHoisted`, `splitFlattened`, `unknownItem`, `cycle`, `missingReference`, `truncatedName`) with counts and a content-free example (no titles in logs).
2. **Planner**: `ImportPlan.make(staging, options, existing BrowserState) -> (draft BrowserState, summary)` assigns fresh UUIDs deterministically from `(sourceFileHash, arcItemID)` (UUIDv5-style) so a re-import of the same file is recognizable.
3. **Duplicate policy [D]**: default "import as new workspaces, marked with an import batch id; if the same Arc space id was already imported, show 'Already imported' and offer Skip (default) / Import again as copy". Needs a small schema addition (`importedFrom: {source, arcSpaceID, batch}` on `Workspace`, version 3) **[D]**.
4. **Preview UI** (sheet in `BatoBrowserUI`): per-space tree with counts (pins, folders, depth, tabs, favorites), per-space include checkboxes, Profile mapping, unsupported-data summary (grouped, expandable), "Nothing from Arc will be modified; no passwords or cookies are imported."
5. **Apply**: pre-import snapshot (copy of `organization.json` to a labelled snapshot file before any write), build draft via `BrowserState.transact`-style validation, `OrganizationStore.save` once (atomic, conflict-checked). Failure leaves the store untouched. Undo = restore snapshot **[D]** whether to ship an Undo button.
6. **Privacy**: never read `User Data/` (cookies, Login Data, history). Parser input limited to the sidebar JSON, size cap (e.g. 64 MB) and depth/node budgets. Redact titles/URLs from logs and test output.

## Synthetic fixture (`spikes/arc-import/fixtures/*.json`, hand-written)
`basic.json`: 3 spaces (two share the default profile, one custom `Profile 1`), emoji + gradient theme, per-profile favorites, pinned tabs, folder depth 5 (tests hoist), empty folder, interleaved pins/folders, 2-child split and a 3-child split, duplicate URL, Unicode and 200-char titles, an `arc://` pin, a Today tab, an unknown `data` kind. Variants: `kv-array-items.json` (alternating form) vs object-list form, `malformed.json`, `missing-keys.json`, `cycle.json`, `dangling-children.json`, `huge-theme.json`. Fake URLs use `example.test`; no real tab names.

## Acceptance
1. Parser unit tests: exact expected counts/order for `basic.json`; each issue kind emitted exactly once per cause; both alternating and object-list forms parse equal.
2. Malformed/cyclic/dangling inputs: no crash, no partial state, clear error or warnings.
3. Plan output passes `BrowserState.validate()` (depth <= 4, unique IDs, split rules, `#RRGGBB`).
4. Source file SHA-256 identical before/after; test opens it read-only.
5. Apply: snapshot exists before the write; injected failure mid-apply leaves `organization.json` byte-identical; successful apply loads after restart.
6. Re-import of the same file: no silent duplicates; chosen policy applied.
7. Preview shows counts matching the plan and an unsupported summary; accessibility labels on the sheet.
8. Private-fixture run by the user on a *copy* of their real file, results counts only; never committed.

## First bounded milestone (about 1 day, no UI, no schema change)
New `BatoImport` target with `ArcSidebarParser`, `ArcStaging`, `ImportPlan` (always "new workspaces"), the synthetic fixtures and tests for acceptance 1-4, plus a CLI-less test that applies a plan to an in-memory `BrowserState` and validates. Then milestone 2: schema v3 + snapshot + preview sheet.

## Decisions needed
1. Profile mapping: new Bato Profile per Arc profile (recommended) vs map to existing.
2. Import Today tabs by default?
3. Schema v3 `importedFrom` for idempotency, and Skip as the default duplicate policy.
4. Undo-via-snapshot button in V1 or snapshot-only.
5. Whether to offer reading from the default Arc path (open panel pre-pointed) in the first release.

## Decisions (2026-11-07)

- Each Arc profile imports into a new Bato Profile; Spaces become its workspaces.
- Today tabs are off by default; Undo uses the pre-import snapshot.
