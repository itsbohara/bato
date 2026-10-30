import Foundation
import SwiftUI
import BatoCore
import BatoPersistence

@MainActor
final class ShellSession: ObservableObject {
    @Published private(set) var state: BrowserState?
    @Published var errorMessage: String?
    @Published var showsCommandBar = false
    @Published var sidebarVisible = true
    private let store: OrganizationStore<BrowserState>

    init(directory: URL) {
        store = OrganizationStore(directory: directory, validate: { try $0.validate() })
        do {
            if let restored = try store.load() {
                state = restored
            } else {
                let initial = BrowserState.initial()
                try store.save(initial)
                state = initial
            }
        } catch {
            errorMessage = "Bato couldn’t open its organization. The existing file has been left intact."
        }
    }

    // Publish a mutation only after persistence succeeds. The visible model and
    // committed file therefore describe the same organization after every action.
    @discardableResult
    func change(_ mutate: (inout BrowserState) throws -> Void) -> Bool {
        guard var candidate = state else { return false }
        do {
            try mutate(&candidate)
            try candidate.validate()
            try store.save(candidate)
            state = candidate
            return true
        } catch {
            if let error = error as? OrganizationStore<BrowserState>.StoreError, error == .conflict {
                errorMessage = "Organization changed outside this session. Close and reopen the preview to load the latest version."
            } else {
                errorMessage = "This change couldn’t be saved. Your previous organization is still active."
            }
            return false
        }
    }

    func addTab(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false,
              url.user == nil, url.password == nil else {
            errorMessage = "Enter a website address using HTTP or HTTPS."
            return false
        }
        return change { state in
            _ = try state.addTab(url: url, title: url.host ?? "New tab")
        }
    }

    func addWorkspace() {
        guard !showsCommandBar, let state else { return }
        change { candidate in
            let id = try candidate.addWorkspace(name: "Workspace \(state.workspaces.count + 1)",
                                               profileID: state.currentWorkspace.profileID)
            try candidate.activateWorkspace(id)
        }
    }

    func closeSelection() {
        if showsCommandBar { showsCommandBar = false; return }
        guard let id = state?.currentWorkspace.activeEntryID else { return }
        change { try $0.closeEntry(id) }
    }
}
