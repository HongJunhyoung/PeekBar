import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowNudgeService {
    func stripThickness(portrait: Bool) -> CGFloat {
        let s = PeekBarSettings.shared
        if portrait {
            return CGFloat(s.thumbnailHeight + s.fontSize + 22)
        } else {
            return CGFloat(s.thumbnailWidth + 16)
        }
    }

    /// Track recently nudged windows with a cooldown to prevent fighting with macOS
    private var cooldowns: [CGWindowID: Date] = [:]
    private let cooldownInterval: TimeInterval = 5

    func nudgeAllWindows() {
        guard PermissionService.hasAccessibility else { return }

        let now = Date()
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        // Clean up cooldowns for windows that no longer exist
        let activeIDs = Set(
            windowList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        )
        cooldowns = cooldowns.filter { activeIDs.contains($0.key) }

        for entry in windowList {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  pid != ownPID
            else { continue }

            // Skip if recently nudged (cooldown prevents fighting)
            if let lastNudge = cooldowns[windowID],
               now.timeIntervalSince(lastNudge) < cooldownInterval {
                continue
            }

            let axFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard axFrame.width > 50 && axFrame.height > 50 else { continue }

            let nsY = primaryHeight - axFrame.origin.y - axFrame.height
            let nsFrame = NSRect(x: axFrame.origin.x, y: nsY, width: axFrame.width, height: axFrame.height)
            let center = CGPoint(x: nsFrame.midX, y: nsFrame.midY)

            for screen in NSScreen.screens {
                guard screen.frame.contains(center) else { continue }

                let reserved = reservedArea(for: screen)
                guard nsFrame.intersects(reserved) else { continue }

                let isPortrait = screen.frame.height > screen.frame.width
                let vf = screen.visibleFrame

                let appElement = AXUIElementCreateApplication(pid)

                // Collect candidate AX windows: mainWindow, focusedWindow, and kAXWindows list
                var candidates: [AXUIElement] = []
                for attr in ["AXMainWindow", "AXFocusedWindow"] {
                    var ref: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appElement, attr as CFString, &ref) == .success {
                        candidates.append(ref as! AXUIElement)
                    }
                }
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    candidates.append(contentsOf: axWindows)
                }

                var nudged = false
                for axWindow in candidates {
                    // Try to get position/size
                    var posRef: CFTypeRef?
                    let posErr = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
                    var sizeRef: CFTypeRef?
                    let sizeErr = AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)

                    guard posErr == .success, sizeErr == .success else {
                        // Log role and error for debugging
                        var roleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef)
                        NSLog("[PeekBar] wid=\(windowID) pid=\(pid) role=\(roleRef as? String ?? "?") posErr=\(posErr.rawValue) sizeErr=\(sizeErr.rawValue)")
                        continue
                    }

                    var pos = CGPoint.zero
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
                    var size = CGSize.zero
                    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

                    let tol: CGFloat = 5
                    guard abs(pos.x - axFrame.origin.x) < tol
                        && abs(pos.y - axFrame.origin.y) < tol else { continue }

                    NSLog("[PeekBar] NUDGING wid=\(windowID) pos=\(pos) size=\(size)")

                    if isPortrait {
                        let stripBottomNS = reserved.minY
                        let stripBottomAX = primaryHeight - stripBottomNS
                        var newPos = pos
                        var newSize = size

                        newPos.y = stripBottomAX
                        let availableHeight = stripBottomNS - vf.origin.y
                        newSize.height = min(size.height, availableHeight)

                        setSize(axWindow, newSize)
                        setPosition(axWindow, newPos)
                    } else {
                        let stripRight = reserved.maxX
                        let availableWidth = vf.maxX - stripRight
                        var newSize = size
                        var newPos = pos

                        newSize.width = min(size.width, availableWidth)
                        newPos.x = stripRight

                        setSize(axWindow, newSize)
                        setPosition(axWindow, newPos)
                    }

                    cooldowns[windowID] = now
                    nudged = true
                    break
                }
                if !nudged {
                    NSLog("[PeekBar] FAILED to nudge wid=\(windowID) — no AX candidate worked, candidates=\(candidates.count)")
                }
                break
            }
        }
    }

    func reservedArea(for screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let isPortrait = screen.frame.height > screen.frame.width
        let thickness = stripThickness(portrait: isPortrait)
        let margin: CGFloat = 6

        if isPortrait {
            return NSRect(x: vf.origin.x, y: vf.maxY - thickness - margin, width: vf.width, height: thickness + margin)
        } else {
            return NSRect(x: vf.origin.x, y: vf.origin.y, width: thickness + margin, height: vf.height)
        }
    }

    // MARK: - AX Helpers

    private func getPosition(_ element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    private func getSize(_ element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return size
    }

    private func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    private func setSize(_ element: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }
}
