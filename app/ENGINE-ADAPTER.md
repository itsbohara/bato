# Chromium page adapter

The organization preview remains separate from the source-built browser. `BatoRuntime` defines the next connection: stable organization IDs map to process-local `LivePage` generations, never persisted CEF identifiers. Its fake-engine tests establish coordinator behavior; they do not establish Chromium integration.

## Coordinator contract

`PageRuntime` accepts a validated committed document, a main-actor `PageEngine`, and a throwing commit closure. Initialize and wire engine callbacks before calling `start()`. Only the selected entry loads; other restored entries remain unloaded. Switching to an already loaded entry reuses its generation. Pages in inactive workspaces can remain loaded. A Profile must appear in the adapter's supported set before activation or engine effects; a UUID does not create a Chromium request context.

Organization mutations commit before publication and engine creation. A command can commit successfully and then report `creationRejected`; the committed entry remains available for retry. Creation failure is distinct from physical closure. Navigation callbacks update the session destination/title while preserving a saved destination. Unsupported/internal URLs and embedded credentials are ignored by the organization model.

Closing a loaded entry requests an engine close. Only the matching `closed` callback removes a temporary entry or resets/unloads a saved entry. A cancelled beforeunload must report `closeCancelled`, retaining the entry. A failed save after physical closure leaves the committed entry unloaded; it does not immediately recreate it. Old generations cannot navigate or close a reopened entry.

## Exact pinned CEF seam

The authored native-slot `active_browser_id_v1` export resolves a live, unblocked window token to its active WebContents and CEF browser identifier. It returns zero when unavailable. Resolve that identifier with public `CefBrowserHost::GetBrowserByIdentifier`. The diagnostic native navigation action targets the current page on each explicit action; it is not a stable organization binding.

The full adapter must bind a generation to one fixed browser identifier, verify its request context with `IsSame`, and retain a `CefRefPtr` for operations. Navigate through `GetMainFrame()->LoadURL`; select through `GetHost()->SetFocus(true)`. In this pinned Chrome host, setting focus selects that browser's tab. Close through `CloseBrowser(false)` and await `OnBeforeClose`, preserving beforeunload.

Do not bind or focus inline in `OnAfterCreated`: `ChromeBrowserDelegate::CreateBrowserHost` calls `Attach` and the callback before `SetBrowser` and before tab-strip insertion completes. Retain the reference and post reconciliation to the CEF UI thread. Main-frame `OnAddressChange` and `OnTitleChange` must copy callback strings and route them by the fixed binding, even when another page is active.

`CreateBrowser` creates another normal window. Same-window tab creation needs a bounded checked `IDC_NEW_TAB` command and an unambiguous returned browser identity after dispatch. Do not guess which later `OnAfterCreated` belongs to a command. Source and runtime verification of that creation contract, close-cancellation notification, and blank/unloaded selection are still required before implementing the real `PageEngine` adapter. Do not substitute separate CEF windows or hide these limitations behind the organization preview.

## Next acceptance

Wire the actual native sidebar/session to the adapter, then demonstrate selected-entry creation, switching without accidental re-navigation, navigation/title persistence, saved reset, temporary close, beforeunload cancellation, and lazy clean restart. Restrict the first integration to one explicitly bound engine Profile. Multi-Profile isolation, native split ownership and remaining extension acceptance continue as separate gates.
