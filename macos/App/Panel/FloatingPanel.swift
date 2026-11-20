// A Spotlight-style panel: borderless, floating above other windows, and
// closing as soon as it loses focus.

import AppKit
import SwiftUI

import CrossroadsCore

/// A borderless panel will not take key focus unless it says it can.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        model.closePanel = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        model.panelDidOpen()
        place(panel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func make() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Clicking another app puts it away, like Spotlight.
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelView(model: model))
        return panel
    }

    /// A little above center, where Spotlight sits, on the screen with the mouse.
    private func place(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return panel.center() }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * 0.08
            )
        )
    }
}
