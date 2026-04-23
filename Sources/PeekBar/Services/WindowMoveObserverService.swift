import AppKit
import ApplicationServices

/// Watches the currently frontmost app's windows for AX move/resize events so
/// the nudge service can react the moment the user drops a drag. We only ever
/// watch one app at a time — the frontmost — to keep the AX surface small and
/// avoid mass observer churn on app launches.
@MainActor
final class WindowMoveObserverService {
    private let onChange: () -> Void
    private var watchedPID: pid_t?
    private var observer: AXObserver?
    private var watchedWindows: [AXUIElement] = []
    private var debounceTask: Task<Void, Never>?
    /// Ignore inbound move/resize events until this date. Used to swallow the
    /// echo from our own setPosition writes so we don't loop on ourselves.
    private var suppressUntil: Date = .distantPast

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func watch(pid: pid_t) {
        guard PermissionService.hasAccessibility else { return }
        guard pid != watchedPID else { return }
        stop()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let svc = Unmanaged<WindowMoveObserverService>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { svc.handleEvent() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success,
              let obs = observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for axWindow in axWindows {
            AXObserverAddNotification(obs, axWindow, kAXWindowMovedNotification as CFString, refcon)
            AXObserverAddNotification(obs, axWindow, kAXWindowResizedNotification as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)

        self.observer = obs
        self.watchedWindows = axWindows
        self.watchedPID = pid
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let obs = observer {
            for axWindow in watchedWindows {
                AXObserverRemoveNotification(obs, axWindow, kAXWindowMovedNotification as CFString)
                AXObserverRemoveNotification(obs, axWindow, kAXWindowResizedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        watchedWindows = []
        watchedPID = nil
    }

    /// Suppress inbound events for `duration`. Call before any code path that
    /// programmatically moves/resizes a watched window.
    func suppress(for duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        if until > suppressUntil { suppressUntil = until }
    }

    private func handleEvent() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            guard let self else { return }
            if Date() < self.suppressUntil { return }
            self.onChange()
        }
    }
}
