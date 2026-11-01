# Bato progress

Updated 2026-11-01. Rough planning estimate: **40% of a usable V1**, with the polished Arc-style interface around **30–35%**. These estimates reflect feature coverage and remaining integration work, not elapsed time or a measured completion score. The current build is an engineering alpha, not a daily-use release.

| Area | Current state | Remaining |
| --- | --- | --- |
| Chromium foundation | Pinned source build; native Swift hosting; real pages and bounded focus/close checks | Remaining window, split, modal, compatibility and production acceptance |
| Organization | Persistent workspaces; shared Favorites; pins/tabs; ordered flat folders with collapse, membership and safe dissolve; entry/workspace ordering and transfers | Nested folders, broader workspace/Profile lifecycle and import mapping |
| Page coordination | Stable IDs; lazy creation; live-page reuse; saved/session URLs; confirmed/cancelled close | Broader crash/recovery and lifecycle coverage |
| Find Page | Current-Profile search, atomic activation, unloaded opening and live reuse; integrated command-bar page results | Broader search/ranking polish |
| Arc-style interface | Adaptive sidebar, Favorites, rounded content, engine-delivered site icons; duplicate horizontal tabs hidden in owned normal windows | Remaining native browser chrome and broader visual polish |
| Sidebar behavior | Coordinated dock/hide/reveal, Cmd+S, 220–400-point drag/keyboard resizing and accessible controls; bounded real-host checks passed | Persisted preferences, animation, broader window/transition acceptance |
| Command bar | Floating native Cmd+T bar; URL/web search; current-Profile page switching; keyboard selection; browser commands; session-local provider choice | Persisted search settings, broader command coverage and acceptance |
| Splits | Chromium split experiments | Bato ownership, divider integration and saved pairs |
| Peek | Not implemented | Preview, dismiss and promote |
| Profiles | Synthetic storage sharing/isolation demonstrated | Application context binding and Profile controls |
| Extensions | Narrow installation/persistence/use checks recorded | Remaining acceptance; extensive testing deferred by user |
| Blocking | Not implemented | Default blocking, controls and persistent site exceptions |
| Import | Not implemented | Arc staging preview, organization mapping and transactional import |
| Archive and browser essentials | Not implemented as product features | Archive/restore, settings, history, downloads and external-link handling |
| Persistence and recovery | Atomic organization store, stale-write protection and previous-good backup | Migration, broader recovery and backup workflows |
| Distribution | Developer source host only | Packaging, signing, updates, security/performance and daily-use readiness |

Sidebar geometry milestone passed bounded real-host checks, including hidden page commands, native-sheet restoration and steady-fullscreen Cmd+S suppression. Geometry remains session-local. General window resizing/minimum size, rapid fullscreen transitions and independent button-free hover are not runtime-accepted; see `spikes/engine-native-slot/GEOMETRY-RESULTS.md`.

Command-bar bounded real-host checks passed local URL creation/close, encoded Google search, cross-workspace unloaded activation, live reuse, hidden-sidebar entry and cancellation. A clean restart retained rendering and live-page activity through the URL/close roundtrip. The initial run also had an unexplained black original renderer, recovered by unloading/reopening; its cause remains open and is retained in `spikes/engine-native-slot/COMMAND-BAR-RESULTS.md`. Provider preference is session-local; complete browser chrome remains future work.

Chrome/icons/folders passed bounded real-host checks: folder create/group/collapse/rename/dissolve, exact preservation of entries/selection, clean-restart folder persistence, real loaded-page icons, normal/fullscreen tab-strip restoration and Chromium site information. Folder edits created no extra browsers. Icons remain session-local; folders are flat. See `spikes/engine-native-slot/CHROME-FOLDERS-RESULTS.md` for explicit limits.

## Next milestones

1. Add Bato split-pair ownership and native controls, then Peek. Flat folders, engine-delivered icons and scoped tab-strip removal are implemented within recorded acceptance.
2. Continue remaining browser-chrome polish, nested organization and preferences alongside broader window/lifecycle acceptance.
3. Add remaining Profile/import/blocking/essential workflows and release readiness.

Use bounded subagents for implementation and review. Keep verification proportional: targeted model/runtime tests and a short real-host check for affected behavior; repeat heavy engine/dependency checks when engine integration or dependencies change, rather than for every metadata or visual edit. Keep remaining acceptance gates explicit without reopening the full extension matrix for unrelated application changes.
