# Bato

A native macOS browser with an Arc-inspired interface, built with Swift and Chromium.

## Status

Pre-implementation research and design. No browser build or extension compatibility has been demonstrated yet. Apple Silicon is the initial target.

## Direction

- Native Swift interface with Arc-like layout, Bato branding, and workspace colors.
- Workspaces with shared or isolated Profiles; Profile-wide Favorites and workspace pins, folders, and temporary tabs.
- Floating command bar, Peek, split pairs, local storage, optional archive, and Arc organization import.
- Chrome extension compatibility targets: Bitwarden, AdGuard AdBlocker, and MetaMask.
- Built-in ad/tracker blocking enabled by default, with per-site exceptions.
- AI chat and cross-device sync are deferred beyond V1.

Chromium integration remains undecided. Extension behavior and native embedding must pass a feasibility gate before selecting the foundation.

## Project documents

- [Design](DESIGN.md)
- [Chromium feasibility](CHROMIUM-FEASIBILITY.md)
- [Arc import and blocking](IMPORT-AND-BLOCKING.md)
- [Work plan](TASK.md)

## Development

Development uses focused subagents, with integration and verification coordinated in the main chat. Runtime data, private browsing captures, credentials, and browser profiles must never be committed.

## License

Bato is licensed under the [MIT License](LICENSE). Dependencies retain their own licenses and notices.
