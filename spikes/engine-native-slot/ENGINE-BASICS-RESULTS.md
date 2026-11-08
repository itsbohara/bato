# Engine basics results

Run 2026-11-08 on a throwaway instance: `launch-engbasics-v1.py` (state `runtime/engbasics-state-v1` cloned from `sidebar-seed`, Profile `runtime/profiles/engbasics-v1`, `--use-mock-keychain`, `--autoplay-policy=no-user-gesture-required` for the audio fixture only). Window selected by pid, quit through the app menu (exit 0, `logs/engbasics-v1-exit.json`). Build: `logs/engine-basics-build-v1.log` (exit 0). Screenshots: `/Volumes/Mahesh/personal/bato-build/tmp/sbs-shots/engine-basics-*.png`.

| # | Item | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Cmd-Shift-N private window is Bato-like | pass with a gap | 05: no horizontal tab strip, Chromium's vertical tab strip in a dark private tint, "Incognito" chip, no AI Mode chip. Gap: it is Chromium's own vertical strip, not Bato's native sidebar or card styling, and Bato does not track its tabs |
| 2 | AI Mode chip and entry points removed | pass | `AimEnabled` disabled in workspace mode (02, 05 omnibox focused, no chip). Not checked: the View menu "Always Show AI Mode" item |
| 3a | Audio state exported per tab | pass | `bato_native_slot_register_audio_callbacks_v1`, `bato_native_slot_set_muted_v1` present in the framework (`nm`); `BatoSwiftAudioConfigure/Changed` in `libBatoNativeSlot.dylib` |
| 3b | Speaker glyph on an audible row | pass | 03: `speaker.wave.2.fill` right of the title, title still truncates before it |
| 3c | Click toggles mute | pass | 04: row shows `speaker.slash.fill`, AX label "Unmute tab"; second click back to "Mute tab" |
| 3d | Badge follows the row off-selection | pass | 06: tab keeps playing and keeps its glyph while another tab is selected |
| 3e | Badge disappears when audio stops or tab closes | not driven | covered by unit tests only (`TabAudioTests`); the fixture's Pause button was not reachable through AX |
| 4 | Profile avatar hidden in the toolbar | pass | 01, 03, 06: toolbar shows only back/forward/reload, address field, star and three-dot menu. The private window keeps the Incognito badge on purpose |
| 5 | chrome://history "Sync history" promo hidden | pass (no A/B) | 06: no promo banner (`UnoPhase2FollowUp` disabled). Not compared against the previous build |

## Changes by layer

- Engine (`engine.patch`, 30 files): `chrome_content_browser_client_cef_mac.mm` (audio observer, two exports), `bato_native_slot.h` (22 exports now), `avatar_toolbar_button_interface.cc` (no avatar for regular Profiles), `vertical_tab_strip_state_controller_impl.cc` (incognito windows show vertical tabs).
- Client (`client.patch`): `cefsimple_mac.mm` disables `AimEnabled` and `UnoPhase2FollowUp` in workspace mode; `native_slot_client.mm` registers the audio callbacks and forwards them to Swift (additive, like downloads); `WorkspaceSlot.swift` maps browser id to entry id; `BUILD.gn`, `compile_native_slot.py` list the new `TabAudio.swift`.
- Swift (`app/Sources/BatoBrowserUI/TabAudio.swift`, one hook line in `NativeWorkspaceController.swift`): `TabAudioCenter` state and the row badge; `TabAudioTests.swift`.
- Tests: `test_patch.py` export count 20 to 22.

## Open items

- Private window is not a Bato window. A native sidebar for an off-the-record Profile needs the client to run a second, non-persisting workspace; not attempted.
- The private window's vertical-tabs switch is made through the shared pref service. No `vertical_tabs.enabled` key reached the Profile's Preferences file after a clean quit, but a regular stock window opened in the same session was not inspected.
- Audio "audible" is Chromium's flag (the same one as the stock tab badge); a muted tab shows the slash glyph until unmuted or closed.
- `native_slot.py check` reports `client/WorkspaceSlot.swift` differing from staging: the concurrent menu work edited it after this run's regenerate. Re-mirror and regenerate before the next build.
