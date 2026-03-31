import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager: ServerModeManager
    weak var hotkeyManager: HotkeyManager?

    private var cancellables = Set<AnyCancellable>()

    // Menu items that need dynamic updates
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var shortcutMenuItem: NSMenuItem!

    // Settings panel
    private var settingsWindow: NSWindow?

    init(manager: ServerModeManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        setupButton()
        setupMenu()
        observeManager()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "ServerMode")
        button.image = image?.withSymbolConfiguration(config)
        button.toolTip = "ServerMode — Inactive"
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // Status display
        statusMenuItem = NSMenuItem(title: "Server Mode: OFF", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        statusMenuItem.attributedTitle = NSAttributedString(string: "Server Mode: OFF", attributes: [.font: font])
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Toggle
        toggleMenuItem = NSMenuItem(title: "Activate Server Mode", action: #selector(toggleServerMode), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        // Delay submenu
        let delayItem = NSMenuItem(title: "Display Sleep Delay", action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for (title, seconds) in [("10 seconds", 10), ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300)] {
            let item = NSMenuItem(title: title, action: #selector(setDelay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = UserDefaults.standard.integer(forKey: "displaySleepDelay") == seconds ? .on : .off
            delayMenu.addItem(item)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        // Keyboard shortcut entry
        shortcutMenuItem = NSMenuItem(title: "Keyboard Shortcut: ⌘⇧0", action: #selector(openShortcutRecorder), keyEquivalent: "")
        shortcutMenuItem.target = self
        menu.addItem(shortcutMenuItem)

        menu.addItem(.separator())

        // Launch at Login
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit ServerMode", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observeManager() {
        manager.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.updateMenuForState(active: active)
            }
            .store(in: &cancellables)

        manager.$countdownRemaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.updateCountdownDisplay(remaining)
            }
            .store(in: &cancellables)
    }

    // MARK: - State Updates

    private func updateMenuForState(active: Bool) {
        let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        if active {
            let title = "Server Mode: ON"
            statusMenuItem.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "display.and.arrow.down", accessibilityDescription: "ServerMode Active")
            statusItem.button?.image = image?.withSymbolConfiguration(config)
            statusItem.button?.toolTip = "ServerMode — Active"

            toggleMenuItem.title = "Deactivate Server Mode"
        } else {
            let title = "Server Mode: OFF"
            statusMenuItem.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "display", accessibilityDescription: "ServerMode")
            statusItem.button?.image = image?.withSymbolConfiguration(config)
            statusItem.button?.toolTip = "ServerMode — Inactive"

            toggleMenuItem.title = "Activate Server Mode"
        }
    }

    private func updateCountdownDisplay(_ remaining: Int?) {
        let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        if let remaining {
            let title = "Displays off in \(remaining)s..."
            statusMenuItem.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        } else if manager.isActive {
            let title = "Server Mode: ON"
            statusMenuItem.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        }
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            refreshMenu()
        }
    }

    private func refreshMenu() {
        // Refresh delay checkmarks
        if let delayItem = statusItem.menu?.item(withTitle: "Display Sleep Delay"),
           let delayMenu = delayItem.submenu {
            let currentDelay = UserDefaults.standard.integer(forKey: "displaySleepDelay")
            for item in delayMenu.items {
                item.state = item.tag == currentDelay ? .on : .off
            }
        }

        // Refresh launch at login
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Refresh shortcut display
        if let hk = hotkeyManager {
            shortcutMenuItem.title = "Keyboard Shortcut: \(hk.shortcutDisplayString)"
        }
    }

    // MARK: - Actions

    @objc private func toggleServerMode() {
        manager.toggle()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "displaySleepDelay")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = "Failed to update login item: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openShortcutRecorder() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ShortcutRecorderPanel(hotkeyManager: hotkeyManager!)
        let hostingController = NSHostingController(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keyboard Shortcut"
        panel.contentViewController = hostingController
        panel.center()
        panel.isFloatingPanel = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = panel
    }

    @objc private func quitApp() {
        manager.deactivate()
        NSApp.terminate(nil)
    }
}
