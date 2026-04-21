import Foundation
import Observation

extension Notification.Name {
    static let peekBarSettingsChanged = Notification.Name("peekBarSettingsChanged")
    static let peekBarMonitorChangeChanged = Notification.Name("peekBarMonitorChangeChanged")
}

@Observable
final class PeekBarSettings {
    static let shared = PeekBarSettings()

    var fontSize: Double {
        didSet { save("fontSize", fontSize) }
    }
    var thumbnailSpacing: Double {
        didSet { save("thumbnailSpacing", thumbnailSpacing) }
    }
    var thumbnailWidth: Double {
        didSet { save("thumbnailWidth", thumbnailWidth) }
    }
    var thumbnailHeight: Double {
        didSet { save("thumbnailHeight", thumbnailHeight) }
    }

    /// Apps (bundle IDs) whose thumbnails are polled every 5s for change detection.
    /// When a change is spotted, the thumbnail bounces and highlights the changed region
    /// until the user activates the app.
    var monitorChangeBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(monitorChangeBundleIDs), forKey: "monitorChangeBundleIDs")
            NotificationCenter.default.post(name: .peekBarMonitorChangeChanged, object: nil)
        }
    }

    func toggleMonitorChange(_ bundleID: String) {
        if monitorChangeBundleIDs.contains(bundleID) {
            monitorChangeBundleIDs.remove(bundleID)
        } else {
            monitorChangeBundleIDs.insert(bundleID)
        }
    }

    private func save(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .peekBarSettingsChanged, object: nil)
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "fontSize": 13.0,
            "thumbnailSpacing": 4.0,
            "thumbnailWidth": 200.0,
            "thumbnailHeight": 120.0,
        ])
        self.fontSize = defaults.double(forKey: "fontSize")
        self.thumbnailSpacing = defaults.double(forKey: "thumbnailSpacing")
        self.thumbnailWidth = defaults.double(forKey: "thumbnailWidth")
        self.thumbnailHeight = defaults.double(forKey: "thumbnailHeight")
        // Migrate old liveRefreshBundleIDs key to monitorChangeBundleIDs (one-shot)
        if defaults.object(forKey: "monitorChangeBundleIDs") == nil,
           let legacy = defaults.stringArray(forKey: "liveRefreshBundleIDs") {
            defaults.set(legacy, forKey: "monitorChangeBundleIDs")
            defaults.removeObject(forKey: "liveRefreshBundleIDs")
        }
        let stored = defaults.stringArray(forKey: "monitorChangeBundleIDs") ?? []
        self.monitorChangeBundleIDs = Set(stored)
    }
}
