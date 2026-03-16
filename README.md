# SnapPin

A lightweight screenshot and pin tool for macOS, inspired by Snipaste.

## Features

- **F1** — Take a screenshot (freeze screen, drag to select area)
- **F3** — Pin the screenshot to screen (after selection)
- **Cmd+C** — Copy screenshot to clipboard (after selection)
- **Esc** — Cancel screenshot or close pinned image

### Screenshot Editing
- **Drag handles** to resize the selection area
- **Drag inside** to move the selection
- **Shift + Arrow Keys** to nudge selection by 1px
- **Cmd+Z** to undo the last annotation

### Annotation Tools
- **Arrow** — Draw arrows to highlight areas
- **Rectangle** — Draw rectangles to frame content
- **Text** — Add text labels with full IME support (Chinese, Japanese, etc.)
- **Mosaic** — Brush to pixelate sensitive information
- **Color Picker** — Choose annotation color (red, orange, yellow, green, blue, purple, white, black)

### Pinned Image
- **Scroll** to zoom in/out
- **Drag** to move
- **Cmd+C** to copy to clipboard
- **Esc** to close

## Installation

### Download DMG
Download the latest `.dmg` from [GitHub Releases](https://github.com/meowWhat/SnapPin/releases), open it, and drag `SnapPin.app` to your Applications folder.

### Build from Source
Requires Swift 5.9+ and macOS 14+.

```bash
git clone https://github.com/meowWhat/SnapPin.git
cd SnapPin
swift build
bash build_app.sh
open SnapPin.app
```

## Permissions

SnapPin requires the following macOS permissions:

- **Screen Recording** — To capture screenshots
- **Accessibility** — For global hotkeys (optional, improves reliability)

On first launch, an onboarding window will guide you through granting these permissions.

## Tech Stack

- Swift + AppKit (native macOS)
- ScreenCaptureKit (screen capture)
- HotKey (Carbon-based global hotkeys via [soffes/HotKey](https://github.com/soffes/HotKey))
- Core Graphics (annotation rendering)

## License

MIT
