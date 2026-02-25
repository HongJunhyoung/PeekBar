import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, on screen: NSScreen) {
        // Use the designated (non-screen) initializer, then move to screen
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.setFrame(contentRect, display: false)
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
