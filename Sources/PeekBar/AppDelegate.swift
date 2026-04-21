import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelManager: PanelManager?
    private var captureService: WindowCaptureService?
    private let store = WindowStore()
    private let nudgeService = WindowNudgeService()

    /// Only active while at least one app is marked for Live Refresh
    /// AND the screen is not locked/asleep.
    private var liveRefreshTimer: Timer?
    private var isScreenLocked = false
    private var isDisplayAsleep = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        flipMenuBarIcon()

        if !PermissionService.allPermissionsGranted {
            PermissionService.requestAllPermissions()
            pollPermissionsAndStart()
        } else {
            startServices()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        liveRefreshTimer?.invalidate()
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
        let capture = WindowCaptureService(store: store)
        captureService = capture

        panelManager = PanelManager(store: store)
        panelManager?.setupPanels()

        // Initial full sweep
        Task { await capture.captureAll() }
        nudgeService.nudgeAllWindows()

        registerObservers()
        updateLiveRefreshTimer()
    }

    // MARK: - Observers

    private func registerObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        // App activation → capture newly-activated app's windows (may include new windows)
        ws.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.onAppActivated(pid: app.processIdentifier)
            }
        }

        // App deactivation → capture deactivated app's windows ("last seen" snapshot)
        ws.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.onAppDeactivated(pid: app.processIdentifier)
            }
        }

        ws.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                // Small delay: newly launched apps may not have windows ready yet
                try? await Task.sleep(for: .milliseconds(500))
                guard let service = self?.captureService else { return }
                await service.capture(pid: pid)
            }
        }

        ws.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.store.removeWindows(pid: pid)
            }
        }

        ws.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let service = self.captureService else { return }
                Task { await service.captureAll() }
                self.nudgeService.nudgeAllWindows()
            }
        }

        // Display sleep → pause live refresh
        ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplayAsleep = true
                self?.updateLiveRefreshTimer()
            }
        }
        ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isDisplayAsleep = false
                self.updateLiveRefreshTimer()
                // State might have drifted during sleep — full refresh
                if let service = self.captureService {
                    Task { await service.captureAll() }
                }
            }
        }

        // Screen lock / unlock (distributed notifications)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = true
                self?.updateLiveRefreshTimer()
            }
        }
        dnc.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = false
                self?.updateLiveRefreshTimer()
            }
        }

        // Panel rebuild on settings change
        NotificationCenter.default.addObserver(
            forName: .peekBarSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelManager?.setupPanels()
            }
        }

        // Live refresh membership change → reconsider timer state
        NotificationCenter.default.addObserver(
            forName: .peekBarLiveRefreshChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLiveRefreshTimer()
            }
        }
    }

    // MARK: - Event handlers

    private func onAppActivated(pid: pid_t) {
        if let service = captureService {
            Task { await service.capture(pid: pid) }
        }
        nudgeService.nudgeAllWindows()
    }

    private func onAppDeactivated(pid: pid_t) {
        if let service = captureService {
            Task { await service.capture(pid: pid) }
        }
    }

    // MARK: - Live Refresh timer

    private func updateLiveRefreshTimer() {
        let bundleIDs = PeekBarSettings.shared.liveRefreshBundleIDs
        let shouldRun = !bundleIDs.isEmpty && !isScreenLocked && !isDisplayAsleep

        if shouldRun && liveRefreshTimer == nil {
            liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    let ids = PeekBarSettings.shared.liveRefreshBundleIDs
                    guard !ids.isEmpty else { return }
                    await self?.captureService?.capture(bundleIDs: ids)
                }
            }
        } else if !shouldRun, let t = liveRefreshTimer {
            t.invalidate()
            liveRefreshTimer = nil
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
