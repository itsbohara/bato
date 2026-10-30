# Organization slice acceptance

Date:2026-10-30. Swift6.2.4, Xcode26.3(17C529), macOS27.0.1, Apple Silicon. This is a native organization preview, not a working browser or completed personal alpha.

## Automated verification

The final Swift package suite covers11 core cases,9 store cases and3 shell-session cases. Core tests exercise saved-vs-session destinations, stable IDs/order, Profile-wide Favorites, workspace ownership, temporary closure, invalid schemas/credentials and rollback on rejected commands. Store tests exercise actual round trips, backups, corrupt/unsupported preservation, stale writers, unsafe targets, permissions and write failures. Session tests establish that an external newer commit cannot be overwritten or published as a successful change, failed loads remain uneditable, and closing the command bar preserves the selected entry.

The initial shell-session test compilation needed an explicit inner `try` in a Swift Testing macro; corrected before the final suite. No weakened checks or disabled tests.

## Native runtime observations

Through actual native computer control on a dedicated synthetic store:

- First launch created an empty Personal Profile/workspace. Cmd+T opened the floating address entry; AX identified its editable field. The initial SwiftUI focus request failed to receive typing. A native NSTextField now requests focus when attached to its window; after observing field focus, typing/Enter created the entry.
- Command-bar background controls were disabled and absent from the active accessibility tree. Three Tab attempts retained the native address field under the current Mac keyboard settings. Escape dismissed the bar. This is not complete keyboard/full-accessibility acceptance.
- Right-click context-menu Pin converted a temporary entry. After observing that conversion, Cmd+W cleared selection while preserving the pin. A separate temporary entry was removed by Cmd+W. No live renderer unload is implied.
- A Favorite remained visible in a second workspace sharing its Profile; the first workspace’s pin was absent there. The new workspace became active. Cmd+S hid/restored the sidebar.
- Normal Cmd+Q exited0. Restart restored2workspaces,1Favorite,1pin,1temporary entry and active workspace/selection. Before/after organization JSON compared equal, including stable IDs and order. The native tree showed the selected temporary destination and shared Favorite.
- A separate deliberately invalid synthetic document produced an alert and unavailable-organization view. Cmd+T exposed no editing controls. Quit exited0 and the invalid bytes remained unchanged.

Two automated action batches were too fast for UI transitions: Pin immediately followed by Cmd+W closed the temporary entry before the deferred menu action ran; a later rapid Cmd+T/type sequence dropped the first character before field attachment. Both were rejected visibly without corrupting the store; repeating with fresh focus/action observations passed. These observations do not establish timing behavior for real typing and should inform later command-bar integration.

All organization fixtures and generated bundles remain under the SSD workspace. No real browser data, private screenshots, credentials or engine Profiles were used. Engine source and build artifacts were unchanged.

## Next slice

Connect the organization/session and native sidebar to the source-built Chromium adapter. Map stable page IDs to live engine pages, apply Profile ownership, and feed navigation/title/close events back through validated commands. Retain the saved destination independently from live navigation and preserve lazy restore. Then continue remaining extension/focused-split, pointer-divider and modal-input acceptance. The provisional shell does not select a production engine foundation.

## Live-page coordinator follow-up

On2026-10-30, added `BatoRuntime` with14 fake-engine tests. The complete package suite now passes37 tests:11 core,9 store,3 shell-session and14 runtime. Initialization has no engine effects; explicit start restores selection. The runtime loads only the selected entry, reuses loaded generations, rejects unsupported Profiles before effects, and persists changes before publication/creation. Engine-confirmed closure controls saved reset/temporary removal; cancellation retains organization, including navigation received while a close was pending. Invalid URLs and stale generation callbacks are ignored.

Independent review caught stale visible content after failed creation and after physical closure followed by a failed save. Both paths now reconcile the engine's visible selection, including hiding it when the committed selected entry is unloaded. Tests cover these foreground/background failures and synchronous creation/navigation callbacks that change selection. Review found no remaining blockers in this coordinator slice.

These are coordinator tests, not Chromium adapter acceptance. The organization preview remains unchanged and does not render pages. The separate source-built native-slot diagnostic now navigates actual Chromium pages; see its results and [the connection contract](ENGINE-ADAPTER.md). Same-window creation, stable binding, navigation/title callbacks, close cancellation, and unloaded-content selection must still be implemented in the real adapter.
