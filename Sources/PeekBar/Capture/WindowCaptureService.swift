import AppKit
import ScreenCaptureKit

actor WindowCaptureService {
    private let store: WindowStore
    private let captureWidth = 480
    private let captureHeight = 320
    private var refreshCounter: UInt64 = 0

    init(store: WindowStore) {
        self.store = store
    }

    /// Called by Timer from AppDelegate — triggers a single capture cycle.
    /// The caller cancels the previous Task before starting a new one,
    /// so a hung ScreenCaptureKit call won't block future captures forever.
    func captureOnce() async {
        await captureAllWindows()
    }

    private func captureAllWindows() async {
        do {
            guard !Task.isCancelled else { return }
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            )
            guard !Task.isCancelled else { return }

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

            let ownAppName = ProcessInfo.processInfo.processName

            let eligibleWindows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                let bundleID = app.bundleIdentifier ?? ""
                let appName = app.applicationName
                return app.processID != ownPID
                    && bundleID != ownBundleID
                    && appName != ownAppName
                    && !excludedBundleIDs.contains(bundleID)
                    && window.isOnScreen
                    && window.frame.width > 50
                    && window.frame.height > 50
            }

            var windowInfos: [WindowInfo] = []

            await withTaskGroup(of: WindowInfo?.self) { group in
                for window in eligibleWindows {
                    group.addTask { [self] in
                        // Timeout per window to prevent one hung capture from blocking all
                        await withTimeoutOrNil(seconds: 3) {
                            await self.captureWindow(window) ?? nil
                        } ?? nil
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

            refreshCounter += 1
            for i in windowInfos.indices {
                windowInfos[i].refreshToken = refreshCounter
            }

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

/// Returns the result of `operation` or nil if it takes longer than `seconds`.
private func withTimeoutOrNil<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        // Return the first result — either the value or nil (timeout)
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
