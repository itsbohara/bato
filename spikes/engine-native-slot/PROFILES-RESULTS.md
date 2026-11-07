# Multi-Profile and visual polish: real-host results

**profiles-v1 (below, sections A-C) crashed on Quit (exit -11) and is superseded by profiles-v2 and profiles-v3 at the end of this file; v2 and v3 guarded on `logs/integrate-v3-exit.json` and `logs/profiles-v2-exit.json`.**

Run `profiles-v1` on 2026-11-07, uncommitted build, wrapper `tmp/launch-profiles-v1.py` (guard `logs/integrate-v3-exit.json` exit 0), fresh state `runtime/profiles-state-v1` cloned from split-pairs-state-v1, `--use-mock-keychain`, cache path `runtime/profiles/workspace-v3` (launch Profile), synthetic Arc file `tmp/arc-fixture/StorableSidebar.json`, fixture server 127.0.0.1:18765 (revalidated, still running). Logs and screenshots are private under the SSD `logs/profiles-v1*`. No source changed, nothing committed or rebuilt.

**Overall: isolation and window routing work; persistence does not (D1), and Quit with three windows crashed (D2).**

## A. Profiles
- Import created Profiles `Arc` (EB7E187B) and `Arc - Profile 1` (C7B9998D) with workspaces Work, Space 2 (Arc) and Side (Arc - Profile 1).
- Selecting an Arc pin opened exactly one new window (list-windows 1 to 2, cascaded +22pt); the Side pin opened a third. The launch window stayed on the launch Profile.
- Directories created: `<cache>/Default/EB7E187B-...` and `<cache>/Default/C7B9998D-...`, empty. No new top-level entry in `<cache>`. See D1: this is not `<cache>/<UUID>`.
- Storage isolation (localStorage, cookie, IndexedDB, CacheStorage on 127.0.0.1:18765): launch Profile wrote `bato-shared-a`; Profile B first read all null; B wrote `bato-b-value`; launch Profile read back `bato-shared-a` (unchanged). Closing the B window and reselecting the B page opened a new window (reopen uses the saved URL, example.test, so the storage page was re-navigated by hand) and it read `bato-b-value` for localStorage, cookie and IndexedDB, sessionStorage null. This holds only in memory (D1).
- Sidebar follows the key window: clicking the launch window changed its sidebar to Personal while the Arc window showed Work. One earlier instance (11-launch-window-after-b.png) showed Work in the launch window right after raising it; intermittent, not reproduced.
- Cross-Profile split: not constructible through the UI. Move to Workspace lists only same-Profile workspaces (Space 2 for a Work pin) and splits are per workspace; engine refusal is covered by ProfileRoutingTests only.
- Relaunch persistence: not run. The v1 exit receipt is -11, so the discipline guard blocks a v2 wrapper, and D1 means contexts are in-memory anyway.
- Quit with three windows through "Bato Quit application": organization bytes unchanged (pre-quit == final) but exit code -11 (D2).

## B. Visual
- Traffic lights: AX frames y 46-62 (centre 54) against the toolbar 31-77 (centre 54), identical in the launch and Profile windows and with the sidebar hidden. Pass.
- Sidebar spans the full window height (y 31, h 1040) with the workspace name beside the lights; toolbar starts at x 360, the sidebar edge. Pass.
- Tint visible: Work warm brown, Research and Personal subtle cool grey, selected row picks up the accent (orange in Work). Compared with Dia 02-new-tab.jpg, Dia's tint is stronger and its label sits with a clear gap after the lights.
- Hidden sidebar (toggle button, restored with Sidebar > Toggle Sidebar menu): toolbar goes full width, lights still centred. Pass.
- Fullscreen enter and exit (green button, exit by physical click at the light): worked, sidebar restored with the same layout. Fullscreen shows Chromium's stock tab strip, including a second `about:blank` tab in Profile windows (known from compact-folders).
- Omnibox on about:blank: the field holds the literal text `about:blank` (AX value), focused, not a placeholder. Default search engine name unchecked: `chrome://settings/search` did not navigate from the omnibox.

## C. Import sheet
- Preview: rows start at the top of the list (3 rows then empty list area); summary "3 workspaces in 2 new Profiles - 13 pins - 6 folders - 3 favorites - 0 tabs". Pass.
- Reopening with the same file: every row "Already imported from this file", unchecked and disabled, summary all zeros, Import disabled. Ticking "Import already imported spaces again as copies" enables the rows, restores 13/6/3 counts and enables Import. Cancelled. Pass.

## Defects
- **D1 (high): contexts are not persistent.** `OpenProfileWindow` uses `GetGlobalContext()->GetCachePath()` which is `<cache>/Default`, so contexts request `<cache>/Default/<UUID>`. CEF logs `Cannot create profile at path .../Default/<UUID>` (one per Profile) and falls back to an off-the-record profile; `leveldb_proto` logs "In memory database cannot use the given directory". Empty directories are created but nothing is stored, so cookies and storage are lost at quit. The path must be a direct child of the user data dir (`<cache>`), not of `Default`.
- **D2 (high): Quit with three windows exits -11.** SIGSEGV in `BrowserNativeWidgetMac::OnWidgetActivationChanged` to `BrowserView::IsFullscreen` on a destroyed widget, reached from `windowDidResignKey` during window order-out (`logs/profiles-v1.log` line 166). Native quit markers all appeared, organization unchanged. integrate-v1 also exited -11 earlier.
- **D3 (medium): label crowds the green light.** The workspace label frame starts at x 195 while the green light ends at x 196 (1pt overlap); Work/Personal text touches the light. `trafficLightClearance` 62 plus inset 10 is too small for lights ending at 74.
- **D4 (medium): stale import completion text.** "New Profiles need browser Profile support that isn't connected yet, so these workspaces can be seen in the sidebar but not opened until it is." still shown after import although Profiles now open (04-import-complete.png).
- **D5 (low): pin titles overwritten by page title.** Opening pin Docs showed "example.test" (the error page title); after navigating it showed "Bato storage fixture B"; reopen reverted to the saved URL.
- **D6 (low): copies summary says "2 new Profiles"** although the file's Profiles already exist; unverified whether copies reuse them (cancelled).
- **D7 (low): My own mistake, not a defect.** An early Cmd-Shift-G was delivered to Chromium and opened find bar; closed.
- Notes: the sidebar content is hidden while a sheet is attached (pre-existing); the first click in web content only focuses the pane, so typing needs two clicks.

## Re-run on the fixed build: profiles-v2 and profiles-v3

Wrappers `tmp/launch-profiles-v2.py` (guard `integrate-v3-exit.json`, state `runtime/profiles-state-v2` cloned from split-pairs-state-v1) and `tmp/launch-profiles-v3.py` (guard `profiles-v2-exit.json`, state `runtime/profiles-state-v3` copied from profiles-state-v2's final organization, same cache path). Logs `logs/profiles-v2*`, `logs/profiles-v3*`, screenshots in `logs/profiles-v{2,3}-shots/`. Neither log contains `Cannot create profile` or `profile-window-refused`.

### v2 (fixed build, import then three windows)
- Import completion copy is now "Each new Profile keeps its own logins and site data in a separate browser window, opened the first time you use one of its workspaces." (D4 fixed).
- D1 fixed: opening Arc and Arc - Profile 1 pins created `<cache>/EB7E187B-...` and `<cache>/C7B9998D-...` (direct children of the cache path; the stale empty `Default/<UUID>` dirs from v1 remain). They hold real profile data: 3.6M and 3.5M with Cookies, LocalStorage(-wal), IndexedDB, Cache and others.
- Isolation holds: Arc profile first read all null, wrote `bato-b-value`; the launch Profile still read `bato-shared-a`.
- D3 fixed: the label now has a clear gap after the green light (matches Dia's spacing).
- Quit with three windows through the app menu: markers once each (`sample-native-quit-requested` 1, three `native-slot-detached`, seven `closed` browsers down to 0, `sample-quit-message-loop-requested`), but **the process did not exit** (D8). Main thread idle in the run loop for about 5 minutes; `close-app` timed out. I sent SIGTERM to my owned pid, which exited 0 (`logs/profiles-v2-exit.json`). Organization pre-quit == final. The exit 0 therefore is not a natural exit.

### v3 (relaunch, persistence)
- Start organization == v2 final. The app opened a window directly for the saved selection (Side).
- B persistence: Work and a navigation to storage.html in the Arc window read `bato-b-value` for localStorage, cookie, indexedDB and cacheStorage (sessionStorage null, expected). **Pass.**
- Launch Profile persistence: **fails (D9).** Selecting Personal opened a window that read null everywhere, and a new empty `<cache>/3DAF918F-...` (3.4M) appeared. The Personal data written earlier lives in `<cache>/Default`. Because the saved selection at startup was a non-launch Profile, the launch Profile has no special handling and gets a fresh context. The Side window also read null (no cross-contamination).
- Quit with three windows through the app menu: same hang as v2 (D8); markers once per window (`native-slot-detached` 3, closed 7 to 0); SIGTERM exit 0 (`logs/profiles-v3-exit.json`). Organization pre-quit == final.

### D6 and D3 and D4 check
- D6 **not fixed**: with "import again as copies" ticked the summary still says "3 workspaces in 2 new Profiles", although both Profiles exist (`logs/profiles-v3-shots/06-copies.png`). Cancelled.
- D3, D4: fixed (see v2). D1, D2: D1 fixed; D2's crash did not recur but Quit now hangs (D8).

### New defects
- **D8 (high): Quit with multiple Profile windows hangs.** All browsers close, the quit message loop request is logged, but the process never exits (reproduced in v2 and v3). Likely suspect: Profile request contexts kept alive in the engine's per-Profile context map (unverified).
- **D9 (high): the launch Profile loses its identity when startup selection is another Profile.** It opens on a new `<cache>/<launchProfileUUID>` context instead of the global `Default` context, so its existing data disappears from view.

## profiles-v4: D9, D8 and D6 fixes

Wrapper `tmp/launch-profiles-v4.py`, guard `logs/integrate-v3-exit.json` (v2 and v3 exited 0 only after SIGTERM, so their receipts are not natural), state `runtime/profiles-state-v4` copied from profiles-state-v3's final organization (saved selection: Side, a non-launch Profile), same cache path. Logs `logs/profiles-v4*`, screenshots `logs/profiles-v4-shots/`, hang sample `logs/profiles-v4-hang-sample.txt`.

- **D9 not fixed.** Startup opened Side (about:blank launch window also present). Selecting Personal reused the about:blank window and created no new `<cache>/<UUID>` dir (dir list identical before and after), but the page read null instead of the earlier `bato-shared-a`, and the log shows "Multiple CacheStorage instances using the same directory detected". A Write marker in that Personal window updated `<cache>/C7B9998D-...` (Side's Profile) `LocalStorage-wal` and left `Default/LocalStorage-wal` untouched, so the Personal page ran in the Side Profile's context. The earlier value is still in `Default` (cookie and localStorage found there).
- **B values persisted.** Selecting Work opened the Arc window; storage.html read `bato-b-value` for localStorage, cookie, indexedDB and cacheStorage.
- **D8 not fixed.** Quit via the app menu with three windows logged `profile-contexts-released` (count 2, then 0), seven browsers closed, `sample-quit-message-loop-requested`, `native-quit-controller-returned` and three `native-slot-detached`, yet the process was still alive after 60 s and 3 min 54 s. The sample shows the main thread idle in `NSApplication run` with only a `CrShutdownDetector` thread; no thread was waiting on a profile. SIGTERM then exited 0 (`logs/profiles-v4-exit.json`; again not a natural exit). Organization pre-quit == final.
- **D6.** With "import again as copies" ticked the summary now reads "3 workspaces as copies in 2 new Profiles - 13 pins - 6 folders - 3 favorites - 0 tabs"; the all-imported state shows zero counts. Copies are labelled, but the text still says "2 new Profiles" for Profiles that already exist (`04-copies.png`). Cancelled.
- No `Cannot create profile` or `profile-window-refused` in the log.
