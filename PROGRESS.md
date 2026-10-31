# Bato progress

Updated 2026-10-31. Rough planning estimate: **30% of a usable V1**, with the polished Arc-style interface around **10–15%**. These estimates reflect feature coverage and remaining integration work, not elapsed time or a measured completion score. The current build is an engineering alpha, not a daily-use release.

| Area | Current state | Remaining |
| --- | --- | --- |
| Chromium foundation | Pinned source build; native Swift hosting; real pages and bounded focus/close checks | Remaining window, split, modal, compatibility and production acceptance |
| Organization | Persistent workspaces, names/colors/order; shared Favorites; pins and temporary tabs; entry order and same-Profile transfers | Folders and broader workspace/Profile lifecycle |
| Page coordination | Stable IDs; lazy creation; live-page reuse; saved/session URLs; confirmed/cancelled close | Broader crash/recovery and lifecycle coverage |
| Find Page | Current-Profile search, atomic activation, unloaded opening and live reuse passed in the real host; sheet visibility defect resolved | Complete command-bar integration |
| Arc-style interface | Basic native sidebar and controls | Layout, rounded content area, proportions, materials, spacing and visual polish |
| Sidebar behavior | Fixed visible sidebar | Resizing, hiding, left-edge reveal and Cmd+S |
| Command bar | Native HTTP(S) address entry; separate Find Page picker | Floating Cmd+T bar, web search and browser commands |
| Splits | Chromium split experiments | Bato ownership, divider integration and saved pairs |
| Peek | Not implemented | Preview, dismiss and promote |
| Profiles | Synthetic storage sharing/isolation demonstrated | Application context binding and Profile controls |
| Extensions | Narrow installation/persistence/use checks recorded | Remaining acceptance; extensive testing deferred by user |
| Blocking | Not implemented | Default blocking, controls and persistent site exceptions |
| Import | Not implemented | Arc staging preview, organization mapping and transactional import |
| Archive and browser essentials | Not implemented as product features | Archive/restore, settings, history, downloads and external-link handling |
| Persistence and recovery | Atomic organization store, stale-write protection and previous-good backup | Migration, broader recovery and backup workflows |
| Distribution | Developer source host only | Packaging, signing, updates, security/performance and daily-use readiness |

## Next milestones

1. Build larger visible interface milestones: Arc-style chrome/sidebar layout and sidebar behavior.
2. Complete command-bar workflows and folders, then Bato split/Peek integration.
3. Add remaining Profile/import/blocking/essential workflows and release readiness.

Use bounded subagents for implementation and review. Keep verification proportional: targeted model/runtime tests and a short real-host check for affected behavior; repeat heavy engine/dependency checks when engine integration or dependencies change, rather than for every metadata or visual edit. Keep remaining acceptance gates explicit without reopening the full extension matrix for unrelated application changes.
