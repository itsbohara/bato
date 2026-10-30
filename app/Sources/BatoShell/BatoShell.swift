import SwiftUI
import AppKit
import BatoCore

@main
@MainActor
struct BatoShell {
    static func main() {
        let app = NSApplication.shared
        let delegate = ShellDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class ShellDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var session: ShellSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let directory: URL
        if let index = arguments.firstIndex(of: "--state-directory"),
           arguments.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
                .appendingPathComponent("Bato Shell Preview", isDirectory: true)
        }
        let session = ShellSession(directory: directory)
        self.session = session
        configureMenu()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Bato · Shell preview"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 780, height: 540)
        window.contentView = NSHostingView(rootView: ShellView(session: session))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureMenu() {
        let bar = NSMenu()
        func menu(_ name: String) -> NSMenu {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: name)
            item.submenu = menu
            bar.addItem(item)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, in menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        item("Quit Bato Shell Preview", #selector(quit), "q", in: menu("Bato"))
        let file = menu("File")
        item("New Tab", #selector(newTab), "t", in: file)
        item("New Workspace", #selector(newWorkspace), "", in: file)
        item("Close Selected Tab", #selector(closeTab), "w", in: file)
        let edit = menu("Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        item("Toggle Sidebar", #selector(toggleSidebar), "s", in: menu("View"))
        NSApp.mainMenu = bar
    }

    @objc private func newTab() { session?.showsCommandBar = true }
    @objc private func newWorkspace() { session?.addWorkspace() }
    @objc private func closeTab() { session?.closeSelection() }
    @objc private func toggleSidebar() { session?.sidebarVisible.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

private struct ShellView: View {
    @ObservedObject var session: ShellSession
    @State private var address = ""

    private let accent = Color(red: 0.66, green: 0.40, blue: 0.43)

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let state = session.state {
                HStack(spacing: 0) {
                    if session.sidebarVisible { sidebar(state) }
                    destination(state)
                        .padding(.trailing, 10).padding(.vertical, 10)
                        .padding(.leading, session.sidebarVisible ? 0 : 10)
                }
                .disabled(session.showsCommandBar)
                .accessibilityHidden(session.showsCommandBar)
                if session.showsCommandBar { commandBar }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 32))
                    Text("Organization unavailable").font(.title2.weight(.semibold))
                    Text("Close this preview and check its organization file before trying again.")
                        .foregroundStyle(.secondary)
                }.padding(40)
            }
        }
        .alert("Couldn’t complete this change", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) { Button("OK") { session.errorMessage = nil } }
        message: { Text(session.errorMessage ?? "") }
    }

    private func sidebar(_ state: BrowserState) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("bato").font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Text("SHELL PREVIEW").font(.system(size: 8, weight: .semibold)).tracking(1)
                    .foregroundStyle(.secondary)
            }.padding(.top, 24)
            Button { session.showsCommandBar = true } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New tab")
                    Spacer()
                    Text("⌘T").foregroundStyle(.tertiary)
                }.padding(10)
            }
            .buttonStyle(.plain)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let profile = state.profiles.first(where: { $0.id == state.currentWorkspace.profileID }) {
                        entrySection("Favorites", entries: profile.favorites, state: state)
                    }
                    entrySection("Pinned", entries: state.currentWorkspace.pins, state: state)
                    entrySection("Tabs", entries: state.currentWorkspace.tabs, state: state)
                }
            }
            Spacer(minLength: 0)
            Divider().opacity(0.5)
            HStack {
                Circle().fill(accent).frame(width: 8, height: 8)
                Menu {
                    ForEach(state.workspaces) { workspace in
                        Button(workspace.name) { session.change { try $0.activateWorkspace(workspace.id) } }
                    }
                    Divider()
                    Button("New Workspace") { session.addWorkspace() }
                } label: {
                    Text(state.currentWorkspace.name).fontWeight(.medium)
                }.menuStyle(.borderlessButton)
            }
            Text(profileName(state)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.bottom, 20)
        .frame(width: 254)
        .background(accent.opacity(0.09))
    }

    private func profileName(_ state: BrowserState) -> String {
        state.profiles.first(where: { $0.id == state.currentWorkspace.profileID })?.name ?? ""
    }

    private func entrySection(_ title: String, entries: [PageEntry], state: BrowserState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold))
                .tracking(1.3).foregroundStyle(.secondary).padding(.horizontal, 8)
            if entries.isEmpty {
                Text(title == "Tabs" ? "Your open tabs appear here" : "No \(title.lowercased()) yet")
                    .font(.caption).foregroundStyle(.tertiary).padding(8)
            }
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Button {
                        session.change { try $0.selectEntry(entry.id) }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: entry.kind == .favorite ? "star" : entry.kind == .pinned ? "pin" : "globe")
                                .frame(width: 16).foregroundStyle(.secondary)
                            Text(entry.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { session.change { try $0.closeEntry(entry.id) } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                    }.buttonStyle(.plain)
                        .help(entry.kind == .temporary ? "Close tab" : "Unload saved page")
                        .accessibilityLabel(entry.kind == .temporary ? "Close \(entry.title)" : "Unload \(entry.title)")
                }
                .padding(.horizontal, 9).padding(.vertical, 9)
                .background(state.currentWorkspace.activeEntryID == entry.id ? accent.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contextMenu {
                    if entry.kind == .temporary {
                        Button("Pin Tab") { session.change { try $0.pinEntry(entry.id) } }
                        Button("Add to Favorites") { session.change { try $0.favoriteEntry(entry.id) } }
                    }
                }
            }
        }
    }

    private func destination(_ state: BrowserState) -> some View {
        let selected = state.visibleEntries.first { $0.id == state.currentWorkspace.activeEntryID }
        return VStack(spacing: 0) {
            HStack {
                if !session.sidebarVisible {
                    Button { session.sidebarVisible = true } label: { Image(systemName: "sidebar.left") }
                        .buttonStyle(.plain).help("Show sidebar")
                }
                Spacer()
                Text(selected?.lastURL.host ?? "Bato").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.frame(height: 46)
            Divider().opacity(0.4)
            Spacer()
            VStack(spacing: 15) {
                Image(systemName: selected == nil ? "square.stack.3d.up" : "globe")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(accent)
                Text(selected?.title ?? "A place for your next idea")
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                Text("Organization preview · web pages aren’t connected yet")
                    .font(.callout).foregroundStyle(.secondary)
                if let selected {
                    Text(selected.lastURL.absoluteString).font(.caption.monospaced())
                        .foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                } else {
                    Button("New tab") { session.showsCommandBar = true }
                        .buttonStyle(.bordered)
                }
            }.padding(40)
            Spacer()
            Text("Workspace and tab changes are saved on this Mac")
                .font(.caption2).foregroundStyle(.tertiary).padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06), lineWidth: 1))
    }

    private var commandBar: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { session.showsCommandBar = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    AddressField(text: $address, submit: addAddress,
                                 cancel: { session.showsCommandBar = false })
                        .frame(height: 26)
                }
                Divider()
                HStack {
                    Text("Add to \(session.state?.currentWorkspace.name ?? "workspace")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { session.showsCommandBar = false }
                    Button("Add tab", action: addAddress).buttonStyle(.borderedProminent).tint(accent)
                }
            }
            .padding(20).frame(width: 510)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 30, y: 12)
            .padding(.top, 90)
            .onExitCommand { session.showsCommandBar = false }
        }
    }

    private func addAddress() {
        if session.addTab(address) {
            address = ""
            session.showsCommandBar = false
        }
    }
}

private struct AddressField: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CommandAddressField {
        let field = CommandAddressField()
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 18)
        field.placeholderString = "Enter a website address"
        field.setAccessibilityLabel("Website address")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: CommandAddressField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        init(_ parent: AddressField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.submit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.cancel()
                return true
            }
            return false
        }
    }
}

private final class CommandAddressField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Request focus only after the actual AppKit field joins its window.
        window?.makeFirstResponder(self)
    }
}
