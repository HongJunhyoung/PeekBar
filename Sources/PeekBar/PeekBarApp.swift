import SwiftUI
import AppKit

struct MenuBarIcon: View {
    var body: some View {
        Image(nsImage: Self.icon)
    }

    static let icon: NSImage = {
        if let url = Bundle.module.url(forResource: "MenuBarIconTemplate", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 26, height: 14)
            img.isTemplate = true
            return img
        }
        return NSImage(size: NSSize(width: 26, height: 14))
    }()
}

@main
struct PeekBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private var settings = PeekBarSettings.shared

    var body: some Scene {
        MenuBarExtra {
            SettingsView(settings: settings)
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
    }
}
