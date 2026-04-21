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

    private enum Scope {
        case all
        case pid(pid_t)
        case bundleIDs(Set<String>)

        func matches(_ window: SCWindow) -> Bool {
            switch self {
            case .all: return true
            case .pid(let p): return window.owningApplication?.processID == p
            case .bundleIDs(let ids):
                guard let bid = window.owningApplication?.bundleIdentifier else { return false }
                return ids.contains(bid)
            }
        }

        func matches(_ info: WindowInfo) -> Bool {
            switch self {
            case .all: return true
            case .pid(let p): return info.pid == p
            case .bundleIDs(let ids): return ids.contains(info.bundleID)
            }
        }
    }

    /// Full enumeration + capture. Replaces the entire window list in the store.
    /// Use on app launch, space change, and wake.
    func captureAll() async {
        await capture(scope: .all)
    }

    /// Capture only windows matching the given bundle IDs. Merges into store
    /// without disturbing other windows. Used by Live Refresh timer.
    func capture(bundleIDs: Set<String>) async {
        guard !bundleIDs.isEmpty else { return }
        await capture(scope: .bundleIDs(bundleIDs))
    }

    /// Capture only windows owned by the given PID. Merges into store.
    /// Used on app activation / deactivation to refresh that app's thumbnails.
    func capture(pid: pid_t) async {
        await capture(scope: .pid(pid))
    }

    private func capture(scope: Scope) async {
        do {
            guard !Task.isCancelled else { return }
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            )
            guard !Task.isCancelled else { return }

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownBundleID = Bundle.main.bundleIdentifier ?? "com.hongjh.PeekBar"
            let excludedBundleIDs: Set<String> = [
                "com.apple.notificationcenterui",
                "com.apple.UserNotificationCenter",
                "com.apple.dock",
                "com.apple.controlcenter",
                "com.apple.systemuiserver",
                "com.apple.WindowManager",
                "com.apple.Spotlight",
                "com.apple.loginwindow",
                "com.apple.screencaptureui",
                "com.apple.AssistiveControl",
            ]
            let ownAppName = ProcessInfo.processInfo.processName

            let eligibleWindows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                let bundleID = app.bundleIdentifier
                let appName = app.applicationName
                return app.processID != ownPID
                    && bundleID != ownBundleID
                    && appName != ownAppName
                    && !excludedBundleIDs.contains(bundleID)
                    && window.isOnScreen
                    && window.frame.width > 50
                    && window.frame.height > 50
                    && scope.matches(window)
            }

            var windowInfos: [WindowInfo] = []
            await withTaskGroup(of: WindowInfo?.self) { group in
                for window in eligibleWindows {
                    group.addTask { [self] in
                        await withTimeoutOrNil(seconds: 3) {
                            await self.captureWindow(window) ?? nil
                        } ?? nil
                    }
                }
                for await info in group {
                    if let info { windowInfos.append(info) }
                }
            }

            windowInfos.sort { ($0.appName, $0.title) < ($1.appName, $1.title) }
            refreshCounter += 1
            for i in windowInfos.indices {
                windowInfos[i].refreshToken = refreshCounter
            }

            switch scope {
            case .all:
                await store.update(with: windowInfos)
            case .pid, .bundleIDs:
                let capturedScope = scope
                await store.merge(updates: windowInfos, inScope: { capturedScope.matches($0) })
            }
        } catch {
            // Permission denied or other error — silently retry next cycle
        }
    }

    private func captureWindow(_ window: SCWindow) async -> WindowInfo? {
        let pid = window.owningApplication?.processID ?? 0
        let bundleID = window.owningApplication?.bundleIdentifier ?? ""
        let title = window.title ?? ""
        let appName = window.owningApplication?.applicationName ?? "Unknown"

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
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
            bundleID: bundleID,
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
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
