import AppKit
import ScreenCaptureKit

actor WindowCaptureService {
    private let store: WindowStore
    private let captureWidth = 480
    private let captureHeight = 320
    private var isRunning = false
    private var captureTask: Task<Void, Never>?

    init(store: WindowStore) {
        self.store = store
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        captureTask = Task {
            while !Task.isCancelled && isRunning {
                await captureAllWindows()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        isRunning = false
        captureTask?.cancel()
        captureTask = nil
    }

    func refreshNow() {
        Task { await captureAllWindows() }
    }

    private func captureAllWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            )

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownBundleID = Bundle.main.bundleIdentifier ?? "com.hongjh.PeekBar"

            // System apps to exclude (notifications, Dock, Control Center, etc.)
            let excludedBundleIDs: Set<String> = [
                "com.apple.notificationcenterui",   // Notification Center
                "com.apple.UserNotificationCenter",  // User notifications
                "com.apple.dock",                    // Dock + badges
                "com.apple.controlcenter",           // Control Center
                "com.apple.systemuiserver",          // System UI (menu extras)
                "com.apple.WindowManager",           // Window Manager / Stage Manager
                "com.apple.Spotlight",               // Spotlight
                "com.apple.loginwindow",             // Login window
                "com.apple.screencaptureui",         // Screenshot UI
                "com.apple.AssistiveControl",        // Assistive Control
            ]

            let eligibleWindows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                let bundleID = app.bundleIdentifier ?? ""
                return app.processID != ownPID
                    && bundleID != ownBundleID
                    && !excludedBundleIDs.contains(bundleID)
                    && window.isOnScreen
                    && window.frame.width > 50
                    && window.frame.height > 50
            }

            var windowInfos: [WindowInfo] = []

            await withTaskGroup(of: WindowInfo?.self) { group in
                for window in eligibleWindows {
                    group.addTask { [self] in
                        await self.captureWindow(window)
                    }
                }
                for await info in group {
                    if let info {
                        windowInfos.append(info)
                    }
                }
            }

            // Sort by app name then title for consistent ordering
            windowInfos.sort { ($0.appName, $0.title) < ($1.appName, $1.title) }

            await store.update(with: windowInfos)
        } catch {
            // Permission denied or other error — silently retry next cycle
        }
    }

    private func captureWindow(_ window: SCWindow) async -> WindowInfo? {
        let pid = window.owningApplication?.processID ?? 0
        let title = window.title ?? ""
        let appName = window.owningApplication?.applicationName ?? "Unknown"

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Capture a fixed-size crop from the top-left of the window (no scaling)
        let cropW = min(CGFloat(captureWidth), window.frame.width)
        let cropH = min(CGFloat(captureHeight), window.frame.height)
        config.sourceRect = CGRect(x: 0, y: 0, width: cropW, height: cropH)
        config.width = captureWidth
        config.height = captureHeight
        config.scalesToFit = false
        config.showsCursor = false

        var thumbnail: NSImage?
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            thumbnail = NSImage(
                cgImage: image,
                size: NSSize(width: captureWidth, height: captureHeight)
            )
        } catch {
            // Capture failed for this window — return info without thumbnail
        }

        return WindowInfo(
            id: window.windowID,
            pid: pid,
            title: title,
            appName: appName,
            frame: window.frame,
            thumbnail: thumbnail
        )
    }
}
