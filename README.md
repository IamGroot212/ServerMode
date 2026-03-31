# ServerMode

A lightweight macOS menu bar utility that activates "Server Mode": turns off all connected displays while keeping the Mac fully running — no sleep, no screensaver. Useful for remote work via SSH or similar tools.

## Requirements

- macOS 13.0+
- Xcode 15+ (for building)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Build

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
cd ServerMode
xcodegen generate

# Build via command line
xcodebuild -project ServerMode.xcodeproj -scheme ServerMode -configuration Release build
```

Or open `ServerMode.xcodeproj` in Xcode, set signing to "Sign to Run Locally", and press Cmd+B.

## Install

After building, find `ServerMode.app` in DerivedData or the build output directory:

```bash
# Find the built app
APP=$(find ~/Library/Developer/Xcode/DerivedData/ServerMode-*/Build/Products -name "ServerMode.app" -maxdepth 2 | head -1)

# Copy to Applications
cp -R "$APP" /Applications/

# Remove quarantine attribute (needed for unsigned builds)
xattr -cr /Applications/ServerMode.app
```

## Usage

ServerMode lives in the menu bar. Click the display icon to access:

- **Toggle Server Mode** — activates/deactivates with your configured keyboard shortcut
- **Display Sleep Delay** — choose how long before displays turn off (10s to 5min)
- **Keyboard Shortcut** — configure a global hotkey (default: Cmd+Shift+0)
- **Launch at Login** — start automatically on login

### How Server Mode Works

When activated:
1. Creates an IOPMAssertion to prevent system sleep
2. Shows a countdown in the menu bar
3. Posts a notification at T-3 seconds
4. Turns off all displays via `pmset displaysleepnow`

When deactivated:
1. Wakes all displays
2. Releases the sleep prevention assertion
3. System returns to normal sleep behavior

### Permissions

- **Accessibility Access** (optional but recommended): Required for the global keyboard shortcut to work when ServerMode is not focused. Go to System Settings > Privacy & Security > Accessibility and add ServerMode.
- **Notifications** (optional): For countdown warnings before displays turn off.

## Project Structure

```
ServerMode/
  ServerModeApp.swift          — App entry point, AppDelegate
  StatusBarController.swift    — Menu bar item and menu
  ServerModeManager.swift      — Sleep assertion and display control
  HotkeyManager.swift          — Global keyboard shortcut
  SettingsPanel.swift           — Shortcut recorder panel
```
