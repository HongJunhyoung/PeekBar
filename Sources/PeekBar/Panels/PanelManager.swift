import AppKit
import SwiftUI

@MainActor
final class PanelManager {
    private var panels: [NSScreen: FloatingPanel] = [:]
    private let store: WindowStore
    private func stripThickness(portrait: Bool) -> CGFloat {
        let s = PeekBarSettings.shared
        if portrait {
            // Top strip — height needs to fit: thumbnail height + font + padding
            return CGFloat(s.thumbnailHeight + s.fontSize + 22)
        } else {
            // Left strip — width needs to fit: thumbnail width + padding
            return CGFloat(s.thumbnailWidth + 16)
        }
    }

    init(store: WindowStore) {
        self.store = store
        setupScreenChangeObserver()
    }

    func setupPanels() {
        tearDownPanels()
        for screen in NSScreen.screens {
            let isPortrait = screen.frame.height > screen.frame.width
            let frame = panelFrame(for: screen)
            let panel = FloatingPanel(contentRect: frame, on: screen)

            // Portrait → top (horizontal strip), Landscape → left (vertical strip)
            let hostingView = NSHostingView(
                rootView: ThumbnailStripView(
                    store: store,
                    screen: screen,
                    isVertical: !isPortrait
                )
            )
            panel.contentView = hostingView
            panel.orderFrontRegardless()
            panels[screen] = panel
        }
    }

    func tearDownPanels() {
        for (_, panel) in panels {
            panel.close()
        }
        panels.removeAll()
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let isPortrait = screen.frame.height > screen.frame.width
        let thickness = stripThickness(portrait: isPortrait)

        if isPortrait {
            return NSRect(
                x: vf.origin.x,
                y: vf.maxY - thickness,
                width: vf.width,
                height: thickness
            )
        } else {
            return NSRect(
                x: vf.origin.x,
                y: vf.origin.y,
                width: thickness,
                height: vf.height
            )
        }
    }

    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupPanels()
            }
        }
    }
}
