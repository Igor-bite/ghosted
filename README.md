# Vanish

macOS menu-bar app that adds a **Vanish Camera** virtual camera. Pick it in any call app (Zoom, Meet, Teams, Telegram, FaceTime…) and vanish into dust with a shortcut (⌃⌥V), a finger snap or a “V” sign.

Design: `docs/superpowers/specs/2026-11-16-vanish-design.md` · Plan: `docs/superpowers/plans/2026-11-16-vanish.md`

## Layout

| Path | What |
|---|---|
| `App/` | Vanish.app: capture → Vision segmentation → Core Image / Metal dust → CMIO sink |
| `CameraExtension/` | CoreMediaIO Camera Extension: relays sink frames to the source stream; bilingual stub when the app is not running |
| `Shared/` | Constants shared by both targets |
| `Packages/VanishCore/` | Pure logic (state machine, gestures, room-plate stats) with unit tests |
| `project.yml` | XcodeGen project definition (the `.xcodeproj` is generated, not committed) |

## Build

```bash
brew install xcodegen
xcodegen generate
swift test --package-path Packages/VanishCore
xcodebuild -project Vanish.xcodeproj -scheme Vanish -configuration Debug -derivedDataPath build/DD -allowProvisioningUpdates build
```

Signing: team `4D7YJ8BY8H`, automatic signing. A Debug build needs this Mac registered in the developer account. The system extension activates only when the app runs from `/Applications` and the user approves it (macOS 15+: General → Login Items & Extensions → Camera Extensions; macOS 13–14: Privacy & Security → Allow).

## Release (not wired yet)

Developer ID Application + Developer ID provisioning profiles for the app and the extension (system-extension install + App Groups), hardened runtime, notarized DMG. Sparkle updates are planned; `SUFeedURL` gets fixed at first release.
