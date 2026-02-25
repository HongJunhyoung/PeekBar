import AppKit
import CoreGraphics

enum PermissionService {
    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var allPermissionsGranted: Bool {
        hasScreenRecording && hasAccessibility
    }

    static func requestAllPermissions() {
        if !hasScreenRecording {
            requestScreenRecording()
        }
        if !hasAccessibility {
            requestAccessibility()
        }
    }
}
