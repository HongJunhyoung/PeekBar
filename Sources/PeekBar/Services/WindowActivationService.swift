import AppKit
import ApplicationServices

// Private API to get CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

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

        // First try: match by CGWindowID (most reliable)
        for axWindow in axWindows {
            var axWindowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axWindowID) == .success,
               axWindowID == windowInfo.id {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMainAttribute as CFString,
                    kCFBooleanTrue
                )
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }

        // Fallback: match by title + position
        for axWindow in axWindows {
            if matchesFallback(axWindow: axWindow, windowInfo: windowInfo) {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMainAttribute as CFString,
                    kCFBooleanTrue
                )
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }

        // Last resort: raise the first window
        if let firstWindow = axWindows.first {
            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
        }
    }

    func matchesPublic(axWindow: AXUIElement, windowInfo: WindowInfo) -> Bool {
        var axWindowID: CGWindowID = 0
        if _AXUIElementGetWindow(axWindow, &axWindowID) == .success,
           axWindowID == windowInfo.id {
            return true
        }
        return matchesFallback(axWindow: axWindow, windowInfo: windowInfo)
    }

    private func matchesFallback(axWindow: AXUIElement, windowInfo: WindowInfo) -> Bool {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let axTitle = titleRef as? String ?? ""

        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)

        if let posRef, let sizeRef {
            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

            let tolerance: CGFloat = 30
            let posMatch = abs(pos.x - windowInfo.frame.origin.x) < tolerance
                && abs(pos.y - windowInfo.frame.origin.y) < tolerance

            if !windowInfo.title.isEmpty && axTitle == windowInfo.title && posMatch {
                return true
            }

            if posMatch
                && abs(size.width - windowInfo.frame.width) < tolerance
                && abs(size.height - windowInfo.frame.height) < tolerance {
                return true
            }
        }

        if !windowInfo.title.isEmpty && axTitle == windowInfo.title {
            return true
        }

        return false
    }
}
