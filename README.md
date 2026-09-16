# Decaf

A macOS menu bar app that prevents sleep while specific apps are running.

Pick which apps should keep your Mac awake — when any of them is running, sleep is blocked. When the last one quits, normal sleep resumes. Your selections are remembered across restarts.

## Features

- **Per-app control** — toggle sleep prevention for individual apps, not a blanket "stay awake" switch
- **Persistent selections** — toggled apps remain in the list even after they quit, ready for next launch
- **Keep Display On** — optionally prevent the display from sleeping too
- **Hide apps** — declutter the menu by hiding apps you'll never need (e.g. Finder)
- **Launch at Login** — start automatically with your Mac
- **Zero orphans** — the underlying `caffeinate` process is tied to Decaf's PID, so it cleans up automatically even if Decaf crashes or is force-quit

## Binary install

Download the latest `Decaf.zip` from the [Releases](https://github.com/0x0L/Decaf/releases) page. On first launch, macOS will block the app because it isn't notarized. To allow it:

1. Try to open Decaf — the system will show a warning
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the Decaf message
4. Confirm by clicking **Open Anyway** in the dialog that appears

The exact warning text may vary by macOS version. See [Apple’s instructions for opening unsigned apps](https://support.apple.com/en-us/102445).

## Usage

Click the mug icon to see your running apps. Toggle any app on to prevent sleep while it runs. A filled mug means sleep is blocked; an outlined mug means idle.

Open Settings to hide apps from the menu, toggle "Keep Display On", or enable Launch at Login. Hiding an app does not disable its sleep prevention: turn its toggle off before hiding it if you no longer want to monitor it.

Decaf tracks normal foreground-capable apps, not every background process. It responds to workspace events and checks state approximately every 0.5 seconds. Apps such as Books may keep a background process after ⌘Q; they stop counting as running once their app interface quits.

## Requirements

- macOS 27+

## Development

Use Xcode 27 on macOS 27 or later. Open `Decaf.xcodeproj`, select the Decaf scheme, and run it, or build and test from the repository root:

```sh
xcodebuild build -project Decaf.xcodeproj -scheme Decaf -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Decaf.xcodeproj -scheme Decaf -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

The Release app is at `build/Build/Products/Release/Decaf.app`. Ad-hoc sign it before opening it:

```sh
codesign --sign - --force --deep build/Build/Products/Release/Decaf.app
codesign --verify --deep --strict build/Build/Products/Release/Decaf.app
```

Quit any running Decaf instance before opening another build. SwiftLint is optional for local builds; the Xcode build phase runs it when installed at `/opt/homebrew/bin/swiftlint`. Tagged releases run the tests before creating the archive.

Monitoring combines workspace notifications with a timer in common run-loop modes, so checks continue while a menu is open. Keep the timer: activation-policy changes are not always accompanied by exit notifications. Per-app KVO was removed after crashes and should not be restored without investigating that failure.

When changing monitoring or process management, also test Books launching, quitting with ⌘Q, and reopening several times. Confirm the mug clears after quit and that a stopped `caffeinate` helper recovers while a selected app is active. Helper launch errors and recovery are available in Console under the `org.0x0L.Decaf` subsystem.

## License

MIT
