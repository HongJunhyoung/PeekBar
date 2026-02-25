import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    var frame: CGRect
    var thumbnail: NSImage?

    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    func isOnScreen(_ screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        let centerX = frame.midX
        let centerY = frame.midY
        return screenFrame.contains(CGPoint(x: centerX, y: centerY))
    }
}
