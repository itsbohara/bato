# Browser essentials plan: history, downloads, settings

Reference: Dia's Settings is a standalone native window (left rail of panes, rounded grouped rows, switches, pill buttons); history and downloads are ordinary pages. UI notes derive from the private capture library (settings 10, 11, 16); no capture is copied here. No Ardia code is used.

## What Chromium already gives us

Each Bato Profile is its own Chrome profile and request context, so Chromium already keeps these per Profile:

- `chrome://history`: full history UI, search, delete, Clear browsing data.
- `chrome://downloads`: list, open, show in Finder, cancel, resume, plus the toolbar download bubble in the Chromium toolbar row.
- `chrome://settings`: search engine, passwords, permissions, languages, and so on.

Bato does not rebuild any of these. Dia does the same: they are web pages.

## What Bato owns natively

Only things that are Bato-specific and have no Chromium page:

- Settings window (Cmd-,): Profiles, Privacy (per-Profile blocking switch and exceptions), Import (Arc), Shortcuts (reference), Advanced (links to the Chromium pages above).
- Later: a sidebar downloads indicator (needs download events from the client), Appearance (needs a persisted store), per-Profile data clearing.

## How each is reached

| Destination | Menu / shortcut | Command bar | Route |
| --- | --- | --- | --- |
| History | Chromium History menu, Cmd-Y | "History" | `IDC_SHOW_HISTORY` intercepted in `BatoWorkspaceChromeCommand` (command 5) |
| Downloads | Chromium Window menu, Shift-Cmd-J | "Downloads" | `IDC_SHOW_DOWNLOADS` (command 6) |
| Settings | App menu Settings, Cmd-, | "Settings" | `IDC_OPTIONS` (command 7) opens the native window |
| Chromium settings | Settings > Advanced > Open | none | opens `chrome://settings/` |

Because every route funnels through the same Chromium command id, the menu, the accelerator and the command bar all behave identically.

## Per Profile

`PageRuntime.openEssential` selects the essential's tab in the current Workspace or opens it there. A Workspace belongs to one Profile, so the page is created in that Profile's Chromium window and context. Each Profile therefore has its own History and Downloads tab; one is never reused across Profiles. The essentials are normal organized temporary tabs (sidebar row, close, restore).

## Safety

`BrowserEssential.accepts` allows exactly `chrome://history|downloads|settings` with no path, query, fragment or credentials. Organization validation and the client's page-creation check use that same allowlist; navigation, Peek and icon fetches stay web-only.

## First slice (implemented)

1. Essentials model, allowlist and runtime open/reuse.
2. Command-bar entries and Chromium command interception.
3. Native Settings window (Profiles, Privacy, Import, Shortcuts, Advanced).
4. Tests; engine-side changes limited to the client files.

## Later slices

Sidebar downloads indicator and progress; Appearance and persisted Bato preferences; per-Profile clear-data entry; settings deep links from the command bar.
