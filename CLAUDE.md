# CLAUDE.md — PeekBar

## Project Overview

PeekBar is a macOS menu bar app that displays a persistent strip of live window thumbnails — an always-on Mission Control. Built with Swift 5.10, SwiftUI, and ScreenCaptureKit. Requires macOS 14.0+.

## Build & Run

```bash
swift build                          # debug build
.build/debug/PeekBar                 # run debug binary
bash build-app.sh                    # release build → PeekBar.app (signed)
open PeekBar.app                     # run release app
```

`build-app.sh` signs with a local "PeekBar Self-Signed" certificate so TCC permissions (Screen Recording, Accessibility) persist across rebuilds. Falls back to ad-hoc signing if the certificate is not found. To create the certificate, see README.

## Architecture

```
Sources/PeekBar/
  PeekBarApp.swift              # SwiftUI App entry point (MenuBarExtra)
  AppDelegate.swift             # Lifecycle, event observers, service wiring

  Capture/
    WindowCaptureService.swift  # Actor — captures via ScreenCaptureKit
                                # Scoped: captureAll / capture(pid:) / captureForMonitoring(bundleIDs:)
                                # Owns 8x8 grayscale signature cache for change detection

  Models/
    WindowInfo.swift            # Window data model (id, pid, bundleID, title, frame, thumbnail)

  Panels/
    FloatingPanel.swift         # NSPanel config (floating, borderless, all spaces)
    PanelManager.swift          # Creates/manages panels per screen

  Services/
    PermissionService.swift     # Screen Recording + Accessibility permission checks
    ScreenLayoutService.swift   # Screen geometry helpers
    WindowActivationService.swift  # Raises windows via Accessibility API
    WindowNudgeService.swift    # Auto-moves windows to avoid strip overlap
    ChangeMonitorService.swift  # 5s timer driving Monitor Changes feature

  Store/
    Settings.swift              # PeekBarSettings — @Observable singleton, UserDefaults
                                # Includes monitorChangeBundleIDs (opt-in 5s change detection)
    WindowStore.swift           # @Observable — windows, custom labels, custom order, unseenChanges
                                # update(with:) full replace, merge(updates:inScope:) partial

  Views/
    SettingsView.swift          # Settings UI in MenuBarExtra
    ThumbnailStripView.swift    # ScrollView + HStack/VStack of thumbnails, drag-to-reorder
    ThumbnailItemView.swift     # Individual thumbnail — hover, click, context menu, eye badge,
                                # change-region overlay + bounce animation
```

## Key Patterns

- **@Observable** (Swift Observation) for reactive state — no Combine
- **Singletons**: `PeekBarSettings.shared` (settings), `WindowStore` (created in AppDelegate)
- **Event-driven capture** (no polling):
  - App activation/deactivation → `capture(pid:)` — refreshes that app's windows only
  - App launch → `capture(pid:)` after 500ms (windows may not be ready)
  - App terminate → `store.removeWindows(pid:)`
  - Space change, display wake → `captureAll()` (full re-enum)
  - "Last seen" snapshot: when user switches away from an app, we capture that app's windows once. Hover-to-activate naturally refreshes whichever window the user cares about.
- **Monitor Changes (opt-in 5s polling)**: Right-click thumbnail → "Monitor Changes (5s)" toggles the app's bundleID in `PeekBarSettings.monitorChangeBundleIDs`. `ChangeMonitorService` polls those bundles every 5s; `WindowCaptureService.captureForMonitoring` downsamples each thumbnail to an 8x8 grayscale signature and reports a normalized change region per window. Detected changes are stamped on `WindowStore.unseenChanges`, which the thumbnail renders as a yellow overlay rectangle + bounce. Indicators clear automatically when the user activates the app (the "I saw it" signal); the capture service also drops the cached baseline so in-app changes don't trigger a false alert later. Frontmost-app filter skips ticks for the app you're already viewing.
- **Lock/sleep pause**: `ChangeMonitorService` auto-stops on screen lock (`com.apple.screenIsLocked`) and display sleep (`screensDidSleepNotification`). Resumes on unlock/wake. Prevents ScreenCaptureKit from hanging while display is off (root cause of WindowServer watchdog freezes).
- **Per-window capture timeout**: 3s timeout per window to prevent one hung capture from blocking all
- **Frame stabilization**: WindowStore ignores frame changes < 20px to prevent jitter
- **Custom order**: Drag-to-reorder thumbnails; order survives desktop switches (not aggressively cleaned)
- **Custom labels**: Renamed thumbnails survive desktop switches
- **Nudge margin**: 6px gap between strip and nudged windows for visual separation
- **Nudge trigger**: event-based (on activation change + space change), no standalone timer
- **Code signing**: Self-signed certificate keeps TCC permissions across rebuilds

## Permissions Required

- **Screen Recording** — ScreenCaptureKit thumbnail capture
- **Accessibility** — window activation, nudging, close

## Testing

No test target. Verify manually:
- Thumbnails appear on launch and update when switching apps (deactivation snapshot)
- Drag to reorder thumbnails
- Custom order/labels persist across desktop switches
- Right-click context menu: Rename, Full Size, Monitor Changes (5s), Close Window
- Hover-to-activate (0.5s delay)
- Monitor Changes: enable on a messenger app → eye badge appears top-right; trigger a content change while the app is in background → thumbnail bounces and a yellow rectangle outlines the changed region. Activate the app → indicator clears immediately for all that app's windows.
- Lock screen while Monitor Changes enabled → on unlock, no WindowServer watchdog spin in `/Library/Logs/DiagnosticReports/`
