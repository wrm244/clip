# Repository Guidelines

## Project Structure & Module Organization

`project.yml` is the XcodeGen source of truth; regenerate `Clip.xcodeproj` instead of editing it manually. Application code lives in `Sources/`: `App/` contains lifecycle and coordination, `Models/` data types, `Services/` clipboard/storage/hotkey logic, `UI/` SwiftUI and AppKit views, and `Support/` localization, logging, and widget-feed types. The widget extension is in `Widget/`. Build scripts are in `Scripts/`, packaging metadata is in `Support/`, and the GitHub Pages site and images are in `docs/`.

## Build, Test, and Development Commands

Requires Xcode 27, macOS 27 SDK, and XcodeGen (`brew install xcodegen`).

- `xcodegen generate` — regenerate the Xcode project after adding, removing, or moving files.
- `open Clip.xcodeproj` — open the workspace and run the `Clip` scheme in Xcode.
- `xcodebuild -project Clip.xcodeproj -scheme Clip -configuration Debug -destination 'platform=macOS' -derivedDataPath build build` — command-line build.
- `Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.8` — package a Release build.
- `swiftc -O Scripts/seed-clipboard.swift -o /tmp/clipseed && /tmp/clipseed run Scripts/seed-content.sample.json 1100` — generate clipboard fixtures.

## Coding Style & Naming Conventions

Use four-space indentation, Swift 6 conventions, and file names matching the primary type. Types use `UpperCamelCase`; properties, methods, and enum cases use `lowerCamelCase`. Keep UI/state on `MainActor`; place database, file, and image work behind the existing actors and pass `Sendable` DTOs. There is no SwiftLint or formatter configuration—match surrounding code and preserve strict-concurrency correctness. Keep all localization tables in sync when adding UI text.

## Testing Guidelines

There is currently no XCTest/Swift Testing target or coverage threshold. Before submitting changes, build at least Debug and manually smoke-test the affected flow: clipboard capture, search/filtering, preview, paste, hotkey, settings, and widget when relevant. Add a test target and `xcodebuild test` command if introducing automated tests.

## Commit & Pull Request Guidelines

Commit history primarily uses concise Simplified Chinese subjects such as `修复 ...`, `新增 ...`, or `发布 vX.Y.Z: ...`; non-trivial commits add bulleted details. Conventional Commits are not required. Keep pull requests focused and include a behavior summary, linked issue, validation performed, and before/after screenshots for UI changes. Never commit signing credentials. Release changes must update both targets' version/build fields in `project.yml`.
