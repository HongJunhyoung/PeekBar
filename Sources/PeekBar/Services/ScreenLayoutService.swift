import AppKit

enum ScreenLayoutService {
    static var screens: [NSScreen] {
        NSScreen.screens
    }

    static func isPortrait(_ screen: NSScreen) -> Bool {
        screen.frame.height > screen.frame.width
    }

    static func isLandscape(_ screen: NSScreen) -> Bool {
        screen.frame.width >= screen.frame.height
    }
}
