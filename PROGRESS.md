# Bato progress

Updated 2026-11-01. Rough planning estimate: **45% of a usable V1**, with the polished Arc-style interface around **35–40%**. These estimates reflect feature coverage and remaining integration work, not elapsed time or a measured completion score. The current build is an engineering alpha, not a daily-use release.

| Area | Current state | Remaining |
| --- | --- | --- |
| Chromium foundation | Pinned source build; native Swift hosting; real pages and bounded focus/close checks | Remaining window, split, modal, compatibility and production acceptance |
| Organization | Persistent workspaces; shared Favorites; pins/tabs; ordered flat folders with collapse, membership and safe dissolve; entry/workspace ordering and transfers | Nested folders, broader workspace/Profile lifecycle and import mapping |
| Page coordination | Stable IDs; lazy creation; live-page reuse; saved/session URLs; confirmed/cancelled close | Broader crash/recovery and lifecycle coverage |
| Find Page | Current-Profile search, atomic activation, unloaded opening and live reuse; integrated command-bar page results | Broader search/ranking polish |
| Arc-style interface | Adaptive sidebar, Favorites, rounded content, engine-delivered site icons; duplicate horizontal tabs hidden in owned normal windows | Remaining native browser chrome and broader visual polish |
| Sidebar behavior | Coordinated dock/hide/reveal, Cmd+S, 220–400-point drag/keyboard resizing and accessible controls; bounded real-host checks passed | Persisted preferences, animation, broader window/transition acceptance |
| Command bar | Floating native Cmd+T bar; URL/web search; current-Profile page switching; keyboard selection; browser commands; session-local provider choice | Persisted search settings, broader command coverage and acceptance |
| Splits | Bato-owned native Chromium pairs; saved pair controls; lazy member opening/live reuse; menu-driven divider ratio; exact clean-quit persistence and same-binary restart | Pointer divider resizing, keyboard/focus acceptance and broader split compatibility |
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

Split pairs now have stable Bato ownership, native controls and saved pair metadata over actual Chromium splits. Bounded host checks passed opening an unloaded second member, interaction in both panes, Pin/Separate/reopen, live reuse and workspace switching. A navigated saved side retained its saved destination; Cmd+W Cancel preserved the page and activity, Leave selected the surviving side, and reopening used the saved URL. Menu-driven Widen Left visibly resized the pair from 0.5 to 0.6. All 116 Swift tests passed, including generation, failure, persistence and split-side-focus regressions. See [split-pair results](spikes/engine-native-slot/SPLIT-PAIRS-RESULTS.md).

The first split run quit cleanly but incorrectly cleared active-pair metadata through anchor recovery. The client now gates recovery against the authoritative active browser. With the final binary, the second normal Quit exited 0 and preserved exact pre-quit/final organization bytes, including the active pair and the 0.6 ratio. The same-binary third launch restored the stable pair UUID, ordered members and the 0.6 ratio as actual side-by-side pages; left-page activity advanced 0→1. Its normal Quit exited 0 with exactly one detach, message-loop return and completed shutdown. Root verified third-launch before/final bytes exactly equal the second final bytes. The prior organization remains untouched, and final state excluding split metadata exactly matches the original baseline pages, URLs, folders and selection. Direct pointer drag and AX slider Right/value-input attempts produced no confirmed divider change; Tab traversal remained in the native address field for an unknown reason. These pointer/focus checks are open. Observed native-ratio debouncing is implemented and covered by tests; only menu-driven ratio changes and persistence are runtime-accepted here.

## Next milestones

Reference research on 2026-11-01 added 43 private Dia screenshots with accessibility snapshots, a searchable gallery, coverage index and file manifest. Captures include Apps/Slack connection, grouping preferences and generated group, completed public-page and Slack chat answers, splits and settings. This adds reference coverage, not Bato functionality or completion percentage. See [reference library](REFERENCES.md); personal screenshots stay outside this public repo. AI remains deferred in V1.

1. Add Peek preview, dismiss and promotion. Retain pointer-divider/focus acceptance as explicit open gates; saved pairs and native controls are implemented within recorded limits.
2. Continue remaining browser-chrome polish, nested organization and preferences alongside broader window/lifecycle acceptance.
3. Add remaining Profile/import/blocking/essential workflows and release readiness.

Use bounded subagents for implementation and review. Keep verification proportional: targeted model/runtime tests and a short real-host check for affected behavior; repeat heavy engine/dependency checks when engine integration or dependencies change, rather than for every metadata or visual edit. Keep remaining acceptance gates explicit without reopening the full extension matrix for unrelated application changes.
