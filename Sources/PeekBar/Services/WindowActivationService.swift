import AppKit
import ApplicationServices

final class WindowActivationService {
    func activate(_ windowInfo: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: windowInfo.pid) else { return }

        // Activate the owning application
        app.activate()

        // Use Accessibility API to raise the specific window
        let appElement = AXUIElementCreateApplication(windowInfo.pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            if matches(axWindow: axWindow, windowInfo: windowInfo) {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMainAttribute as CFString,
                    kCFBooleanTrue
                )
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }

        // Fallback: if no exact match, just raise the first window
        if let firstWindow = axWindows.first {
            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
        }
    }

    func matchesPublic(axWindow: AXUIElement, windowInfo: WindowInfo) -> Bool {
        matches(axWindow: axWindow, windowInfo: windowInfo)
    }

    private func matches(axWindow: AXUIElement, windowInfo: WindowInfo) -> Bool {
        // Match by title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let axTitle = titleRef as? String ?? ""

        if !windowInfo.title.isEmpty && axTitle == windowInfo.title {
            return true
        }

        // Match by position if title is empty or ambiguous
        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)

        if let posRef, let sizeRef {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

            let tolerance: CGFloat = 5
            if abs(pos.x - windowInfo.frame.origin.x) < tolerance
                && abs(pos.y - windowInfo.frame.origin.y) < tolerance
                && abs(size.width - windowInfo.frame.width) < tolerance
                && abs(size.height - windowInfo.frame.height) < tolerance {
                return true
            }
        }

        return false
    }
}
