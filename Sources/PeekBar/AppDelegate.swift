import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelManager: PanelManager?
    private var captureService: WindowCaptureService?
    private let store = WindowStore()
    private let nudgeService = WindowNudgeService()
    private var nudgeTimer: Timer?
    private var captureTimer: Timer?
    private var captureTask: Task<Void, Never>?

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
        captureTimer?.invalidate()
        nudgeTimer?.invalidate()
        panelManager?.tearDownPanels()
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
        // Timer fires every 2s. Each tick cancels any stuck previous capture
        // and starts a fresh one — prevents actor queue buildup if
        // ScreenCaptureKit hangs (e.g., after sleep/wake).
        scheduleCaptureNow()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleCaptureNow() }
        }

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
            Task { @MainActor in self?.scheduleCaptureNow() }
        }
    }

    /// Cancel any in-flight capture and start a fresh one.
    /// If ScreenCaptureKit is hung, the old Task is cancelled and
    /// a new one is created — the actor processes the new call once
    /// the cancelled one unblocks.
    private func scheduleCaptureNow() {
        captureTask?.cancel()
        captureTask = Task {
            await captureService?.captureOnce()
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
