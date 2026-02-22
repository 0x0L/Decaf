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

## Install

Download the latest `Decaf.zip` from [Releases](https://github.com/0x0L/Decaf/releases), unzip it, and drag `Decaf.app` to your Applications folder.

On first launch, macOS will block the app because it isn't notarized. To allow it:

1. Try to open Decaf — the system will show a warning
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the Decaf message
4. Confirm by clicking **Open Anyway** in the dialog that appears

You only need to do this once.

## Usage

Click the mug icon to see your running apps. Toggle any app on to prevent sleep while it runs. A filled mug means sleep is blocked; an outlined mug means idle.

Open Settings to hide apps from the menu, toggle "Keep Display On", or enable Launch at Login.

## Requirements

- macOS 15+

## License

MIT
