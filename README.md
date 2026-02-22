# Decaf

A macOS menu bar utility that keeps your Mac awake while specific apps are running.

Unlike a simple caffeinate toggle, Decaf lets you pick which running apps should prevent sleep. If any toggled app is running, your Mac stays awake. When the last one quits, sleep is allowed again. Selections persist across restarts.

## Install

1. Open `Decaf.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Decaf appears in the menu bar as a coffee cup icon

## Usage

- Click the menu bar icon to see running apps
- Toggle any app to keep your Mac awake while it runs
- Filled cup = caffeinate active, outlined cup = idle

## Requirements

- macOS 15+
- Xcode 16+

## License

MIT
