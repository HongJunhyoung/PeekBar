import AppKit

/// Owns the 5s polling timer that watches monitored apps for thumbnail changes
/// and stamps the WindowStore with `unseenChanges` indicators. Skips ticks where
/// the monitored app is currently frontmost (the user is already looking at it).
@MainActor
final class ChangeMonitorService {
    private let store: WindowStore
    private let captureService: WindowCaptureService
    private var timer: Timer?

    init(store: WindowStore, captureService: WindowCaptureService) {
        self.store = store
        self.captureService = captureService
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isRunning: Bool { timer != nil }

    private func tick() {
        var bundleIDs = PeekBarSettings.shared.monitorChangeBundleIDs
        guard !bundleIDs.isEmpty else { return }

        if let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            bundleIDs.remove(frontBundleID)
        }
        guard !bundleIDs.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            let report = await self.captureService.captureForMonitoring(bundleIDs: bundleIDs)
            for (windowID, region) in report {
                if let region {
                    self.store.markChange(windowID: windowID, region: region)
                }
            }
        }
    }
}
