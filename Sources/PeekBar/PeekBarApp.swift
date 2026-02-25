import SwiftUI
import AppKit

struct MenuBarIcon: View {
    var body: some View {
        Image(nsImage: Self.icon)
    }

    static let icon: NSImage = {
        let w: CGFloat = 18
        let h: CGFloat = 16
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()

        NSColor.black.setFill()

        let rectW: CGFloat = 4.5
        let rectH: CGFloat = 3.5
        let gap: CGFloat = 1.5
        let totalW = rectW * 3 + gap * 2
        let startX = (w - totalW) / 2
        let topY = h - rectH - 2

        for i in 0..<3 {
            let x = startX + CGFloat(i) * (rectW + gap)
            NSBezierPath(roundedRect: NSRect(x: x, y: topY, width: rectW, height: rectH),
                        xRadius: 0.8, yRadius: 0.8).fill()
        }

        let barY = topY - 2.5
        NSBezierPath(roundedRect: NSRect(x: startX, y: barY, width: totalW, height: 1.5),
                    xRadius: 0.5, yRadius: 0.5).fill()

        img.unlockFocus()
        img.isTemplate = true
        return img
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
