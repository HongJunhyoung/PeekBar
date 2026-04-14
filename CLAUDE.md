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
  AppDelegate.swift             # Lifecycle, timers, service wiring

  Capture/
    WindowCaptureService.swift  # Actor — captures window screenshots via ScreenCaptureKit
                                # Timer-driven from AppDelegate (every 2s)

  Models/
    WindowInfo.swift            # Window data model (Identifiable, Equatable)

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
    WindowStore.swift           # @Observable — windows array, custom labels, custom order

  Views/
    SettingsView.swift          # Settings UI in MenuBarExtra
    ThumbnailStripView.swift    # ScrollView + HStack/VStack of thumbnails, drag-to-reorder
    ThumbnailItemView.swift     # Individual thumbnail — hover, click, context menu
```

## Key Patterns

- **@Observable** (Swift Observation) for reactive state — no Combine
- **Singletons**: `PeekBarSettings.shared` (settings), `WindowStore` (created in AppDelegate)
- **Timer-driven capture**: `AppDelegate` owns a repeating Timer that calls `captureService.captureOnce()`. Avoids Task-loop issues where async loops silently stop.
- **Per-window capture timeout**: 3s timeout per window to prevent one hung capture from blocking all
- **Frame stabilization**: WindowStore ignores frame changes < 20px to prevent jitter
- **Custom order**: Drag-to-reorder thumbnails; order survives desktop switches (not aggressively cleaned)
- **Custom labels**: Renamed thumbnails survive desktop switches
- **Nudge margin**: 6px gap between strip and nudged windows for visual separation
- **Code signing**: Self-signed certificate keeps TCC permissions across rebuilds

## Permissions Required

- **Screen Recording** — ScreenCaptureKit thumbnail capture
- **Accessibility** — window activation, nudging, close

## Testing

No test target. Verify manually:
- Thumbnails refresh every ~2s
- Drag to reorder thumbnails
- Custom order/labels persist across desktop switches
- Right-click context menu: Rename, Full Size, Close Window
- Hover-to-activate (0.5s delay)
