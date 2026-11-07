# Arc import: preview and apply, real-host check (2026-11-07)

Synthetic data only. The input was a copy of `fixtures/basic.json` saved as `StorableSidebar.json` in a temporary folder; no real Arc data was opened. (The open panel starts in the default Arc folder; it was only navigated away from using Go to Folder.)

## What exists
Workspace actions ("...") menu, "Import from Arc...": open panel, parse via `BatoImport`, preview sheet, one-transaction apply through `OrganizationStore` with a pre-import snapshot file (`organization.snapshot.pre-import.json`) and an Undo button.

## Results (host build with integration, `runtime/integrate-state-v2`)
| Check | Result |
| --- | --- |
| Menu item opens panel, chosen file parses | pass |
| Preview lists spaces with counts: Work 11 pins, 6 folders, 0 tabs, 1 split; Space 2 1 pin; Side 1 pin | pass |
| Summary line "3 workspaces in 2 new Profiles, 13 pins, 6 folders, 3 favorites, 0 tabs"; unsupported/simplified list (damaged item, deep folder moved up, unknown type, shortened names, repeated favorite, icons/themes, split, arc:/file: pages, mixed order) | pass |
| Today toggle: default off; on changes Space 2 to 2 tabs and total to 2 tabs; off again imports 0 tabs | pass |
| Import: result sheet "Added 3 workspaces in 2 new Profiles ..." with Undo Import and Done; organization file gains Profiles "Arc" and "Arc - Profile 1" and workspaces Work, Space 2, Side; existing data and active workspace preserved; schema version 1 became 2 | pass |
| Snapshot file bytes equal the pre-import organization bytes | pass (sha256 match) |
| Undo Import: organization bytes equal pre-import bytes | pass (sha256 match) |
| Import again, Done, import a third time: every space shows "Already imported from this file", unchecked and disabled; an "Import already imported spaces again as copies" checkbox exists; Cancel leaves the file unchanged | pass |
| Source file hash unchanged | pass |

## Defects and notes
- The sheet's space list renders with blank space above the rows (rows sit at the bottom of the scroll area).
- When every space is already imported the summary line still reads "3 workspaces in 2 new Profiles ..." and the Import button stays enabled although nothing is selected.
- The success sheet says new Profiles need browser Profile support that is not connected yet, so imported workspaces are visible but cannot open pages; imported workspaces were not opened or checked in the sidebar in this run.
- Undo is available only until another change; after Done it is gone, so "import, Undo, import" produces a fresh import, not "already imported" (the duplicate message was reached via import, Done, import).
- Not run: failure injection mid-apply, restart after a successful apply, per-space unchecking, "import as copies".

Logs (SSD /Volumes/Mahesh/personal/bato-build): logs/integrate-v2.log, integrate-v2-pre-import.json, integrate-v2-post-import.json, integrate-v2-after-second-import.json, integrate-v2-before-quit.json, tmp/arc-fixture/.
Note: the v2 run itself exited -11 on quit because of the blocking poll bug described in spikes/blocking/RESULTS.md (fixed; v3 exited 0); the organization file was written before that and equalled the pre-quit copy.
