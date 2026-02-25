import AppKit
import Observation

@Observable
final class WindowStore {
    var windows: [WindowInfo] = []
    /// Custom labels keyed by CGWindowID
    var customLabels: [CGWindowID: String] = [:]
    /// Stable frames to prevent jitter from alert animations
    private var stableFrames: [CGWindowID: CGRect] = [:]

    func windows(for screen: NSScreen) -> [WindowInfo] {
        windows.filter { $0.isOnScreen(screen) }
    }

    func displayName(for window: WindowInfo) -> String {
        customLabels[window.id] ?? window.appName
    }

    func setCustomLabel(_ label: String, for windowID: CGWindowID) {
        if label.isEmpty {
            customLabels.removeValue(forKey: windowID)
        } else {
            customLabels[windowID] = label
        }
    }

    @MainActor
    func update(with newWindows: [WindowInfo]) {
        let activeIDs = Set(newWindows.map(\.id))

        // Clean up stale entries
        for key in customLabels.keys where !activeIDs.contains(key) {
            customLabels.removeValue(forKey: key)
        }
        for key in stableFrames.keys where !activeIDs.contains(key) {
            stableFrames.removeValue(forKey: key)
        }

        // Stabilize frames — only update if moved more than 20px
        let threshold: CGFloat = 20
        var stabilized: [WindowInfo] = []
        for var win in newWindows {
            if let prev = stableFrames[win.id] {
                let dx = abs(win.frame.origin.x - prev.origin.x)
                let dy = abs(win.frame.origin.y - prev.origin.y)
                let dw = abs(win.frame.width - prev.width)
                let dh = abs(win.frame.height - prev.height)
                if dx < threshold && dy < threshold && dw < threshold && dh < threshold {
                    // Small jitter — keep previous stable frame
                    win.frame = prev
                } else {
                    // Real move — update stable frame
                    stableFrames[win.id] = win.frame
                }
            } else {
                stableFrames[win.id] = win.frame
            }
            stabilized.append(win)
        }

        self.windows = stabilized
    }
}
