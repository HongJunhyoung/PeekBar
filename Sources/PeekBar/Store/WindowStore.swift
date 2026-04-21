import AppKit
import Observation

struct ChangeIndicator: Equatable {
    /// Bounding box of the changed area, normalized to the thumbnail (0...1).
    let region: CGRect
    /// Increments on every detected change so SwiftUI re-fires the bounce.
    let bumpToken: UInt64
}

@Observable
final class WindowStore {
    var windows: [WindowInfo] = []
    /// Custom labels keyed by CGWindowID
    var customLabels: [CGWindowID: String] = [:]
    /// User-defined display order per screen (keyed by screen number)
    var customOrder: [CGWindowID] = []
    /// Pending change indicators per window — cleared when the user views the app.
    var unseenChanges: [CGWindowID: ChangeIndicator] = [:]
    /// Stable frames to prevent jitter from alert animations
    private var stableFrames: [CGWindowID: CGRect] = [:]
    private var nextBumpToken: UInt64 = 0

    func windows(for screen: NSScreen) -> [WindowInfo] {
        let filtered = windows.filter { $0.isOnScreen(screen) }
        guard !customOrder.isEmpty else { return filtered }
        let lookup = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        var ordered: [WindowInfo] = []
        for id in customOrder {
            if let win = lookup[id] { ordered.append(win) }
        }
        for win in filtered where !customOrder.contains(win.id) {
            ordered.append(win)
        }
        return ordered
    }

    func moveWindow(_ sourceID: CGWindowID, before targetID: CGWindowID, on screen: NSScreen) {
        // Ensure customOrder reflects current screen windows
        let current = windows(for: screen).map(\.id)
        if customOrder.isEmpty || Set(customOrder).intersection(current).count != current.count {
            customOrder = current
        }
        guard let srcIdx = customOrder.firstIndex(of: sourceID) else { return }
        customOrder.remove(at: srcIdx)
        if let dstIdx = customOrder.firstIndex(of: targetID) {
            customOrder.insert(sourceID, at: dstIdx)
        } else {
            customOrder.append(sourceID)
        }
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

        // Clean up stale frames (labels and order are preserved
        // across desktop switches since windows may reappear)
        for key in stableFrames.keys where !activeIDs.contains(key) {
            stableFrames.removeValue(forKey: key)
        }
        // Note: customOrder is NOT cleaned up here — windows may temporarily
        // disappear during desktop switches and reappear later.
        // Stale IDs in customOrder are harmless (skipped in windows(for:)).

        self.windows = stabilizeFrames(newWindows)
    }

    /// Merge a targeted re-scan into the store. `inScope` identifies which existing
    /// windows were covered by the scan — any of those not present in `updates` are
    /// treated as closed and removed. Windows outside the scope are preserved.
    @MainActor
    func merge(updates: [WindowInfo], inScope: (WindowInfo) -> Bool) {
        let stabilized = stabilizeFrames(updates)
        let updatesByID = Dictionary(uniqueKeysWithValues: stabilized.map { ($0.id, $0) })

        var merged: [WindowInfo] = []
        for existing in windows {
            if let updated = updatesByID[existing.id] {
                merged.append(updated)
            } else if inScope(existing) {
                // Was in scope of this scan but missing → closed
                stableFrames.removeValue(forKey: existing.id)
                unseenChanges.removeValue(forKey: existing.id)
                continue
            } else {
                merged.append(existing)
            }
        }
        let existingIDs = Set(windows.map(\.id))
        for update in stabilized where !existingIDs.contains(update.id) {
            merged.append(update)
        }
        merged.sort { ($0.appName, $0.title) < ($1.appName, $1.title) }
        self.windows = merged
    }

    /// Remove all windows owned by the given PID (e.g., app terminated).
    @MainActor
    func removeWindows(pid: pid_t) {
        let removedIDs = Set(windows.filter { $0.pid == pid }.map(\.id))
        windows.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            stableFrames.removeValue(forKey: id)
            unseenChanges.removeValue(forKey: id)
        }
    }

    @MainActor
    func markChange(windowID: CGWindowID, region: CGRect) {
        nextBumpToken &+= 1
        unseenChanges[windowID] = ChangeIndicator(region: region, bumpToken: nextBumpToken)
    }

    @MainActor
    func clearChanges(forWindowID windowID: CGWindowID) {
        unseenChanges.removeValue(forKey: windowID)
    }

    @MainActor
    func clearChanges(forBundleID bundleID: String) {
        let ids = windows.filter { $0.bundleID == bundleID }.map(\.id)
        for id in ids {
            unseenChanges.removeValue(forKey: id)
        }
    }

    private func stabilizeFrames(_ newWindows: [WindowInfo]) -> [WindowInfo] {
        let threshold: CGFloat = 20
        var stabilized: [WindowInfo] = []
        for var win in newWindows {
            if let prev = stableFrames[win.id] {
                let dx = abs(win.frame.origin.x - prev.origin.x)
                let dy = abs(win.frame.origin.y - prev.origin.y)
                let dw = abs(win.frame.width - prev.width)
                let dh = abs(win.frame.height - prev.height)
                if dx < threshold && dy < threshold && dw < threshold && dh < threshold {
                    win.frame = prev
                } else {
                    stableFrames[win.id] = win.frame
                }
            } else {
                stableFrames[win.id] = win.frame
            }
            stabilized.append(win)
        }
        return stabilized
    }
}
