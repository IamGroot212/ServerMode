import SwiftUI
import UserNotifications

@main
struct ServerModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var serverModeManager: ServerModeManager?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: [
            "displaySleepDelay": 30,
            "hotkeyKeyCode": 29,
            "hotkeyModifierFlags": NSEvent.ModifierFlags.command.union(.shift).rawValue
        ])

        let manager = ServerModeManager()
        self.serverModeManager = manager

        let statusBar = StatusBarController(manager: manager)
        self.statusBarController = statusBar

        let hotkey = HotkeyManager { [weak manager] in
            manager?.toggle()
        }
        self.hotkeyManager = hotkey

        manager.hotkeyManager = hotkey
        statusBar.hotkeyManager = hotkey

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverModeManager?.deactivate()
        hotkeyManager?.removeMonitors()
    }
}
