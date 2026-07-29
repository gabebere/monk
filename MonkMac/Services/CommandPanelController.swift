import AppKit
import Combine
import SwiftUI

enum CommandPanelMetrics {
    static let composerSize = NSSize(width: 680, height: 620)
    static let activeFocusSize = NSSize(width: 560, height: 430)
}

@MainActor
final class CommandPanelController: NSObject, NSWindowDelegate {
    private let panel: FocusCommandPanel
    private let store: FocusSessionStore
    private var activePolicyCancellable: AnyCancellable?

    init(store: FocusSessionStore, catalog: ApplicationCatalog) {
        let panel = FocusCommandPanel(
            contentRect: NSRect(origin: .zero, size: CommandPanelMetrics.composerSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        self.store = store
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]

        let rootView = FocusCommandView(
            store: store,
            catalog: catalog,
            onDismiss: { [weak panel] in panel?.orderOut(nil) }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)

        activePolicyCancellable = store.$activePolicy
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isActive in
                DispatchQueue.main.async { [weak self] in
                    self?.updatePanelSize(isActive: isActive)
                }
            }
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        updatePanelSize(isActive: store.activePolicy != nil)
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSPanel === panel else { return }
        hide()
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 70
        )
        panel.setFrameOrigin(origin)
    }

    private func updatePanelSize(isActive: Bool) {
        let size = isActive ? CommandPanelMetrics.activeFocusSize : CommandPanelMetrics.composerSize
        guard panel.contentLayoutRect.size != size else { return }

        panel.setContentSize(size)
        if panel.isVisible {
            positionPanel()
        }
    }
}

final class FocusCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
