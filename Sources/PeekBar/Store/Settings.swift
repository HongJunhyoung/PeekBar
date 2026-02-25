import Foundation
import Observation

extension Notification.Name {
    static let peekBarSettingsChanged = Notification.Name("peekBarSettingsChanged")
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
    }
}
