# Bato

A native macOS browser with an Arc-inspired interface, built with Swift and Chromium.

## Status

Provisional alpha development has started on Apple Silicon. The first native [organization preview](app/README.md) implements workspace, Favorite, pin and temporary-tab state with local persistence. It does not render web pages yet. The source-built CEF/native-host experiments and selected extension behavior have been exercised; complete compatibility and daily-use readiness remain open. See the [evidence matrix](FEASIBILITY-RESULTS.md).

## Direction

- Native Swift interface with Arc-like layout, Bato branding, and workspace colors.
- Workspaces with shared or isolated Profiles; Profile-wide Favorites and workspace pins, folders, and temporary tabs.
- Floating command bar, Peek, split pairs, local storage, optional archive, and Arc organization import.
- Chrome extension compatibility targets: Bitwarden, AdGuard AdBlocker, and MetaMask.
- Built-in ad/tracker blocking enabled by default, with per-site exceptions.
- AI chat and cross-device sync are deferred beyond V1.

The source-built CEF/native-slot path is the provisional integration candidate. Remaining extension and native-host acceptance continues alongside application work; production foundation selection remains open.

## Project documents

- [Design](DESIGN.md)
- [Chromium feasibility](CHROMIUM-FEASIBILITY.md)
- [Arc import and blocking](IMPORT-AND-BLOCKING.md)
- [Work plan](TASK.md)
- [Build the native organization preview](app/README.md)
- [Run the feasibility harness](spikes/cef-baseline/README.md)
- [Controlled test fixtures](spikes/fixtures/README.md)

## Development

Development uses focused subagents, with integration and verification coordinated in the main chat. Runtime data, private browsing captures, credentials, and browser profiles must never be committed.

## License

Bato is licensed under the [MIT License](LICENSE). Dependencies retain their own licenses and notices.
