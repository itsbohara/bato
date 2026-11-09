import AppKit
import BatoCore
import BatoImport

/// What the first-run card needs from the app. Every closure runs on the main actor.
public struct OnboardingHooks {
    public var importer: BrowserImporter
    public var defaultSource: () -> ImportSource?
    /// Saves the snapshot into the current Profile as one transaction and returns a one-line result.
    public var commitImport: (BrowserSnapshot, Set<ImportItem>) -> Result<String, OnboardingImportFailure>
    public var applyLook: (_ theme: SpaceTheme?, _ appearance: AppAppearance) -> Void
    /// Called once when the card ends by any route, including Skip Setup.
    public var finished: () -> Void

    public init(importer: BrowserImporter, defaultSource: @escaping () -> ImportSource?,
                commitImport: @escaping (BrowserSnapshot, Set<ImportItem>) -> Result<String, OnboardingImportFailure>,
                applyLook: @escaping (SpaceTheme?, AppAppearance) -> Void, finished: @escaping () -> Void) {
        self.importer = importer
        self.defaultSource = defaultSource
        self.commitImport = commitImport
        self.applyLook = applyLook
        self.finished = finished
    }
}

public struct OnboardingImportFailure: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Bato's first-run card: a dimmed child window over the browser window with a centred card.
@MainActor
public final class OnboardingController: NSObject {
    private static let cardSize: CGFloat = 640

    private let parent: NSWindow
    private let hooks: OnboardingHooks
    private let panel: OnboardingPanel
    private let card = NSVisualEffectView()
    private var flow = OnboardingFlow()
    private var choices = OnboardingChoices()
    private var current: NSView?
    private var resizeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var importSummary: String?

    private var detected: [DetectedBrowser] = []
    private var detail: BrowserDetail?

    private struct BrowserDetail {
        var browser: DetectedBrowser
        var profileIndex = 0
        var selection: ImportSelection?
        var error: String?
        var isImporting = false
        var profile: DetectedProfile { browser.profiles[profileIndex] }
    }

    public init(parent: NSWindow, hooks: OnboardingHooks) {
        self.parent = parent
        self.hooks = hooks
        panel = OnboardingPanel(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.onEscape = { [weak self] in self?.back() }
        buildChrome()
    }

    public func show() {
        detected = BrowserDetector(home: hooks.importer.home).detect()
        parent.addChildWindow(panel, ordered: .above)
        panel.setFrame(parent.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: parent,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self.map { $0.panel.setFrame($0.parent.frame, display: true) } }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckAccess() }
        }
        present(animated: false)
    }

    private func close() {
        [resizeObserver, activeObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        parent.removeChildWindow(panel)
        panel.orderOut(nil)
        parent.makeKeyAndOrderFront(nil)
        hooks.finished()
    }

    // MARK: Flow

    private func advance() {
        flow.advance()
        flow.isEnded ? close() : present(animated: true)
    }

    private func back() {
        if flow.step == .bringOver, detail != nil {
            detail = nil
            present(animated: true)
        } else if flow.canGoBack {
            flow.goBack()
            present(animated: true)
        }
    }

    private func skip() {
        flow.skip()
        close()
    }

    private func finishLook() {
        hooks.applyLook(choices.theme, choices.appearance)
        advance()
    }

    // MARK: Chrome

    private func buildChrome() {
        let dim = NSView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        dim.layer?.cornerRadius = 10
        panel.contentView = dim

        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.appearance = NSAppearance(named: .darkAqua)
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        dim.addSubview(card)
        let width = card.widthAnchor.constraint(equalToConstant: Self.cardSize)
        let height = card.heightAnchor.constraint(equalToConstant: Self.cardSize)
        [width, height].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: dim.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: dim.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: dim.widthAnchor, constant: -40),
            card.heightAnchor.constraint(lessThanOrEqualTo: dim.heightAnchor, constant: -40),
            width, height,
        ])
    }

    private func present(animated: Bool) {
        let next = makeStepView()
        next.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(next)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: card.leadingAnchor), next.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            next.topAnchor.constraint(equalTo: card.topAnchor), next.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        let old = current
        current = next
        panel.makeFirstResponder(nil)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let old else {
            old?.removeFromSuperview()
            return
        }
        next.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            next.animator().alphaValue = 1
            old.animator().alphaValue = 0
        }, completionHandler: { old.removeFromSuperview() })
    }

    private func makeStepView() -> NSView {
        switch flow.step {
        case .welcome: welcomeView()
        case .bringOver: detail == nil ? browserGridView() : browserDetailView()
        case .makeItYours: makeItYoursView()
        case .done: doneView()
        }
    }

    // MARK: Welcome and done

    private func welcomeView() -> NSView {
        let start = OnboardingButton(title: "Get Started", style: .primary) { [weak self] in self?.advance() }
        let skip = OnboardingButton(title: "Skip Setup", style: .text) { [weak self] in self?.skip() }
        return centered([appIcon(120), spacer(8), title("Welcome to Bato"),
                         subtitle("A calm, organized browser. Let’s get you set up in a minute."), spacer(18),
                         fixedWidth(start, 275), skip])
    }

    private func doneView() -> NSView {
        let finish = OnboardingButton(title: "Start Browsing", style: .primary) { [weak self] in self?.advance() }
        var views: [NSView] = [appIcon(96), spacer(8), title("You’re all set"),
                               subtitle("Change any of this in Settings whenever you like.")]
        if let importSummary { views.append(subtitle(importSummary)) }
        return centered(views + [spacer(18), fixedWidth(finish, 275)])
    }

    private func centered(_ views: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -80),
        ])
        for case let button as OnboardingButton in views where button.style == .primary { button.keyEquivalent = "\r" }
        return container
    }

    // MARK: Bring everything over

    private func browserGridView() -> NSView {
        let header = header("Bring Everything Over", "Pick the browser you used before and choose what comes along.")
        let body: NSView
        if detected.isEmpty {
            body = emptyNote("Start fresh", "No other browsers were found on this Mac. Bato starts clean, and you can bring data over later from Settings.")
        } else {
            let defaultSource = hooks.defaultSource()
            let choices = BrowserChoice.choices(from: detected, defaultSource: defaultSource)
            let grid = NSGridView()
            grid.rowSpacing = 12
            grid.columnSpacing = 12
            for start in stride(from: 0, to: choices.count, by: 2) {
                let row = choices[start..<min(start + 2, choices.count)].map { choice in
                    BrowserCard(choice: choice) { [weak self] in self?.open(choice.source) } as NSView
                }
                grid.addRow(with: row + (row.count == 1 ? [NSView()] : []))
            }
            grid.column(at: 0).width = 276
            grid.column(at: 1).width = 276
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.documentView = FlippedView(wrapping: grid)
            body = scroll
        }
        return page(header: header, body: body, footer: footer(primary: "Continue", primaryEnabled: true,
                                                              onPrimary: { [weak self] in self?.advance() }))
    }

    private func open(_ source: ImportSource) {
        guard let browser = detected.first(where: { $0.source == source }), !browser.profiles.isEmpty else { return }
        detail = BrowserDetail(browser: browser)
        loadCounts()
        present(animated: true)
    }

    private func loadCounts() {
        guard let current = detail else { return }
        let importer = hooks.importer, source = current.browser.source, profile = current.profile
        Task { [weak self] in
            let counts = await Task.detached { importer.counts(source, profile: profile) }.value
            guard let self, self.detail?.browser.source == source, self.detail?.profile == profile else { return }
            self.detail?.selection = ImportSelection(source: source, counts: counts)
            self.refreshDetail()
        }
    }

    private func refreshDetail() {
        guard flow.step == .bringOver, detail != nil else { return }
        let old = current
        let next = browserDetailView()
        next.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(next)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: card.leadingAnchor), next.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            next.topAnchor.constraint(equalTo: card.topAnchor), next.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        current = next
        old?.removeFromSuperview()
    }

    private func recheckAccess() {
        guard detail?.selection?.access == .needsFullDiskAccess else { return }
        loadCounts()
    }

    private func browserDetailView() -> NSView {
        guard let state = detail else { return NSView() }
        let backPill = OnboardingButton(title: "‹  From \(state.browser.source.displayName)", style: .pill) { [weak self] in self?.back() }
        var rows: [NSView] = []
        var footerEnabled = false
        if let selection = state.selection {
            switch selection.access {
            case .needsFullDiskAccess:
                rows = [explanation("Safari keeps its data in a protected folder. Allow Bato in System Settings > Privacy & Security > Full Disk Access, then come back here.",
                                    action: ("Open Full Disk Access Settings", { Self.openFullDiskAccess() }))]
            case .nothingToImport:
                rows = [emptyNote("Nothing to bring over", "Bato didn’t find anything it can read in this browser.")]
            case .ready:
                rows = selection.rows.map { row in
                    ToggleRow(row: row) { [weak self] in
                        self?.detail?.selection?.toggle(row.item)
                        self?.refreshDetail()
                    }
                }
                footerEnabled = selection.canContinue && !state.isImporting
            }
        } else {
            rows = [subtitle("Checking what can be brought over…")]
        }
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.spacing = 1
        list.alignment = .leading
        rows.forEach { $0.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        var bodyViews: [NSView] = [list]
        if state.browser.profiles.count > 1 { bodyViews.insert(profilePicker(state), at: 0) }
        if let error = state.error { bodyViews.append(errorLabel(error)) }
        let body = NSStackView(views: bodyViews)
        body.orientation = .vertical
        body.spacing = 14
        body.alignment = .leading
        bodyViews.forEach { $0.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        return page(header: headerBlock(backPill, "Choose what to bring over", state.browser.subtitleNote), body: body,
                    footer: footer(primary: state.isImporting ? "Importing…" : "Continue", primaryEnabled: footerEnabled,
                                   onPrimary: { [weak self] in self?.runImport() }))
    }

    private func profilePicker(_ state: BrowserDetail) -> NSView {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: state.browser.profiles.map(\.name))
        popup.selectItem(at: state.profileIndex)
        let target = PopupTarget { [weak self] index in
            self?.detail?.profileIndex = index
            self?.detail?.selection = nil
            self?.loadCounts()
            self?.refreshDetail()
        }
        popup.target = target
        popup.action = #selector(PopupTarget.changed(_:))
        objc_setAssociatedObject(popup, &PopupTarget.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return popup
    }

    private func runImport() {
        guard var state = detail, let selection = state.selection, selection.canContinue, !state.isImporting else { return }
        state.isImporting = true
        state.error = nil
        detail = state
        refreshDetail()
        let importer = hooks.importer, source = state.browser.source, profile = state.profile, items = selection.selectedItems
        Task { [weak self] in
            let read = await Task.detached { () -> Result<BrowserSnapshot, ImportReadError> in
                do { return .success(try importer.read(source, profile: profile, items: items)) }
                catch { return .failure(error as? ImportReadError ?? .unreadable) }
            }.value
            guard let self, self.detail != nil else { return }
            let outcome = read.mapError { OnboardingImportFailure($0.errorDescription ?? "The browser’s data could not be read.") }
                .flatMap { self.hooks.commitImport($0, items) }
            self.detail?.isImporting = false
            switch outcome {
            case .success(let summary):
                self.importSummary = summary
                self.detail = nil
                self.advance()
            case .failure(let failure):
                self.detail?.error = failure.message
                self.refreshDetail()
            }
        }
    }

    private static func openFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Make it yours

    private func makeItYoursView() -> NSView {
        let tiles = NSStackView(views: TabLayout.allCases.map { layout in
            LayoutTile(layout: layout, isSelected: choices.tabLayout == layout) { [weak self] in
                guard let self, self.choices.select(layout) else { return }
                self.present(animated: false)
            }
        })
        tiles.distribution = .fillEqually
        tiles.spacing = 12

        let swatches = NSStackView(views: OnboardingThemePreset.all.enumerated().map { index, preset in
            ThemeSwatch(preset: preset, isSelected: choices.themeIndex == index) { [weak self] in
                guard let self, self.choices.selectTheme(at: index) else { return }
                self.present(animated: false)
            }
        })
        swatches.distribution = .fillEqually
        swatches.spacing = 6

        let newTab = segmented(NewTabStyle.allCases.map(\.title), selected: NewTabStyle.allCases.firstIndex(of: choices.newTab) ?? 0,
                               enabled: NewTabStyle.allCases.map(\.isAvailable)) { [weak self] index in
            _ = self?.choices.select(NewTabStyle.allCases[index])
        }
        let appearance = segmented(AppAppearance.allCases.map(\.title), selected: AppAppearance.allCases.firstIndex(of: choices.appearance) ?? 0,
                                   enabled: nil) { [weak self] index in
            self?.choices.appearance = AppAppearance.allCases[index]
        }
        let sections = NSStackView(views: [
            section("Tabs", tiles), section("Space Theme", swatches),
            section("New Tab", newTab, note: "Full Page is coming soon."), section("Appearance", appearance),
        ])
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 14
        sections.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true }
        return page(header: header("Make It Yours", "Pick a starting look. You can change it any time in Settings."), body: sections,
                    footer: footer(primary: "Continue", primaryEnabled: true, onPrimary: { [weak self] in self?.finishLook() }),
                    compact: true)
    }

    private func section(_ name: String, _ content: NSView, note: String? = nil) -> NSView {
        let label = NSTextField(labelWithString: name.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        var views: [NSView] = [label, content]
        if let note {
            let caption = NSTextField(labelWithString: note)
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .tertiaryLabelColor
            views.append(caption)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func segmented(_ titles: [String], selected: Int, enabled: [Bool]?, change: @escaping (Int) -> Void) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
        control.selectedSegment = selected
        enabled?.enumerated().forEach { control.setEnabled($1, forSegment: $0) }
        let target = PopupTarget { change($0) }
        control.target = target
        control.action = #selector(PopupTarget.changed(_:))
        objc_setAssociatedObject(control, &PopupTarget.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return control
    }

    // MARK: Layout helpers

    private func page(header: NSView, body: NSView, footer: NSView, compact: Bool = false) -> NSView {
        let container = NSView()
        for view in [header, body, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let inset: CGFloat = 32
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: compact ? 28 : 36),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: compact ? 16 : 24),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            body.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        if body is NSScrollView { body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12).isActive = true }
        return container
    }

    private func header(_ text: String, _ detail: String) -> NSView {
        let stack = NSStackView(views: [appIcon(56), title(text), subtitle(detail)])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        return stack
    }

    private func headerBlock(_ pill: NSView, _ heading: String, _ note: String?) -> NSView {
        let stack = NSStackView(views: [pill, title(heading)] + (note.map { [subtitle($0)] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    private func footer(primary: String, primaryEnabled: Bool, onPrimary: @escaping () -> Void) -> NSView {
        let backButton = OnboardingButton(title: "Back", style: .secondary) { [weak self] in self?.back() }
        let primaryButton = OnboardingButton(title: primary, style: .primary, action: onPrimary)
        primaryButton.isEnabled = primaryEnabled
        primaryButton.keyEquivalent = "\r"
        let spring = NSView()
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [backButton, spring, primaryButton])
        stack.spacing = 10
        for button in [backButton, primaryButton] { button.widthAnchor.constraint(equalToConstant: 110).isActive = true }
        return stack
    }

    private func title(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }

    private func subtitle(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.preferredMaxLayoutWidth = 460
        return label
    }

    private func errorLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemRed
        return label
    }

    private func emptyNote(_ heading: String, _ text: String) -> NSView {
        let stack = NSStackView(views: [title(heading), subtitle(text)])
        stack.orientation = .vertical
        stack.spacing = 8
        return stack
    }

    private func explanation(_ text: String, action: (String, () -> Void)) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        let button = OnboardingButton(title: action.0, style: .secondary, action: action.1)
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return stack
    }

    private func appIcon(_ size: CGFloat) -> NSView {
        let view = NSImageView(image: NSApp.applicationIconImage)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func fixedWidth(_ view: NSView, _ width: CGFloat) -> NSView {
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }
}

private extension DetectedBrowser {
    var subtitleNote: String? { notes.first }
}

// MARK: - Panel

private final class OnboardingPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }

    convenience init(wrapping content: NSView) {
        self.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

private final class PopupTarget: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let change: (Int) -> Void
    init(_ change: @escaping (Int) -> Void) { self.change = change }
    @MainActor @objc func changed(_ sender: Any?) {
        if let popup = sender as? NSPopUpButton { change(popup.indexOfSelectedItem) }
        if let control = sender as? NSSegmentedControl { change(control.selectedSegment) }
    }
}

// MARK: - Controls

private final class OnboardingButton: NSButton {
    enum Style { case primary, secondary, text, pill }

    let style: Style
    private let handler: () -> Void

    init(title: String, style: Style, action: @escaping () -> Void) {
        self.style = style
        handler = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        target = self
        self.action = #selector(fire)
        font = .systemFont(ofSize: style == .pill ? 13 : 14, weight: style == .text ? .regular : .medium)
        layer?.cornerRadius = style == .pill ? 14 : 10
        refresh()
        if style != .text { heightAnchor.constraint(equalToConstant: style == .pill ? 28 : 40).isActive = true }
    }

    required init?(coder: NSCoder) { nil }

    override var isEnabled: Bool { didSet { refresh() } }
    override func updateLayer() { refresh() }

    private func refresh() {
        let foreground: NSColor = style == .primary ? .white : (style == .text ? .secondaryLabelColor : .labelColor)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 14), .foregroundColor: foreground.withAlphaComponent(isEnabled ? 1 : 0.4)])
        switch style {
        case .primary: layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isEnabled ? 1 : 0.35).cgColor
        case .secondary, .pill: layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        case .text: layer?.backgroundColor = nil
        }
    }

    @objc private func fire() { handler() }
}

private final class BrowserCard: NSControl {
    private let handler: () -> Void

    init(choice: BrowserChoice, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let icon = NSImageView(image: Self.icon(for: choice.source))
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let name = NSTextField(labelWithString: choice.name)
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        let detail = NSTextField(labelWithString: choice.isCurrentDefault ? "Your browser now" : choice.subtitle)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = choice.isCurrentDefault ? .controlAccentColor : .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.contentTintColor = .tertiaryLabelColor
        let row = NSStackView(views: [icon, text, chevron])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(choice.name), \(choice.subtitle)")
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { handler() }

    private static func icon(for source: ImportSource) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }
}

private final class ToggleRow: NSView {
    init(row: ImportSelection.Row, toggled: @escaping () -> Void) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let detail = NSTextField(labelWithString: row.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let toggle = NSSwitch()
        toggle.state = row.isOn ? .on : .off
        toggle.isEnabled = row.isEnabled
        let target = PopupTarget { _ in toggled() }
        toggle.target = target
        toggle.action = #selector(PopupTarget.changed(_:))
        objc_setAssociatedObject(toggle, &PopupTarget.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let spring = NSView()
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [text, spring, toggle])
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// A mini wireframe of the window with the tab strip where the layout puts it.
private final class LayoutTile: NSControl {
    private let layout: TabLayout
    private let isSelected: Bool
    private let handler: () -> Void

    init(layout: TabLayout, isSelected: Bool, handler: @escaping () -> Void) {
        self.layout = layout
        self.isSelected = isSelected
        self.handler = handler
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 112).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(layout.isAvailable ? layout.title : "\(layout.title), coming soon")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { if layout.isAvailable { handler() } }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = layout.isAvailable ? 1 : 0.4
        let frame = NSRect(x: 0, y: 0, width: bounds.width, height: 84).insetBy(dx: 1, dy: 1)
        NSColor.white.withAlphaComponent(0.08 * alpha).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        let strip = NSColor.white.withAlphaComponent(0.28 * alpha)
        let page = NSColor.white.withAlphaComponent(0.12 * alpha)
        let inner = frame.insetBy(dx: 6, dy: 6)
        let stripRect: NSRect, pageRect: NSRect
        switch layout {
        case .sidebar:
            stripRect = NSRect(x: inner.minX, y: inner.minY, width: 22, height: inner.height)
            pageRect = NSRect(x: inner.minX + 26, y: inner.minY, width: inner.width - 26, height: inner.height)
        case .sidebarRight:
            stripRect = NSRect(x: inner.maxX - 22, y: inner.minY, width: 22, height: inner.height)
            pageRect = NSRect(x: inner.minX, y: inner.minY, width: inner.width - 26, height: inner.height)
        case .top:
            stripRect = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 12)
            pageRect = NSRect(x: inner.minX, y: inner.minY + 16, width: inner.width, height: inner.height - 16)
        }
        strip.setFill()
        NSBezierPath(roundedRect: stripRect, xRadius: 4, yRadius: 4).fill()
        page.setFill()
        NSBezierPath(roundedRect: pageRect, xRadius: 4, yRadius: 4).fill()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
            outline.lineWidth = 2
            outline.stroke()
        }
        let caption = layout.isAvailable ? layout.title : "\(layout.title) · Coming soon"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (caption as NSString).draw(in: NSRect(x: 0, y: 90, width: bounds.width, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha), .paragraphStyle: style])
    }
}

private final class ThemeSwatch: NSControl {
    private let preset: OnboardingThemePreset
    private let isSelected: Bool
    private let handler: () -> Void

    init(preset: OnboardingThemePreset, isSelected: Bool, handler: @escaping () -> Void) {
        self.preset = preset
        self.isSelected = isSelected
        self.handler = handler
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 56).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(preset.name)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { handler() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: bounds.midX - 16, y: 4, width: 32, height: 32)
        let circle = NSBezierPath(ovalIn: rect)
        if let theme = preset.theme {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            let colors = theme.stops.map { NSColor(hex: $0.color) }
            if colors.count > 1 { NSGradient(colors: colors)?.draw(in: rect, angle: -45) } else { colors[0].setFill(); rect.fill() }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.white.withAlphaComponent(0.1).setFill()
            circle.fill()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 7, y: rect.maxY - 7))
            slash.line(to: NSPoint(x: rect.maxX - 7, y: rect.minY + 7))
            NSColor.white.withAlphaComponent(0.5).setStroke()
            slash.lineWidth = 1.5
            slash.stroke()
        }
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 2
            ring.stroke()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (preset.name as NSString).draw(in: NSRect(x: 0, y: 40, width: bounds.width, height: 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
    }
}
