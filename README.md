# PeekBar

Always-on Mission Control for macOS. A persistent strip of live window thumbnails visible at all times.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Live window thumbnails** — continuously updated previews of all open windows
- **Per-monitor layout** — horizontal strip on top for portrait monitors, vertical strip on left for landscape
- **Click to activate** — click any thumbnail to bring that window to front
- **Hover to activate** — hover over a thumbnail for 0.5s to auto-switch
- **Drag to reorder** — drag thumbnails to arrange display order; order persists across desktop switches
- **Custom labels** — rename thumbnails via right-click context menu; labels persist across desktop switches
- **Auto-nudge** — automatically moves windows to avoid overlapping the thumbnail strip
- **Context menu** — right-click thumbnails to rename, full-size, or close windows
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

### Release Build

```bash
bash build-app.sh
open PeekBar.app
```

### Code Signing (Persist Permissions)

By default, `build-app.sh` signs with a local "PeekBar Self-Signed" certificate so that Screen Recording and Accessibility permissions survive rebuilds. To set up the certificate:

```bash
# Generate certificate (valid 10 years)
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /tmp/peekbar.key -out /tmp/peekbar.crt \
  -days 3650 -subj "/CN=PeekBar Self-Signed" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle and import into login keychain
openssl pkcs12 -export -out /tmp/peekbar.p12 \
  -inkey /tmp/peekbar.key -in /tmp/peekbar.crt \
  -passout pass:peekbar -legacy
security import /tmp/peekbar.p12 -k ~/Library/Keychains/login.keychain-db \
  -P peekbar -T /usr/bin/codesign

# Trust for code signing
security add-trusted-cert -p codeSign -r trustRoot \
  -k ~/Library/Keychains/login.keychain-db /tmp/peekbar.crt
```

If the certificate is not found, the build falls back to ad-hoc signing (permissions reset each rebuild).

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
- Hover a thumbnail for 0.5s to auto-switch
- Drag thumbnails to reorder them
- Right-click a thumbnail for options (Rename, Full Size, Close Window)

## License

MIT
