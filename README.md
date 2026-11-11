<p align="center">
  <b>English</b> | <a href="README_CN.md">简体中文</a>
</p>

# 💧 LiquidClip

A lightweight, beautiful macOS clipboard history manager built with native **Liquid Glass (Frosted Acrylic/Vibrancy)** aesthetics. Built with **Swift 6 + SwiftUI + AppKit**, zero Web/Electron runtimes, launching in 0.02s with ~15MB RAM footprint.

---

## ✨ Features

- 🪟 **macOS Native Liquid Glass Design**: Powered by `NSVisualEffectView` HUD translucency, dual specular border highlights, fluid spring animations, and automatic Dark/Light appearance.
- 📋 **Rich Content Types**:
  - **Text**: Character count, word count, line count, quick transforms (UPPERCASE, lowercase, Title Case, strip whitespace).
  - **Images**: High-res thumbnail preview, pixel dimensions, export to Downloads.
  - **Colors**: Auto-detects HEX/RGB codes, displays live color swatch, generates SwiftUI / HEX / RGB snippets with one click.
  - **URLs**: Host & path breakdown, one-click open in default browser.
  - **Files**: Native file icon, path, reveal in Finder.
- ⌨️ **Keyboard First**:
  - <kbd>⌘</kbd> + <kbd>⇧</kbd> + <kbd>V</kbd> to toggle anywhere (Carbon API, zero lag).
  - <kbd>1</kbd> ~ <kbd>9</kbd> instant quick paste for top 9 items.
  - <kbd>↵</kbd> Enter to paste, <kbd>Space</kbd> to inspect, <kbd>⌘</kbd>+<kbd>P</kbd> to pin, <kbd>⌫</kbd> to delete, <kbd>Esc</kbd> to close.
  - Instant fuzzy search by text, source app name, color, or filename.
- 🔒 **Privacy & Smart Filtering**:
  - Automatically conceals sensitive items from 1Password, Bitwarden, KeePassXC, Apple Keychain, etc.
  - 100% local storage in `~/Library/Application Support/LiquidClip/`, zero telemetry.
  - Auto-promotes duplicate copies to top.
- 🚀 **Ultra-lightweight**:
  - Executable size: **only 1.47 MB**.
  - RAM: **~15 MB**.

---

## 🚀 Quick Start

Run the pre-built application:
```bash
open "LiquidClip/dist/LiquidClip.app"
```

Or install it to `/Applications`:
```bash
cp -R LiquidClip/dist/LiquidClip.app /Applications/
```

### ⚠️ macOS Gatekeeper ("Cannot be opened" / "Unverified Developer")

Because LiquidClip is free open-source software built without an expensive Apple Developer ID certificate ($99/year), macOS Gatekeeper may show a warning upon first launch. You can bypass this in seconds using any of these methods:

- **Method 1 (Recommended)**: In Finder, **Right-click (or Control-click)** `LiquidClip.app` in `/Applications`, choose **Open** from the menu, and click **Open** in the prompt (only needed once).
- **Method 2**: Go to Mac **System Settings** -> **Privacy & Security**, scroll down to the Security section, and click **Open Anyway**.
- **Method 3**: Run this one-liner in Terminal to remove the quarantine flag:
  ```bash
  xattr -cr /Applications/LiquidClip.app
  ```

To build from source:
```bash
cd LiquidClip
./scripts/build_app.sh
```
