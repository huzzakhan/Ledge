import AppKit
import SwiftUI
import Combine

/// Which widget (if any) is expanded into its big card.
final class DockState: ObservableObject {
    @Published var expanded: WidgetKind?

    func toggle(_ kind: WidgetKind) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            expanded = (expanded == kind) ? nil : kind
        }
    }

    func collapse() {
        guard expanded != nil else { return }
        withAnimation(.easeOut(duration: 0.18)) { expanded = nil }
    }
}

/// Borderless floating panel that never steals focus from your apps,
/// but can still take keyboard input (e.g. typing a new reminder).
final class DockPanel: NSPanel {
    var onEscape: (() -> Void)?

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: 120),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = true
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockController: NSObject {
    let panel = DockPanel()
    let settings = AppSettings.shared
    let state = DockState()

    private var contentSize: CGSize = .zero
    private var bag = Set<AnyCancellable>()
    private var mouseMonitor: Any?
    private var isPositioning = false
    private var hasAppeared = false

    override init() {
        super.init()

        let root = DockRootView(settings: settings, state: state) { [weak self] size in
            DispatchQueue.main.async { self?.contentSizeChanged(size) }
        }
        let host = FirstMouseHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host
        panel.alphaValue = 0
        panel.onEscape = { [weak self] in self?.state.collapse() }

        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: .ledgeReposition, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)

        settings.$position.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.reposition() }
        }.store(in: &bag)

        settings.$dockVisible.dropFirst().sink { [weak self] visible in
            DispatchQueue.main.async {
                if visible { self?.show() } else { self?.hide() }
            }
        }.store(in: &bag)

        // Clicking anywhere outside Ledge closes an open card.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.state.collapse()
        }

        if settings.dockVisible {
            panel.orderFrontRegardless()
        }
    }

    func show() {
        panel.orderFrontRegardless()
        reposition()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        state.expanded = nil
        panel.orderOut(nil)
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        contentSize = size
        reposition()
        if !hasAppeared && settings.dockVisible {
            hasAppeared = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 1
            }
        }
    }

    @objc func reposition() {
        guard contentSize != .zero else { return }
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let w = contentSize.width
        let h = contentSize.height

        let origin: CGPoint
        switch settings.position {
        case .bottom:
            origin = CGPoint(x: vf.midX - w / 2, y: vf.minY - 6)
        case .top:
            origin = CGPoint(x: vf.midX - w / 2, y: vf.maxY - h + 6)
        case .floating:
            let anchor = settings.floatingAnchor ?? CGPoint(x: vf.midX, y: vf.minY + 60)
            origin = CGPoint(x: anchor.x - w / 2, y: anchor.y)
        }

        isPositioning = true
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: w, height: h)).integral, display: true)
        isPositioning = false
    }

    @objc private func panelMoved(_ note: Notification) {
        guard !isPositioning, settings.position == .floating else { return }
        let f = panel.frame
        settings.floatingAnchor = CGPoint(x: f.midX, y: f.minY)
    }
}
