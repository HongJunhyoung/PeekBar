import SwiftUI
import AppKit

struct ThumbnailItemView: View {
    let windowInfo: WindowInfo
    @Bindable var store: WindowStore
    let onTap: () -> Void
    var settings = PeekBarSettings.shared

    @State private var isHovered = false
    @State private var hoverTimer: Timer?

    private var displayName: String {
        store.displayName(for: windowInfo)
    }

    var body: some View {
        VStack(spacing: 2) {
            if let thumbnail = windowInfo.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: settings.thumbnailWidth, height: settings.thumbnailHeight)
                    .clipped()
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: settings.thumbnailWidth, height: settings.thumbnailHeight)
                    .overlay {
                        Image(systemName: "macwindow")
                            .foregroundColor(.gray)
                    }
            }

            Text(displayName)
                .font(.system(size: settings.fontSize, weight: .medium))
                .lineLimit(1)
                .foregroundColor(
                    store.customLabels[windowInfo.id] != nil
                        ? .yellow
                        : .white
                )
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.2) : Color.clear)
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            hoverTimer?.invalidate()
            hoverTimer = nil
            if hovering {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    Task { @MainActor in
                        onTap()
                    }
                }
            }
        }
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Rename") {
                showRenameDialog()
            }
            Button("Full Size") {
                maximizeWindow()
            }
            Divider()
            Button("Close Window") {
                closeWindow()
            }
        }
        .help(windowInfo.title.isEmpty ? windowInfo.appName : "\(windowInfo.appName): \(windowInfo.title)")
    }

    private func showRenameDialog() {
        let alert = NSAlert()
        alert.messageText = "Rename Thumbnail"
        alert.informativeText = "Enter a custom label for \(windowInfo.appName):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = store.customLabels[windowInfo.id] ?? windowInfo.appName
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newLabel = input.stringValue.trimmingCharacters(in: .whitespaces)
            store.setCustomLabel(newLabel, for: windowInfo.id)
        } else if response == .alertThirdButtonReturn {
            store.setCustomLabel("", for: windowInfo.id)
        }
    }

    private func maximizeWindow() {
        guard PermissionService.hasAccessibility else { return }

        // Find the screen this window is on
        guard let screen = NSScreen.screens.first(where: { windowInfo.isOnScreen($0) }) else { return }
        let vf = screen.visibleFrame
        let isPortrait = screen.frame.height > screen.frame.width
        let stripThickness = CGFloat(isPortrait
            ? settings.thumbnailHeight + settings.fontSize + 16
            : settings.thumbnailWidth + 16)

        let appElement = AXUIElementCreateApplication(windowInfo.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        let activationService = WindowActivationService()
        for axWindow in axWindows {
            if activationService.matchesPublic(axWindow: axWindow, windowInfo: windowInfo) {
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

                var newX: CGFloat
                var newY: CGFloat  // AX coords (top-left)
                var newW: CGFloat
                var newH: CGFloat

                if isPortrait {
                    // Strip at top
                    newX = vf.origin.x
                    newW = vf.width
                    newH = vf.height - stripThickness
                    newY = primaryHeight - vf.origin.y - newH // AX top-left y
                    // Adjust: strip is at top of visibleFrame, so available area is below it
                    let availableBottomNS = vf.origin.y
                    let availableTopNS = vf.maxY - stripThickness
                    newH = availableTopNS - availableBottomNS
                    newY = primaryHeight - availableTopNS
                } else {
                    // Strip on left
                    newX = vf.origin.x + stripThickness
                    newW = vf.width - stripThickness
                    newH = vf.height
                    newY = primaryHeight - vf.maxY // AX top-left y
                }

                var pos = CGPoint(x: newX, y: newY)
                var size = CGSize(width: newW, height: newH)

                if let posValue = AXValueCreate(.cgPoint, &pos) {
                    AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
                }
                if let sizeValue = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
                }
                break
            }
        }
    }

    private func closeWindow() {
        guard PermissionService.hasAccessibility else { return }
        let appElement = AXUIElementCreateApplication(windowInfo.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var axWindowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axWindowID) == .success,
               axWindowID == windowInfo.id {
                AXUIElementPerformAction(axWindow, kAXPressAction as CFString)
                // Close via the close button
                var closeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeRef) == .success {
                    AXUIElementPerformAction(closeRef as! AXUIElement, kAXPressAction as CFString)
                }
                return
            }
        }
    }
}
