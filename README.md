# PeekBar

Always-on Mission Control for macOS. A persistent strip of live window thumbnails visible at all times.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Live window thumbnails** — continuously updated previews of all open windows
- **Per-monitor layout** — horizontal strip on top for portrait monitors, vertical strip on left for landscape
- **Click to activate** — click any thumbnail to bring that window to front
- **Auto-nudge** — automatically moves windows to avoid overlapping the thumbnail strip
- **Context menu** — right-click thumbnails to rename, full-size, or quit apps
- **Configurable** — adjust font size, spacing, and thumbnail dimensions from the menu bar
- **Start on login** — optional launch at login via Settings

## Requirements

- macOS 14.0+
- Screen Recording permission
- Accessibility permission

## Build & Run

```bash
cd ~/Developer/PeekBar
swift build
.build/debug/PeekBar
```

## Permissions

On first launch, PeekBar will request:

1. **Screen Recording** — needed to capture window thumbnails via ScreenCaptureKit
2. **Accessibility** — needed to raise windows and auto-nudge positions

Grant both in **System Settings > Privacy & Security**.

## Usage

- PeekBar appears as a menu bar icon (three rectangles)
- Click the icon to open settings
- Thumbnails appear automatically on each monitor
- Click a thumbnail to switch to that window
- Right-click a thumbnail for options (Rename, Full Size, Quit)

## License

MIT
