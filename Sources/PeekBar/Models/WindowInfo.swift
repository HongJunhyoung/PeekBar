import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String
    let title: String
    let appName: String
    var frame: CGRect
    var thumbnail: NSImage?
    /// Monotonic counter to force SwiftUI re-render on thumbnail refresh
    var refreshToken: UInt64 = 0

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.title == rhs.title && lhs.refreshToken == rhs.refreshToken
    }

    func isOnScreen(_ screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        let centerX = frame.midX
        let centerY = frame.midY
        return screenFrame.contains(CGPoint(x: centerX, y: centerY))
    }
}
