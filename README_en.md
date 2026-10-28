<div align="center">
  <img src="docs/icon.png" width="96" alt="Clip icon">
  <h1>Clip</h1>
  <p><b>Clipboard history manager for macOS</b><br>One shortcut, and your history is right there.</p>
</div>

<p align="center">
  <b>简体中文</b> ·
  <a href="README_en.md">English</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_fr.md">Français</a>
</p>

<div align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="Clip panel with preview expanded">
</div>

---

## The problem

You copy a snippet of code, switch over to check the docs, then come back needing it again — and the clipboard already holds something else.

Clip quietly remembers everything you copy, in the background. Hit <kbd>⇧⌘V</kbd> to bring it up, arrow keys to pick an entry, <kbd>↵</kbd> to paste it right where your cursor is.

<p align="center">
  <img src="docs/img/剪切板2.png" width="480" alt="Clip compact panel">
</p>

No window docked to the side, no tabs, no having to remember where you put something. The history is right in front of you — scroll and pick.

## Features

### Remembers everything

Text, links, color values, code, file paths, images — whatever you copy, Clip keeps it, tagged with the app it came from.

<p align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="Type detection and preview">
</p>

The row of pills at the top filters by type, with live counts. Screenshots, design mockups, color values you grabbed — each lands in its own place instead of piling into one undifferentiated list.

### Ready the moment you call it

- **Appears at your cursor** — wherever your pointer is; flips to the other side when there's no room on screen
- **Fixed height** — however many entries you have, only the list scrolls, so the window never jumps up or down as it opens
- **Enter pastes immediately** — straight to your cursor position, no need to switch back to the previous app yourself

### Look before you decide

Select an entry and press <kbd>→</kbd> to expand the preview to the right. The **top-left corner stays pinned**, so the list you're reading doesn't shift sideways. Click an image to blow it up to screen size for comparison; click anywhere or press `esc` to dismiss.

### Keyboard only, and that's fine

| Key | Action |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Show / hide the panel (rebindable to any combination) |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move selection |
| <kbd>↵</kbd> | Paste at cursor |
| <kbd>⌥↵</kbd> | Paste as plain text (no formatting) |
| <kbd>→</kbd> <kbd>←</kbd> | Expand / collapse preview |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | Paste the Nth entry directly |
| <kbd>⌘P</kbd> | Pin / unpin |
| <kbd>⌘⌫</kbd> | Delete the selected entry |
| <kbd>⌘Z</kbd> | Undo the last delete (within 20 seconds) |
| <kbd>esc</kbd> | Dismiss the panel |

### Also in the menu bar

Not in the mood for keyboard shortcuts? Click the status bar icon instead. Toggle recording, glance at recent entries, paste straight from the menu bar.

<p align="center">
  <img src="docs/img/任务栏弹窗.png" width="520" alt="Menu bar panel">
</p>

### On your desktop too

A Notification Center / desktop widget shows your most recent entries. Click one to copy it, click empty space to summon the full panel.

### Find the one you need

The search box at the top filters as you type. Entries you've pinned (<kbd>⌘P</kbd>) are never cleaned up automatically, so parameters, URLs and snippets you use constantly can stay within reach indefinitely.

## Install

Requires **macOS 27 (Golden Gate) or later**.

Download the `.dmg` from [Releases](https://github.com/wrm244/clip/releases) and drag it into Applications.

On first launch a clipboard icon appears in the menu bar. To let Clip press <kbd>⌘V</kbd> for you, go to **System Settings → Privacy & Security → Accessibility** and enable Clip. It works without that permission too — it just copies to the clipboard and prompts you to paste manually.

## Privacy

A clipboard manager can see everything you copy, so this deserves a clear answer:

- **Secrets are ignored by default.** Clipboard content that password managers (1Password, TypeIt4me, etc.) mark as concealed is never recorded
- **It won't record its own writes** — your history is never copied back into itself
- **Pause anytime** with a single switch
- **Your data stays on your Mac.** History lives in `~/Library/Application Support/Clip`. Nothing is uploaded, nothing is synced, no account involved
- **Bounded by design.** Entry count (300 by default) and retention period are both configurable, and you can wipe everything with one click

## License

Released under the [MIT](LICENSE) license. Use it, modify it, redistribute it.

## All settings

**General** — language, recording toggle, ignoring concealed content, retention limits, automatic pasting.

<p align="center">
  <img src="docs/img/设置通用.png" width="620" alt="Settings · General">
</p>

**Appearance** — light/dark, list density, whether to show source apps, panel size, and whether the panel appears at the cursor or centered at the top of the screen.

<p align="center">
  <img src="docs/img/设置外观.png" width="620" alt="Settings · Appearance">
</p>

**Shortcuts** — rebind the global hotkey, and a quick reference for every shortcut inside the panel.

Every change **takes effect immediately**. There's no Apply button, and nothing needs a restart.

## Support

- Chinese and English interface, switchable in settings, following the system language by default
- Light and dark appearance, either following the system or set manually
- Launch at login
- Respects system accessibility features: Reduce Transparency, Increase Contrast, Reduce Motion

---

<details>
<summary><b>Developer notes (build · architecture · implementation)</b></summary>

### Tech stack

Native SwiftUI + AppKit, **zero third-party dependencies**. Runs as a menu bar agent (`LSUIElement`), so it never occupies a Dock slot. SwiftData for incremental persistence, with binary data such as images stored as external files.

- Target: macOS 27.0+, Swift 6 (strict concurrency)
- UI follows the [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) and uses the system-native Liquid Glass
- Signing: self-signed certificate `Clip Self Signed`, which keeps Accessibility authorization valid across versions (see below for why)

### Build

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate                       # generate Clip.xcodeproj from project.yml
open Clip.xcodeproj                     # then Run from Xcode
```

Command-line build:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Clip.xcodeproj -scheme Clip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
```

Artifact: `build/Build/Products/Release/Clip.app`

> Re-run `xcodegen generate` after adding or removing source files (the project collects sources by directory).
> Don't keep multiple copies of Clip.app on disk (e.g. Debug and Release side by side) — they share one data
> directory, and on launch the app detects the other copy and steps aside for it.

### Packaging and release

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.6
```

`.github/workflows/release.yml` builds, packages and uploads automatically when you push a `v*` tag.
CI signing needs two secrets: `P12_BASE64` (single-line base64 of the p12) and `P12_PASSWORD`.

### Why not ad-hoc signing

Ad-hoc signing has no stable identity, so the designated requirement macOS records for privacy grants (TCC, e.g. Accessibility) can only be `cdhash H"…"` — a hash of the entire binary. Every rebuild changes the cdhash, which immediately invalidates the grant and forces users to re-authorize after each update.

With a self-signed certificate the designated requirement becomes `identifier "com.river.Clip" and certificate leaf = H"…"`, bound only to the bundle id and certificate — so authorization survives any change to the binary.

One-time certificate creation: Keychain Access → Certificate Assistant → Create a Certificate…, name it `Clip Self Signed`, identity type Self Signed Root, certificate type Code Signing, then set it to Always Trust.

> **The p12 must contain both the certificate and the private key.** Exporting only the private key imports
> successfully but no identity can be assembled. Export the whole identity with
> `security export -t identities` to avoid this.

### Architecture notes

**Capture pipeline**: `NSPasteboard.general.changeCount` is polled every 0.4s (`Timer` with `tolerance` 0.2 — negligible CPU cost) → on change, parsed into a `ClipDraft` → deduped / transcoded / stored → written to SwiftData incrementally. When the panel is open, the frontmost app is Clip itself; that case is retried later rather than dropped, so nothing is missed.

**Concurrency model**: `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `SWIFT_STRICT_CONCURRENCY=complete`. UI and state live on the main actor; database/file I/O and image transcoding are isolated in two actors, `ClipStorage` and `ImageTranscoder`, so the main thread never touches I/O.

Key SwiftData decisions: `@Model` classes are explicitly `nonisolated`; `ModelContext` is created lazily inside actor methods (so the first access doesn't land on the main queue); `@Model` instances never cross actor boundaries — only the Sendable `ClipItem` DTO is exposed; autosave is off and every write calls `save()` explicitly (autosave isn't reliable under force quit); the schema starts from `VersionedSchema` + `SchemaMigrationPlan`.

**Window**: `NSPanel(.borderless, .fullSizeContentView, .nonactivatingPanel)` with `canBecomeKey = true` so you can type in search, at `level = .floating`. Expanding the preview only widens the window to the right and keeps the top-left corner pinned — it never recomputes position.

**Hotkey**: Carbon `RegisterEventHotKey`, hopping back to the main actor with `MainActor.assumeIsolated` inside the C callback. Unlike `CGEventTap`, this needs no Accessibility permission.

**Loop prevention**: writes to the clipboard carry a `com.river.clip.marker` type, which the poller skips.

**Menu bar panel**: uses the macOS 27 `NSStatusItem` expanded-interface session (`NSStatusItemExpandedInterfaceDelegate`) rather than `NSPopover` — the system session provides keyboard navigation and menu tracking. Three hard constraints: don't set a `menu`, don't toggle manually via target/action, and dismiss via `expandedInterfaceSession?.cancel()`.

**Data locations**:

```
~/Library/Application Support/Clip/
├── Clip.store      SwiftData database (SQLite underneath)
├── Blobs/          PNG originals, JPG thumbnails, RTF rich text
└── Widget/         Read-only snapshot for the desktop widget (feed.json + Thumbs/)
```

Settings live in `~/Library/Preferences/com.river.Clip.plist`.

### Directory layout

```
project.yml                 XcodeGen project definition
Support/Info.plist          LSUIElement, clip:// URL scheme
Sources/
  App/                      entry point, lifecycle, app-level coordination
  Models/                   item model, settings, shortcuts
  Services/                 capture, parsing, transcoding, storage, hotkey, paste
  UI/                       panel, preview, menu bar panel, settings window
  Support/                  localization, logging, widget feed
Widget/                     desktop widget (read-only snapshot approach)
Scripts/                    make-dmg.sh, seed-clipboard.swift
```

`Scripts/seed-clipboard.swift` is a development helper: it writes a series of entries to the system clipboard from a JSON manifest, which makes it easy to generate test data of every type.

```bash
swiftc -O Scripts/seed-clipboard.swift -o /tmp/clipseed
/tmp/clipseed run Scripts/seed-content.sample.json 1100
```

### Known limitations

- "Launch at login" uses `SMAppService.mainApp`, which can fail when the app isn't in `/Applications` (the settings pane shows an error if it does)
- Images are capped at 8MB by default (larger ones are downsampled); history is capped at 300 entries; pinned entries are never evicted
- The desktop widget reads the main app's snapshot directory via `temporary-exception.files.home-relative-path.read-only` — the only viable sharing channel for a build without an App Group. Shipping to the Mac App Store would require an App Group plus proper signing
- The widget snapshot contains the titles of your 12 most recent entries (this can't currently be disabled)
- Signed with a self-signed certificate; Mac App Store distribution or notarization requires a Developer ID certificate

</details>

<p align="center">
  <sub>Pure SwiftUI + AppKit · Zero third-party dependencies · Your data stays on your Mac</sub>
</p>