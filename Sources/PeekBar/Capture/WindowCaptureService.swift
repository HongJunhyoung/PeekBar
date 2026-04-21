import AppKit
import ScreenCaptureKit

/// Per-window capture result that pairs the model with the underlying CGImage,
/// so monitoring callers can compute change signatures without re-decoding.
private struct CaptureResult: @unchecked Sendable {
    var info: WindowInfo
    let cgImage: CGImage?
}

actor WindowCaptureService {
    private let store: WindowStore
    private let captureWidth = 480
    private let captureHeight = 320
    private var refreshCounter: UInt64 = 0
    /// Last seen 8x8 grayscale signature per monitored window.
    /// Populated only by captureForMonitoring; non-monitoring captures don't touch it.
    private var lastSignature: [CGWindowID: [UInt8]] = [:]

    init(store: WindowStore) {
        self.store = store
    }

    private enum Scope {
        case all
        case pid(pid_t)
        case bundleIDs(Set<String>)

        func matches(_ window: SCWindow) -> Bool {
            switch self {
            case .all: return true
            case .pid(let p): return window.owningApplication?.processID == p
            case .bundleIDs(let ids):
                guard let bid = window.owningApplication?.bundleIdentifier else { return false }
                return ids.contains(bid)
            }
        }

        func matches(_ info: WindowInfo) -> Bool {
            switch self {
            case .all: return true
            case .pid(let p): return info.pid == p
            case .bundleIDs(let ids): return ids.contains(info.bundleID)
            }
        }
    }

    /// Full enumeration + capture. Replaces the entire window list in the store.
    /// Use on app launch, space change, and wake.
    func captureAll() async {
        _ = await capture(scope: .all)
    }

    /// Capture only windows owned by the given PID. Merges into store.
    /// Used on app activation / deactivation to refresh that app's thumbnails.
    func capture(pid: pid_t) async {
        _ = await capture(scope: .pid(pid))
    }

    /// Forget the cached change-detection baselines for these windows so the next
    /// monitoring tick treats them as freshly observed. Call when the user has just
    /// viewed/used these windows so subsequent in-use changes don't trigger a false
    /// "change" indicator.
    func clearSignatures(forWindowIDs ids: Set<CGWindowID>) {
        for id in ids { lastSignature.removeValue(forKey: id) }
    }

    /// Capture monitored bundles and report which windows' thumbnails changed
    /// since the previous monitoring tick. The returned region (when non-nil) is
    /// normalized to [0,1] with a top-left origin against the thumbnail.
    /// First time a window is seen, its baseline signature is recorded and
    /// the region is reported as nil (no false positive on initial capture).
    func captureForMonitoring(bundleIDs: Set<String>) async -> [(CGWindowID, CGRect?)] {
        guard !bundleIDs.isEmpty else { return [] }
        let results = await capture(scope: .bundleIDs(bundleIDs))

        var report: [(CGWindowID, CGRect?)] = []
        var seen: Set<CGWindowID> = []
        for result in results {
            seen.insert(result.info.id)
            guard let cgImage = result.cgImage,
                  let newSig = signature(of: cgImage) else { continue }
            let region: CGRect?
            if let prevSig = lastSignature[result.info.id] {
                region = diffRegion(prev: prevSig, next: newSig)
            } else {
                region = nil
            }
            lastSignature[result.info.id] = newSig
            report.append((result.info.id, region))
        }
        // Drop signatures for windows that no longer match this monitored scope
        // (e.g., the user untoggled monitoring or the window closed).
        for id in lastSignature.keys where !seen.contains(id) {
            lastSignature.removeValue(forKey: id)
        }
        return report
    }

    @discardableResult
    private func capture(scope: Scope) async -> [CaptureResult] {
        do {
            guard !Task.isCancelled else { return [] }
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            )
            guard !Task.isCancelled else { return [] }

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownBundleID = Bundle.main.bundleIdentifier ?? "com.hongjh.PeekBar"
            let excludedBundleIDs: Set<String> = [
                "com.apple.notificationcenterui",
                "com.apple.UserNotificationCenter",
                "com.apple.dock",
                "com.apple.controlcenter",
                "com.apple.systemuiserver",
                "com.apple.WindowManager",
                "com.apple.Spotlight",
                "com.apple.loginwindow",
                "com.apple.screencaptureui",
                "com.apple.AssistiveControl",
            ]
            let ownAppName = ProcessInfo.processInfo.processName

            let eligibleWindows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                let bundleID = app.bundleIdentifier
                let appName = app.applicationName
                return app.processID != ownPID
                    && bundleID != ownBundleID
                    && appName != ownAppName
                    && !excludedBundleIDs.contains(bundleID)
                    && window.isOnScreen
                    && window.frame.width > 50
                    && window.frame.height > 50
                    && scope.matches(window)
            }

            var results: [CaptureResult] = []
            await withTaskGroup(of: CaptureResult?.self) { group in
                for window in eligibleWindows {
                    group.addTask { [self] in
                        await withTimeoutOrNil(seconds: 3) {
                            await self.captureWindow(window)
                        } ?? nil
                    }
                }
                for await result in group {
                    if let result { results.append(result) }
                }
            }

            results.sort { ($0.info.appName, $0.info.title) < ($1.info.appName, $1.info.title) }
            refreshCounter += 1
            for i in results.indices {
                results[i].info.refreshToken = refreshCounter
            }

            let infos = results.map(\.info)
            switch scope {
            case .all:
                await store.update(with: infos)
            case .pid, .bundleIDs:
                let capturedScope = scope
                await store.merge(updates: infos, inScope: { capturedScope.matches($0) })
            }
            return results
        } catch {
            return []
        }
    }

    private func captureWindow(_ window: SCWindow) async -> CaptureResult? {
        let pid = window.owningApplication?.processID ?? 0
        let bundleID = window.owningApplication?.bundleIdentifier ?? ""
        let title = window.title ?? ""
        let appName = window.owningApplication?.applicationName ?? "Unknown"

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let cropW = min(CGFloat(captureWidth), window.frame.width)
        let cropH = min(CGFloat(captureHeight), window.frame.height)
        config.sourceRect = CGRect(x: 0, y: 0, width: cropW, height: cropH)
        config.width = captureWidth
        config.height = captureHeight
        config.scalesToFit = false
        config.showsCursor = false

        var thumbnail: NSImage?
        var capturedCGImage: CGImage?
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            capturedCGImage = image
            thumbnail = NSImage(
                cgImage: image,
                size: NSSize(width: captureWidth, height: captureHeight)
            )
        } catch {
            // Capture failed for this window — return info without thumbnail
        }

        let info = WindowInfo(
            id: window.windowID,
            pid: pid,
            bundleID: bundleID,
            title: title,
            appName: appName,
            frame: window.frame,
            thumbnail: thumbnail
        )
        return CaptureResult(info: info, cgImage: capturedCGImage)
    }

    // MARK: - Change detection

    private static let signatureCols = 8
    private static let signatureRows = 8

    /// Downsamples the CGImage to an 8x8 grayscale buffer; each byte is the
    /// average luminance of one cell. Returns 64 bytes laid out row-major,
    /// row 0 = top of the image.
    private func signature(of cgImage: CGImage) -> [UInt8]? {
        let cols = Self.signatureCols
        let rows = Self.signatureRows
        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let result: CGContext? = pixels.withUnsafeMutableBytes { buf -> CGContext? in
            guard let base = buf.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: cols,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: cols,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }
        guard let ctx = result else { return nil }
        ctx.interpolationQuality = .low
        // Flip so pixel row 0 corresponds to the top of the source image.
        ctx.translateBy(x: 0, y: CGFloat(rows))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        return pixels
    }

    /// Returns the bounding box (normalized 0...1, top-left origin) of cells
    /// whose grayscale changed by more than `threshold`. Returns nil if nothing
    /// changed.
    private func diffRegion(prev: [UInt8], next: [UInt8], threshold: Int = 12) -> CGRect? {
        let cols = Self.signatureCols
        let rows = Self.signatureRows
        guard prev.count == cols * rows, next.count == cols * rows else { return nil }
        var minCol = cols, maxCol = -1, minRow = rows, maxRow = -1
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let diff = abs(Int(prev[i]) - Int(next[i]))
                if diff > threshold {
                    if c < minCol { minCol = c }
                    if c > maxCol { maxCol = c }
                    if r < minRow { minRow = r }
                    if r > maxRow { maxRow = r }
                }
            }
        }
        guard maxCol >= 0 else { return nil }
        let cellW = 1.0 / CGFloat(cols)
        let cellH = 1.0 / CGFloat(rows)
        return CGRect(
            x: CGFloat(minCol) * cellW,
            y: CGFloat(minRow) * cellH,
            width: CGFloat(maxCol - minCol + 1) * cellW,
            height: CGFloat(maxRow - minRow + 1) * cellH
        )
    }
}

/// Returns the result of `operation` or nil if it takes longer than `seconds`.
private func withTimeoutOrNil<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
