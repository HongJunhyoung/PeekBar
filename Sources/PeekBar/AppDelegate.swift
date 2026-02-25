import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelManager: PanelManager?
    private var captureService: WindowCaptureService?
    private let store = WindowStore()
    private let nudgeService = WindowNudgeService()
    private var nudgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and remove notification badge
        NSApp.setActivationPolicy(.accessory)

        // Flip the menu bar icon upside down
        flipMenuBarIcon()

        if !PermissionService.allPermissionsGranted {
            PermissionService.requestAllPermissions()
            pollPermissionsAndStart()
        } else {
            startServices()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nudgeTimer?.invalidate()
        panelManager?.tearDownPanels()
        Task { await captureService?.stop() }
    }

    private func flipMenuBarIcon() {
        guard let symbol = NSImage(systemSymbolName: "rectangle.grid.3x1", accessibilityDescription: "PeekBar") else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let size = configured.size

        let flipped = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            configured.draw(in: rect)
            return true
        }
        flipped.isTemplate = true

        // Find the MenuBarExtra's status button and replace its image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows {
                guard String(describing: type(of: window)).contains("StatusBar") else { continue }
                if let button = window.contentView?.subviews.compactMap({ $0 as? NSControl }).first {
                    (button as? NSButton)?.image = flipped
                }
            }
        }
    }

    private func startServices() {
        captureService = WindowCaptureService(store: store)
        Task { await captureService?.start() }

        panelManager = PanelManager(store: store)
        panelManager?.setupPanels()

        // Nudge existing windows immediately, then check periodically for new ones
        nudgeService.nudgeAllWindows()
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.nudgeService.nudgeAllWindows()
            }
        }

        // Rebuild panels when settings change
        NotificationCenter.default.addObserver(
            forName: .peekBarSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.panelManager?.setupPanels()
            }
        }

        // Refresh thumbnails immediately on desktop/space switch
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let captureService = self?.captureService else { return }
            Task { await captureService.refreshNow() }
        }
    }

    private func pollPermissionsAndStart() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                if PermissionService.allPermissionsGranted {
                    timer.invalidate()
                    self?.startServices()
                }
            }
        }
    }
}
