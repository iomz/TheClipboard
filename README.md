<p align="center">
  <img src="Resources/Artwork/AppIcon.png" width="128" height="128" alt="The Clipboard icon">
</p>
<h1 align="center">The Clipboard</h1>
<p align="center">📋 Copy now. Find it later. A little clipboard companion for macOS.</p>
<p align="center">
  <a href="https://github.com/iomz/TheClipboard/releases"><img src="https://img.shields.io/github/v/release/iomz/TheClipboard?style=flat&color=8b5cf6" alt="Latest release"></a>
  <a href="#-download"><img src="https://img.shields.io/badge/macOS-26%2B-007AFF?style=flat" alt="macOS 26 or later"></a>
  <a href="#-download"><img src="https://img.shields.io/badge/Apple_Silicon-arm64-14b8a6?style=flat" alt="Apple Silicon — arm64"></a>
</p>

## ✨ Little things, kept handy

- 📋 Native macOS clip collection, saved locally.
- ⚡ A compact, keyboard-driven picker for quick pasting.
- 📝 Keep rich formatting—or paste plain text instead.
- 🔎 Search past clips and browse them in History Manager.
- ⭐ Favorite the things you reach for most.
- 🦋 Sparkle updates, right from the menu bar.

## ⌨️ Your shortcuts

| Shortcut         | Action                                                    |
| ---------------- | --------------------------------------------------------- |
| ⌥⌘V              | Open the picker in Normal mode                            |
| ⌥⌘C              | Open Favorites; toggle modes while the picker is open      |
| ⌃N / ⌃P or ↓ / ↑ | Move through picker results                               |
| Return           | Paste the selected clip                                   |
| ⇧Return          | Paste the selected clip as plain text, when available     |
| ⇧⌘V              | Paste the current clipboard as plain text, when available |
| ⇧⌘Space          | Open History Manager from the picker                      |
| Esc              | Dismiss the picker                                        |

Type in the picker to search. Favorites mode shows only favorited entries. Switching modes keeps your search and paste destination. If a picker shortcut is unavailable, use **Open Fast Picker…** or **Open Favorite Picker…** from the menu bar. If macOS input-source shortcuts intercept ⇧⌘Space, use **Open History Manager…** from the menu bar.

## 📦 Download

Requires **macOS 26+ and Apple Silicon**. Download [The Clipboard v0.6.0](https://github.com/iomz/TheClipboard/releases/download/v0.6.0/TheClipboard-0.6.0-arm64.dmg), or browse [Releases](https://github.com/iomz/TheClipboard/releases). To build from source, see the [build instructions](DEVELOPMENT.md).

🪴 A fresh application identity with its own clips, favorites and settings. No data or preferences are imported from another app. Allow Accessibility for **The Clipboard** when prompted to paste into other apps.

⚠️ Builds are **development-signed, not Developer ID signed or Apple-notarized**. Gatekeeper may block launch. If blocked, stop rather than bypassing macOS security.

## 🦋 Updating

Sparkle checks The Clipboard's own releases. Choose **Check for Updates…** from the menu bar. Automatic checks are opt-in; downloads and installation remain manual.

## 🛠️ Make yourself at home

Built with SwiftPM and AppKit. See [DEVELOPMENT.md](DEVELOPMENT.md) for building, testing and contributing. Small fixes and thoughtful ideas welcome! 💛

## 🪪 Author & License

**Iori Mizutani** ([@iomz](https://github.com/iomz))

MIT License. See [LICENSE](LICENSE).
