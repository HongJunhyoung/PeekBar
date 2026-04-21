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
                                # Scoped: captureAll / capture(pid:) / capture(bundleIDs:)

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

  Store/
    Settings.swift              # PeekBarSettings — @Observable singleton, UserDefaults
                                # Includes liveRefreshBundleIDs (opt-in 2s refresh)
    WindowStore.swift           # @Observable — windows, custom labels, custom order
                                # update(with:) full replace, merge(updates:inScope:) partial

  Views/
    SettingsView.swift          # Settings UI in MenuBarExtra
    ThumbnailStripView.swift    # ScrollView + HStack/VStack of thumbnails, drag-to-reorder
    ThumbnailItemView.swift     # Individual thumbnail — hover, click, context menu, live badge
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
- **Live Refresh (opt-in 2s polling)**: Right-click thumbnail → "Live Refresh (2s)" toggles the app's bundleID in `PeekBarSettings.liveRefreshBundleIDs`. Separate lightweight timer captures only those bundleIDs. For messenger/monitor apps where backgrounded content changes matter.
- **Lock/sleep pause**: Live Refresh timer auto-invalidates on screen lock (`com.apple.screenIsLocked`) and display sleep (`screensDidSleepNotification`). Resumes on unlock/wake. Prevents ScreenCaptureKit from hanging while display is off (root cause of WindowServer watchdog freezes).
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
- Right-click context menu: Rename, Full Size, Live Refresh (2s), Close Window
- Hover-to-activate (0.5s delay)
- Live Refresh: enable on a messenger app → small red dot appears → thumbnail updates every 2s
- Lock screen while Live Refresh enabled → on unlock, no WindowServer watchdog spin in `/Library/Logs/DiagnosticReports/`
