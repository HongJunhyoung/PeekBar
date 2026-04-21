import Foundation
import Observation

extension Notification.Name {
    static let peekBarSettingsChanged = Notification.Name("peekBarSettingsChanged")
    static let peekBarLiveRefreshChanged = Notification.Name("peekBarLiveRefreshChanged")
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

    /// Apps (bundle IDs) whose thumbnails refresh on a 2s timer instead of only on events.
    /// Opt-in for messenger/monitor apps where backgrounded content changes matter.
    var liveRefreshBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(liveRefreshBundleIDs), forKey: "liveRefreshBundleIDs")
            NotificationCenter.default.post(name: .peekBarLiveRefreshChanged, object: nil)
        }
    }

    func toggleLiveRefresh(_ bundleID: String) {
        if liveRefreshBundleIDs.contains(bundleID) {
            liveRefreshBundleIDs.remove(bundleID)
        } else {
            liveRefreshBundleIDs.insert(bundleID)
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
        let stored = defaults.stringArray(forKey: "liveRefreshBundleIDs") ?? []
        self.liveRefreshBundleIDs = Set(stored)
    }
}
